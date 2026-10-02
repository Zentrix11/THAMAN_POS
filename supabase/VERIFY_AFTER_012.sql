-- THAMAN Production verification after migration 012.
-- Every row should return passed = true before release.
with checks as (
  select
    'temporary_password_expiry_columns'::text as check_name,
    (select count(*) = 3
       from information_schema.columns
      where table_schema='public' and table_name='pos_owner_accounts'
        and column_name in ('temporary_password_set_at','temporary_password_expires_at','temporary_password_set_by')) as passed,
    '3 owner recovery audit/expiry columns'::text as detail

  union all select
    'temporary_passwords_are_bounded',
    not exists(
      select 1 from public.pos_owner_accounts
       where must_change_password=true and temporary_password_expires_at is null
    ),
    'no active temporary owner password may remain without an expiry timestamp'

  union all select
    'admin_reset_rpc_present',
    to_regprocedure('public.admin_reset_pos_owner_password(uuid,text)') is not null,
    'temporary password reset RPC exists'

  union all select
    'admin_reset_rpc_acl',
    has_function_privilege('authenticated','public.admin_reset_pos_owner_password(uuid,text)','EXECUTE')
      and not has_function_privilege('anon','public.admin_reset_pos_owner_password(uuid,text)','EXECUTE'),
    'only authenticated admin path can execute owner reset'

  union all select
    'owner_login_base_not_public',
    not has_function_privilege('anon','public.pos_owner_login(text,text,text,text)','EXECUTE')
      and not has_function_privilege('authenticated','public.pos_owner_login(text,text,text,text)','EXECUTE'),
    'clients must use proof-aware login wrapper'

  union all select
    'activation_v4_present',
    to_regprocedure('public.pos_activate_device_v4(text,text,text,text,text,text)') is not null,
    'proof-aware hardened activation RPC exists'

  union all select
    'activation_v4_client_acl',
    has_function_privilege('anon','public.pos_activate_device_v4(text,text,text,text,text,text)','EXECUTE'),
    'POS can call hardened activation endpoint'

  union all select
    'activation_fingerprint_index',
    exists(
      select 1 from pg_indexes
       where schemaname='public' and tablename='pos_activation_attempts'
         and indexname='idx_pos_activation_attempts_fingerprint'
    ),
    'activation-code fingerprint throttling index exists'

  union all select
    'message_owner_rate_index',
    exists(
      select 1 from pg_indexes
       where schemaname='public' and tablename='subscription_request_messages'
         and indexname='idx_subscription_request_messages_rate'
    ),
    'request message rate-limit index exists'

  union all select
    'message_table_rls',
    coalesce((select relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='public' and c.relname='subscription_request_messages'),false),
    'message table has row-level security enabled'

  union all select
    'admin_realtime_policy',
    exists(
      select 1 from pg_policies
       where schemaname='public' and tablename='subscription_request_messages'
         and policyname='thaman_admin_realtime_read_subscription_messages'
    ),
    'authenticated THAMAN owner policy exists for safe admin realtime'

  union all select
    'message_admin_rpc_acl',
    has_function_privilege('authenticated','public.admin_send_subscription_request_message_v1(uuid,text)','EXECUTE')
      and not has_function_privilege('anon','public.admin_send_subscription_request_message_v1(uuid,text)','EXECUTE'),
    'only authenticated admin can use admin send-message RPC'

  union all select
    'message_owner_rpc_acl',
    has_function_privilege('anon','public.pos_send_subscription_request_message_v1(text,text,text,uuid,text)','EXECUTE'),
    'POS can send request-scoped owner messages through proof-aware RPC'

  union all select
    'expiry_warning_column',
    exists(
      select 1 from information_schema.columns
       where table_schema='public' and table_name='subscriptions' and column_name='expiry_warning_days'
    ),
    'per-subscription expiry warning lead time exists'

  union all select
    'realtime_publication_message_table',
    exists(
      select 1 from pg_publication_tables
       where pubname='supabase_realtime' and schemaname='public' and tablename='subscription_request_messages'
    ),
    'admin message table is included in Supabase Realtime publication'
)
select check_name, passed, detail
from checks
order by check_name;
