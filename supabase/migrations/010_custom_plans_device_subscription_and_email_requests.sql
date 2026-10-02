-- THAMAN Admin V1.9 / THAMAN POS V9.6
-- Custom per-subscriber plans, exact device->subscription ownership,
-- custom-plan requests, and email notification metadata.
-- Run AFTER migration 009.

alter table public.plans add column if not exists is_custom boolean not null default false;
alter table public.plans add column if not exists custom_business_id uuid references public.businesses(id) on delete cascade;
alter table public.plans add column if not exists custom_duration_days integer;

alter table public.plans drop constraint if exists plans_billing_cycle_check;
alter table public.plans add constraint plans_billing_cycle_check
  check (billing_cycle in ('monthly','yearly','custom'));

alter table public.plans drop constraint if exists plans_custom_duration_valid;
alter table public.plans add constraint plans_custom_duration_valid
  check (custom_duration_days is null or custom_duration_days between 1 and 3650);

create index if not exists idx_plans_custom_business
  on public.plans(custom_business_id)
  where is_custom = true;

alter table public.devices add column if not exists subscription_id uuid references public.subscriptions(id) on delete set null;
create index if not exists idx_devices_subscription on public.devices(subscription_id);

-- Best-effort backfill for existing devices. Future activations/heartbeats bind the
-- exact subscription used by the activation code.
update public.devices d
set subscription_id = (
  select s.id
  from public.subscriptions s
  where s.business_id = d.business_id
  order by s.created_at desc
  limit 1
)
where d.subscription_id is null;

alter table public.subscription_requests add column if not exists requested_duration_days integer;
alter table public.subscription_requests add column if not exists requested_device_limit integer;
alter table public.subscription_requests add column if not exists requested_budget numeric(12,2);
alter table public.subscription_requests add column if not exists contact_email text not null default '';
alter table public.subscription_requests add column if not exists contact_phone text not null default '';
alter table public.subscription_requests add column if not exists email_notified_at timestamptz;

alter table public.subscription_requests drop constraint if exists subscription_requests_request_type_check;
alter table public.subscription_requests add constraint subscription_requests_request_type_check
  check (request_type in ('renewal','change_plan','subscribe','custom'));

alter table public.subscription_requests drop constraint if exists subscription_requests_custom_duration_valid;
alter table public.subscription_requests add constraint subscription_requests_custom_duration_valid
  check (requested_duration_days is null or requested_duration_days between 1 and 3650);

alter table public.subscription_requests drop constraint if exists subscription_requests_custom_device_limit_valid;
alter table public.subscription_requests add constraint subscription_requests_custom_device_limit_valid
  check (requested_device_limit is null or requested_device_limit between 1 and 500);

alter table public.subscription_requests drop constraint if exists subscription_requests_custom_budget_valid;
alter table public.subscription_requests add constraint subscription_requests_custom_budget_valid
  check (requested_budget is null or requested_budget >= 0);

