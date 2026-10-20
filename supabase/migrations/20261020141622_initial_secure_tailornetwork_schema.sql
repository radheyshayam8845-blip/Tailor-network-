-- TailorNetwork: secure multi-tenant Supabase schema.
-- Apply through a Supabase migration; do not run manually in the SQL editor.
-- Inventory Management and Machine Management are intentionally excluded.

create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;


-- Non-repeating public IDs. Sequences are intentionally never reset.
create sequence if not exists public.tailor_id_seq;
create sequence if not exists public.company_id_seq;

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  global_id text not null unique default ('CO' || lpad(nextval('public.company_id_seq')::text, 6, '0')),
  name text not null,
  company_code text,
  admin_mobile text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (id)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','tailor')),
  name text not null,
  mobile text not null unique,
  company_id uuid references public.companies(id),
  global_id text unique,
  created_at timestamptz not null default now(),
  check ((role = 'admin' and company_id is not null and global_id is null)
      or (role = 'tailor' and company_id is null and global_id is not null))
);

create or replace function private.assign_profile_global_id()
returns trigger
language plpgsql
set search_path = ''
as $profile_id$
begin
  if new.role = 'tailor' and new.global_id is null then
    new.global_id := 'TW' || lpad(nextval('public.tailor_id_seq')::text, 6, '0');
  elsif new.role = 'admin' then
    new.global_id := null;
  end if;
  return new;
end;
$profile_id$;

create trigger profiles_assign_global_id
before insert on public.profiles
for each row execute function private.assign_profile_global_id();

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  tailor_user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique (company_id, tailor_user_id)
);

create table public.lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  line_code text,
  name text not null,
  color text,
  dept_head text,
  daily_target integer,
  unique (company_id, id)
);

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  tailor_user_id uuid references public.profiles(id) on delete set null,
  name text not null,
  staff_id text not null,
  mobile text,
  line_id uuid,
  designation text,
  skill text,
  join_date date,
  status text not null default 'active',
  unique (company_id, staff_id),
  unique (company_id, id),
  foreign key (company_id, line_id) references public.lines(company_id, id)
);

create table public.operations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  piece_rate numeric(10,2) not null check (piece_rate >= 0),
  garment_type text,
  line_name text,
  unique (company_id, id)
);

create table public.styles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  style_number text not null,
  style_name text not null,
  total_quantity integer not null default 0 check (total_quantity >= 0),
  status text not null default 'active',
  lines text[] not null default '{}',
  op_names text[] not null default '{}',
  combos jsonb not null default '[]'::jsonb,
  unique (company_id, style_number),
  unique (company_id, id)
);

create table public.dept_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  style_id uuid,
  data jsonb not null default '{}'::jsonb,
  foreign key (company_id, style_id) references public.styles(company_id, id) on delete cascade
);

create table public.work_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entry_date date not null,
  worker_id uuid not null,
  style_id uuid not null,
  operation_id uuid not null,
  pieces integer not null check (pieces > 0),
  piece_rate numeric(10,2) not null check (piece_rate >= 0),
  amount numeric(12,2) generated always as (pieces * piece_rate) stored,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  entered_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  foreign key (company_id, worker_id) references public.workers(company_id, id),
  foreign key (company_id, style_id) references public.styles(company_id, id),
  foreign key (company_id, operation_id) references public.operations(company_id, id)
);
create index work_entries_company_date_idx on public.work_entries(company_id, entry_date);
create index work_entries_worker_idx on public.work_entries(worker_id);

create table public.subscription_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cycle_key text not null,
  amount numeric(12,2) not null check (amount >= 0),
  status text not null default 'unpaid',
  due_date date,
  paid_at timestamptz,
  razorpay_order_id text,
  razorpay_payment_id text,
  unique (company_id, cycle_key)
);

-- Security-definer helpers avoid recursive RLS evaluation on profiles/invitations.

create or replace function private.my_company()
returns uuid
language sql stable security definer
set search_path = ''
set row_security = off
as $$
  select p.company_id
  from public.profiles p
  where p.id = (select auth.uid()) and p.role = 'admin'
  limit 1
$$;

