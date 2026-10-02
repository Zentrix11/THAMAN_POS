-- THAMAN Admin V2.0 / THAMAN POS V9.7
-- Final production hardening:
-- 1) per-subscriber expiry warning window
-- 2) request-scoped owner/admin messaging for custom-plan negotiations
-- 3) activation brute-force throttling
-- 4) versioned activation RPC with device proof preserved
-- Run AFTER migration 010.

-- ---------------------------------------------------------------------------
-- Per-subscription expiry warning
-- ---------------------------------------------------------------------------
alter table public.subscriptions
  add column if not exists expiry_warning_days integer;

alter table public.subscriptions
  drop constraint if exists subscriptions_expiry_warning_days_check;
alter table public.subscriptions
  add constraint subscriptions_expiry_warning_days_check
  check (expiry_warning_days is null or expiry_warning_days between 0 and 365);

create or replace function public.admin_set_subscription_expiry_warning_days(
  p_subscription_id uuid,
  p_days integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
begin
  if not public.is_thaman_owner() then
    raise exception 'Not authorized';
  end if;
  if p_days is null or p_days not between 0 and 365 then
    raise exception 'Expiry warning days must be between 0 and 365';
  end if;

  update public.subscriptions
  set expiry_warning_days = p_days
  where id = p_subscription_id
  returning business_id into v_business_id;

  if v_business_id is null then
    raise exception 'Subscription not found';
  end if;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(
    auth.uid(), v_business_id, 'expiry_warning_changed',
    'تم ضبط تنبيه انتهاء الاشتراك قبل ' || p_days || ' يوم',
    jsonb_build_object('subscription_id',p_subscription_id,'expiry_warning_days',p_days)
  );
end;
$$;

revoke all on function public.admin_set_subscription_expiry_warning_days(uuid,integer)
  from public, anon;
grant execute on function public.admin_set_subscription_expiry_warning_days(uuid,integer)
  to authenticated;

-- Return the subscriber-specific warning window when set, otherwise the global
-- application setting. The remaining duration in POS is calculated from ends_at.
create or replace function public.pos_subscription_status(p_activation_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
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
      coalesce(s.expiry_warning_days, cfg.expiry_warning_days) as expiry_warning_days,
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
              'blocked', d.blocked,
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

revoke all on function public.pos_subscription_status(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Internal owner/admin messaging, scoped to subscription requests
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_request_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.subscription_requests(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  sender_type text not null check (sender_type in ('owner','admin')),
  sender_admin_user_id uuid,
  message text not null check (char_length(message) between 1 and 4000),
  read_by_owner boolean not null default false,
  read_by_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_subscription_request_messages_request
  on public.subscription_request_messages(request_id, created_at);
create index if not exists idx_subscription_request_messages_business
  on public.subscription_request_messages(business_id, created_at desc);

alter table public.subscription_request_messages enable row level security;
revoke all on table public.subscription_request_messages from public, anon, authenticated;

create or replace function public.pos_list_custom_plan_requests_v1(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_requests jsonb;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code,p_device_uid,p_device_proof) r;
  if v_business_id is null then
    return jsonb_build_object('ok',false,'error','license_denied','server_time',now());
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', q.id,
      'status', q.status,
      'request_type', q.request_type,
      'customer_note', q.customer_note,
      'admin_note', q.admin_note,
      'requested_duration_days', q.requested_duration_days,
      'requested_device_limit', q.requested_device_limit,
      'requested_budget', q.requested_budget,
      'created_at', q.created_at,
      'handled_at', q.handled_at,
      'unread_owner_count', (
        select count(*)::integer from public.subscription_request_messages m
        where m.request_id=q.id and m.sender_type='admin' and m.read_by_owner=false
      ),
      'messages', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',m.id,
          'sender_type',m.sender_type,
          'message',m.message,
          'read_by_owner',m.read_by_owner,
          'read_by_admin',m.read_by_admin,
          'created_at',m.created_at
        ) order by m.created_at asc)
        from public.subscription_request_messages m
        where m.request_id=q.id
      ),'[]'::jsonb)
    ) order by q.created_at desc
  ),'[]'::jsonb)
  into v_requests
  from public.subscription_requests q
  where q.business_id=v_business_id and q.request_type='custom';

  return jsonb_build_object('ok',true,'requests',v_requests,'server_time',now());
end;
$$;

