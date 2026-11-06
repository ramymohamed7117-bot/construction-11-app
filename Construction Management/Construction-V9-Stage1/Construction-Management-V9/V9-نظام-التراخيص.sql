create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- V9 Licensing module. Run once in the EXISTING Supabase project.
-- Adds separate licensing tables/functions and a write guard on app_records.
-- Does not alter or delete existing app_records rows.

create table if not exists public.app_licenses (
  user_id uuid primary key references auth.users(id) on delete cascade,
  trial_started_at timestamptz,
  expires_at timestamptz,
  status text not null default 'trial' check (status in ('trial','active','expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_license_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  duration_days integer not null check (duration_days in (30,90,180,365)),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  redeemed_by uuid references auth.users(id),
  redeemed_at timestamptz
);

alter table public.app_licenses enable row level security;
alter table public.app_license_codes enable row level security;

drop policy if exists "app_licenses_select_own" on public.app_licenses;
create policy "app_licenses_select_own" on public.app_licenses
  for select to authenticated using (auth.uid() = user_id);
-- No direct client write policies. All writes go through the functions below.

create or replace function public.ensure_app_license()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_exp timestamptz;
  v_status text;
  v_owner boolean;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select exists(select 1 from public.app_admins where user_id = v_uid) into v_owner;
  if v_owner then
    return jsonb_build_object('is_owner', true, 'status', 'owner', 'expires_at', null, 'remaining_days', null);
  end if;

  insert into public.app_licenses(user_id, trial_started_at, expires_at, status)
  values (v_uid, now(), now() + interval '30 days', 'trial')
  on conflict (user_id) do nothing;

  update public.app_licenses
     set status = case when expires_at > now() and trial_started_at is not null and status = 'trial' then 'trial'
                       when expires_at > now() then 'active' else 'expired' end,
         updated_at = now()
   where user_id = v_uid;

  select expires_at, status into v_exp, v_status
    from public.app_licenses where user_id = v_uid;

  return jsonb_build_object(
    'is_owner', false,
    'status', v_status,
    'expires_at', v_exp,
    'remaining_days', greatest(0, ceil(extract(epoch from (v_exp - now())) / 86400))::integer
  );
end;
$$;

create or replace function public.redeem_app_license_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_code public.app_license_codes%rowtype;
  v_exp timestamptz;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.app_admins where user_id = v_uid) then
    return jsonb_build_object('ok', true, 'status', 'owner', 'message', 'Owner account does not require activation');
  end if;
  if p_code is null or length(trim(p_code)) < 8 then raise exception 'Invalid activation code'; end if;

  perform public.ensure_app_license();

  select * into v_code
    from public.app_license_codes
   where code_hash = encode(digest(upper(trim(p_code)), 'sha256'), 'hex')
   for update;

  if not found then raise exception 'Activation code is invalid'; end if;
  if v_code.redeemed_at is not null then raise exception 'Activation code has already been used'; end if;

  update public.app_license_codes
     set redeemed_by = v_uid, redeemed_at = now()
   where id = v_code.id;

  update public.app_licenses
     set expires_at = greatest(coalesce(expires_at, now()), now()) + make_interval(days => v_code.duration_days),
         status = 'active', updated_at = now()
   where user_id = v_uid
   returning expires_at into v_exp;

  return jsonb_build_object('ok', true, 'status', 'active', 'expires_at', v_exp, 'duration_days', v_code.duration_days);
end;
$$;

create or replace function public.admin_create_app_license_codes(p_duration_days integer, p_quantity integer default 1)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_codes jsonb := '[]'::jsonb;
  i integer;
begin
  if v_uid is null or not exists(select 1 from public.app_admins where user_id = v_uid) then
    raise exception 'Owner permission required';
  end if;
  if p_duration_days not in (30,90,180,365) then raise exception 'Unsupported license duration'; end if;
  if p_quantity < 1 or p_quantity > 50 then raise exception 'Quantity must be between 1 and 50'; end if;

  for i in 1..p_quantity loop
    v_code := 'DIA-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20));
    insert into public.app_license_codes(code_hash, duration_days, created_by)
    values (encode(digest(v_code, 'sha256'), 'hex'), p_duration_days, v_uid);
    v_codes := v_codes || jsonb_build_array(v_code);
  end loop;
  return jsonb_build_object('duration_days', p_duration_days, 'codes', v_codes);
end;
$$;

-- Server-side enforcement: direct REST writes to app_records are denied after expiry.
create or replace function public.enforce_app_license_for_records()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_exp timestamptz;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.app_admins where user_id = v_uid) then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  select expires_at into v_exp from public.app_licenses where user_id = v_uid;
  if v_exp is null or v_exp <= now() then
    raise exception 'APP_LICENSE_EXPIRED: Activate a valid license to add or change data';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists app_records_license_guard on public.app_records;
create trigger app_records_license_guard
before insert or update or delete on public.app_records
for each row execute function public.enforce_app_license_for_records();

revoke all on function public.ensure_app_license() from public;
revoke all on function public.redeem_app_license_code(text) from public;
revoke all on function public.admin_create_app_license_codes(integer, integer) from public;
grant execute on function public.ensure_app_license() to authenticated;
grant execute on function public.redeem_app_license_code(text) to authenticated;
grant execute on function public.admin_create_app_license_codes(integer, integer) to authenticated;

grant select on public.app_licenses to authenticated;
revoke all on public.app_license_codes from anon, authenticated;

-- Verification: should return the licensing objects and trigger.
select table_name from information_schema.tables
where table_schema = 'public' and table_name in ('app_licenses','app_license_codes')
order by table_name;
