-- THAMAN POS V9.8 / THAMAN Admin V2.1
-- Production hardening round:
-- 1) expiring temporary owner passwords (24 hours)
-- 2) stronger activation throttling by device + activation-code fingerprint
-- 3) safer request-chat message throttling
-- 4) admin-side Supabase Realtime SELECT channel for custom-plan conversations
-- Run AFTER migration 011.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Expiring temporary owner passwords
-- ---------------------------------------------------------------------------
alter table public.pos_owner_accounts
  add column if not exists temporary_password_set_at timestamptz,
  add column if not exists temporary_password_expires_at timestamptz,
  add column if not exists temporary_password_set_by uuid;

comment on column public.pos_owner_accounts.temporary_password_expires_at is
  'When must_change_password=true, the temporary password is rejected after this timestamp.';

-- Existing temporary passwords created before this migration receive a short,
-- deterministic grace window instead of remaining valid forever.
update public.pos_owner_accounts
set temporary_password_set_at = coalesce(temporary_password_set_at, now()),
    temporary_password_expires_at = coalesce(temporary_password_expires_at, now() + interval '24 hours')
where must_change_password = true
  and temporary_password_expires_at is null;

create or replace function public.admin_reset_pos_owner_password(
  p_business_id uuid,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_owner public.pos_owner_accounts%rowtype;
  v_expires_at timestamptz := now() + interval '24 hours';
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;

  -- Temporary credentials are intentionally stronger than normal legacy
  -- credentials because they are shared out-of-band by an administrator.
  if length(coalesce(p_new_password,'')) < 12
     or p_new_password !~ '[A-Z]'
     or p_new_password !~ '[a-z]'
     or p_new_password !~ '[0-9]'
     or p_new_password !~ '[^A-Za-z0-9]' then
    raise exception 'Temporary password must be at least 12 characters and include upper, lower, number and symbol';
  end if;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id = p_business_id
  limit 1;
  if v_owner.id is null then raise exception 'POS owner account not found'; end if;

  update public.pos_owner_accounts
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
      must_change_password = true,
      temporary_password_set_at = now(),
      temporary_password_expires_at = v_expires_at,
      temporary_password_set_by = auth.uid(),
      updated_at = now()
  where id = v_owner.id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(
    auth.uid(),p_business_id,'admin_reset_pos_owner_password',
    'تم تعيين كلمة مرور مؤقتة لمدة 24 ساعة لحساب مالك THAMAN POS',
    jsonb_build_object('owner_id',v_owner.id,'expires_at',v_expires_at)
  );

  return jsonb_build_object(
    'ok', true,
    'email', v_owner.email,
    'display_name', v_owner.display_name,
    'temporary_password_expires_at', v_expires_at
  );
end;
$$;

create or replace function public.pos_owner_login(
  p_activation_code text,
  p_device_uid text,
  p_email text,
  p_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
  v_failures integer;
  v_account_failures integer;
begin
  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code, p_device_uid);
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'license_denied', 'server_time', now());
  end;

  delete from public.pos_owner_login_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer into v_failures
  from public.pos_owner_login_attempts
  where business_id = v_business_id
    and device_uid = btrim(p_device_uid)
    and lower(email) = lower(btrim(p_email))
    and success = false
    and attempted_at > now() - interval '15 minutes';

  select count(*)::integer into v_account_failures
  from public.pos_owner_login_attempts
  where business_id = v_business_id
    and lower(email) = lower(btrim(p_email))
    and success = false
    and attempted_at > now() - interval '15 minutes';

  if coalesce(v_failures, 0) >= 8 or coalesce(v_account_failures, 0) >= 20 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts', 'retry_after_seconds', 900, 'server_time', now());
  end if;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id = v_business_id
    and lower(email) = lower(btrim(p_email))
  limit 1;

  if v_owner.id is not null
     and v_owner.must_change_password
     and v_owner.temporary_password_expires_at is not null
     and v_owner.temporary_password_expires_at <= now() then
    insert into public.pos_owner_login_attempts(business_id, device_uid, email, success)
    values(v_business_id, btrim(p_device_uid), lower(btrim(p_email)), false);
    return jsonb_build_object(
      'ok', false,
      'error', 'temporary_password_expired',
      'temporary_password_expires_at', v_owner.temporary_password_expires_at,
      'server_time', now()
    );
  end if;

  if v_owner.id is null or not v_owner.active or
     extensions.crypt(coalesce(p_password,''), v_owner.password_hash) <> v_owner.password_hash then
    insert into public.pos_owner_login_attempts(business_id, device_uid, email, success)
    values(v_business_id, btrim(p_device_uid), lower(btrim(p_email)), false);
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials', 'server_time', now());
  end if;

  insert into public.pos_owner_login_attempts(business_id, device_uid, email, success)
  values(v_business_id, btrim(p_device_uid), lower(btrim(p_email)), true);

  delete from public.pos_owner_login_attempts
  where business_id = v_business_id
    and device_uid = btrim(p_device_uid)
    and lower(email) = lower(btrim(p_email))
    and success = false;

  update public.pos_owner_accounts
  set last_login_at = now(), updated_at = now()
  where id = v_owner.id;

  return jsonb_build_object(
    'ok', true,
    'owner_id', v_owner.id,
    'business_id', v_business_id,
    'role', 'owner',
    'display_name', v_owner.display_name,
    'phone', v_owner.phone,
    'email', v_owner.email,
    'must_change_password', v_owner.must_change_password,
    'temporary_password_expires_at', v_owner.temporary_password_expires_at,
    'server_time', now()
  );
