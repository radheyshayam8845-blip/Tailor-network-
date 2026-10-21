-- Server-side login throttling. No client role can read or mutate these records.
create table if not exists public.auth_login_attempts (
  mobile text primary key check (mobile ~ '^\\d{10}$'),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  window_started_at timestamptz not null default now(),
  locked_until timestamptz
);

alter table public.auth_login_attempts enable row level security;
revoke all on public.auth_login_attempts from public, anon, authenticated;
grant all on public.auth_login_attempts to service_role;

create or replace function public.consume_login_attempt(p_mobile text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_row public.auth_login_attempts%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if p_mobile is null or p_mobile !~ '^\\d{10}$' then return false; end if;

  insert into public.auth_login_attempts(mobile, attempt_count, window_started_at)
  values (p_mobile, 0, v_now)
  on conflict (mobile) do nothing;

  select * into current_row
  from public.auth_login_attempts
  where mobile = p_mobile
  for update;

  if current_row.locked_until is not null and current_row.locked_until > v_now then
    return false;
  end if;

  if v_now - current_row.window_started_at >= interval '15 minutes' then
    update public.auth_login_attempts
      set attempt_count = 1, window_started_at = v_now, locked_until = null
      where mobile = p_mobile;
    return true;
  end if;

  if current_row.attempt_count >= 9 then
    update public.auth_login_attempts
      set locked_until = v_now + interval '15 minutes'
      where mobile = p_mobile;
    return false;
  end if;

  update public.auth_login_attempts
    set attempt_count = attempt_count + 1
    where mobile = p_mobile;
  return true;
end;
$$;

create or replace function public.clear_login_attempts(p_mobile text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.auth_login_attempts where mobile = p_mobile;
$$;

revoke all on function public.consume_login_attempt(text) from public, anon, authenticated;
revoke all on function public.clear_login_attempts(text) from public, anon, authenticated;
grant execute on function public.consume_login_attempt(text) to service_role;
grant execute on function public.clear_login_attempts(text) to service_role;
