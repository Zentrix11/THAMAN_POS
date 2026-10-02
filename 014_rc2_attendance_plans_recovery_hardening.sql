-- THAMAN SQL 014 - RC2 hardening
-- Run AFTER 013_access_reuse_bulk_lock_and_owner_pin.sql.
-- Fixes safe plan removal/history and stabilizes the POS plan catalog RPC.

-- ---------------------------------------------------------------------------
-- 1) Never destroy a plan referenced by subscription history.
--    Referenced plans are archived (active=false); unused plans are deleted.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_plan(p_plan_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
  v_used boolean;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;

  select name into v_name from public.plans where id = p_plan_id;
  if v_name is null then raise exception 'Plan not found'; end if;

  select exists(select 1 from public.subscriptions where plan_id = p_plan_id)
    into v_used;

  if v_used then
    update public.plans
       set active = false,
           updated_at = now()
     where id = p_plan_id;

    insert into public.activity(admin_user_id, business_id, action, description)
    values(auth.uid(), null, 'plan_archived', 'تم تعطيل وإخفاء الباقة المستخدمة ' || v_name || ' مع الاحتفاظ بسجل الاشتراكات');
  else
    delete from public.plans where id = p_plan_id;
    insert into public.activity(admin_user_id, business_id, action, description)
    values(auth.uid(), null, 'plan_deleted', 'تم حذف الباقة غير المستخدمة ' || v_name);
  end if;
end;
$$;

revoke all on function public.admin_delete_plan(uuid) from public, anon;
grant execute on function public.admin_delete_plan(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Stable catalog endpoint. It resolves the active device once and builds
--    the plan catalog directly instead of chaining through legacy catalog RPCs.
-- ---------------------------------------------------------------------------
create or replace function public.pos_available_plans_v3(
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
  v_subscription_id uuid;
  v_current_plan_id uuid;
  v_plans jsonb;
begin
  select r.business_id, r.subscription_id
    into v_business_id, v_subscription_id
  from public.pos_resolve_active_device_v2(p_activation_code, p_device_uid, p_device_proof) r
  limit 1;

  if v_business_id is null or v_subscription_id is null then
    return jsonb_build_object('ok', false, 'error', 'license_denied', 'server_time', now());
  end if;

  select s.plan_id into v_current_plan_id
  from public.subscriptions s
  where s.id = v_subscription_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'code', p.code,
    'description', coalesce(p.description,''),
    'billing_cycle', p.billing_cycle,
    'price', p.price,
    'previous_price', p.previous_price,
    'max_devices', p.max_devices,
    'is_offer', coalesce(p.is_offer,false),
    'offer_badge', coalesce(p.offer_badge,''),
    'display_order', coalesce(p.display_order,0),
    'is_current', p.id = v_current_plan_id,
    'is_custom', coalesce(p.is_custom,false),
    'custom_duration_days', p.custom_duration_days
  ) order by coalesce(p.is_offer,false) desc,
             (p.id = v_current_plan_id) desc,
             coalesce(p.display_order,0) asc,
             p.price asc,
             p.name), '[]'::jsonb)
    into v_plans
  from public.plans p
  where (p.active = true or p.id = v_current_plan_id)
    and (
      coalesce(p.is_custom,false) = false
      or p.custom_business_id = v_business_id
      or p.id = v_current_plan_id
    );

  return jsonb_build_object(
    'ok', true,
    'subscription_id', v_subscription_id,
    'current_plan_id', v_current_plan_id,
    'plans', v_plans,
    'server_time', now()
  );
exception when others then
  return jsonb_build_object('ok', false, 'error', 'catalog_server_error', 'detail', sqlerrm, 'server_time', now());
end;
$$;

revoke all on function public.pos_available_plans_v3(text,text,text) from public;
grant execute on function public.pos_available_plans_v3(text,text,text) to anon, authenticated;

-- Refresh PostgREST schema cache when available.
notify pgrst, 'reload schema';