end;
$$;

create or replace function public.pos_change_owner_password(
  p_activation_code text,
  p_device_uid text,
  p_email text,
  p_current_password text,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
begin
  if length(coalesce(p_new_password,'')) < 10
     or p_new_password !~ '[A-Z]'
     or p_new_password !~ '[a-z]'
     or p_new_password !~ '[0-9]' then
    return jsonb_build_object('ok', false, 'error', 'password_weak');
  end if;
  if coalesce(p_current_password,'') = p_new_password then
    return jsonb_build_object('ok', false, 'error', 'password_same');
  end if;

  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code, p_device_uid);
  exception when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
  end;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id = v_business_id
    and lower(email) = lower(btrim(p_email))
    and active = true
  limit 1;

  if v_owner.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  if v_owner.must_change_password
     and v_owner.temporary_password_expires_at is not null
     and v_owner.temporary_password_expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'temporary_password_expired');
  end if;

  if extensions.crypt(coalesce(p_current_password,''), v_owner.password_hash) <> v_owner.password_hash then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  update public.pos_owner_accounts
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
      must_change_password = false,
      temporary_password_set_at = null,
      temporary_password_expires_at = null,
      temporary_password_set_by = null,
      updated_at = now()
  where id = v_owner.id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(null,v_business_id,'pos_owner_password_changed','تم تغيير كلمة مرور مالك THAMAN POS بعد الدخول بكلمة مؤقتة',jsonb_build_object('owner_id',v_owner.id));

  return jsonb_build_object('ok', true, 'server_time', now());
end;
$$;

-- Owner status now exposes only the expiry timestamp, never password material.
create or replace function public.pos_owner_status(
  p_activation_code text,
  p_device_uid text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
begin
  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code, p_device_uid);
  exception when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
  end;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id = v_business_id
  limit 1;

  if v_owner.id is null then
    return jsonb_build_object('ok', true, 'owner_exists', false, 'business_id', v_business_id);
  end if;

  return jsonb_build_object(
    'ok', true,
    'owner_exists', true,
    'owner_id', v_owner.id,
    'business_id', v_business_id,
    'display_name', v_owner.display_name,
    'phone', v_owner.phone,
    'email', v_owner.email,
    'active', v_owner.active,
    'must_change_password', v_owner.must_change_password,
    'temporary_password_expires_at', v_owner.temporary_password_expires_at,
    'last_login_at', v_owner.last_login_at
  );
end;
$$;

-- Keep the proof-aware wrappers from migration 009 while routing through the
-- hardened base functions above.
alter function public.admin_reset_pos_owner_password(uuid,text)
  set search_path = pg_catalog, public, extensions;
alter function public.pos_owner_login(text,text,text,text)
  set search_path = '';
