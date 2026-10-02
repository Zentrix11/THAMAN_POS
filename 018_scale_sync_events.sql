-- THAMAN scale foundation 018
-- Run after 001..017. Does not delete pos_store_state.
-- Hundreds of thousands of tenants cannot share one JSON snapshot per store.
-- New installs should append operations here; the snapshot remains for current clients.

create table if not exists public.pos_sync_events (
  id bigserial primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  device_uid text not null default '',
  client_seq bigint not null,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (business_id, device_uid, client_seq)
);

create index if not exists idx_pos_sync_events_business_id
  on public.pos_sync_events(business_id, id);

alter table public.pos_sync_events enable row level security;
revoke all on table public.pos_sync_events from anon, authenticated;

create or replace function public.pos_append_sync_events(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_events jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_item jsonb;
  v_count integer := 0;
begin
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'invalid_events');
  end if;
  if jsonb_array_length(p_events) > 200 then
    return jsonb_build_object('ok', false, 'error', 'batch_too_large');
  end if;

  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(p_activation_code, p_device_uid, p_device_proof) r;
  if v_business_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied');
  end if;

  for v_item in select value from jsonb_array_elements(p_events)
  loop
    insert into public.pos_sync_events(business_id, device_uid, client_seq, kind, payload)
    values (
      v_business_id,
      btrim(p_device_uid),
      coalesce((v_item->>'client_seq')::bigint, 0),
      coalesce(v_item->>'kind', 'unknown'),
      coalesce(v_item->'payload', '{}'::jsonb)
    )
    on conflict (business_id, device_uid, client_seq) do nothing;
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'accepted', v_count);
end;
$$;

revoke all on function public.pos_append_sync_events(text, text, text, jsonb) from public;
grant execute on function public.pos_append_sync_events(text, text, text, jsonb) to anon, authenticated;

create or replace function public.admin_page_businesses(
  p_limit integer default 50,
  p_offset integer default 0
) returns setof public.businesses
language sql
stable
security definer
set search_path = ''
as $$
  select *
  from public.businesses
  order by created_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.admin_page_businesses(integer, integer) from public;
grant execute on function public.admin_page_businesses(integer, integer) to authenticated;
