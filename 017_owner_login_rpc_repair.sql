-- THAMAN SQL 017 - Owner login RPC repair / schema compatibility
-- Safe to run after 001-016. Recreates the authoritative owner-login RPC
-- and reapplies EXECUTE grants used by THAMAN POS.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.pos_owner_login_v3(
  p_activation_code text,
  p_device_uid text,
  p_device_proof text,
  p_email text,
  p_password text,
  p_pin text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_owner public.pos_owner_accounts%rowtype;
  v_failures integer;
  v_account_failures integer;
begin
  select r.business_id into v_business_id
  from public.pos_resolve_active_device_v2(
    p_activation_code,
    p_device_uid,
    p_device_proof
  ) r;

  if v_business_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'license_denied',
      'server_time', now()
    );
  end if;

  delete from public.pos_owner_login_attempts
  where attempted_at < now() - interval '24 hours';

  select count(*)::integer into v_failures
  from public.pos_owner_login_attempts
  where business_id = v_business_id
    and device_uid = btrim(p_device_uid)
    and lower(email) = lower(btrim(p_email))
    and success = false
    and attempted_at > now() - interval '15 minutes';

  select count(*)::integer into v_account_failures
  from public.pos_owner_login_attempts
  where business_id = v_business_id
    and lower(email) = lower(btrim(p_email))
    and success = false
    and attempted_at > now() - interval '15 minutes';

  if coalesce(v_failures, 0) >= 8 or coalesce(v_account_failures, 0) >= 20 then
    return jsonb_build_object(
      'ok', false,
      'error', 'too_many_attempts',
      'retry_after_seconds', 900,
      'server_time', now()
    );
  end if;

  select * into v_owner
  from public.pos_owner_accounts
  where business_id = v_business_id
    and lower(email) = lower(btrim(p_email))
  limit 1;

  if v_owner.id is not null
     and v_owner.must_change_password
     and v_owner.temporary_password_expires_at is not null
     and v_owner.temporary_password_expires_at <= now() then
    insert into public.pos_owner_login_attempts(
      business_id, device_uid, email, success
    ) values (
      v_business_id, btrim(p_device_uid), lower(btrim(p_email)), false
    );

    return jsonb_build_object(
      'ok', false,
      'error', 'temporary_password_expired',
      'temporary_password_expires_at', v_owner.temporary_password_expires_at,
      'server_time', now()
    );
  end if;

  if v_owner.id is null
     or not v_owner.active
     or extensions.crypt(coalesce(p_password, ''), v_owner.password_hash) <> v_owner.password_hash
     or extensions.crypt(coalesce(p_pin, ''), v_owner.pin_hash) <> v_owner.pin_hash then
    insert into public.pos_owner_login_attempts(
      business_id, device_uid, email, success
    ) values (
      v_business_id, btrim(p_device_uid), lower(btrim(p_email)), false
    );

    return jsonb_build_object(
      'ok', false,
      'error', 'invalid_credentials',
      'server_time', now()
    );
  end if;

  insert into public.pos_owner_login_attempts(
    business_id, device_uid, email, success
  ) values (
    v_business_id, btrim(p_device_uid), lower(btrim(p_email)), true
  );

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
    'must_change_password', v_owner.must_change_password,
    'temporary_password_expires_at', v_owner.temporary_password_expires_at,
    'server_time', now()
  );
end;
$$;

revoke all on function public.pos_owner_login_v3(text,text,text,text,text,text) from public;
grant execute on function public.pos_owner_login_v3(text,text,text,text,text,text) to anon, authenticated;

notify pgrst, 'reload schema';