create or replace function public.pos_send_subscription_request_message_v1(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_request_id uuid,
  p_message text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_message_id uuid;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code,p_device_uid,p_device_proof) r;
  if v_business_id is null then
    return jsonb_build_object('ok',false,'error','license_denied','server_time',now());
  end if;
  if coalesce(char_length(btrim(p_message)),0) < 1 or char_length(btrim(p_message)) > 4000 then
    return jsonb_build_object('ok',false,'error','invalid_message','server_time',now());
  end if;
  if not exists(
    select 1 from public.subscription_requests q
    where q.id=p_request_id and q.business_id=v_business_id and q.request_type='custom'
  ) then
    return jsonb_build_object('ok',false,'error','request_not_found','server_time',now());
  end if;

  insert into public.subscription_request_messages(
    request_id,business_id,sender_type,message,read_by_owner,read_by_admin
  ) values (
    p_request_id,v_business_id,'owner',btrim(p_message),true,false
  ) returning id into v_message_id;

  update public.subscription_requests
  set status = case when status='new' then 'contacting' else status end
  where id=p_request_id;

  return jsonb_build_object('ok',true,'message_id',v_message_id,'server_time',now());
end;
$$;

create or replace function public.pos_mark_subscription_request_messages_read_v1(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code,p_device_uid,p_device_proof) r;
  if v_business_id is null then
    return jsonb_build_object('ok',false,'error','license_denied','server_time',now());
  end if;
  if not exists(select 1 from public.subscription_requests q where q.id=p_request_id and q.business_id=v_business_id) then
    return jsonb_build_object('ok',false,'error','request_not_found','server_time',now());
  end if;
  update public.subscription_request_messages
  set read_by_owner=true
  where request_id=p_request_id and business_id=v_business_id and sender_type='admin';
  return jsonb_build_object('ok',true,'server_time',now());
end;
$$;

create or replace function public.admin_list_subscription_request_messages_v1(
  p_request_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_messages jsonb;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  if not exists(select 1 from public.subscription_requests where id=p_request_id) then
    raise exception 'Request not found';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,
    'request_id',m.request_id,
    'business_id',m.business_id,
    'sender_type',m.sender_type,
    'message',m.message,
    'read_by_owner',m.read_by_owner,
    'read_by_admin',m.read_by_admin,
    'created_at',m.created_at
  ) order by m.created_at asc),'[]'::jsonb)
  into v_messages
  from public.subscription_request_messages m
  where m.request_id=p_request_id;
  return v_messages;
end;
$$;

create or replace function public.admin_subscription_request_unread_counts_v1()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'request_id', q.id,
    'unread_admin_count', (
      select count(*)::integer
      from public.subscription_request_messages m
      where m.request_id=q.id and m.sender_type='owner' and m.read_by_admin=false
    )
  ) order by q.created_at desc), '[]'::jsonb)
  into v_rows
  from public.subscription_requests q
  where q.request_type='custom';
  return v_rows;
end;
$$;