-- Apply a private plan to the latest subscription of one subscriber without
-- changing its activation code. Existing linked devices therefore stay valid.
create or replace function public.admin_apply_custom_plan(
  p_business_id uuid,
  p_name text,
  p_duration_days integer,
  p_device_limit integer,
  p_price numeric,
  p_description text default '',
  p_starts_at timestamptz default now()
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subscription_id uuid;
  v_plan_id uuid;
  v_plan_code text;
  v_occupied integer;
begin
  if not public.is_thaman_owner() then
    raise exception 'Not authorized';
  end if;
  if not exists(select 1 from public.businesses where id = p_business_id) then
    raise exception 'Subscriber not found';
  end if;
  if coalesce(btrim(p_name),'') = '' then
    raise exception 'Custom plan name is required';
  end if;
  if p_duration_days is null or p_duration_days not between 1 and 3650 then
    raise exception 'Duration must be between 1 and 3650 days';
  end if;
  if p_device_limit is null or p_device_limit not between 1 and 500 then
    raise exception 'Device limit must be between 1 and 500';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Price must be zero or greater';
  end if;

  select s.id into v_subscription_id
  from public.subscriptions s
  where s.business_id = p_business_id
  order by s.created_at desc
  limit 1;

  if v_subscription_id is null then
    raise exception 'Subscriber must have an existing subscription first';
  end if;

  select count(*)::integer into v_occupied
  from public.devices d
  where d.business_id = p_business_id
    and (d.active = true or coalesce(d.blocked,false) = true);

  if p_device_limit < v_occupied then
    raise exception 'Device limit cannot be lower than occupied seats (%)', v_occupied;
  end if;

  -- Keep only the newest custom plan published for this subscriber.
  update public.plans
  set active = false
  where is_custom = true
    and custom_business_id = p_business_id
    and active = true;

  v_plan_code := 'CUSTOM-' || substr(replace(v_subscription_id::text, '-', ''), 1, 8)
                 || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS');

  insert into public.plans(
    name, code, billing_cycle, price, max_devices, active,
    description, is_offer, offer_badge, previous_price, display_order,
    is_custom, custom_business_id, custom_duration_days
  ) values (
    btrim(p_name), v_plan_code, 'custom', p_price, p_device_limit, true,
    coalesce(p_description,''), false, '', null, 0,
    true, p_business_id, p_duration_days
  ) returning id into v_plan_id;

  update public.subscriptions
  set plan_id = v_plan_id,
      starts_at = coalesce(p_starts_at, now()),
      ends_at = coalesce(p_starts_at, now()) + make_interval(days => p_duration_days),
      status = 'active',
      device_limit = p_device_limit
  where id = v_subscription_id;

  update public.businesses set status = 'active' where id = p_business_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(
    auth.uid(), p_business_id, 'custom_plan_applied',
    'تم تطبيق باقة مخصصة: ' || btrim(p_name) || ' • ' || p_duration_days || ' يوم • ' || p_device_limit || ' أجهزة',
    jsonb_build_object(
      'plan_id', v_plan_id,
      'subscription_id', v_subscription_id,
      'duration_days', p_duration_days,
      'device_limit', p_device_limit,
      'price', p_price
    )
  );

  return v_plan_id;
end;
$$;

revoke all on function public.admin_apply_custom_plan(uuid,text,integer,integer,numeric,text,timestamptz)
  from public, anon;
grant execute on function public.admin_apply_custom_plan(uuid,text,integer,integer,numeric,text,timestamptz)
  to authenticated;

-- Public catalog: normal plans are visible to everyone with a valid THAMAN
-- installation; custom plans are visible only to the subscriber they belong to.
create or replace function public.pos_available_plans(
  p_activation_code text,
  p_device_uid text
) returns jsonb
language plpgsql
security definer
set search_path = ''
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
    'is_current', p.id=v_current_plan_id,
    'is_custom', p.is_custom,
    'custom_duration_days', p.custom_duration_days
  ) order by p.is_offer desc, p.is_current desc, p.display_order asc, p.price asc, p.name), '[]'::jsonb)
  into v_plans
  from public.plans p
  where p.active=true
    and (
      coalesce(p.is_custom,false)=false
      or p.custom_business_id=v_business_id
      or p.id=v_current_plan_id
    );

  return jsonb_build_object(
    'ok', true,
    'business_id', v_business_id,
    'subscription_id', v_subscription_id,
    'current_plan_id', v_current_plan_id,
    'plans', v_plans
  );
end;
$$;

-- Keep normal renewal/change requests from targeting another subscriber's
-- private custom plan, even if a modified client somehow learns its UUID.
create or replace function public.pos_create_subscription_request(
  p_activation_code text,
  p_device_uid text,
  p_request_type text,
  p_requested_plan_id uuid,
  p_customer_note text default ''
) returns jsonb
language plpgsql
security definer
set search_path = ''
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
  if not exists(
    select 1 from public.plans p
    where p.id=v_target_plan
      and p.active=true
      and (
        coalesce(p.is_custom,false)=false
        or p.custom_business_id=v_business_id
        or p.id=v_current_plan_id
      )
  ) then
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
    update public.subscription_requests
    set customer_note=coalesce(p_customer_note,customer_note)
    where id=v_existing_id;
    return jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_existing_id, 'request_type', v_request_type);
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

-- Keep the legacy/no-proof endpoint private. POS calls the v2 proof-aware wrapper.
revoke all on function public.pos_create_subscription_request(text,text,text,uuid,text)
  from public, anon, authenticated;

