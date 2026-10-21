# Step 2 — Supabase schema gap analysis and safe migration plan

**Status:** Design/plan only. No database DDL was applied by this step.
**Repository base:** `main`; design branch: `stage-2.4/schema-gap-plan`.
**Product constraints:** no Inventory Management and no Machine Management.
**Scale goal:** design for up to 10,000 factory tenants; enforce tenant boundaries in PostgreSQL/RLS, not only in React.

## 1. Verified current state

### Repository schema
The current `schema.sql` defines 10 tables: `companies`, `profiles`, `invitations`, `lines`, `workers`, `operations`, `styles`, `dept_allocations`, `work_entries`, and `subscription_invoices`.

Observed important constraints:
- `profiles.role` currently allows only `admin` and `tailor`.
- Admin profile must have a `company_id`; tailor profile must have no company and must have a global ID.
- `private.my_company()` returns a company only when the profile role is `admin`.
- Existing company-owned tables use composite foreign keys for cross-tenant integrity on worker/style/operation references.
- RLS is enabled for all 10 application tables and explicit grants are used.
- `dept_allocations.data` is flexible JSONB; attendance, job posts/applications, and supervisor permission assignments have no dedicated tables yet.

### Supabase projects (live metadata check)
Two projects are connected:
- `tailor-network-test` — ref `ftoiimdfxvlmrkiloguu`, region `ap-south-1`, active. Migration history currently returns **zero rows**.
- `radheyshayam8845-blip's Project` — ref `hvsgcrnvlwsjydbyhsmx`, region `ap-southeast-1`, active. Migration history lists `20261020141622`, `20261020144123`, and `20261020144259`.

**Important:** the repository schema and connected project histories are not in sync. Do not apply the next migration until the intended target project is explicitly confirmed and its live tables/RLS are checked. The test-named project having no recorded migrations does not, by itself, prove it has no manually created tables.

## 2. Proposed schema additions (design)

### A. Department supervisors and permissions — required
Proposed `department_supervisors` mapping:
- `id uuid primary key`
- `company_id uuid not null`
- `line_id uuid not null`
- `supervisor_user_id uuid not null`
- `permissions jsonb not null default '{}'`
- `created_at timestamptz not null default now()`
- unique assignment on `(company_id, line_id, supervisor_user_id)`
- composite FK `(company_id, line_id)` → `lines(company_id, id)`
- FK supervisor profile → `profiles(id)`

Permission keys to define explicitly (not arbitrary client-supplied keys): `manage_workers`, `mark_attendance`, `enter_work`, `approve_work`, `view_reports`. Each assignment is scoped to a single department/line. Operations and Styles management should remain admin-only by default unless product policy explicitly grants them.

**Blocking prerequisite:** `profiles.role` and its row check currently exclude `supervisor`. A reviewed migration must update that role model and the company/global-ID check, auth-gateway signup/invitation logic, and role-aware RLS helper together. Do not just add a frontend manager role. Discover the exact live constraint names before writing the final migration.

### B. Worker attendance — required
Proposed `worker_attendance` fields:
- `id uuid primary key`
- `company_id uuid not null`
- `worker_id uuid not null`
- `attendance_date date not null`
- `status text not null check status in ('present','absent','half_day','leave')`
- `remarks text`
- `marked_by uuid references profiles(id)`
- `created_at timestamptz not null default now()`
- unique `(company_id, worker_id, attendance_date)`
- composite FK `(company_id, worker_id)` → `workers(company_id, id)`

This keeps a worker's current `workers.status` (employment status) separate from day-by-day attendance. Index at least `(company_id, attendance_date)` and `(company_id, worker_id, attendance_date)`. RLS must allow only company admins and authorized supervisors to mark/read the appropriate line's records. A tailor must not mark attendance for others.

### C. Job Portal — required
Proposed `job_posts` fields:
- `id uuid primary key`, `company_id uuid not null`, `created_by uuid references profiles(id)`
- `title text not null`, `description text`, `garment_types text[] not null default '{}'`, `skills text[] not null default '{}'`
- `location text`, `status text not null check status in ('draft','published','closed')`
- `expires_at timestamptz`, `created_at timestamptz not null default now()`
- composite tenant FK to `companies` as applicable; index `(company_id, status, created_at desc)`

Proposed `job_applications` fields:
- `id uuid primary key`, `company_id uuid not null`, `job_post_id uuid not null`, `applicant_user_id uuid not null references profiles(id)`
- `message text`, `status text not null check status in ('submitted','reviewing','shortlisted','rejected','withdrawn','accepted')`
- `created_at timestamptz not null default now()`, `updated_at timestamptz not null default now()`
- unique `(job_post_id, applicant_user_id)`; composite FK `(company_id, job_post_id)` → `job_posts(company_id, id)`

