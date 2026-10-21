begin;

select plan(15);

select has_table(
  'public',
  'auth_signup_attempts',
  'signup attempt table exists'
);

select has_index(
  'public',
  'companies',
  'companies_company_code_normalized_uidx',
  'normalized company-code unique index exists'
);

select has_function(
  'public',
  'consume_signup_attempt',
  array['text'],
  'signup limiter RPC exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.auth_signup_attempts'::regclass),
  'signup attempts table has row-level security enabled'
);

select ok(
  not has_function_privilege('anon', 'public.consume_signup_attempt(text)', 'EXECUTE'),
  'anon cannot execute signup limiter'
);

select ok(
  not has_function_privilege('authenticated', 'public.consume_signup_attempt(text)', 'EXECUTE'),
  'authenticated cannot execute signup limiter'
);

select ok(
  has_function_privilege('service_role', 'public.consume_signup_attempt(text)', 'EXECUTE'),
  'service_role can execute signup limiter'
);

select is(
  public.consume_signup_attempt('not-a-mobile'),
  false,
  'invalid mobile is rejected'
);

-- Use a test-only mobile and roll the whole test back at the end.
delete from public.auth_signup_attempts where mobile = '0000000001';

select is(public.consume_signup_attempt('0000000001'), true, 'attempt 1 is allowed');
select is(public.consume_signup_attempt('0000000001'), true, 'attempt 2 is allowed');
select is(public.consume_signup_attempt('0000000001'), true, 'attempt 3 is allowed');
select is(public.consume_signup_attempt('0000000001'), true, 'attempt 4 is allowed');
select is(public.consume_signup_attempt('0000000001'), true, 'attempt 5 is allowed');
select is(public.consume_signup_attempt('0000000001'), false, 'attempt 6 is blocked');
select is(public.consume_signup_attempt('0000000001'), false, 'attempts remain blocked during lockout');

select * from finish();
rollback;
