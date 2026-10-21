# Step 1 — TailorNetwork source, collection, screen, and persistence audit

**Status:** Source-level inventory completed for the current `main` App.jsx blob. Review-only; no app logic, database, environment, production deployment, or production data changed.
**Source:** `App.jsx` (blob SHA `6f8828ba23b818e116f8c7edb18fa002af31e510`, TailorNetwork v38 marker).
**Scope constraints:** Keep Inventory Management and Machine Management out of the product.

## 1. Executive summary

- The frontend is a large single-file React app (React.createElement output) with hardcoded `MOCK_DB`, demo seeders, and browser LocalStorage persistence.
- `PERSISTED` hydrates mock/app state before the app starts. Hiding demo buttons or clearing one key alone will not remove all sample records.
- A current-month work-entry seeder runs unconditionally at module load; several other seeders are gated by demo mode.
- Login/session handling in this file is still a frontend prototype. The existing Supabase auth helper files are not evidence that the Login/Register UI is wired end-to-end.
- The code comments and implementation disagree in places about authentication/PIN format. Backend contract must be made authoritative before wiring the UI.
- The UI includes manager role behavior, department work entry, a tailor network/connect area and job/hiring-post features. These are not fully represented in the current 10-table Supabase schema.
- **Do not remove `MOCK_DB` arrays or clear user storage before backend cutover and a tested migration path.**

## 2. MOCK_DB collection inventory

Fields below are observed in seed records or construction paths; some fields are optional/added dynamically. This is not a claim that every record has every field.

| Collection / object | Observed fields | Purpose / notes |
|---|---|---|
| `currentUser` | `id, name, mobile, role, tenantName, companyId` | Hardcoded default demo identity; must never be an authentication source in production. |
| `companies[]` | `id, name, companyCode, adminMobile` | Hardcoded sample companies; dynamic profile/settings may add further fields. |
| `companyOwners[]` | `id, name, mobile, companyId, tenantName, role`, password-record fields from `makePasswordRecord` | Demo owner/admin account list. PIN/password material must remain server-side and must not be stored as plaintext. |
| `tailorAccounts[]` | `id, globalId, name, mobile, garmentTypes, createdAt`, password-record fields; some flows add profile/location/skill metadata | Global tailor accounts, separate from a company until connected. Dynamic shape. |
| `idRegistry` | `tailor, company, retired` (and optional `scheme`) | Frontend-only monotonically increasing IDs. Must move to database-generated IDs for multi-device concurrency. |
| `invitations[]` | `id, companyId, companyName, tailorId, tailorGlobalId, tailorName, maskedMobile, staffId, designation, lineIds, lineNames, status, createdAt, respondedAt`; some records include a `source` marker | Company-to-tailor invitations and responses. |
| `workers[]` | `companyId, id, name, staffId, mobile, line, lineId, joinDate, status, designation, skill`; dynamic fields include `tailorUserId` / manager/team fields | Company-specific worker/tailor records. No normalized attendance-history collection in this mock schema. |
| `lines[]` | `companyId, id, lineCode, name, color, deptHead, workerCount, dailyTarget`; dynamic fields include `managerMobile, managerCanAddMembers` | Departments/production lines. Department-wise permissions are currently not modeled as a full roles/permissions table. |
| `operations[]` | `companyId, id, name, pieceRate, garmentType, line` | Operation catalogue; piece-rate system belongs inside Operation Management. |
| `styles[]` | `companyId, id, styleNumber, styleName, totalQuantity, completedQty, status, lines, opNames, combos` | Style catalogue and operation grouping. Additional fields may be attached by Style Files helpers. |
| `workEntries[]` | `companyId, id, date, workerId, styleId, operationId, workerName, staffId, styleName, operation, pieces, pieceRate, amount, line`; optional `status, enteredBy` | Production records; demo seeder also generates current-month records. |
| `selfEntries[]` | `companyId, id, workerName, staffId, date, style, operation, pieces, status` | Sample personal/self-entry history; distinct from the primary admin work-entry list. |

### Extra state persisted outside MOCK_DB

