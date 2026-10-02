-- THAMAN Admin V1.4 / THAMAN POS V9.1
-- Real first-run device activation, heartbeat, device blocking and owner-only delete operations.
-- Run AFTER 001, 002, 003 and 004 in the same Supabase project.

alter table public.devices add column if not exists blocked boolean not null default false;
alter table public.devices add column if not exists blocked_at timestamptz;
alter table public.devices add column if not exists block_reason text not null default '';

create index if not exists idx_devices_blocked on public.devices(business_id, blocked);

-- Server-authoritative device allowance, including the configured grace period.
-- A suspended business can never activate/re-link devices.
create or replace function public.effective_device_limit(p_business_id uuid) returns integer
language sql stable security definer set search_path = public
as $$
  select coalesce(s.device_limit, p.max_devices)
  from public.subscriptions s
  join public.plans p on p.id = s.plan_id
  join public.businesses b on b.id = s.business_id
  cross join public.app_settings cfg
  where cfg.id = 1
    and s.business_id = p_business_id
    and b.status = 'active'
    and s.status in ('active','trial')
    and s.ends_at + make_interval(days => cfg.grace_period_days) > now()
  order by s.created_at desc
  limit 1;
$$;

-- A blocked device must never be activated even through a direct table update.
create or replace function public.enforce_device_limit() returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_limit integer;
  v_count integer;
begin
  if new.blocked is true and new.active is true then
    raise exception 'Blocked device cannot be activated';
  end if;
  if new.active is not true then return new; end if;

  v_limit := public.effective_device_limit(new.business_id);
  if v_limit is null then
    raise exception 'No active subscription allows device activation for this business';
  end if;

  if tg_op = 'UPDATE' then
    select count(*) into v_count
    from public.devices
    where business_id = new.business_id and (active = true or blocked = true) and id <> new.id;
  else
    select count(*) into v_count
    from public.devices
    where business_id = new.business_id and (active = true or blocked = true);
  end if;

  if v_count >= v_limit then
    raise exception 'Device limit reached (% active of % allowed)', v_count, v_limit;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_device_limit on public.devices;
create trigger trg_enforce_device_limit
before insert or update of active, business_id, blocked on public.devices
for each row execute function public.enforce_device_limit();

