-- THAMAN verify after SQL 017
select
  to_regprocedure('public.pos_owner_login_v3(text,text,text,text,text,text)') is not null
    as owner_login_v3_exists,
  has_function_privilege(
    'anon',
    'public.pos_owner_login_v3(text,text,text,text,text,text)',
    'EXECUTE'
  ) as anon_can_execute,
  has_function_privilege(
    'authenticated',
    'public.pos_owner_login_v3(text,text,text,text,text,text)',
    'EXECUTE'
  ) as authenticated_can_execute;
