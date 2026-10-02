-- THAMAN SQL 016 - RC4 delete compatibility + owner password reset support
-- Run AFTER 015_rc3_admin_delete_and_recovery_fix.sql

-- ---------------------------------------------------------------------------
-- 1) Fix subscription deletion. RC3 accidentally referenced a legacy relation
--    named subscription_change_requests. The real table is subscription_requests.
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

  select business_id into v_business_id
  from public.subscriptions
  where id = p_subscription_id;

  if v_business_id is null then raise exception 'Subscription not found'; end if;

  update public.payments
     set subscription_id = null
   where subscription_id = p_subscription_id;

  update public.devices
     set subscription_id = null,
         active = false,
         updated_at = now()
   where subscription_id = p_subscription_id;

  -- The production schema uses subscription_requests. Keep this guarded so
  -- installations missing migration 006 do not fail during deletion.
  if to_regclass('public.subscription_requests') is not null then
    execute 'update public.subscription_requests set current_subscription_id = null, updated_at = now() where current_subscription_id = $1'
      using p_subscription_id;
  end if;

  delete from public.subscriptions where id = p_subscription_id;

  if not exists(select 1 from public.subscriptions where business_id = v_business_id) then
    update public.devices set active = false, updated_at = now() where business_id = v_business_id;
    delete from public.pos_owner_accounts where business_id = v_business_id;
    update public.businesses
       set status = 'archived', email = null, updated_at = now()
     where id = v_business_id;
  end if;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(
    auth.uid(), v_business_id, 'subscription_deleted',
    'تم حذف الاشتراك بأمان وفك المراجع المرتبطة به',
    jsonb_build_object('subscription_id', p_subscription_id)
  );
end;
$$;

create or replace function public.admin_delete_device(p_device_id uuid) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_name text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;

  select business_id, coalesce(nullif(device_name,''), device_uid)
    into v_business_id, v_name
    from public.devices
   where id = p_device_id;

  if v_business_id is null then raise exception 'Device not found'; end if;

  delete from public.devices where id = p_device_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(), v_business_id, 'device_deleted', 'تم حذف الجهاز بأمان', jsonb_build_object('device_id',p_device_id,'device_name',v_name));
end;
$$;

create or replace function public.admin_bulk_delete_devices(p_device_ids uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_count integer := 0;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  foreach v_id in array coalesce(p_device_ids,array[]::uuid[]) loop
    if exists(select 1 from public.devices where id=v_id) then
      perform public.admin_delete_device(v_id);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

create or replace function public.admin_bulk_delete_subscriptions(p_subscription_ids uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_count integer := 0;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  foreach v_id in array coalesce(p_subscription_ids,array[]::uuid[]) loop
    if exists(select 1 from public.subscriptions where id=v_id) then
      perform public.admin_delete_subscription(v_id);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.admin_delete_subscription(uuid) from public, anon;
revoke all on function public.admin_delete_device(uuid) from public, anon;
revoke all on function public.admin_bulk_delete_devices(uuid[]) from public, anon;
revoke all on function public.admin_bulk_delete_subscriptions(uuid[]) from public, anon;
grant execute on function public.admin_delete_subscription(uuid) to authenticated;
grant execute on function public.admin_delete_device(uuid) to authenticated;
grant execute on function public.admin_bulk_delete_devices(uuid[]) to authenticated;
grant execute on function public.admin_bulk_delete_subscriptions(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Owner self-service password reset token store.
--    Token generation + email delivery is performed by the packaged Edge
--    Function owner-password-reset using the service-role key.
-- ---------------------------------------------------------------------------
create table if not exists public.pos_owner_password_resets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.pos_owner_accounts(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  requested_at timestamptz not null default now(),
  request_ip text,
  user_agent text
);

create index if not exists idx_pos_owner_password_resets_owner
  on public.pos_owner_password_resets(owner_id, requested_at desc);
create index if not exists idx_pos_owner_password_resets_expiry
  on public.pos_owner_password_resets(expires_at);

alter table public.pos_owner_password_resets enable row level security;
revoke all on table public.pos_owner_password_resets from anon, authenticated;

create or replace function public.owner_password_reset_complete_v1(
  p_request_id uuid,
  p_new_password text
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_owner_id uuid;
begin
  -- Edge Function invokes this with the service-role key. Do not expose to
  -- normal authenticated or anonymous clients.
  if coalesce(p_new_password,'') = '' then raise exception 'password_required'; end if;

  select owner_id into v_owner_id
  from public.pos_owner_password_resets
  where id = p_request_id
    and used_at is null
    and expires_at > now()
  for update;

  if v_owner_id is null then return false; end if;

  update public.pos_owner_accounts
     set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf',12)),
         must_change_password = false,
         temporary_password_set_at = null,
         temporary_password_expires_at = null,
         temporary_password_set_by = null,
         updated_at = now()
   where id = v_owner_id;

  update public.pos_owner_password_resets
     set used_at = now()
   where id = p_request_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  select null, business_id, 'owner_self_password_reset', 'تم تغيير كلمة مرور المالك من رابط الاستعادة الآمن', jsonb_build_object('owner_id',id)
  from public.pos_owner_accounts where id = v_owner_id;

  return true;
end;
$$;

revoke all on function public.owner_password_reset_complete_v1(uuid,text) from public, anon, authenticated;
grant execute on function public.owner_password_reset_complete_v1(uuid,text) to service_role;

notify pgrst, 'reload schema';
