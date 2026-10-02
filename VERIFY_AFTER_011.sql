-- Run after 011_release_hardening_messages_expiry.sql.
-- Every row should return passed = true.
select * from (
  select 'subscription_expiry_warning_column' as check_name,
         exists(select 1 from information_schema.columns where table_schema='public' and table_name='subscriptions' and column_name='expiry_warning_days') as passed
  union all select 'request_messages_table', to_regclass('public.subscription_request_messages') is not null
  union all select 'request_messages_rls', exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='subscription_request_messages' and c.relrowsecurity)
  union all select 'activation_attempts_table', to_regclass('public.pos_activation_attempts') is not null
  union all select 'activation_attempts_rls', exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='pos_activation_attempts' and c.relrowsecurity)
  union all select 'activate_v4_exists', to_regprocedure('public.pos_activate_device_v4(text,text,text,text,text,text)') is not null
  union all select 'pos_list_custom_requests_exists', to_regprocedure('public.pos_list_custom_plan_requests_v1(text,text,text)') is not null
  union all select 'pos_send_request_message_exists', to_regprocedure('public.pos_send_subscription_request_message_v1(text,text,text,uuid,text)') is not null
  union all select 'admin_send_request_message_exists', to_regprocedure('public.admin_send_subscription_request_message_v1(uuid,text)') is not null
  union all select 'admin_expiry_warning_exists', to_regprocedure('public.admin_set_subscription_expiry_warning_days(uuid,integer)') is not null
  union all select 'activate_v4_anon_allowed', has_function_privilege('anon','public.pos_activate_device_v4(text,text,text,text,text,text)','EXECUTE')
  union all select 'request_messages_anon_table_blocked', not has_table_privilege('anon','public.subscription_request_messages','SELECT')
  union all select 'activation_attempts_anon_table_blocked', not has_table_privilege('anon','public.pos_activation_attempts','SELECT')
  union all select 'admin_send_anon_blocked', not has_function_privilege('anon','public.admin_send_subscription_request_message_v1(uuid,text)','EXECUTE')
) checks
order by check_name;

select 'admin_subscription_request_unread_counts_v1_exists' as check_name,
       to_regprocedure('public.admin_subscription_request_unread_counts_v1()') is not null as passed;
