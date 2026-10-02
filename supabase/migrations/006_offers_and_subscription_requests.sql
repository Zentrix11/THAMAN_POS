-- THAMAN Admin V1.5 / THAMAN POS V9.2
-- Public plan catalog + subscriber renewal/plan-change requests.
-- Run AFTER migrations 001-005 in the SAME Supabase project.

alter table public.plans add column if not exists description text not null default '';
alter table public.plans add column if not exists is_offer boolean not null default false;
alter table public.plans add column if not exists offer_badge text not null default '';
alter table public.plans add column if not exists previous_price numeric(12,2);
alter table public.plans add column if not exists display_order integer not null default 0;

do $$ begin
  alter table public.plans add constraint plans_previous_price_valid check(previous_price is null or previous_price >= 0);
exception when duplicate_object then null; end $$;

create table if not exists public.subscription_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  current_subscription_id uuid references public.subscriptions(id) on delete set null,
  current_plan_id uuid references public.plans(id) on delete set null,
  requested_plan_id uuid references public.plans(id) on delete set null,
  request_type text not null check(request_type in ('renewal','change_plan','subscribe')),
  status text not null default 'new' check(status in ('new','contacting','completed','rejected')),
  customer_note text not null default '',
  admin_note text not null default '',
  handled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_subscription_requests_status_created on public.subscription_requests(status, created_at desc);
create index if not exists idx_subscription_requests_business on public.subscription_requests(business_id, created_at desc);

do $$ begin
  create trigger trg_subscription_requests_updated before update on public.subscription_requests
  for each row execute function public.set_updated_at();
exception when duplicate_object then null; end $$;

alter table public.subscription_requests enable row level security;
revoke all on table public.subscription_requests from anon, authenticated;
grant select, insert, update, delete on table public.subscription_requests to authenticated;

drop policy if exists admin_select on public.subscription_requests;
drop policy if exists admin_insert on public.subscription_requests;
drop policy if exists admin_update on public.subscription_requests;
drop policy if exists admin_delete on public.subscription_requests;
create policy admin_select on public.subscription_requests for select to authenticated using (public.is_thaman_owner());
create policy admin_insert on public.subscription_requests for insert to authenticated with check (public.is_thaman_owner());
create policy admin_update on public.subscription_requests for update to authenticated using (public.is_thaman_owner()) with check (public.is_thaman_owner());
create policy admin_delete on public.subscription_requests for delete to authenticated using (public.is_thaman_owner());

-- Returns the active catalog for an already-enrolled POS installation.
create or replace function public.pos_available_plans(
  p_activation_code text,
  p_device_uid text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_current_plan_id uuid;
  v_business_status text;
  v_subscription_status text;
  v_ends_at timestamptz;
  v_grace integer;
  v_device_active boolean;
  v_device_blocked boolean;
  v_plans jsonb;
begin
  select b.id, s.id, s.plan_id, b.status, s.status, s.ends_at, cfg.grace_period_days
  into v_business_id, v_subscription_id, v_current_plan_id, v_business_status, v_subscription_status, v_ends_at, v_grace
  from public.subscriptions s
  join public.businesses b on b.id = s.business_id
  cross join public.app_settings cfg
  where cfg.id = 1 and upper(s.activation_code) = upper(btrim(p_activation_code))
  order by s.created_at desc limit 1;

  if v_subscription_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if v_business_status <> 'active' then return jsonb_build_object('ok', false, 'error', 'business_suspended'); end if;
  if v_subscription_status not in ('active','trial') then return jsonb_build_object('ok', false, 'error', 'subscription_' || v_subscription_status); end if;
  if v_ends_at + make_interval(days => coalesce(v_grace,0)) <= now() then return jsonb_build_object('ok', false, 'error', 'subscription_expired'); end if;

  select active, blocked into v_device_active, v_device_blocked
  from public.devices where business_id=v_business_id and device_uid=btrim(p_device_uid) limit 1;
  if v_device_active is null then return jsonb_build_object('ok', false, 'error', 'device_not_registered'); end if;
  if coalesce(v_device_blocked,false) then return jsonb_build_object('ok', false, 'error', 'device_blocked'); end if;
  if not coalesce(v_device_active,false) then return jsonb_build_object('ok', false, 'error', 'device_unlinked'); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'code', p.code,
    'description', p.description,
    'billing_cycle', p.billing_cycle,
    'price', p.price,
    'previous_price', p.previous_price,
    'max_devices', p.max_devices,
    'is_offer', p.is_offer,
    'offer_badge', p.offer_badge,
    'display_order', p.display_order,
    'is_current', p.id=v_current_plan_id
  ) order by p.is_offer desc, p.display_order asc, p.price asc, p.name), '[]'::jsonb)
  into v_plans from public.plans p where p.active=true;

  return jsonb_build_object(
    'ok', true,
    'business_id', v_business_id,
    'subscription_id', v_subscription_id,
    'current_plan_id', v_current_plan_id,
    'plans', v_plans
  );
end;
$$;