create or replace function public.admin_send_subscription_request_message_v1(
  p_request_id uuid,
  p_message text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_message_id uuid;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  if coalesce(char_length(btrim(p_message)),0) < 1 or char_length(btrim(p_message)) > 4000 then
    raise exception 'Message must be between 1 and 4000 characters';
  end if;
  select business_id into v_business_id from public.subscription_requests where id=p_request_id;
  if v_business_id is null then raise exception 'Request not found'; end if;

  insert into public.subscription_request_messages(
    request_id,business_id,sender_type,sender_admin_user_id,message,read_by_owner,read_by_admin
  ) values (
    p_request_id,v_business_id,'admin',auth.uid(),btrim(p_message),false,true
  ) returning id into v_message_id;

  update public.subscription_requests
  set status=case when status='new' then 'contacting' else status end
  where id=p_request_id;

  insert into public.activity(admin_user_id,business_id,action,description,meta)
  values(auth.uid(),v_business_id,'subscription_request_message_sent','تم إرسال رسالة للمشترك بخصوص طلب الاشتراك',jsonb_build_object('request_id',p_request_id,'message_id',v_message_id));

  return v_message_id;
end;
$$;

create or replace function public.admin_mark_subscription_request_messages_read_v1(
  p_request_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  update public.subscription_request_messages
  set read_by_admin=true
  where request_id=p_request_id and sender_type='owner';
end;
$$;

revoke all on function public.pos_list_custom_plan_requests_v1(text,text,text) from public;
revoke all on function public.pos_send_subscription_request_message_v1(text,text,text,uuid,text) from public;
revoke all on function public.pos_mark_subscription_request_messages_read_v1(text,text,text,uuid) from public;
revoke all on function public.admin_list_subscription_request_messages_v1(uuid) from public, anon;
revoke all on function public.admin_subscription_request_unread_counts_v1() from public, anon;
revoke all on function public.admin_send_subscription_request_message_v1(uuid,text) from public, anon;
revoke all on function public.admin_mark_subscription_request_messages_read_v1(uuid) from public, anon;

grant execute on function public.pos_list_custom_plan_requests_v1(text,text,text) to anon, authenticated;
grant execute on function public.pos_send_subscription_request_message_v1(text,text,text,uuid,text) to anon, authenticated;
grant execute on function public.pos_mark_subscription_request_messages_read_v1(text,text,text,uuid) to anon, authenticated;
grant execute on function public.admin_list_subscription_request_messages_v1(uuid) to authenticated;
grant execute on function public.admin_subscription_request_unread_counts_v1() to authenticated;
grant execute on function public.admin_send_subscription_request_message_v1(uuid,text) to authenticated;
grant execute on function public.admin_mark_subscription_request_messages_read_v1(uuid) to authenticated;

-- Preserve the original custom request note as the first conversation message
-- for requests that predate this migration.
insert into public.subscription_request_messages(
  request_id,business_id,sender_type,message,read_by_owner,read_by_admin,created_at
)
select q.id,q.business_id,'owner',btrim(q.customer_note),true,false,q.created_at
from public.subscription_requests q
where q.request_type='custom'
  and coalesce(btrim(q.customer_note),'') <> ''
  and not exists(select 1 from public.subscription_request_messages m where m.request_id=q.id);

-- ---------------------------------------------------------------------------
-- Activation throttling. This sits in front of v3 so all existing proof/device
-- binding logic remains intact.
-- ---------------------------------------------------------------------------
create table if not exists public.pos_activation_attempts (
  id bigint generated always as identity primary key,
  device_uid text not null,
  activation_code_fingerprint text not null default '',
  attempted_at timestamptz not null default now(),
  success boolean not null default false
);

create index if not exists idx_pos_activation_attempts_guard
  on public.pos_activation_attempts(device_uid, attempted_at desc);

alter table public.pos_activation_attempts enable row level security;
revoke all on table public.pos_activation_attempts from public, anon, authenticated;

create or replace function public.pos_activate_device_v4(
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
  v_failed integer;
  v_result jsonb;
  v_ok boolean;
  v_fingerprint text;
begin
  if coalesce(btrim(p_device_uid),'') = '' then
    return jsonb_build_object('ok',false,'error','device_uid_missing','server_time',now());
  end if;

  delete from public.pos_activation_attempts where attempted_at < now() - interval '24 hours';

  select count(*)::integer into v_failed
  from public.pos_activation_attempts
  where device_uid=btrim(p_device_uid)
    and success=false
    and attempted_at >= now() - interval '15 minutes';

  if v_failed >= 10 then
    return jsonb_build_object(
      'ok',false,
      'error','activation_rate_limited',
      'retry_after_seconds',900,
      'server_time',now()
    );
  end if;

  v_result := public.pos_activate_device_v3(
    p_activation_code,p_device_uid,p_device_proof,p_device_name,p_platform,p_app_version
  );
  v_ok := coalesce((v_result->>'ok')::boolean,false);
  v_fingerprint := encode(extensions.digest(upper(btrim(coalesce(p_activation_code,''))), 'sha256'),'hex');

  insert into public.pos_activation_attempts(device_uid,activation_code_fingerprint,success)
  values(btrim(p_device_uid),v_fingerprint,v_ok);

  if v_ok then
    delete from public.pos_activation_attempts
    where device_uid=btrim(p_device_uid) and success=false;
  end if;

  return v_result || jsonb_build_object('server_time',now());
end;
$$;

revoke all on function public.pos_activate_device_v4(text,text,text,text,text,text) from public;
grant execute on function public.pos_activate_device_v4(text,text,text,text,text,text) to anon, authenticated;

comment on function public.pos_activate_device_v4(text,text,text,text,text,text) is
  'Proof-aware activation with a 10-failed-attempts/15-minute throttle per installation UID.';
comment on function public.admin_set_subscription_expiry_warning_days(uuid,integer) is
  'Sets a subscriber-specific expiry warning lead time without changing subscription identity or activation code.';
comment on table public.subscription_request_messages is
  'Private request-scoped conversation between THAMAN Admin and the subscriber owner.';