- `entries`: shared work entries.
- `workers`, `styles`, `lines`: shared editable collections.
- `workerLineMap`: worker ID → list of department/line IDs.
- `deptAllocations`: style/department/cycle/quantity allocation records; observed fields include `id, companyId, styleId, department, operationId, cycleKey, cycleLabel, allocatedQty, remarks, createdAt`.
- `cycleType`, `graceDays`, `companySettings`: work-cycle and entry-grace configuration, with settings intended to be keyed by company ID.
- `selfNotes`, `selfAdvances`: personal tailor notes/advances, intentionally separate from admin payroll/report totals.
- Runtime state also includes selected cycle, navigation state, active department, auto-open flags, and other transient UI state; these are not all part of the persisted payload.

## 3. LocalStorage inventory and read/write behavior

| Key | Purpose | Read/write behavior | Cutover treatment |
|---|---|---|---|
| `twe_state_v7` | Main app state snapshot | Read by `PERSISTED`; auto-saved after changes with entries/workers/styles/line map/allocations/settings/self notes/advances. Saved `user` is explicitly deleted during hydration. | Stop using only after all dependent screens read authenticated Supabase data; migrate only approved business records, never treat this as an auth session. |
| `twe_mock_v2` | Mock account/catalog fragments | Hydrates operations, companies, owners, tailor accounts, invitations, and ID registry; `saveMockParts()` writes them back. | Legacy mock source; remove after auth/data cutover. |
| `twe_state_v3`, `twe_state_v4`, `twe_state_v5`, `twe_state_v6`, `twe_mock_v1` | Older versions | Current code removes these keys during startup. | Do not expand this cleanup to unrelated keys. Confirm migration/retention expectations first. |
| `taylo_intro_seen` | Intro/role-information page dismissal | Read to choose initial login/intro screen; written when intro is dismissed. | UI preference; can remain device-local if desired. |
| `taylo_remember_mobile` | Remembered mobile number | Read during login initialization; helper uses LocalStorage to read/write/delete. | Prefer storing only a non-sensitive convenience value; never PIN/password/session tokens. |
| `tw_sub_demo_shift_days` | Demo subscription-clock offset | Read/written only for demo subscription simulation. | Remove from production feature; server time is authoritative. |
| `twes_connect_prototype_v1` | Connect/network prototype data | Read/written by Connect panel. | Job/network posts and connections need a real tenant-aware backend before this can be removed. |
| `twes_custom_post_opts_v1` | Custom job-post garment/skill options | Stores arrays `garments` and `skills` on the device. | Decide whether these are personal preferences or shared company data; backend migration if shared. |

**Important:** the current source also contains a `twResetData()` demo reset path (gated by demo mode) and a startup deletion of old versioned keys. Do not run destructive reset hooks during production validation.

## 4. Screen / navigation inventory

### Admin navigation items declared in `NAV_ITEMS`

| Route ID | UI label | Role / behavior |
|---|---|---|
| `departments` | Departments | Admin; department list and embedded department workflow. |
| `styles` | Style Report / Styles | Admin; style list/detail, operations and allocations. |
| `operations` | Operations | Admin; operation catalogue and piece-rate editing. |
| `approvals` | Tailor Record | Admin; approval/records area; code comments indicate Work Report tabs are integrated here. |
| `work-report` | Work Report | Admin; report view and cycle filter. |
| `connect` | TailorNetwork | Admin; network/connect/hiring-post flows. |
| `self-entry` | Self Entry | Tailor; tailor self-entry experience. |

### Additional routes / panels found in the render switch

- `dashboard` — Dashboard (also used as the drawer/header shell).
- `dept-work` — department-specific Work Entry panel.
- Role-specific panels: `TailorPanel` for tailor, `ManagerPanel` for manager.
- Login/registration sub-screens: `role-info`, `register-owner`, `tailor-wait`, `register-tailor`, plus login flow.
- Profile is implemented as a page/panel inside the app; it is not an entry in the primary `NAV_ITEMS` array.
- Job/hiring-post functionality is part of the Connect/TailorNetwork prototype rather than a dedicated standalone backend module.

## 5. Existing Supabase schema: 10 application tables

The repository's `schema.sql` defines:
1. `companies`
2. `profiles`
3. `invitations`
4. `lines`
5. `workers`
6. `operations`
7. `styles`
8. `dept_allocations`
9. `work_entries`
10. `subscription_invoices`

RLS is declared for these tables. The schema intentionally excludes Inventory Management and Machine Management. This document only audits repository files; it does **not** re-check live Supabase configuration or prove that a migration is currently applied.

## 6. MOCK_DB → Supabase mapping and gaps

