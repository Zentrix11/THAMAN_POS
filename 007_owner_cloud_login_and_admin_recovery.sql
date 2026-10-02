-- THAMAN POS V9.3 / THAMAN Admin V1.6
-- Cloud owner identity, multi-device owner login and THAMAN Admin recovery controls.
-- Run AFTER 006_offers_and_subscription_requests.sql.

create extension if not exists pgcrypto with schema extensions;

-- Cleanup from the unreleased email-code recovery draft, if it was ever tested.
drop function if exists public.service_issue_pos_owner_reset(text,text);
drop function if exists public.pos_complete_owner_password_reset(text,text,text);
drop table if exists public.pos_owner_password_resets;

create table if not exists public.pos_owner_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null unique references public.businesses(id) on delete cascade,
  display_name text not null,
  phone text not null default '',
  email text not null,
  password_hash text not null,
  pin_hash text not null,
  active boolean not null default true,
  must_change_password boolean not null default false,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_pos_owner_accounts_email_lower
  on public.pos_owner_accounts(lower(email));
create index if not exists idx_pos_owner_accounts_business
  on public.pos_owner_accounts(business_id);


alter table public.pos_owner_accounts enable row level security;

revoke all on table public.pos_owner_accounts from anon, authenticated;
grant select on table public.pos_owner_accounts to authenticated;

drop policy if exists thaman_admin_read_pos_owner_accounts on public.pos_owner_accounts;
create policy thaman_admin_read_pos_owner_accounts
  on public.pos_owner_accounts
  for select to authenticated
  using (public.is_thaman_owner());

create or replace function public.pos_valid_business_for_device(
  p_activation_code text,
  p_device_uid text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_subscription_status text;
  v_business_status text;
  v_ends_at timestamptz;
  v_grace integer;
  v_device_active boolean;
  v_device_blocked boolean;
begin
  select b.id, b.status, s.status, s.ends_at, cfg.grace_period_days
  into v_business_id, v_business_status, v_subscription_status, v_ends_at, v_grace
  from public.subscriptions s
  join public.businesses b on b.id = s.business_id
  cross join public.app_settings cfg
  where cfg.id = 1
    and upper(s.activation_code) = upper(btrim(p_activation_code))
  order by s.created_at desc
  limit 1;

  if v_business_id is null then raise exception 'not_found'; end if;
  if v_business_status <> 'active' then raise exception 'business_suspended'; end if;
  if v_subscription_status = 'suspended' then raise exception 'subscription_suspended'; end if;
  if v_subscription_status = 'pending' then raise exception 'subscription_pending'; end if;
  if v_subscription_status not in ('active','trial') then raise exception 'subscription_%', v_subscription_status; end if;
  if v_ends_at + make_interval(days => coalesce(v_grace,0)) <= now() then raise exception 'subscription_expired'; end if;

  select active, blocked into v_device_active, v_device_blocked
  from public.devices
  where business_id = v_business_id and device_uid = btrim(p_device_uid)
  limit 1;

  if v_device_active is null then raise exception 'device_not_registered'; end if;
  if coalesce(v_device_blocked,false) then raise exception 'device_blocked'; end if;
  if not coalesce(v_device_active,false) then raise exception 'device_unlinked'; end if;

  return v_business_id;
end;
$$;

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
    'business_id', v_business_id,
    'owner_id', v_owner.id,
    'display_name', v_owner.display_name,
    'phone', v_owner.phone,
    'email', v_owner.email,
    'active', v_owner.active,
    'must_change_password', v_owner.must_change_password,
    'last_login_at', v_owner.last_login_at
  );
end;
$$;

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
set search_path = public
as $$
declare
  v_business_id uuid;
  v_owner_id uuid;
  v_email text := lower(btrim(p_email));
