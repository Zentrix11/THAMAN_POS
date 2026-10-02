-- THAMAN SQL 014 verification
select * from (
  values
    ('admin_delete_plan(uuid)', to_regprocedure('public.admin_delete_plan(uuid)') is not null),
    ('pos_available_plans_v3(text,text,text)', to_regprocedure('public.pos_available_plans_v3(text,text,text)') is not null),
    ('devices.admin_locked', exists(select 1 from information_schema.columns where table_schema='public' and table_name='devices' and column_name='admin_locked')),
    ('owner PIN RPC v3', to_regprocedure('public.pos_owner_login_v3(text,text,text,text,text,text)') is not null)
) as checks(check_name, ok)
order by check_name;
