-- Step 3 baseline security tests for the existing 10-table schema.
-- Run against the selected local/test Supabase database with: supabase test db
-- This intentionally tests existing baseline only; supervisor permissions need separate tests after implementation.
begin;

select plan(20);

select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.companies'::regclass), 'companies has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.profiles'::regclass), 'profiles has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.invitations'::regclass), 'invitations has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.lines'::regclass), 'lines has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.workers'::regclass), 'workers has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.operations'::regclass), 'operations has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.styles'::regclass), 'styles has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.dept_allocations'::regclass), 'dept_allocations has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.work_entries'::regclass), 'work_entries has RLS enabled');
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.subscription_invoices'::regclass), 'subscription_invoices has RLS enabled');

select ok(not has_table_privilege('anon', 'public.companies', 'SELECT'), 'anon cannot select companies');
select ok(not has_table_privilege('anon', 'public.profiles', 'SELECT'), 'anon cannot select profiles');
select ok(not has_table_privilege('anon', 'public.invitations', 'SELECT'), 'anon cannot select invitations');
select ok(not has_table_privilege('anon', 'public.lines', 'SELECT'), 'anon cannot select lines');
select ok(not has_table_privilege('anon', 'public.workers', 'SELECT'), 'anon cannot select workers');
select ok(not has_table_privilege('anon', 'public.operations', 'SELECT'), 'anon cannot select operations');
select ok(not has_table_privilege('anon', 'public.styles', 'SELECT'), 'anon cannot select styles');
select ok(not has_table_privilege('anon', 'public.dept_allocations', 'SELECT'), 'anon cannot select dept_allocations');
select ok(not has_table_privilege('anon', 'public.work_entries', 'SELECT'), 'anon cannot select work_entries');
select ok(not has_table_privilege('anon', 'public.subscription_invoices', 'SELECT'), 'anon cannot select subscription_invoices');

select * from finish();
rollback();