begin
  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code, p_device_uid);
  exception when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
  end;

  if coalesce(btrim(p_display_name),'') = '' then return jsonb_build_object('ok',false,'error','owner_name_missing'); end if;
  if v_email = '' or position('@' in v_email) < 2 then return jsonb_build_object('ok',false,'error','email_invalid'); end if;
  if length(coalesce(p_password,'')) < 8 then return jsonb_build_object('ok',false,'error','password_short'); end if;
  if coalesce(p_pin,'') !~ '^[0-9]{4}$' then return jsonb_build_object('ok',false,'error','pin_invalid'); end if;

  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text, 91));

  if exists(select 1 from public.pos_owner_accounts where business_id = v_business_id) then
    return jsonb_build_object('ok', false, 'error', 'owner_already_exists');
  end if;
  if exists(select 1 from public.pos_owner_accounts where lower(email) = v_email) then
    return jsonb_build_object('ok', false, 'error', 'email_already_used');
  end if;

  insert into public.pos_owner_accounts(
    business_id, display_name, phone, email, password_hash, pin_hash
  ) values (
    v_business_id,
    btrim(p_display_name),
    coalesce(btrim(p_phone),''),
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    extensions.crypt(p_pin, extensions.gen_salt('bf', 10))
  ) returning id into v_owner_id;

  update public.businesses
  set owner_name = btrim(p_display_name),
      phone = case when coalesce(btrim(p_phone),'') = '' then phone else btrim(p_phone) end,
      email = v_email
  where id = v_business_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(null,v_business_id,'pos_owner_created','تم إنشاء حساب مالك THAMAN POS السحابي',jsonb_build_object('owner_id',v_owner_id,'email',v_email));

  return jsonb_build_object('ok', true, 'owner_id', v_owner_id, 'business_id', v_business_id);
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
    and lower(email) = lower(btrim(p_email))
  limit 1;

  if v_owner.id is null or not v_owner.active or extensions.crypt(coalesce(p_password,''), v_owner.password_hash) <> v_owner.password_hash then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  update public.pos_owner_accounts set last_login_at = now(), updated_at = now() where id = v_owner.id;

  return jsonb_build_object(
    'ok', true,
    'owner_id', v_owner.id,
    'business_id', v_business_id,
    'role', 'owner',
    'display_name', v_owner.display_name,
    'phone', v_owner.phone,
    'email', v_owner.email,
    'must_change_password', v_owner.must_change_password
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
set search_path = public
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
begin
  if length(coalesce(p_new_password,'')) < 8 then
    return jsonb_build_object('ok', false, 'error', 'password_short');
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

  if v_owner.id is null or extensions.crypt(coalesce(p_current_password,''), v_owner.password_hash) <> v_owner.password_hash then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  update public.pos_owner_accounts
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
      must_change_password = false,
      updated_at = now()
  where id = v_owner.id;


  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(null,v_business_id,'pos_owner_password_changed','تم تغيير كلمة مرور مالك THAMAN POS بعد الدخول بكلمة مؤقتة',jsonb_build_object('owner_id',v_owner.id));

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.admin_reset_pos_owner_password(
  p_business_id uuid,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.pos_owner_accounts%rowtype;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  if length(coalesce(p_new_password,'')) < 8 then raise exception 'Password must be at least 8 characters'; end if;

  select * into v_owner from public.pos_owner_accounts where business_id = p_business_id limit 1;
  if v_owner.id is null then raise exception 'POS owner account not found'; end if;

  update public.pos_owner_accounts
  set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
      must_change_password = true,
      updated_at = now()
  where id = v_owner.id;


  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(),p_business_id,'admin_reset_pos_owner_password','تم تعيين كلمة مرور مؤقتة لحساب مالك THAMAN POS',jsonb_build_object('owner_id',v_owner.id));

  return jsonb_build_object('ok', true, 'email', v_owner.email, 'display_name', v_owner.display_name);
end;
$$;

create or replace function public.admin_reset_pos_owner_pin(
  p_business_id uuid,
  p_new_pin text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.pos_owner_accounts%rowtype;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  if coalesce(p_new_pin,'') !~ '^[0-9]{4}$' then raise exception 'PIN must be exactly 4 digits'; end if;
  select * into v_owner from public.pos_owner_accounts where business_id = p_business_id limit 1;
  if v_owner.id is null then raise exception 'POS owner account not found'; end if;

  update public.pos_owner_accounts
  set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)), updated_at = now()
  where id = v_owner.id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(),p_business_id,'admin_reset_pos_owner_pin','تم إعادة تعيين PIN لمالك THAMAN POS',jsonb_build_object('owner_id',v_owner.id));

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.pos_valid_business_for_device(text,text) from public;
revoke all on function public.pos_owner_status(text,text) from public;
revoke all on function public.pos_provision_owner(text,text,text,text,text,text,text) from public;
revoke all on function public.pos_owner_login(text,text,text,text) from public;
revoke all on function public.pos_change_owner_password(text,text,text,text,text) from public;
revoke all on function public.admin_reset_pos_owner_password(uuid,text) from public;
revoke all on function public.admin_reset_pos_owner_pin(uuid,text) from public;

grant execute on function public.pos_owner_status(text,text) to anon, authenticated;
grant execute on function public.pos_provision_owner(text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.pos_owner_login(text,text,text,text) to anon, authenticated;
grant execute on function public.pos_change_owner_password(text,text,text,text,text) to anon, authenticated;
grant execute on function public.admin_reset_pos_owner_password(uuid,text) to authenticated;
grant execute on function public.admin_reset_pos_owner_pin(uuid,text) to authenticated;
