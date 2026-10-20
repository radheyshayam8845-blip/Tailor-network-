-- Signup abuse protection and company-code uniqueness.
-- This migration is additive. It does not modify or delete existing company data.

-- Company codes are normalized to uppercase by auth-gateway. Enforce uniqueness
-- case-insensitively so existing/manual inserts cannot create duplicate codes.
create unique index if not exists companies_company_code_normalized_uidx
  on public.companies (upper(btrim(company_code)))
  where company_code is not null and btrim(company_code) <> '';

-- Server-only signup attempt table: no client access; service_role calls the RPC.
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

  -- Five registration attempts per mobile in a rolling fixed one-hour window.
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