-- First-run activation endpoint used by THAMAN POS with the publishable key.
-- The activation code acts as the enrollment secret; the function never grants
-- direct CRUD access to licensing tables.
create or replace function public.pos_activate_device(
  p_activation_code text,
  p_device_uid text,
  p_device_name text,
  p_platform text,
  p_app_version text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_business_status text;
  v_subscription_status text;
  v_ends_at timestamptz;
  v_grace integer;
  v_limit integer;
  v_used integer;
  v_device_id uuid;
  v_blocked boolean;
  v_active boolean;
  v_effective_status text;
begin
  if coalesce(btrim(p_activation_code), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'activation_code_missing');
  end if;
  if coalesce(btrim(p_device_uid), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'device_uid_missing');
  end if;

  select
    b.id,
    s.id,
    b.status,
    s.status,
    s.ends_at,
    cfg.grace_period_days,
    coalesce(s.device_limit, p.max_devices)
  into
    v_business_id,
    v_subscription_id,
    v_business_status,
    v_subscription_status,
    v_ends_at,
    v_grace,
    v_limit
  from public.subscriptions s
  join public.businesses b on b.id = s.business_id
  join public.plans p on p.id = s.plan_id
  cross join public.app_settings cfg
  where cfg.id = 1
    and upper(s.activation_code) = upper(btrim(p_activation_code))
  order by s.created_at desc
  limit 1;

  if v_subscription_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_business_status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'business_suspended');
  end if;
  if v_subscription_status = 'suspended' then
    return jsonb_build_object('ok', false, 'error', 'subscription_suspended');
  end if;
  if v_subscription_status = 'pending' then
    return jsonb_build_object('ok', false, 'error', 'subscription_pending');
  end if;
  if v_subscription_status = 'expired' or v_ends_at + make_interval(days => coalesce(v_grace, 0)) <= now() then
    return jsonb_build_object('ok', false, 'error', 'subscription_expired');
  end if;
  if v_subscription_status not in ('active', 'trial') then
    return jsonb_build_object('ok', false, 'error', 'subscription_' || v_subscription_status);
  end if;

  v_effective_status := case when v_ends_at <= now() then 'grace' else v_subscription_status end;

  -- Serialize activation for one subscriber so two simultaneous requests cannot
  -- both pass the device-count check.
  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text, 0));

  -- One installation identity belongs to one subscriber record at a time. This
  -- prevents the same POS installation from being enrolled under two stores.
  if exists (
    select 1 from public.devices
    where device_uid = btrim(p_device_uid) and business_id <> v_business_id
  ) then
    return jsonb_build_object('ok', false, 'error', 'device_registered_elsewhere');
  end if;

  select id, blocked, active
    into v_device_id, v_blocked, v_active
  from public.devices
  where business_id = v_business_id and device_uid = btrim(p_device_uid)
  limit 1;

  if v_device_id is not null then
    if coalesce(v_blocked, false) then
      return jsonb_build_object('ok', false, 'error', 'device_blocked');
    end if;

    if not coalesce(v_active, false) then
      select count(*)::integer into v_used
      from public.devices
      where business_id = v_business_id and (active = true or blocked = true) and id <> v_device_id;
      if coalesce(v_used, 0) >= v_limit then
        return jsonb_build_object('ok', false, 'error', 'device_limit_reached', 'device_limit', v_limit, 'active_device_count', v_used);
      end if;
    end if;

    update public.devices
    set active = true,
        device_name = nullif(btrim(p_device_name), ''),
        platform = nullif(btrim(p_platform), ''),
        app_version = nullif(btrim(p_app_version), ''),
        last_seen_at = now()
    where id = v_device_id;
  else
    select count(*)::integer into v_used
    from public.devices
    where business_id = v_business_id and (active = true or blocked = true);
    if coalesce(v_used, 0) >= v_limit then
      return jsonb_build_object('ok', false, 'error', 'device_limit_reached', 'device_limit', v_limit, 'active_device_count', v_used);
    end if;

    insert into public.devices(
      business_id, device_uid, device_name, platform, app_version,
      last_seen_at, active, blocked
    ) values (
      v_business_id,
      btrim(p_device_uid),
      nullif(btrim(p_device_name), ''),
      nullif(btrim(p_platform), ''),
      nullif(btrim(p_app_version), ''),
      now(), true, false
    ) returning id into v_device_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'device_id', v_device_id,
    'business_id', v_business_id,
    'subscription_id', v_subscription_id,
    'effective_status', v_effective_status,
    'device_limit', v_limit
  );
end;
$$;

-- Lightweight server check performed when an already-activated POS starts.
create or replace function public.pos_device_heartbeat(
  p_activation_code text,
  p_device_uid text,
  p_app_version text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_business_status text;
  v_subscription_status text;
  v_ends_at timestamptz;
  v_grace integer;
  v_device_id uuid;
  v_active boolean;
  v_blocked boolean;
  v_effective_status text;
begin
  select
    b.id, s.id, b.status, s.status, s.ends_at, cfg.grace_period_days
  into
    v_business_id, v_subscription_id, v_business_status,
    v_subscription_status, v_ends_at, v_grace
  from public.subscriptions s
  join public.businesses b on b.id = s.business_id
  cross join public.app_settings cfg
  where cfg.id = 1
    and upper(s.activation_code) = upper(btrim(p_activation_code))
  order by s.created_at desc
  limit 1;

  if v_subscription_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_business_status <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'business_suspended');
  end if;
  if v_subscription_status = 'suspended' then
    return jsonb_build_object('ok', false, 'error', 'subscription_suspended');
  end if;
  if v_subscription_status = 'pending' then
    return jsonb_build_object('ok', false, 'error', 'subscription_pending');
  end if;
  if v_subscription_status = 'expired' or v_ends_at + make_interval(days => coalesce(v_grace, 0)) <= now() then
    return jsonb_build_object('ok', false, 'error', 'subscription_expired');
  end if;
  if v_subscription_status not in ('active', 'trial') then
    return jsonb_build_object('ok', false, 'error', 'subscription_' || v_subscription_status);
  end if;

  select id, active, blocked
    into v_device_id, v_active, v_blocked
  from public.devices
  where business_id = v_business_id and device_uid = btrim(p_device_uid)
  limit 1;

  if v_device_id is null then
    return jsonb_build_object('ok', false, 'error', 'device_not_registered');
  end if;
  if coalesce(v_blocked, false) then
    return jsonb_build_object('ok', false, 'error', 'device_blocked');
  end if;
  if not coalesce(v_active, false) then
    return jsonb_build_object('ok', false, 'error', 'device_unlinked');
  end if;

  update public.devices
  set last_seen_at = now(),
      app_version = coalesce(nullif(btrim(p_app_version), ''), app_version)
  where id = v_device_id;

  v_effective_status := case when v_ends_at <= now() then 'grace' else v_subscription_status end;
  return jsonb_build_object('ok', true, 'effective_status', v_effective_status, 'device_id', v_device_id);
