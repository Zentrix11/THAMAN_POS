-- THAMAN SQL 015 - RC3 deletion/recovery hardening
-- Run AFTER 014_rc2_attendance_plans_recovery_hardening.sql

-- 1) Plan deletion is history-safe. If referenced by any subscription, archive it.
create or replace function public.admin_delete_plan(p_plan_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare v_name text; v_used boolean;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select name into v_name from public.plans where id=p_plan_id;
  if v_name is null then raise exception 'Plan not found'; end if;
  select exists(select 1 from public.subscriptions where plan_id=p_plan_id) into v_used;
  if v_used then
    update public.plans set active=false, updated_at=now() where id=p_plan_id;
    insert into public.activity(admin_user_id,action,description,meta)
    values(auth.uid(),'plan_archived','تم إخفاء الباقة لأنها مرتبطة بسجل اشتراك سابق أو حالي',jsonb_build_object('plan_id',p_plan_id,'plan_name',v_name));
  else
    delete from public.plans where id=p_plan_id;
    insert into public.activity(admin_user_id,action,description,meta)
    values(auth.uid(),'plan_deleted','تم حذف الباقة غير المستخدمة',jsonb_build_object('plan_id',p_plan_id,'plan_name',v_name));
  end if;
end; $$;

-- 2) Subscription deletion clears all known references first, then frees login data
-- when the business no longer has subscriptions.
create or replace function public.admin_delete_subscription(p_subscription_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare v_business_id uuid;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id into v_business_id from public.subscriptions where id=p_subscription_id;
  if v_business_id is null then raise exception 'Subscription not found'; end if;

  update public.payments set subscription_id=null where subscription_id=p_subscription_id;
  update public.devices set subscription_id=null, active=false where subscription_id=p_subscription_id;
  update public.subscription_change_requests set current_subscription_id=null where current_subscription_id=p_subscription_id;
  delete from public.subscriptions where id=p_subscription_id;

  if not exists(select 1 from public.subscriptions where business_id=v_business_id) then
    update public.devices set active=false where business_id=v_business_id;
    delete from public.pos_owner_accounts where business_id=v_business_id;
    update public.businesses set status='archived', email=null, updated_at=now() where id=v_business_id;
  end if;

  insert into public.activity(admin_user_id,business_id,action,description)
  values(auth.uid(),v_business_id,'subscription_deleted','تم حذف الاشتراك بأمان وتحرير بيانات الدخول عند عدم وجود اشتراك آخر');
end; $$;

-- 3) Device delete is isolated and does not touch plans/subscriptions.
create or replace function public.admin_delete_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
declare v_business_id uuid; v_name text;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  select business_id,coalesce(nullif(device_name,''),device_uid) into v_business_id,v_name from public.devices where id=p_device_id;
  if v_business_id is null then raise exception 'Device not found'; end if;
  delete from public.devices where id=p_device_id;
  insert into public.activity(admin_user_id,business_id,action,description)
  values(auth.uid(),v_business_id,'device_deleted','تم حذف الجهاز '||coalesce(v_name,''));
end; $$;

-- 4) Bulk operations call the hardened single-item routines.
create or replace function public.admin_bulk_delete_devices(p_device_ids uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_count integer:=0;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  foreach v_id in array coalesce(p_device_ids,array[]::uuid[]) loop
    if exists(select 1 from public.devices where id=v_id) then perform public.admin_delete_device(v_id); v_count:=v_count+1; end if;
  end loop;
  return v_count;
end; $$;

create or replace function public.admin_bulk_delete_subscriptions(p_subscription_ids uuid[]) returns integer
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_count integer:=0;
begin
  if not public.is_thaman_owner() then raise exception 'Not authorized'; end if;
  foreach v_id in array coalesce(p_subscription_ids,array[]::uuid[]) loop
    if exists(select 1 from public.subscriptions where id=v_id) then perform public.admin_delete_subscription(v_id); v_count:=v_count+1; end if;
  end loop;
  return v_count;
end; $$;

revoke all on function public.admin_delete_plan(uuid) from public, anon;
revoke all on function public.admin_delete_subscription(uuid) from public, anon;
revoke all on function public.admin_delete_device(uuid) from public, anon;
revoke all on function public.admin_bulk_delete_devices(uuid[]) from public, anon;
revoke all on function public.admin_bulk_delete_subscriptions(uuid[]) from public, anon;
grant execute on function public.admin_delete_plan(uuid) to authenticated;
grant execute on function public.admin_delete_subscription(uuid) to authenticated;
grant execute on function public.admin_delete_device(uuid) to authenticated;
grant execute on function public.admin_bulk_delete_devices(uuid[]) to authenticated;
grant execute on function public.admin_bulk_delete_subscriptions(uuid[]) to authenticated;

notify pgrst, 'reload schema';