-- Proof-aware custom-plan request endpoint. The table itself remains private.
create or replace function public.pos_create_custom_plan_request_v2(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_duration_days integer,
  p_device_limit integer,
  p_budget numeric default null,
  p_customer_note text default '',
  p_contact_email text default '',
  p_contact_phone text default ''
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_current_plan_id uuid;
  v_request_id uuid;
  v_existing_id uuid;
  v_owner_name text;
  v_account_no text;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code, p_device_uid, p_device_proof) r;

  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied', 'server_time', now());
  end if;
  if p_duration_days is null or p_duration_days not between 1 and 3650 then
    return jsonb_build_object('ok', false, 'error', 'invalid_duration', 'server_time', now());
  end if;
  if p_device_limit is null or p_device_limit not between 1 and 500 then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_limit', 'server_time', now());
  end if;
  if p_budget is not null and p_budget < 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_budget', 'server_time', now());
  end if;
  if length(coalesce(p_customer_note,'')) > 4000
     or length(coalesce(p_contact_email,'')) > 320
     or length(coalesce(p_contact_phone,'')) > 64 then
    return jsonb_build_object('ok', false, 'error', 'request_too_large', 'server_time', now());
  end if;

  select s.id, s.plan_id, coalesce(nullif(b.owner_name,''),b.name), b.account_no
  into v_subscription_id, v_current_plan_id, v_owner_name, v_account_no
  from public.subscriptions s
  join public.businesses b on b.id=s.business_id
  where s.business_id=v_business_id
  order by s.created_at desc limit 1;

  if v_subscription_id is null then
    return jsonb_build_object('ok', false, 'error', 'subscription_not_found', 'server_time', now());
  end if;

  select id into v_existing_id
  from public.subscription_requests
  where business_id=v_business_id
    and request_type='custom'
    and status in ('new','contacting')
  order by created_at desc limit 1;

  if v_existing_id is not null then
    update public.subscription_requests
    set requested_budget = p_budget,
        customer_note = coalesce(p_customer_note,''),
        contact_email = coalesce(btrim(p_contact_email),''),
        contact_phone = coalesce(btrim(p_contact_phone),'')
    where id = v_existing_id;
    return jsonb_build_object('ok', true, 'duplicate', true, 'request_id', v_existing_id, 'request_type', 'custom', 'server_time', now());
  end if;

  insert into public.subscription_requests(
    business_id,current_subscription_id,current_plan_id,requested_plan_id,
    request_type,status,customer_note,requested_duration_days,requested_device_limit,
    requested_budget,contact_email,contact_phone
  ) values (
    v_business_id,v_subscription_id,v_current_plan_id,null,
    'custom','new',coalesce(p_customer_note,''),p_duration_days,p_device_limit,
    p_budget,coalesce(btrim(p_contact_email),''),coalesce(btrim(p_contact_phone),'')
  ) returning id into v_request_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(
    null,v_business_id,'custom_plan_request_created',
    'طلب باقة مخصصة من ' || coalesce(v_owner_name,'') || ' • ' || coalesce(v_account_no,'') ||
    ' • ' || p_duration_days || ' يوم • ' || p_device_limit || ' أجهزة',
    jsonb_build_object(
      'request_id',v_request_id,
      'duration_days',p_duration_days,
      'device_limit',p_device_limit,
      'budget',p_budget,
      'contact_email',coalesce(btrim(p_contact_email),''),
      'contact_phone',coalesce(btrim(p_contact_phone),'')
    )
  );

  return jsonb_build_object('ok', true, 'duplicate', false, 'request_id', v_request_id, 'request_type', 'custom', 'server_time', now());
end;
$$;

revoke all on function public.pos_create_custom_plan_request_v2(text,text,text,integer,integer,numeric,text,text,text)
  from public;
grant execute on function public.pos_create_custom_plan_request_v2(text,text,text,integer,integer,numeric,text,text,text)
  to anon, authenticated;

