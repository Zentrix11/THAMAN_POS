-- THAMAN SQL 013
-- Access reuse, hard device detach, bulk admin actions, owner PIN login,
-- and password-policy UX alignment.
-- Run AFTER 012_final_security_realtime_notifications.sql.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- 1) Hard device detach: an admin-detached device cannot self-reactivate.
-- ---------------------------------------------------------------------------
alter table public.devices
  add column if not exists admin_locked boolean not null default false,
  add column if not exists admin_locked_at timestamptz,
  add column if not exists admin_locked_by uuid references auth.users(id) on delete set null;

create or replace function public.admin_set_device_active_v2(
  p_device_id uuid,
  p_active boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_blocked boolean;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id, blocked into v_business_id, v_blocked
  from public.devices where id = p_device_id;
  if v_business_id is null then raise exception 'Device not found'; end if;
  if p_active and coalesce(v_blocked,false) then
    raise exception 'Blocked device must be unblocked first';
  end if;

  update public.devices
  set active = p_active,
      admin_locked = not p_active,
      admin_locked_at = case when p_active then null else now() end,
      admin_locked_by = case when p_active then null else auth.uid() end,
      updated_at = now()
  where id = p_device_id;

  insert into public.activity(admin_user_id,business_id,action,description)
  values(auth.uid(),v_business_id,
    case when p_active then 'device_relinked' else 'device_admin_detached' end,
    case when p_active then 'تم إعادة تفعيل الجهاز من لوحة الإدارة' else 'تم فصل الجهاز وقفل إعادة تفعيله ذاتيًا' end);
end;
$$;

-- Preserve v4 signature used by released POS builds while enforcing hard detach.
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
  v_existing_locked boolean;
begin
  if coalesce(btrim(p_device_uid),'') = '' then
    return jsonb_build_object('ok',false,'error','device_uid_missing','server_time',now());
  end if;
  if coalesce(length(btrim(p_activation_code)),0) < 8 or length(btrim(p_activation_code)) > 80 then
    return jsonb_build_object('ok',false,'error','invalid_activation_code','server_time',now());
  end if;

  -- An explicit admin detach is authoritative. The POS cannot self-reactivate.
  select coalesce(d.admin_locked,false) into v_existing_locked
  from public.subscriptions s
  join public.devices d on d.business_id=s.business_id
  where upper(s.activation_code)=upper(btrim(p_activation_code))
    and d.device_uid=btrim(p_device_uid)
  order by s.created_at desc
  limit 1;
  if coalesce(v_existing_locked,false) then
    return jsonb_build_object('ok',false,'error','device_admin_locked','server_time',now());
  end if;

  -- Keep every throttle from migration 012; SQL 013 only adds the admin lock.
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

  select count(*)::integer into v_global_failed
  from public.pos_activation_attempts
  where success=false
    and attempted_at >= now() - interval '1 minute';

  if v_device_failed >= 8 or v_code_failed >= 12 or v_global_failed >= 300 then
    insert into public.pos_activation_attempts(device_uid,activation_code_fingerprint,success)
    values(btrim(p_device_uid),v_fingerprint,false);
    return jsonb_build_object(
      'ok',false,'error','activation_rate_limited',
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

-- ---------------------------------------------------------------------------
-- 2) Owner login requires PIN as well as email/password.
-- ---------------------------------------------------------------------------
create or replace function public.pos_owner_login_v3(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_email text,
  p_password text,
  p_pin text
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
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code,p_device_uid,p_device_proof) r;
  if v_business_id is null then
    return jsonb_build_object('ok',false,'error','license_denied','server_time',now());
  end if;

  delete from public.pos_owner_login_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer into v_failures
  from public.pos_owner_login_attempts
  where business_id=v_business_id
    and device_uid=btrim(p_device_uid)
    and lower(email)=lower(btrim(p_email))
    and success=false
    and attempted_at > now() - interval '15 minutes';

  select count(*)::integer into v_account_failures
  from public.pos_owner_login_attempts
  where business_id=v_business_id
    and lower(email)=lower(btrim(p_email))
    and success=false
    and attempted_at > now() - interval '15 minutes';

  if coalesce(v_failures,0) >= 8 or coalesce(v_account_failures,0) >= 20 then
    return jsonb_build_object('ok',false,'error','too_many_attempts','retry_after_seconds',900,'server_time',now());
  end if;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id=v_business_id and lower(email)=lower(btrim(p_email))
  limit 1;

  if v_owner.id is not null
     and v_owner.must_change_password
     and v_owner.temporary_password_expires_at is not null
     and v_owner.temporary_password_expires_at <= now() then
    insert into public.pos_owner_login_attempts(business_id,device_uid,email,success)
    values(v_business_id,btrim(p_device_uid),lower(btrim(p_email)),false);
    return jsonb_build_object('ok',false,'error','temporary_password_expired',
      'temporary_password_expires_at',v_owner.temporary_password_expires_at,'server_time',now());
  end if;

  if v_owner.id is null or not v_owner.active
     or extensions.crypt(coalesce(p_password,''),v_owner.password_hash) <> v_owner.password_hash
     or extensions.crypt(coalesce(p_pin,''),v_owner.pin_hash) <> v_owner.pin_hash then
    insert into public.pos_owner_login_attempts(business_id,device_uid,email,success)
    values(v_business_id,btrim(p_device_uid),lower(btrim(p_email)),false);
    return jsonb_build_object('ok',false,'error','invalid_credentials','server_time',now());
  end if;

  insert into public.pos_owner_login_attempts(business_id,device_uid,email,success)
  values(v_business_id,btrim(p_device_uid),lower(btrim(p_email)),true);
  delete from public.pos_owner_login_attempts
  where business_id=v_business_id and device_uid=btrim(p_device_uid)
    and lower(email)=lower(btrim(p_email)) and success=false;

  update public.pos_owner_accounts set last_login_at=now(),updated_at=now() where id=v_owner.id;
  return jsonb_build_object(
    'ok',true,'owner_id',v_owner.id,'business_id',v_business_id,'role','owner',
    'display_name',v_owner.display_name,'phone',v_owner.phone,'email',v_owner.email,
    'must_change_password',v_owner.must_change_password,
    'temporary_password_expires_at',v_owner.temporary_password_expires_at,'server_time',now()
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Passwords are user-chosen. Strength is guidance, not a blocking rule.
-- ---------------------------------------------------------------------------
-- Owner setup keeps identity/PIN validation but does not block a user-chosen password by complexity.
create or replace function public.pos_provision_owner(
  p_activation_code text,
  p_device_uid text,
  p_display_name text,
  p_phone text,
  p_email text,
  p_password text,
  p_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_business_id uuid;
  v_owner_id uuid;
  v_email text := lower(btrim(p_email));
begin
  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code,p_device_uid);
  exception when others then
    return jsonb_build_object('ok',false,'error',sqlerrm);
  end;
  if coalesce(btrim(p_display_name),'')='' then return jsonb_build_object('ok',false,'error','owner_name_missing'); end if;
  if v_email='' or position('@' in v_email)<2 then return jsonb_build_object('ok',false,'error','email_invalid'); end if;
  if coalesce(p_password,'')='' then return jsonb_build_object('ok',false,'error','password_empty'); end if;
  if coalesce(p_pin,'') !~ '^[0-9]{4}$' then return jsonb_build_object('ok',false,'error','pin_invalid'); end if;

  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text,91));
  if exists(select 1 from public.pos_owner_accounts where business_id=v_business_id) then
    return jsonb_build_object('ok',false,'error','owner_already_exists');
  end if;
  if exists(select 1 from public.pos_owner_accounts where lower(email)=v_email) then
    return jsonb_build_object('ok',false,'error','email_already_used');
  end if;

  insert into public.pos_owner_accounts(business_id,display_name,phone,email,password_hash,pin_hash)
  values(v_business_id,btrim(p_display_name),coalesce(btrim(p_phone),''),v_email,
    extensions.crypt(p_password,extensions.gen_salt('bf',12)),
    extensions.crypt(p_pin,extensions.gen_salt('bf',10)))
  returning id into v_owner_id;

  update public.businesses
  set owner_name=btrim(p_display_name),
      phone=case when coalesce(btrim(p_phone),'')='' then phone else btrim(p_phone) end,
      email=v_email,updated_at=now()
  where id=v_business_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(null,v_business_id,'pos_owner_created','تم إنشاء حساب مالك THAMAN POS السحابي',
    jsonb_build_object('owner_id',v_owner_id,'email',v_email));
  return jsonb_build_object('ok',true,'owner_id',v_owner_id,'business_id',v_business_id);
