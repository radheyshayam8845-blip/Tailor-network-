-- Correct mobile validation to avoid regex escape ambiguity across SQL settings.
alter table public.auth_login_attempts drop constraint if exists auth_login_attempts_mobile_check;
alter table public.auth_login_attempts add constraint auth_login_attempts_mobile_check check (mobile ~ '^[0-9]{10}$');

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
  if p_mobile is null or p_mobile !~ '^[0-9]{10}$' then return false; end if;
  insert into public.auth_login_attempts(mobile, attempt_count, window_started_at)
  values (p_mobile, 0, v_now)
  on conflict (mobile) do nothing;
  select * into current_row from public.auth_login_attempts where mobile = p_mobile for update;
  if current_row.locked_until is not null and current_row.locked_until > v_now then return false; end if;
  if v_now - current_row.window_started_at >= interval '15 minutes' then
    update public.auth_login_attempts set attempt_count = 1, window_started_at = v_now, locked_until = null where mobile = p_mobile;
    return true;
  end if;
  if current_row.attempt_count >= 9 then
    update public.auth_login_attempts set locked_until = v_now + interval '15 minutes' where mobile = p_mobile;
    return false;
  end if;
  update public.auth_login_attempts set attempt_count = attempt_count + 1 where mobile = p_mobile;
  return true;
end;
$$;