-- Rebind exact subscription id during activation while preserving device proof.
create or replace function public.pos_activate_device_v3(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_device_name text,
  p_platform text,
  p_app_version text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_existing_hash text;
  v_result jsonb;
  v_device_id uuid;
  v_subscription_id uuid;
begin
  if coalesce(btrim(p_device_proof),'') !~ '^[A-Fa-f0-9]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'device_proof_invalid', 'server_time', now());
  end if;
  v_hash := encode(extensions.digest(btrim(p_device_proof), 'sha256'), 'hex');

  select s.id, d.device_proof_hash into v_subscription_id, v_existing_hash
  from public.subscriptions s
  left join public.devices d on d.business_id = s.business_id and d.device_uid = btrim(p_device_uid)
  where upper(s.activation_code) = upper(btrim(p_activation_code))
  order by s.created_at desc
  limit 1;

  if v_existing_hash is not null and v_existing_hash <> v_hash then
    return jsonb_build_object('ok', false, 'error', 'device_proof_mismatch', 'server_time', now());
  end if;

  v_result := public.pos_activate_device(
    p_activation_code, p_device_uid, p_device_name, p_platform, p_app_version
  );
  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result || jsonb_build_object('server_time', now());
  end if;

  begin
    v_device_id := nullif(v_result->>'device_id','')::uuid;
  exception when others then
    v_device_id := null;
  end;

  if v_device_id is null then
    select d.id into v_device_id
    from public.subscriptions s
    join public.devices d on d.business_id = s.business_id
    where upper(s.activation_code) = upper(btrim(p_activation_code))
      and d.device_uid = btrim(p_device_uid)
    order by s.created_at desc
    limit 1;
  end if;

  if v_device_id is null or v_subscription_id is null then
    return jsonb_build_object('ok', false, 'error', 'device_not_found', 'server_time', now());
  end if;

  update public.devices
  set device_proof_hash = coalesce(device_proof_hash, v_hash),
      proof_bound_at = coalesce(proof_bound_at, now()),
      subscription_id = v_subscription_id
  where id = v_device_id
    and (device_proof_hash is null or device_proof_hash = v_hash);

  if not found then
    return jsonb_build_object('ok', false, 'error', 'device_proof_mismatch', 'server_time', now());
  end if;

  return v_result || jsonb_build_object('server_time', now());
end;
$$;

create or replace function public.pos_device_heartbeat_v3(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_app_version text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_business_id uuid;
  v_subscription_id uuid;
  v_existing_hash text;
  v_result jsonb;
begin
  if coalesce(btrim(p_device_proof),'') !~ '^[A-Fa-f0-9]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'device_proof_invalid', 'server_time', now());
  end if;
  v_hash := encode(extensions.digest(btrim(p_device_proof), 'sha256'), 'hex');

  select r.business_id into v_business_id
  from public.pos_resolve_active_device(p_activation_code, p_device_uid) r;
  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied', 'server_time', now());
  end if;

  select s.id into v_subscription_id
  from public.subscriptions s
  where s.business_id=v_business_id
    and upper(s.activation_code)=upper(btrim(p_activation_code))
  order by s.created_at desc limit 1;

  select device_proof_hash into v_existing_hash
  from public.devices
  where business_id = v_business_id and device_uid = btrim(p_device_uid)
  limit 1;

  if v_existing_hash is not null and v_existing_hash <> v_hash then
    return jsonb_build_object('ok', false, 'error', 'device_proof_mismatch', 'server_time', now());
  end if;

  v_result := public.pos_device_heartbeat(p_activation_code, p_device_uid, p_app_version);
  if coalesce((v_result->>'ok')::boolean, false) = false then
    return v_result || jsonb_build_object('server_time', now());
  end if;

  update public.devices
  set device_proof_hash = coalesce(device_proof_hash, v_hash),
      proof_bound_at = coalesce(proof_bound_at, now()),
      subscription_id = coalesce(v_subscription_id, subscription_id)
  where business_id = v_business_id
    and device_uid = btrim(p_device_uid)
    and (device_proof_hash is null or device_proof_hash = v_hash);

  return v_result || jsonb_build_object('server_time', now());
end;
$$;

-- Keep proof-aware endpoints executable by the app roles.
revoke all on function public.pos_activate_device_v3(text,text,text,text,text,text) from public;
revoke all on function public.pos_device_heartbeat_v3(text,text,text,text) from public;
grant execute on function public.pos_activate_device_v3(text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.pos_device_heartbeat_v3(text,text,text,text) to anon, authenticated;

comment on function public.admin_apply_custom_plan(uuid,text,integer,integer,numeric,text,timestamptz) is
  'Creates a private plan for one subscriber and applies it to their latest subscription without rotating activation code.';
comment on function public.pos_create_custom_plan_request_v2(text,text,text,integer,integer,numeric,text,text,text) is
  'Proof-aware custom plan request endpoint for THAMAN POS.';