end;
$$;

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
  if coalesce(p_new_password,'') = '' then raise exception 'Password cannot be empty'; end if;

  select * into v_owner from public.pos_owner_accounts where business_id=p_business_id limit 1;
  if v_owner.id is null then raise exception 'POS owner account not found'; end if;

  update public.pos_owner_accounts
  set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
      must_change_password=true,
      temporary_password_set_at=now(),
      temporary_password_expires_at=v_expires_at,
      temporary_password_set_by=auth.uid(),
      updated_at=now()
  where id=v_owner.id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(),p_business_id,'admin_reset_pos_owner_password',
    'تم تعيين كلمة مرور مؤقتة لحساب المالك',
    jsonb_build_object('owner_id',v_owner.id,'expires_at',v_expires_at));

  return jsonb_build_object('ok',true,'email',v_owner.email,'display_name',v_owner.display_name,
    'temporary_password_expires_at',v_expires_at);
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
set search_path = public, extensions
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
begin
  if coalesce(p_new_password,'')='' then
    return jsonb_build_object('ok',false,'error','password_empty');
  end if;
  if coalesce(p_current_password,'')=p_new_password then
    return jsonb_build_object('ok',false,'error','password_same');
  end if;
  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code,p_device_uid);
  exception when others then
    return jsonb_build_object('ok',false,'error',sqlerrm);
  end;

  select * into v_owner from public.pos_owner_accounts
  where business_id=v_business_id and lower(email)=lower(btrim(p_email)) and active=true limit 1;
  if v_owner.id is null or extensions.crypt(coalesce(p_current_password,''),v_owner.password_hash)<>v_owner.password_hash then
    return jsonb_build_object('ok',false,'error','invalid_credentials');
  end if;

  update public.pos_owner_accounts
  set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
      must_change_password=false,
      temporary_password_set_at=null,
      temporary_password_expires_at=null,
      temporary_password_set_by=null,
      updated_at=now()
  where id=v_owner.id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(null,v_business_id,'pos_owner_password_changed','تم تغيير كلمة مرور مالك THAMAN POS',jsonb_build_object('owner_id',v_owner.id));
  return jsonb_build_object('ok',true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) Deleting the final subscription frees the owner e-mail for a new account.