alter function public.pos_change_owner_password(text,text,text,text,text)
  set search_path = pg_catalog, public, extensions;

revoke all on function public.admin_reset_pos_owner_password(uuid,text) from public, anon;
grant execute on function public.admin_reset_pos_owner_password(uuid,text) to authenticated;
revoke all on function public.pos_owner_login(text,text,text,text) from public, anon, authenticated;
revoke all on function public.pos_change_owner_password(text,text,text,text,text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Activation brute-force throttling: device UID AND code fingerprint
-- ---------------------------------------------------------------------------
create index if not exists idx_pos_activation_attempts_fingerprint
  on public.pos_activation_attempts(activation_code_fingerprint, attempted_at desc);

create or replace function public.pos_activate_device_v4(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_device_name text,
  p_platform text,
  p_app_version text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device_failed integer;
  v_code_failed integer;
  v_global_failed integer;
  v_result jsonb;
  v_ok boolean;
  v_fingerprint text;
begin
  if coalesce(btrim(p_device_uid),'') = '' then
    return jsonb_build_object('ok',false,'error','device_uid_missing','server_time',now());
  end if;
  if coalesce(length(btrim(p_activation_code)),0) < 8 or length(btrim(p_activation_code)) > 80 then
    return jsonb_build_object('ok',false,'error','invalid_activation_code','server_time',now());
  end if;

  v_fingerprint := encode(extensions.digest(upper(btrim(p_activation_code)), 'sha256'),'hex');
  delete from public.pos_activation_attempts where attempted_at < now() - interval '24 hours';

  select count(*)::integer into v_device_failed
  from public.pos_activation_attempts
  where device_uid=btrim(p_device_uid)
    and success=false
    and attempted_at >= now() - interval '15 minutes';

  select count(*)::integer into v_code_failed
  from public.pos_activation_attempts
  where activation_code_fingerprint=v_fingerprint
    and success=false
    and attempted_at >= now() - interval '15 minutes';

  -- A high global ceiling protects the database from automated floods while
  -- staying far above normal legitimate activation traffic.
  select count(*)::integer into v_global_failed
  from public.pos_activation_attempts
  where success=false
    and attempted_at >= now() - interval '1 minute';

  if v_device_failed >= 8 or v_code_failed >= 12 or v_global_failed >= 300 then
    insert into public.pos_activation_attempts(device_uid,activation_code_fingerprint,success)
    values(btrim(p_device_uid),v_fingerprint,false);
    return jsonb_build_object(
      'ok',false,
      'error','activation_rate_limited',
      'retry_after_seconds',case when v_global_failed >= 300 then 60 else 900 end,
      'server_time',now()
    );
  end if;

  v_result := public.pos_activate_device_v3(
    p_activation_code,p_device_uid,p_device_proof,p_device_name,p_platform,p_app_version
  );
  v_ok := coalesce((v_result->>'ok')::boolean,false);

  insert into public.pos_activation_attempts(device_uid,activation_code_fingerprint,success)
  values(btrim(p_device_uid),v_fingerprint,v_ok);

  if v_ok then
    delete from public.pos_activation_attempts
    where (device_uid=btrim(p_device_uid) or activation_code_fingerprint=v_fingerprint)
      and success=false;
  end if;

  return v_result || jsonb_build_object('server_time',now());
end;
$$;

revoke all on function public.pos_activate_device_v4(text,text,text,text,text,text) from public;
grant execute on function public.pos_activate_device_v4(text,text,text,text,text,text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Request-chat hardening + admin Realtime
-- ---------------------------------------------------------------------------
create index if not exists idx_subscription_request_messages_rate
  on public.subscription_request_messages(request_id, sender_type, created_at desc);

-- POS-side spam guard. Admin has its own authenticated account and activity log.
create or replace function public.pos_send_subscription_request_message_v1(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_request_id uuid,
  p_message text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_message_id uuid;
  v_recent_count integer;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code,p_device_uid,p_device_proof) r;
  if v_business_id is null then
    return jsonb_build_object('ok',false,'error','license_denied','server_time',now());
  end if;
  if coalesce(char_length(btrim(p_message)),0) < 1 or char_length(btrim(p_message)) > 4000 then
    return jsonb_build_object('ok',false,'error','invalid_message','server_time',now());
  end if;
  if not exists(
    select 1 from public.subscription_requests q
    where q.id=p_request_id and q.business_id=v_business_id and q.request_type='custom'
  ) then
    return jsonb_build_object('ok',false,'error','request_not_found','server_time',now());
  end if;

  select count(*)::integer into v_recent_count
  from public.subscription_request_messages m
  where m.request_id=p_request_id
    and m.business_id=v_business_id
    and m.sender_type='owner'
    and m.created_at >= now() - interval '1 minute';
  if v_recent_count >= 20 then
    return jsonb_build_object('ok',false,'error','message_rate_limited','retry_after_seconds',60,'server_time',now());
  end if;

  insert into public.subscription_request_messages(
    request_id,business_id,sender_type,message,read_by_owner,read_by_admin
  ) values (
    p_request_id,v_business_id,'owner',btrim(p_message),true,false
  ) returning id into v_message_id;

  update public.subscription_requests
  set status = case when status='new' then 'contacting' else status end
  where id=p_request_id;

  return jsonb_build_object('ok',true,'message_id',v_message_id,'server_time',now());
end;
$$;

revoke all on function public.pos_send_subscription_request_message_v1(text,text,text,uuid,text) from public;
grant execute on function public.pos_send_subscription_request_message_v1(text,text,text,uuid,text) to anon, authenticated;

-- Admin Realtime is safe because only authenticated THAMAN owners are granted
-- SELECT and the RLS policy below verifies the owner profile.
grant select on public.subscription_request_messages to authenticated;
drop policy if exists thaman_admin_realtime_read_subscription_messages on public.subscription_request_messages;
create policy thaman_admin_realtime_read_subscription_messages
  on public.subscription_request_messages
  for select to authenticated
  using (public.is_thaman_owner());

-- Add the table to Supabase Realtime when the standard publication exists.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1
       from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='subscription_request_messages'
     ) then
    execute 'alter publication supabase_realtime add table public.subscription_request_messages';
  end if;
exception when insufficient_privilege then
  -- Managed Supabase projects normally allow this migration. If a restricted
  -- environment does not, messaging still works via RPC live refresh.
  null;
end;
$$;


-- Admin-side message flood guard as a second layer around authenticated access.
create or replace function public.admin_send_subscription_request_message_v1(
  p_request_id uuid,
  p_message text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_message_id uuid;
  v_recent_count integer;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  if coalesce(char_length(btrim(p_message)),0) < 1 or char_length(btrim(p_message)) > 4000 then
    raise exception 'Message must be between 1 and 4000 characters';
  end if;
  select business_id into v_business_id
  from public.subscription_requests
  where id=p_request_id and request_type='custom';
  if v_business_id is null then raise exception 'Request not found'; end if;

  select count(*)::integer into v_recent_count
  from public.subscription_request_messages
  where request_id=p_request_id
    and sender_type='admin'
    and created_at >= now() - interval '1 minute';
  if v_recent_count >= 30 then raise exception 'message_rate_limited'; end if;

  insert into public.subscription_request_messages(
    request_id,business_id,sender_type,sender_admin_user_id,message,read_by_owner,read_by_admin
  ) values (
    p_request_id,v_business_id,'admin',auth.uid(),btrim(p_message),false,true
  ) returning id into v_message_id;

  update public.subscription_requests
  set status=case when status='new' then 'contacting' else status end
  where id=p_request_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(),v_business_id,'subscription_request_message_sent','تم إرسال رسالة للمشترك بخصوص طلب الاشتراك',jsonb_build_object('request_id',p_request_id,'message_id',v_message_id));

  return v_message_id;
end;
$$;

revoke all on function public.admin_send_subscription_request_message_v1(uuid,text) from public, anon;
grant execute on function public.admin_send_subscription_request_message_v1(uuid,text) to authenticated;

comment on function public.admin_reset_pos_owner_password(uuid,text) is
  'Sets a strong temporary owner password that expires after 24 hours without changing subscription/device/business data.';
comment on function public.pos_activate_device_v4(text,text,text,text,text,text) is
  'Proof-aware activation with layered device/code/global throttles.';