create or replace function private.is_my_worker(p_worker_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
set row_security = off
as $$
  select exists (
    select 1 from public.workers w
    where w.id = p_worker_id and w.tailor_user_id = (select auth.uid())
  )
$$;

-- A submitted rate is never trusted: it is read from the same company's operation.
-- Composite foreign keys also prevent cross-company references.
create or replace function private.set_work_entry_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
set row_security = off
as $$
declare
  v_rate numeric(10,2);
  v_worker_tailor uuid;
begin
  select o.piece_rate into v_rate
  from public.operations o
  where o.id = new.operation_id and o.company_id = new.company_id;

  if v_rate is null then
    raise exception 'Operation does not belong to this company';
  end if;

  select w.tailor_user_id into v_worker_tailor
  from public.workers w
  where w.id = new.worker_id and w.company_id = new.company_id;

  if not found then
    raise exception 'Worker does not belong to this company';
  end if;

  if not exists (
    select 1 from public.styles s
    where s.id = new.style_id and s.company_id = new.company_id
  ) then
    raise exception 'Style does not belong to this company';
  end if;

  if (select p.role from public.profiles p where p.id = (select auth.uid())) = 'tailor'
     and v_worker_tailor is distinct from (select auth.uid()) then
    raise exception 'Tailors can submit work only for their own worker record';
  end if;

  new.piece_rate := v_rate;
  if new.entered_by is null then
    new.entered_by := (select auth.uid());
  end if;
  return new;
end;
$$;

create trigger work_entries_set_rate
before insert or update of company_id, worker_id, style_id, operation_id, piece_rate
on public.work_entries
for each row execute function private.set_work_entry_rate();

-- RLS is enabled on every table exposed to the application.
alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.invitations enable row level security;
alter table public.lines enable row level security;
alter table public.workers enable row level security;
alter table public.operations enable row level security;
alter table public.styles enable row level security;
alter table public.dept_allocations enable row level security;
alter table public.work_entries enable row level security;
alter table public.subscription_invoices enable row level security;

create policy profiles_select_self on public.profiles
  for select to authenticated using (id = (select auth.uid()));
-- No client insert/update/delete on profiles: trusted signup/onboarding flow will create them.

create policy companies_select_admin on public.companies
  for select to authenticated using (id = (select private.my_company()));
create policy companies_update_admin on public.companies
  for update to authenticated using (id = (select private.my_company()))
  with check (id = (select private.my_company()));

create policy invitations_admin_all on public.invitations
  for all to authenticated
  using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy invitations_tailor_select on public.invitations
  for select to authenticated using (tailor_user_id = (select auth.uid()));
create policy invitations_tailor_respond on public.invitations
  for update to authenticated
  using (tailor_user_id = (select auth.uid()) and status = 'pending')
  with check (tailor_user_id = (select auth.uid()) and status in ('accepted','rejected'));

create policy lines_admin_all on public.lines
  for all to authenticated using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy workers_admin_all on public.workers
  for all to authenticated using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy workers_tailor_select_own on public.workers
  for select to authenticated using (tailor_user_id = (select auth.uid()));
create policy operations_admin_all on public.operations
  for all to authenticated using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy styles_admin_all on public.styles
  for all to authenticated using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy dept_allocations_admin_all on public.dept_allocations
  for all to authenticated using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy work_entries_admin_all on public.work_entries
  for all to authenticated using (company_id = (select private.my_company()))
  with check (company_id = (select private.my_company()));
create policy work_entries_tailor_select_own on public.work_entries
  for select to authenticated using ((select private.is_my_worker(worker_id)));
create policy work_entries_tailor_insert_own on public.work_entries
  for insert to authenticated
  with check (
    entered_by = (select auth.uid())
    and (select private.is_my_worker(worker_id))
    and company_id = (select w.company_id from public.workers w where w.id = worker_id and w.tailor_user_id = (select auth.uid()))
  );

create policy subscription_invoices_admin_select on public.subscription_invoices
  for select to authenticated using (company_id = (select private.my_company()));
-- Invoice writes are reserved for trusted server-side payment functions.

-- Explicit table grants: RLS controls rows; grants control API/table reachability.
revoke all on table public.companies, public.profiles, public.invitations,
  public.lines, public.workers, public.operations, public.styles,
  public.dept_allocations, public.work_entries, public.subscription_invoices
from anon, authenticated;

grant select, update on public.companies to authenticated;
grant select on public.profiles to authenticated;
grant select, insert on public.invitations to authenticated;
grant update (status) on public.invitations to authenticated;
grant select, insert, update, delete on public.lines, public.workers,
  public.operations, public.styles, public.dept_allocations, public.work_entries
to authenticated;
grant select on public.subscription_invoices to authenticated;

-- Prevent users from escalating their profile role or changing tenant membership.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
revoke insert, update, delete on public.companies from anon, authenticated;
grant select, update on public.companies to authenticated;
revoke insert, update, delete on public.subscription_invoices from anon, authenticated;
grant select on public.subscription_invoices to authenticated;
revoke insert, update, delete on public.invitations from anon, authenticated;
grant select, insert on public.invitations to authenticated;
grant update (status) on public.invitations to authenticated;


revoke all on function private.my_company() from public, anon;
revoke all on function private.is_my_worker(uuid) from public, anon;
revoke all on function private.set_work_entry_rate() from public, anon, authenticated;
revoke all on function private.assign_profile_global_id() from public, anon, authenticated;
grant execute on function private.my_company() to authenticated;
grant execute on function private.is_my_worker(uuid) to authenticated;
