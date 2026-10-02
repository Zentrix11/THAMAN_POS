-- THAMAN POS V9.4 / Admin V1.7
-- Cloud operational-state synchronization and security hardening.
-- Run AFTER migrations 001..007.

create table if not exists public.pos_store_state (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  snapshot jsonb not null default '{}'::jsonb,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by_device text not null default ''
);

alter table public.pos_store_state enable row level security;
revoke all on table public.pos_store_state from anon, authenticated;

create index if not exists idx_pos_store_state_updated_at
  on public.pos_store_state(updated_at desc);

-- Resolve and validate one licensed POS installation. This helper deliberately
-- returns no row when the business/subscription/device is not currently usable.
create or replace function public.pos_resolve_active_device(
  p_activation_code text,
  p_device_uid text
) returns table(business_id uuid, subscription_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select b.id, s.id
  from public.subscriptions s
  join public.businesses b on b.id = s.business_id
  join public.devices d on d.business_id = b.id
  cross join public.app_settings cfg
  where cfg.id = 1
    and upper(s.activation_code) = upper(btrim(p_activation_code))
    and d.device_uid = btrim(p_device_uid)
    and b.status = 'active'
    and s.status in ('active','trial')
    and s.ends_at + make_interval(days => coalesce(cfg.grace_period_days, 0)) > now()
    and d.active = true
    and coalesce(d.blocked, false) = false
  order by s.created_at desc
  limit 1;
$$;
revoke all on function public.pos_resolve_active_device(text,text) from public, anon, authenticated;

create or replace function public.pos_pull_store_state(
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
  v_state public.pos_store_state%rowtype;
begin
  select r.business_id, r.subscription_id
    into v_business_id, v_subscription_id
  from public.pos_resolve_active_device(p_activation_code, p_device_uid) r;

  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end if;

  select * into v_state
  from public.pos_store_state
  where business_id = v_business_id;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'exists', false,
      'business_id', v_business_id,
      'subscription_id', v_subscription_id
    );
  end if;

  update public.devices
  set last_seen_at = now()
  where business_id = v_business_id and device_uid = btrim(p_device_uid);

  return jsonb_build_object(
    'ok', true,
    'exists', true,
    'business_id', v_business_id,
    'subscription_id', v_subscription_id,
    'revision', v_state.revision,
    'updated_at', v_state.updated_at,
    'updated_by_device', v_state.updated_by_device,
    'snapshot', v_state.snapshot
  );
end;
$$;
revoke all on function public.pos_pull_store_state(text,text) from public;
grant execute on function public.pos_pull_store_state(text,text) to anon, authenticated;

create or replace function public.pos_push_store_state(
  p_activation_code text,
  p_device_uid text,
  p_snapshot jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_revision bigint;
begin
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid_snapshot');
  end if;

  -- Basic abuse guard. POS state should remain well below this; large payloads
  -- should be normalized into dedicated tables in a later architecture phase.
  if octet_length(p_snapshot::text) > 15728640 then
    return jsonb_build_object('ok', false, 'error', 'snapshot_too_large');
  end if;

  select r.business_id, r.subscription_id
    into v_business_id, v_subscription_id
  from public.pos_resolve_active_device(p_activation_code, p_device_uid) r;

  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text, 0));

  insert into public.pos_store_state(
    business_id, snapshot, revision, updated_at, updated_by_device
  ) values (
    v_business_id, p_snapshot, 1, now(), btrim(p_device_uid)
  )
  on conflict (business_id) do update
    set snapshot = excluded.snapshot,
        revision = public.pos_store_state.revision + 1,
        updated_at = now(),
        updated_by_device = excluded.updated_by_device
  returning revision into v_revision;

  update public.devices
  set last_seen_at = now()
  where business_id = v_business_id and device_uid = btrim(p_device_uid);

  return jsonb_build_object(
    'ok', true,
    'business_id', v_business_id,
    'subscription_id', v_subscription_id,
    'revision', v_revision,
    'updated_at', now()
  );
end;
$$;
revoke all on function public.pos_push_store_state(text,text,jsonb) from public;
grant execute on function public.pos_push_store_state(text,text,jsonb) to anon, authenticated;

comment on table public.pos_store_state is
  'Server-side operational state snapshot for licensed THAMAN POS devices. Direct table access is denied; POS access is only through validated RPCs.';

-- Brute-force protection for cloud owner login.
create table if not exists public.pos_owner_login_attempts (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  device_uid text not null,
  email text not null,
  attempted_at timestamptz not null default now(),
  success boolean not null default false
);
alter table public.pos_owner_login_attempts enable row level security;
revoke all on table public.pos_owner_login_attempts from anon, authenticated;
create index if not exists idx_pos_owner_login_attempts_guard
  on public.pos_owner_login_attempts(business_id, device_uid, lower(email), attempted_at desc);

