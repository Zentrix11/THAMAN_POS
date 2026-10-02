-- THAMAN SQL 013 verification (run after 001..013)
select 'owner_login_v3' test, to_regprocedure('public.pos_owner_login_v3(text,text,text,text,text,text)') is not null ok
union all select 'device_admin_lock_column', exists(select 1 from information_schema.columns where table_schema='public' and table_name='devices' and column_name='admin_locked')
union all select 'device_admin_lock_time', exists(select 1 from information_schema.columns where table_schema='public' and table_name='devices' and column_name='admin_locked_at')
union all select 'device_active_v2', to_regprocedure('public.admin_set_device_active_v2(uuid,boolean)') is not null
union all select 'bulk_devices', to_regprocedure('public.admin_bulk_delete_devices(uuid[])') is not null
union all select 'bulk_subscriptions', to_regprocedure('public.admin_bulk_delete_subscriptions(uuid[])') is not null
union all select 'bulk_businesses', to_regprocedure('public.admin_bulk_delete_businesses(uuid[])') is not null
union all select 'owner_provision_override', to_regprocedure('public.pos_provision_owner(text,text,text,text,text,text,text)') is not null
union all select 'owner_password_change_override', to_regprocedure('public.pos_change_owner_password(text,text,text,text,text)') is not null
union all select 'admin_owner_password_reset_override', to_regprocedure('public.admin_reset_pos_owner_password(uuid,text)') is not null
union all select 'subscription_delete_override', to_regprocedure('public.admin_delete_subscription(uuid)') is not null
union all select 'activation_v4_override', to_regprocedure('public.pos_activate_device_v4(text,text,text,text,text,text)') is not null;