-- Creates a contact request. It does NOT renew/change the subscription automatically.
create or replace function public.pos_create_subscription_request(
  p_activation_code text,
  p_device_uid text,
  p_request_type text,
  p_requested_plan_id uuid,
  p_customer_note text default ''
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_current_plan_id uuid;
  v_business_status text;
  v_subscription_status text;
  v_ends_at timestamptz;
  v_grace integer;
  v_device_active boolean;
  v_device_blocked boolean;
  v_request_type text;
  v_target_plan uuid;
  v_request_id uuid;
  v_existing_id uuid;
  v_owner_name text;
  v_account_no text;
  v_current_name text;
  v_target_name text;
begin
  select b.id, s.id, s.plan_id, b.status, s.status, s.ends_at, cfg.grace_period_days,
         coalesce(nullif(b.owner_name,''),b.name), b.account_no
  into v_business_id, v_subscription_id, v_current_plan_id, v_business_status, v_subscription_status,
       v_ends_at, v_grace, v_owner_name, v_account_no
  from public.subscriptions s
  join public.businesses b on b.id=s.business_id
  cross join public.app_settings cfg
  where cfg.id=1 and upper(s.activation_code)=upper(btrim(p_activation_code))
  order by s.created_at desc limit 1;

  if v_subscription_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if v_business_status <> 'active' then return jsonb_build_object('ok', false, 'error', 'business_suspended'); end if;
  if v_subscription_status not in ('active','trial') then return jsonb_build_object('ok', false, 'error', 'subscription_' || v_subscription_status); end if;
  if v_ends_at + make_interval(days => coalesce(v_grace,0)) <= now() then return jsonb_build_object('ok', false, 'error', 'subscription_expired'); end if;

  select active, blocked into v_device_active, v_device_blocked
  from public.devices where business_id=v_business_id and device_uid=btrim(p_device_uid) limit 1;
  if v_device_active is null then return jsonb_build_object('ok', false, 'error', 'device_not_registered'); end if;
  if coalesce(v_device_blocked,false) then return jsonb_build_object('ok', false, 'error', 'device_blocked'); end if;
  if not coalesce(v_device_active,false) then return jsonb_build_object('ok', false, 'error', 'device_unlinked'); end if;

  v_target_plan := coalesce(p_requested_plan_id, v_current_plan_id);
  if not exists(select 1 from public.plans where id=v_target_plan and active=true) then
    return jsonb_build_object('ok', false, 'error', 'plan_not_available');
  end if;

  v_request_type := case
    when p_request_type='renewal' or v_target_plan=v_current_plan_id then 'renewal'
    when p_request_type in ('change_plan','subscribe') then p_request_type
    else 'change_plan'
  end;

  select id into v_existing_id from public.subscription_requests
  where business_id=v_business_id
    and request_type=v_request_type
    and coalesce(requested_plan_id,'00000000-0000-0000-0000-000000000000'::uuid)=coalesce(v_target_plan,'00000000-0000-0000-0000-000000000000'::uuid)
    and status in ('new','contacting')
  order by created_at desc limit 1;

  if v_existing_id is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_existing_id);
  end if;

  insert into public.subscription_requests(
    business_id,current_subscription_id,current_plan_id,requested_plan_id,request_type,status,customer_note
  ) values (
    v_business_id,v_subscription_id,v_current_plan_id,v_target_plan,v_request_type,'new',coalesce(p_customer_note,'')
  ) returning id into v_request_id;

  select name into v_current_name from public.plans where id=v_current_plan_id;
  select name into v_target_name from public.plans where id=v_target_plan;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(null,v_business_id,'subscription_request_created',
    'طلب اشتراك جديد من ' || coalesce(v_owner_name,'') || ' • ' || coalesce(v_account_no,'') ||
    ' • ' || case when v_request_type='renewal' then 'تجديد ' || coalesce(v_current_name,'') else 'تغيير من ' || coalesce(v_current_name,'') || ' إلى ' || coalesce(v_target_name,'') end,
    jsonb_build_object('request_id',v_request_id,'request_type',v_request_type,'requested_plan_id',v_target_plan)
  );

  return jsonb_build_object('ok', true, 'duplicate', false, 'request_id', v_request_id, 'request_type', v_request_type);
end;
$$;

create or replace function public.admin_set_subscription_request_status(
  p_request_id uuid,
  p_status text,
  p_admin_note text default ''
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_business_id uuid;
  v_type text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  if p_status not in ('new','contacting','completed','rejected') then raise exception 'Invalid request status'; end if;
  select business_id,request_type into v_business_id,v_type from public.subscription_requests where id=p_request_id;
  if v_business_id is null then raise exception 'Request not found'; end if;
  update public.subscription_requests
  set status=p_status, admin_note=coalesce(p_admin_note,''), handled_at=case when p_status in ('completed','rejected') then now() else null end
  where id=p_request_id;
  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(),v_business_id,'subscription_request_status','تم تحديث حالة طلب الاشتراك إلى '||p_status,jsonb_build_object('request_id',p_request_id,'request_type',v_type));
end;
$$;

revoke all on function public.pos_available_plans(text,text) from public;
revoke all on function public.pos_create_subscription_request(text,text,text,uuid,text) from public;
revoke all on function public.admin_set_subscription_request_status(uuid,text,text) from public;
grant execute on function public.pos_available_plans(text,text) to anon, authenticated;
grant execute on function public.pos_create_subscription_request(text,text,text,uuid,text) to anon, authenticated;
grant execute on function public.admin_set_subscription_request_status(uuid,text,text) to authenticated;