| Frontend source | Current backend target | Status / gap |
|---|---|---|
| `companies` | `companies` | Field names differ (e.g. `companyCode` vs `company_code`); registration must be server-side. |
| `companyOwners`, `tailorAccounts`, `currentUser` | `profiles` + `auth.users` | Frontend demo accounts/password records must not be copied as-is. Auth gateway must create profiles and sessions. |
| `invitations` | `invitations` | Normalize camelCase to snake_case; current DB table has fewer fields than the frontend invitation shape. |
| `lines` | `lines` | Current DB `lines` lacks several UI fields such as color, department head, manager permissions, and worker count. Some are computed/display-only; decide deliberately. |
| `workers` | `workers` | Map `staffId`→`staff_id`, `lineId`→`line_id`; check team/manager metadata and status constraints. |
| `operations` | `operations` | Map `pieceRate`→`piece_rate`, `garmentType`→`garment_type`; operation rate is authoritative for work-entry calculations. |
| `styles` | `styles` | Map camelCase fields; current schema supports `lines`, `op_names`, `combos` but not every optional UI-derived field. |
| `workEntries`, `selfEntries` | `work_entries` | `selfEntries` has a different shape; decide whether it is a view over work entries or a separate private-note concept. Work entry amount should be server/database calculated. |
| `deptAllocations` | `dept_allocations` | DB stores flexible `data jsonb`; verify queryability/constraints and unique allocation rules. |
| Job/hiring posts and Connect prototype data | **No dedicated table in the current 10-table schema** | Design tenant-aware posts, applications/connections, and access policies before backend wiring. |
| `selfNotes`, `selfAdvances` | **No dedicated table in the current 10-table schema** | Decide privacy, retention, and whether these are notes or financial records before adding tables. |
| Worker attendance/history/performance | **No dedicated attendance table in the current 10-table schema** | Product requirement needs date-wise present/absent and performance history; model separately, do not overload worker status. |
| Department-wise supervisor roles/permissions | **No full role/permission table in the current 10-table schema** | Current `profiles.role` permits only `admin` and `tailor`; manager UI exists in frontend. Add secure company-scoped supervisor/permission design before launch. |

## 7. Security and correctness findings to address before Stage 2 integration

1. **Demo identity and sample records:** hardcoded `MOCK_DB.currentUser`, company/owner/worker/style/operation/work-entry samples must never be used as production identity or new-tenant data.
2. **Unconditional current-month seeder:** `seedCurrentMonthDemoEntries()` appends synthetic entries at module load. Remove only after real backend reads/writes are wired and build/smoke tests cover empty tenants.
3. **Storage rehydration:** `PERSISTED` restores saved business data; simply hiding demo buttons does not create a clean tenant.
4. **Authentication mismatch:** frontend comments describe a 6-digit PIN in the login page, while the Supabase helper validates a 10-digit PIN. Select one documented contract and update UI, server, tests and copy consistently before wiring.
5. **LocalStorage is not a secure auth boundary:** never use local mock user state, remembered mobile, or frontend role checks as authorization. Require a valid Supabase session and enforce access in RLS/Edge Functions.
6. **Supervisor/manager access:** frontend manager behavior is not equivalent to database-enforced per-department permissions.
7. **Attendance and job portal gaps:** required product workflows need explicit backend data models and RLS; they are not satisfied by current workers/invitations tables alone.
8. **Sensitive demo credentials:** the source contains sample account/password material. Do not copy or reuse it in a production seed, documentation, or live account.

## 8. Safe next steps after this audit

- Review this report and agree on the missing data models.
- Wire login/company registration to the Supabase Edge Function and validate session restore/logout.
- Add a tenant-scoped data repository layer and empty initial state.
- Connect one module at a time (Departments/Workers → Styles → Operations/rates → Work Entry → Approvals/Reports → Profile → Connect/Job Portal).
- Add worker attendance/performance and supervisor permission schemas before claiming those requirements are implemented.
- Remove demo seeders and legacy mock persistence only after all dependent screens are backend-backed.
- Run build, auth, RLS/tenant A-vs-B isolation, duplicate account, rate-limit, empty-tenant, and migration rollback tests.
- Merge or deploy only after review and explicit approval.

## 9. What this audit does not claim

- It does not prove a live Supabase migration is applied or a Vercel deployment is current.
- It does not claim end-to-end tests passed.
- It does not change `App.jsx`, database contents, environment variables, or production deployment.
- It does not include Inventory Management or Machine Management.