end;
$$;

-- Include the blocked state in the POS subscription/device view.
create or replace function public.pos_subscription_status(p_activation_code text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with matched as (
    select
      s.id as subscription_id,
      s.activation_code,
      s.starts_at,
      s.ends_at,
      s.status as subscription_status,
      s.auto_renew,
      coalesce(s.device_limit, p.max_devices) as device_limit,
      b.id as business_id,
      b.account_no,
      b.owner_name,
      b.name as business_name,
      b.status as business_status,
      p.name as plan_name,
      p.code as plan_code,
      p.billing_cycle,
      p.price,
      cfg.expiry_warning_days,
      cfg.grace_period_days
    from public.subscriptions s
    join public.businesses b on b.id = s.business_id
    join public.plans p on p.id = s.plan_id
    cross join public.app_settings cfg
    where cfg.id = 1
      and upper(s.activation_code) = upper(btrim(p_activation_code))
    order by s.created_at desc
    limit 1
  )
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'subscription_id', m.subscription_id,
        'activation_code', m.activation_code,
        'account_no', m.account_no,
        'subscriber_name', coalesce(nullif(m.owner_name, ''), m.business_name),
        'business_name', m.business_name,
        'business_status', m.business_status,
        'plan_name', m.plan_name,
        'plan_code', m.plan_code,
        'billing_cycle', m.billing_cycle,
        'price', m.price,
        'starts_at', m.starts_at,
        'ends_at', m.ends_at,
        'subscription_status', m.subscription_status,
        'effective_status', case
          when m.business_status <> 'active' then 'suspended'
          when m.subscription_status in ('suspended', 'pending') then m.subscription_status
          when m.ends_at + make_interval(days => m.grace_period_days) <= now() then 'expired'
          when m.ends_at <= now() then 'grace'
          else m.subscription_status
        end,
        'auto_renew', m.auto_renew,
        'device_limit', m.device_limit,
        'active_device_count', (
          select count(*)::integer from public.devices d
          where d.business_id = m.business_id and d.active = true
        ),
        'expiry_warning_days', m.expiry_warning_days,
        'grace_period_days', m.grace_period_days,
        'devices', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', d.id,
              'name', coalesce(nullif(d.device_name, ''), 'THAMAN Device'),
              'platform', coalesce(d.platform, ''),
              'app_version', coalesce(d.app_version, ''),
              'active', d.active,
              'blocked', d.blocked,
              'last_seen_at', d.last_seen_at
            ) order by d.created_at desc
          )
          from public.devices d
          where d.business_id = m.business_id
        ), '[]'::jsonb)
      )
      from matched m
    ),
    jsonb_build_object('ok', false, 'error', 'not_found')
  );
$$;

