-- THAMAN FINAL SECURITY VERIFICATION (read-only)
-- Run AFTER migration 009. Every row should return passed = true.

with checks(check_name, passed) as (
  select 'device_proof_column', exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='devices' and column_name='device_proof_hash'
  )
  union all select 'strict_resolver_exists', to_regprocedure('public.pos_resolve_active_device_v2(text,text,text)') is not null
  union all select 'new_activation_anon_allowed', has_function_privilege('anon', 'public.pos_activate_device_v3(text,text,text,text,text,text)', 'EXECUTE')
  union all select 'old_activation_anon_blocked', not has_function_privilege('anon', 'public.pos_activate_device(text,text,text,text,text)', 'EXECUTE')
  union all select 'new_owner_login_anon_allowed', has_function_privilege('anon', 'public.pos_owner_login_v2(text,text,text,text,text)', 'EXECUTE')
  union all select 'old_owner_login_anon_blocked', not has_function_privilege('anon', 'public.pos_owner_login(text,text,text,text)', 'EXECUTE')
  union all select 'admin_delete_anon_blocked', not has_function_privilege('anon', 'public.admin_delete_business(uuid)', 'EXECUTE')
  union all select 'admin_delete_authenticated_allowed', has_function_privilege('authenticated', 'public.admin_delete_business(uuid)', 'EXECUTE')
  union all select 'store_state_rls', exists(
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='pos_store_state' and c.relrowsecurity
  )
  union all select 'owner_attempts_rls', exists(
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='pos_owner_login_attempts' and c.relrowsecurity
  )
  union all select 'pgcrypto_in_extensions', exists(
    select 1 from pg_catalog.pg_extension e
    join pg_catalog.pg_namespace n on n.oid=e.extnamespace
    where e.extname='pgcrypto' and n.nspname='extensions'
  )
)
select check_name, passed
from checks
order by check_name;