create or replace function public.pos_owner_login(
  p_activation_code text,
  p_device_uid text,
  p_email text,
  p_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
  v_failures integer;
begin
  begin
    v_business_id := public.pos_valid_business_for_device(p_activation_code, p_device_uid);
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end;

  select count(*)::integer into v_failures
  from public.pos_owner_login_attempts
  where business_id = v_business_id
    and device_uid = btrim(p_device_uid)
    and lower(email) = lower(btrim(p_email))
    and success = false
    and attempted_at > now() - interval '15 minutes';

  if coalesce(v_failures, 0) >= 8 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id = v_business_id
    and lower(email) = lower(btrim(p_email))
  limit 1;

  if v_owner.id is null or not v_owner.active or
     extensions.crypt(coalesce(p_password,''), v_owner.password_hash) <> v_owner.password_hash then
    insert into public.pos_owner_login_attempts(business_id, device_uid, email, success)
    values(v_business_id, btrim(p_device_uid), lower(btrim(p_email)), false);
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  insert into public.pos_owner_login_attempts(business_id, device_uid, email, success)
  values(v_business_id, btrim(p_device_uid), lower(btrim(p_email)), true);

  -- A successful login resets the recent failure window for this identity.
  delete from public.pos_owner_login_attempts
  where business_id = v_business_id
    and device_uid = btrim(p_device_uid)
    and lower(email) = lower(btrim(p_email))
    and success = false;

  update public.pos_owner_accounts
  set last_login_at = now(), updated_at = now()
  where id = v_owner.id;

  return jsonb_build_object(
    'ok', true,
    'owner_id', v_owner.id,
    'business_id', v_business_id,
    'role', 'owner',
    'display_name', v_owner.display_name,
    'phone', v_owner.phone,
    'email', v_owner.email,
    'must_change_password', v_owner.must_change_password
  );
end;
$$;
revoke all on function public.pos_owner_login(text,text,text,text) from public;
grant execute on function public.pos_owner_login(text,text,text,text) to anon, authenticated;

-- Periodic cleanup can be run manually or from Supabase cron if pg_cron is enabled.
delete from public.pos_owner_login_attempts
where attempted_at < now() - interval '30 days';

-- Device-bound subscription status: activation code alone no longer authorizes
-- reading subscriber/device metadata after this migration.
create or replace function public.pos_subscription_status_v2(
  p_activation_code text,
  p_device_uid text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_status jsonb;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device(p_activation_code, p_device_uid) r;
  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end if;
  v_status := public.pos_subscription_status(p_activation_code);
  return v_status;
end;
$$;
revoke all on function public.pos_subscription_status(text) from anon, authenticated;
revoke all on function public.pos_subscription_status_v2(text,text) from public;
grant execute on function public.pos_subscription_status_v2(text,text) to anon, authenticated;

-- Server-time wrappers prevent the offline lease from trusting a user-edited
-- device clock at the moment of online validation.
create or replace function public.pos_activate_device_v2(
  p_activation_code text,
  p_device_uid text,
  p_device_name text,
  p_platform text,
  p_app_version text
) returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.pos_activate_device(
    p_activation_code, p_device_uid, p_device_name, p_platform, p_app_version
  ) || jsonb_build_object('server_time', now());
$$;
revoke all on function public.pos_activate_device(text,text,text,text,text) from anon, authenticated;
revoke all on function public.pos_activate_device_v2(text,text,text,text,text) from public;
grant execute on function public.pos_activate_device_v2(text,text,text,text,text) to anon, authenticated;

create or replace function public.pos_device_heartbeat_v2(
  p_activation_code text,
  p_device_uid text,
  p_app_version text
) returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.pos_device_heartbeat(
    p_activation_code, p_device_uid, p_app_version
  ) || jsonb_build_object('server_time', now());
$$;
revoke all on function public.pos_device_heartbeat(text,text,text) from anon, authenticated;
revoke all on function public.pos_device_heartbeat_v2(text,text,text) from public;
grant execute on function public.pos_device_heartbeat_v2(text,text,text) to anon, authenticated;

-- Optimistic-concurrency variant used by V9.4 clients. It prevents a stale
-- device from silently overwriting a newer store snapshot.
create or replace function public.pos_push_store_state_v2(
  p_activation_code text,
  p_device_uid text,
  p_snapshot jsonb,
  p_expected_revision bigint default 0
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_current_revision bigint;
  v_current_snapshot jsonb;
  v_new_revision bigint;
begin
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid_snapshot');
  end if;
  if octet_length(p_snapshot::text) > 15728640 then
    return jsonb_build_object('ok', false, 'error', 'snapshot_too_large');
  end if;

  select r.business_id, r.subscription_id
    into v_business_id, v_subscription_id
  from public.pos_resolve_active_device(p_activation_code, p_device_uid) r;
  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text, 0));

  select revision, snapshot
    into v_current_revision, v_current_snapshot
  from public.pos_store_state
  where business_id = v_business_id;

  if v_current_revision is null then
    if coalesce(p_expected_revision, 0) <> 0 then
      return jsonb_build_object(
        'ok', false,
        'error', 'sync_conflict',
        'revision', 0,
        'snapshot', '{}'::jsonb
      );
    end if;
    insert into public.pos_store_state(
      business_id, snapshot, revision, updated_at, updated_by_device
    ) values (
      v_business_id, p_snapshot, 1, now(), btrim(p_device_uid)
    );
    v_new_revision := 1;
  else
    if coalesce(p_expected_revision, 0) <> v_current_revision then
      return jsonb_build_object(
        'ok', false,
        'error', 'sync_conflict',
        'revision', v_current_revision,
        'snapshot', v_current_snapshot
      );
    end if;

    update public.pos_store_state
    set snapshot = p_snapshot,
        revision = revision + 1,
        updated_at = now(),
        updated_by_device = btrim(p_device_uid)
    where business_id = v_business_id
    returning revision into v_new_revision;
  end if;

  update public.devices
  set last_seen_at = now()
  where business_id = v_business_id and device_uid = btrim(p_device_uid);

  return jsonb_build_object(
    'ok', true,
    'business_id', v_business_id,
    'subscription_id', v_subscription_id,
    'revision', v_new_revision,
    'server_time', now()
  );
end;
$$;
revoke all on function public.pos_push_store_state(text,text,jsonb) from anon, authenticated;
revoke all on function public.pos_push_store_state_v2(text,text,jsonb,bigint) from public;
grant execute on function public.pos_push_store_state_v2(text,text,jsonb,bigint) to anon, authenticated;

-- Server-reserved serial blocks prevent duplicate invoice/account/SKU numbers
-- when multiple tills work at the same time or reconnect after offline use.
create table if not exists public.pos_sequence_counters (
  business_id uuid not null references public.businesses(id) on delete cascade,
  kind text not null,
  next_value bigint not null default 1,
  updated_at timestamptz not null default now(),
  primary key (business_id, kind),
  constraint pos_sequence_kind_check check (
    kind in ('invoice','purchase','stock_count','product','restock','journal','customer','supplier')
  )
);
alter table public.pos_sequence_counters enable row level security;
revoke all on table public.pos_sequence_counters from anon, authenticated;

create or replace function public.pos_reserve_sequence_block(
  p_activation_code text,
  p_device_uid text,
  p_kind text,
  p_block_size integer default 100,
  p_observed_minimum bigint default 0
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_subscription_id uuid;
  v_kind text := lower(btrim(p_kind));
  v_size integer := greatest(1, least(coalesce(p_block_size, 100), 1000));
  v_next bigint;
  v_start bigint;
  v_end bigint;
begin
  if v_kind not in ('invoice','purchase','stock_count','product','restock','journal','customer','supplier') then
    return jsonb_build_object('ok', false, 'error', 'invalid_sequence_kind');
  end if;

  select r.business_id, r.subscription_id
    into v_business_id, v_subscription_id
  from public.pos_resolve_active_device(p_activation_code, p_device_uid) r;
  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_business_id::text || ':' || v_kind, 0));

  insert into public.pos_sequence_counters(business_id, kind, next_value)
  values(v_business_id, v_kind, greatest(1, coalesce(p_observed_minimum, 0) + 1))
  on conflict (business_id, kind) do nothing;

  select next_value into v_next
  from public.pos_sequence_counters
  where business_id = v_business_id and kind = v_kind
  for update;

  v_start := greatest(v_next, coalesce(p_observed_minimum, 0) + 1);
  v_end := v_start + v_size - 1;

  update public.pos_sequence_counters
  set next_value = v_end + 1,
      updated_at = now()
  where business_id = v_business_id and kind = v_kind;

  return jsonb_build_object(
    'ok', true,
    'kind', v_kind,
    'start', v_start,
    'end', v_end,
    'server_time', now()
  );
end;
$$;
revoke all on function public.pos_reserve_sequence_block(text,text,text,integer,bigint) from public;
grant execute on function public.pos_reserve_sequence_block(text,text,text,integer,bigint) to anon, authenticated;
