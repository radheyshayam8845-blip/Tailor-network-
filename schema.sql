-- TailorNetwork — Supabase schema (draft, multi-tenant). Run in Supabase SQL Editor.
-- Har company ka data alag: RLS se sirf apni company_id ke rows dikhte hain.

create extension if not exists pgcrypto;

-- ---------- ID sequences (TW000001 / CO000001, kabhi repeat nahi) ----------
create sequence if not exists tailor_id_seq;
create sequence if not exists company_id_seq;

-- ---------- Core ----------
create table companies (
  id uuid primary key default gen_random_uuid(),
  global_id text unique not null default ('CO' || lpad(nextval('company_id_seq')::text, 6, '0')),
  name text not null,
  company_code text,
  admin_mobile text,
  settings jsonb not null default '{}',          -- cycleType, graceDays, companySettings
  created_at timestamptz not null default now()
);

create table profiles (                           -- auth.users ke saath 1:1
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','tailor')),
  name text not null,
  mobile text unique not null,
  company_id uuid references companies(id),      -- admin ke liye
  global_id text unique,                          -- tailor ke liye TW000001
  created_at timestamptz not null default now()
);

create table invitations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  tailor_user_id uuid not null references profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default now(),
  unique (company_id, tailor_user_id)
);

-- ---------- Per-company data ----------
create table lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  line_code text, name text not null, color text, dept_head text, daily_target int
);
create table workers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  tailor_user_id uuid references profiles(id),
  name text not null, staff_id text not null, mobile text,
  line_id uuid references lines(id), designation text, skill text,
  join_date date, status text not null default 'active',
  unique (company_id, staff_id)
);
create table operations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null, piece_rate numeric(10,2) not null check (piece_rate >= 0),
  garment_type text, line_name text
);
create table styles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  style_number text not null, style_name text not null,
  total_quantity int not null default 0, status text not null default 'active',
  lines text[] not null default '{}',
  op_names text[] not null default '{}',
  combos jsonb not null default '[]'
);
create table dept_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  style_id uuid references styles(id) on delete cascade,
  data jsonb not null default '{}'
);
create table work_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  entry_date date not null,
  worker_id uuid not null references workers(id),
  style_id uuid not null references styles(id),
  operation_id uuid not null references operations(id),
  pieces int not null check (pieces > 0),
  piece_rate numeric(10,2) not null,
  amount numeric(12,2) generated always as (pieces * piece_rate) stored,  -- amount server par nikalta hai
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  entered_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index on work_entries (company_id, entry_date);
create index on work_entries (worker_id);

-- ---------- Subscription (Razorpay) — sirf server likhe ----------
create table subscription_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  cycle_key text not null, amount numeric(12,2) not null,
  status text not null default 'unpaid', due_date date, paid_at timestamptz,
  razorpay_order_id text, razorpay_payment_id text,
  unique (company_id, cycle_key)
);

-- ---------- RLS ----------
create or replace function my_company() returns uuid
  language sql stable security definer set search_path = public as
  $$ select company_id from profiles where id = auth.uid() and role = 'admin' $$;

alter table companies enable row level security;
alter table profiles enable row level security;
alter table invitations enable row level security;
alter table lines enable row level security;
alter table workers enable row level security;
alter table operations enable row level security;
alter table styles enable row level security;
alter table dept_allocations enable row level security;
alter table work_entries enable row level security;
alter table subscription_invoices enable row level security;

create policy own_profile on profiles for select using (id = auth.uid() or company_id = my_company());
create policy own_profile_upd on profiles for update using (id = auth.uid());
create policy company_rw on companies for all using (id = my_company()) with check (id = my_company());

-- Admin apni company ka sab kuch; tailor sirf apni (accepted) company ke apne rows padh sake
do $$ declare t text; begin
  foreach t in array array['lines','workers','operations','styles','dept_allocations','work_entries'] loop
    execute format('create policy %I_admin on %I for all using (company_id = my_company()) with check (company_id = my_company())', t, t);
  end loop;
end $$;

create policy tailor_own_entries on work_entries for select
  using (worker_id in (select id from workers where tailor_user_id = auth.uid()));
create policy tailor_own_worker on workers for select using (tailor_user_id = auth.uid());

create policy inv_company on invitations for all using (company_id = my_company()) with check (company_id = my_company());
create policy inv_tailor_read on invitations for select using (tailor_user_id = auth.uid());
create policy inv_tailor_resp on invitations for update using (tailor_user_id = auth.uid());

create policy sub_read on subscription_invoices for select using (company_id = my_company());
-- subscription_invoices par insert/update policy nahi: sirf service-role (Edge Function / webhook) likhega.