-- Owner-only admin controls. Using RPCs keeps dependent cleanup and audit logging
-- consistent instead of relying on ad-hoc client deletes.
create or replace function public.admin_set_device_blocked(
  p_device_id uuid,
  p_blocked boolean,
  p_reason text default ''
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_business_id uuid;
  v_name text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id, coalesce(nullif(device_name, ''), device_uid)
    into v_business_id, v_name
  from public.devices where id = p_device_id;
  if v_business_id is null then raise exception 'Device not found'; end if;

  update public.devices
  set blocked = coalesce(p_blocked, false),
      blocked_at = case when coalesce(p_blocked, false) then now() else null end,
      block_reason = case when coalesce(p_blocked, false) then coalesce(p_reason, '') else '' end,
      active = case when coalesce(p_blocked, false) then false else active end
  where id = p_device_id;

  insert into public.activity(admin_user_id, business_id, action, description)
  values (
    auth.uid(), v_business_id,
    case when coalesce(p_blocked, false) then 'device_blocked' else 'device_unblocked' end,
    case when coalesce(p_blocked, false)
      then 'تم حظر الجهاز ' || coalesce(v_name, '')
      else 'تم فك حظر الجهاز ' || coalesce(v_name, '') || ' (يبقى مفصولًا حتى إعادة الربط)'
    end
  );
end;
$$;

create or replace function public.admin_delete_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_business_id uuid;
  v_name text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id, coalesce(nullif(device_name, ''), device_uid)
    into v_business_id, v_name from public.devices where id = p_device_id;
  if v_business_id is null then raise exception 'Device not found'; end if;
  delete from public.devices where id = p_device_id;
  insert into public.activity(admin_user_id, business_id, action, description)
  values (auth.uid(), v_business_id, 'device_deleted', 'تم حذف الجهاز ' || coalesce(v_name, ''));
end;
$$;

create or replace function public.admin_delete_subscription(p_subscription_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_business_id uuid;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id into v_business_id from public.subscriptions where id = p_subscription_id;
  if v_business_id is null then raise exception 'Subscription not found'; end if;

  delete from public.subscriptions where id = p_subscription_id;

  if not exists (
    select 1 from public.subscriptions s cross join public.app_settings cfg
    where cfg.id = 1 and s.business_id = v_business_id
      and s.status in ('active','trial')
      and s.ends_at + make_interval(days => cfg.grace_period_days) > now()
  ) then
    update public.businesses set status = 'suspended' where id = v_business_id;
    update public.devices set active = false where business_id = v_business_id and active = true;
  end if;

  insert into public.activity(admin_user_id, business_id, action, description)
  values (auth.uid(), v_business_id, 'subscription_deleted', 'تم حذف الاشتراك');
end;
$$;

create or replace function public.admin_delete_payment(p_payment_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_business_id uuid;
  v_amount numeric;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id, amount into v_business_id, v_amount from public.payments where id = p_payment_id;
  if v_business_id is null then raise exception 'Payment not found'; end if;
  delete from public.payments where id = p_payment_id;
  insert into public.activity(admin_user_id, business_id, action, description)
  values (auth.uid(), v_business_id, 'payment_deleted', 'تم حذف دفعة بقيمة ' || coalesce(v_amount::text, '0'));
end;
$$;

create or replace function public.admin_delete_plan(p_plan_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select name into v_name from public.plans where id = p_plan_id;
  if v_name is null then raise exception 'Plan not found'; end if;
  if exists (select 1 from public.subscriptions where plan_id = p_plan_id) then
    raise exception 'Plan is in use by subscriptions; delete or move those subscriptions first';
  end if;
  delete from public.plans where id = p_plan_id;
  insert into public.activity(admin_user_id, business_id, action, description)
  values (auth.uid(), null, 'plan_deleted', 'تم حذف الباقة ' || v_name);
end;
$$;

create or replace function public.admin_delete_business(p_business_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
  v_account_no text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select coalesce(nullif(owner_name, ''), name), account_no
    into v_name, v_account_no
  from public.businesses where id = p_business_id;
  if v_name is null then raise exception 'Subscriber not found'; end if;

  -- Keep activity history; its FK becomes NULL when the business is removed.
  delete from public.payments where business_id = p_business_id;
  delete from public.devices where business_id = p_business_id;
  delete from public.subscriptions where business_id = p_business_id;
  delete from public.businesses where id = p_business_id;

  insert into public.activity(admin_user_id, business_id, action, description)
  values (auth.uid(), null, 'subscriber_deleted', 'تم حذف المشترك ' || v_name || ' • ' || coalesce(v_account_no, ''));
end;
$$;

revoke all on function public.pos_activate_device(text,text,text,text,text) from public;
revoke all on function public.pos_device_heartbeat(text,text,text) from public;
revoke all on function public.pos_subscription_status(text) from public;
grant execute on function public.pos_activate_device(text,text,text,text,text) to anon, authenticated;
grant execute on function public.pos_device_heartbeat(text,text,text) to anon, authenticated;
grant execute on function public.pos_subscription_status(text) to anon, authenticated;

revoke all on function public.admin_set_device_blocked(uuid,boolean,text) from public;
revoke all on function public.admin_delete_device(uuid) from public;
revoke all on function public.admin_delete_subscription(uuid) from public;
revoke all on function public.admin_delete_payment(uuid) from public;
revoke all on function public.admin_delete_plan(uuid) from public;
revoke all on function public.admin_delete_business(uuid) from public;
grant execute on function public.admin_set_device_blocked(uuid,boolean,text) to authenticated;
grant execute on function public.admin_delete_device(uuid) to authenticated;
grant execute on function public.admin_delete_subscription(uuid) to authenticated;
grant execute on function public.admin_delete_payment(uuid) to authenticated;
grant execute on function public.admin_delete_plan(uuid) to authenticated;
grant execute on function public.admin_delete_business(uuid) to authenticated;