Access rules need two paths: a public-to-signed-in tailor can read published job posts without seeing private company data; the company can manage its own posts and applications; an applicant can read/update only their own application within the permitted state transitions. Do not expose mobile numbers or company settings through public job listings.

### D. Notes and advances — defer pending policy
The frontend has `selfNotes` and `selfAdvances` in local state. Do not automatically migrate these as company-visible financial records. First decide whether notes are private to a tailor and whether advances are actual payroll liabilities. If confirmed, create separate tables with owner/company scope and audit trail rather than storing them in arbitrary JSON.

## 3. Existing-table alignment work

| Existing table | Needed review |
|---|---|
| `profiles` | Supervisor role model, company membership, role assignment only through trusted server path. |
| `companies` | Enforce company-code uniqueness and normalize mobile storage/validation contract. |
| `invitations` | Frontend uses company name, tailor display ID, line IDs/names, designation, response timestamp, and source marker; DB currently stores only company, tailor, status, created time. Decide normalized fields and transition rules. |
| `lines` | Use as departments/production lines; add permissions through mapping table, not a single `dept_head` text field. |
| `workers` | Current line_id is one department only; if workers can work across multiple lines, add a company-scoped worker-line assignment table instead of encoding lists in frontend state. |
| `operations` | Keep piece rate here; rate must be server-derived for work entries. Add uniqueness only after confirming duplicate operation-name rules. |
| `styles` | Current `lines text[]` and `op_names text[]` are display-oriented; normalize style-operation/line assignments if reports need relational joins and referential integrity. |
| `dept_allocations` | Replace or constrain free-form JSONB after reviewing exact fields; define unique cycle/department/style rules to prevent duplicate allocations. |
| `work_entries` | Add supervisor-aware policies and approval workflow. Keep generated amount and operation-derived rate; add appropriate indexes for common tenant/date/worker/style reports. |
| `subscription_invoices` | Keep writes server-side only; payment verification must not be client-trusted. |

## 4. RLS and authorization design

Do not rely on hiding buttons, a client-provided `company_id`, or a role stored in localStorage.

1. Every company-owned record must be constrained by authenticated profile membership and `company_id`.
2. Supervisor authorization must additionally verify an active `department_supervisors` assignment for the specific `line_id` and the exact permission key.
3. Any table with a line/worker relationship must validate tenant identity with composite foreign keys and policy predicates.
4. `UPDATE` policies require both `USING` and `WITH CHECK`; test attempts to move a row to another company/worker/line.
5. Public/signed-in job listings must expose only explicitly approved listing columns, never profile/mobile/company-settings data. Consider a restricted view with `security_invoker = true` (Postgres 15+) or a carefully scoped RPC.
6. Review every `SECURITY DEFINER` function for a fixed `search_path`, explicit identity/tenant checks, and least-privilege execute grants.
7. Do not use editable user metadata as authorization claims. Role and tenant membership must be stored in trusted profile/database records.

## 5. Migration order

1. Confirm the target Supabase project and inspect its live table definitions, constraints, RLS policies, grants, and applied migration list.
2. Reconcile repository migrations with the selected project before adding a new version.
3. Design supervisor role transition and update the auth gateway in the same release; test registration, invitations, logout/session restore, and role downgrade/revocation.
4. Add department supervisor assignments and authorization helper(s), then attendance table and RLS.
5. Add job posts/applications and restricted listing access.
6. Decide whether worker-line assignments are needed and normalize allocations/style operations if reporting requires it.
7. Run advisors and SQL tests: admin access, supervisor allowed/denied permissions, tailor self-only access, tenant A vs tenant B isolation, cross-tenant FK rejection, attendance uniqueness, job post visibility, and application privacy.
8. Only after all checks pass should a migration be proposed for review. Do not apply to production or deploy without explicit approval.

## 6. Acceptance checklist

- [ ] Target Supabase project explicitly confirmed.
- [ ] Live schema and migration history reconciled.
- [ ] No inventory or machine tables/features added.
- [ ] Supervisor can access only assigned departments and only granted actions.
- [ ] Attendance supports date-wise present/absent/half-day/leave history.
- [ ] Work-entry amount and operation rate remain database-enforced.
- [ ] Published job listings reveal no private company/profile fields.
- [ ] Job applications are private to applicant and relevant employer.
- [ ] Cross-tenant reads/writes fail in direct SQL/API tests.
- [ ] Migration is versioned, reviewed, and reversible where practical.
- [ ] No production migration/deployment without approval.
