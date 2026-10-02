-- THAMAN migration 010 verification
-- Run after 010_custom_plans_device_subscription_and_email_requests.sql
-- Every row should have passed = true.

with checks as (
  select 1 as ord, 'plans.is_custom'::text as test_name,
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='plans' and column_name='is_custom') as passed,
    'private/public plan flag'::text as details
  union all select 2, 'plans.custom_business_id',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='plans' and column_name='custom_business_id'),
    'subscriber scope for a custom plan'
  union all select 3, 'plans.custom_duration_days',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='plans' and column_name='custom_duration_days'),
    'custom duration'
  union all select 4, 'devices.subscription_id',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='devices' and column_name='subscription_id'),
    'exact device to subscription link'
  union all select 5, 'subscription_requests.requested_duration_days',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscription_requests' and column_name='requested_duration_days'),
    'custom request duration'
  union all select 6, 'subscription_requests.requested_device_limit',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscription_requests' and column_name='requested_device_limit'),
    'custom request devices'
  union all select 7, 'subscription_requests.requested_budget',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscription_requests' and column_name='requested_budget'),
    'custom request budget'
  union all select 8, 'subscription_requests.contact_email',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscription_requests' and column_name='contact_email'),
    'custom request contact email'
  union all select 9, 'subscription_requests.contact_phone',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscription_requests' and column_name='contact_phone'),
    'custom request contact phone'
  union all select 10, 'subscription_requests.email_notified_at',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscription_requests' and column_name='email_notified_at'),
    'mail delivery marker'
  union all select 11, 'admin_apply_custom_plan RPC',
    to_regprocedure('public.admin_apply_custom_plan(uuid,text,integer,integer,numeric,text,timestamptz)') is not null,
    'Admin can create/apply private plan'
  union all select 12, 'pos_create_custom_plan_request_v2 RPC',
    to_regprocedure('public.pos_create_custom_plan_request_v2(text,text,text,integer,integer,numeric,text,text,text)') is not null,
    'POS proof-aware custom request'
  union all select 13, 'pos_available_plans_v2 RPC',
    to_regprocedure('public.pos_available_plans_v2(text,text,text)') is not null,
    'proof-aware catalog remains available'
  union all select 14, 'pos_activate_device_v3 RPC',
    to_regprocedure('public.pos_activate_device_v3(text,text,text,text,text,text)') is not null,
    'activation remains proof-aware and binds subscription'
  union all select 15, 'pos_device_heartbeat_v3 RPC',
    to_regprocedure('public.pos_device_heartbeat_v3(text,text,text,text)') is not null,
    'heartbeat remains proof-aware and maintains subscription link'
  union all select 16, 'billing_cycle allows custom',
    exists(
      select 1 from pg_constraint c
      join pg_class t on t.oid=c.conrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public' and t.relname='plans' and c.conname='plans_billing_cycle_check'
        and pg_get_constraintdef(c.oid) like '%custom%'
    ),
    'plans check constraint contains custom'
  union all select 17, 'request_type allows custom',
    exists(
      select 1 from pg_constraint c
      join pg_class t on t.oid=c.conrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public' and t.relname='subscription_requests' and c.conname='subscription_requests_request_type_check'
        and pg_get_constraintdef(c.oid) like '%custom%'
    ),
    'request check constraint contains custom'
  union all select 18, 'admin custom-plan RPC is not executable by anon',
    not has_function_privilege('anon', 'public.admin_apply_custom_plan(uuid,text,integer,integer,numeric,text,timestamptz)', 'EXECUTE'),
    'Admin-only mutation is protected'
  union all select 19, 'POS custom request executable by anon',
    has_function_privilege('anon', 'public.pos_create_custom_plan_request_v2(text,text,text,integer,integer,numeric,text,text,text)', 'EXECUTE'),
    'POS can invoke the proof-aware endpoint with publishable key'
  union all select 20, 'subscription_requests RLS enabled',
    coalesce((select relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='subscription_requests'), false),
    'request table remains private behind RLS/RPC'
  union all select 21, 'legacy plan request RPC is not executable by anon',
    not has_function_privilege('anon', 'public.pos_create_subscription_request(text,text,text,uuid,text)', 'EXECUTE'),
    'only the proof-aware v2 request wrapper stays public'
)
select test_name, passed, details from checks order by ord;