-- Historical activity stays; the cloud owner credential is removed.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_subscription(p_subscription_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id into v_business_id from public.subscriptions where id=p_subscription_id;
  if v_business_id is null then raise exception 'Subscription not found'; end if;

  update public.payments set subscription_id=null where subscription_id=p_subscription_id;
  delete from public.subscriptions where id=p_subscription_id;

  if not exists(select 1 from public.subscriptions where business_id=v_business_id) then
    delete from public.devices where business_id=v_business_id;
    delete from public.pos_owner_accounts where business_id=v_business_id;
    update public.businesses
      set status='archived', email=null, updated_at=now()
      where id=v_business_id;
  end if;

  insert into public.activity(admin_user_id,business_id,action,description)
  values(auth.uid(),v_business_id,'subscription_deleted','تم حذف الاشتراك وتحرير بيانات الدخول عند عدم وجود اشتراك آخر');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) Bulk admin actions used by multi-select UI.
-- ---------------------------------------------------------------------------
create or replace function public.admin_bulk_delete_devices(p_device_ids uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  with deleted as (
    delete from public.devices where id=any(p_device_ids) returning id
  ) select count(*)::integer into v_count from deleted;
  insert into public.activity(admin_user_id,action,description,meta)
  values(auth.uid(),'devices_bulk_deleted','تم حذف عدة أجهزة دفعة واحدة',jsonb_build_object('count',v_count));
  return v_count;
end; $$;

create or replace function public.admin_bulk_delete_subscriptions(p_subscription_ids uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_count integer:=0;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  foreach v_id in array coalesce(p_subscription_ids,array[]::uuid[]) loop
    if exists(select 1 from public.subscriptions where id=v_id) then
      perform public.admin_delete_subscription(v_id);
      v_count:=v_count+1;
    end if;
  end loop;
  return v_count;
end; $$;

revoke all on function public.admin_set_device_active_v2(uuid,boolean) from public, anon;
revoke all on function public.admin_bulk_delete_devices(uuid[]) from public, anon;
revoke all on function public.admin_bulk_delete_subscriptions(uuid[]) from public, anon;
revoke all on function public.pos_owner_login_v3(text,text,text,text,text,text) from public;
grant execute on function public.admin_set_device_active_v2(uuid,boolean) to authenticated;
grant execute on function public.admin_bulk_delete_devices(uuid[]) to authenticated;
grant execute on function public.admin_bulk_delete_subscriptions(uuid[]) to authenticated;
grant execute on function public.pos_owner_login_v3(text,text,text,text,text,text) to anon, authenticated;

-- Bulk subscriber/customer deletion. Uses the existing hardened single-delete routine.
create or replace function public.admin_bulk_delete_businesses(p_business_ids uuid[]) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  foreach v_id in array coalesce(p_business_ids, array[]::uuid[]) loop
    if exists(select 1 from public.businesses where id=v_id) then
      perform public.admin_delete_business(v_id);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.admin_bulk_delete_businesses(uuid[]) from public, anon;
grant execute on function public.admin_bulk_delete_businesses(uuid[]) to authenticated;
