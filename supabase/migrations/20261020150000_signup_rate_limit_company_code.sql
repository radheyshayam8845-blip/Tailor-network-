-- Signup abuse protection and normalized company-code uniqueness.
-- Additive only: this migration does not delete or modify existing company rows.
-- If duplicate normalized codes already exist, stop and reconcile them before retrying.

do $$
begin
  if exists (
    select 1
    from public.companies
    where company_code is not null and btrim(company_code) <> ''
    group by upper(btrim(company_code))
    having count(*) > 1
  ) then
    raise exception 'Duplicate normalized company_code values exist; reconcile them before applying signup security migration';
  end if;
end;
$$;

create unique index if not exists companies_company_code_normalized_uidx
  on public.companies (upper(btrim(company_code)))
  where company_code is not null and btrim(company_code) <> '';

create table if not exists public.auth_signup_attempts (
  mobile text primary key check (mobile ~ '^[0-9]{10}$'),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  window_started_at timestamptz not null default now(),
  locked_until timestamptz
);

alter table public.auth_signup_attempts enable row level security;
revoke all on table public.auth_signup_attempts from public, anon, authenticated;
grant all on table public.auth_signup_attempts to service_role;

create or replace function public.consume_signup_attempt(p_mobile text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_row public.auth_signup_attempts%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if p_mobile is null or p_mobile !~ '^[0-9]{10}$' then
    return false;
  end if;

  insert into public.auth_signup_attempts(mobile, attempt_count, window_started_at)
  values (p_mobile, 0, v_now)
  on conflict (mobile) do nothing;

  select * into current_row
  from public.auth_signup_attempts
  where mobile = p_mobile
  for update;

  if current_row.locked_until is not null and current_row.locked_until > v_now then
    return false;
  end if;

  -- Allow five attempts in a fixed one-hour window; lock further attempts for one hour.
  if v_now - current_row.window_started_at >= interval '1 hour' then
    update public.auth_signup_attempts
      set attempt_count = 1, window_started_at = v_now, locked_until = null
      where mobile = p_mobile;
    return true;
  end if;

  if current_row.attempt_count >= 5 then
    update public.auth_signup_attempts
      set locked_until = v_now + interval '1 hour'
      where mobile = p_mobile;
    return false;
  end if;

  update public.auth_signup_attempts
    set attempt_count = attempt_count + 1
    where mobile = p_mobile;
  return true;
end;
$$;

revoke all on function public.consume_signup_attempt(text) from public, anon, authenticated;
grant execute on function public.consume_signup_attempt(text) to service_role;
