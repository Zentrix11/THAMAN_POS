-- THAMAN POS V9.0 - read-only subscription center endpoint.
-- Run after THAMAN Admin migrations 001, 002 and 003 in the SAME Supabase project.
-- This endpoint exposes only the current subscriber's licensing metadata when
-- the caller knows that subscription's activation code. It does not grant CRUD
-- access to the underlying admin tables.

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

revoke all on function public.pos_subscription_status(text) from public;
grant execute on function public.pos_subscription_status(text) to anon, authenticated;
