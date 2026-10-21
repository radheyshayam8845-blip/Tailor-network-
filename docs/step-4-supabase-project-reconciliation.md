# Step 4 — Supabase project and migration reconciliation

**Status:** Read-only live catalog checks and repository planning only. No migrations applied; no data, secrets, accounts, or deployments changed.
**Branch:** `stage-4/project-reconciliation`
**Scope:** Garment Factory Management SaaS. Inventory Management and Machine Management remain excluded.

## Executive decision

Do **not** apply schema changes yet. There are two active Supabase projects and the project called `tailor-network-test` has no public/private application tables and no migration history. The other project has the current 10-table application schema plus `auth_login_attempts`, RLS enabled on all 11 tables, and three migration-history entries.

A project name is not authorization to mutate it. The repository and remote migration histories must be reconciled before migrations can safely run. Supabase's official workflow compares local migration files with the remote `supabase_migrations.schema_migrations` table; when they differ, the recommended path is to inspect/pull and reconcile the schema, not blindly mark migrations applied. See https://supabase.com/docs/guides/deployment/database-migrations.

## Live read-only findings

### Project A — `tailor-network-test`
- Ref: `ftoiimdfxvlmrkiloguu`
- Region: `ap-south-1`
- Status: active/healthy
- Read-only catalog query: no ordinary tables found in `public` or `private`.
- Migration history: empty.
- Interpretation: appears uninitialized from the inspected catalog; no evidence it is currently hosting the app schema.

### Project B — `radheyshayam8845-blip's Project`
- Ref: `hvsgcrnvlwsjydbyhsmx`
- Region: `ap-southeast-1`
- Status: active/healthy
- Migration history: `20261020141622`, `20261020144123`, `20261020144259`.
- Public tables found: `companies`, `profiles`, `invitations`, `lines`, `workers`, `operations`, `styles`, `dept_allocations`, `work_entries`, `subscription_invoices`, `auth_login_attempts`.
- RLS enabled: all 11 tables above.
- Policies found: admin-scoped company data policies, tailor-self policies for profiles/workers/work entries, and invitation response policies.
- Company rows currently: 0.
- Company code constraints: only primary key on `id` and unique constraint on `global_id` were found; `company_code` has no unique constraint in this live schema.

## Blocking discrepancies / risks

1. **Target is not confirmed.** The test-named project is empty; the populated project has an owner/project name, not a clear dev/test label. Do not choose automatically.
2. **Migration state differs.** Project B has three applied versions while the source schema/migration set must be checked version-by-version. Project A has none. Never run the initial schema against Project B without proving it is not already applied.
3. **RLS is present but not the whole authorization story.** RLS is enabled on the 11 tables, but there is no supervisor assignment table or department-specific permission model in the current public table inventory.
4. **Company code uniqueness is missing.** There are zero company rows today, so no existing duplicates were found; still add a database-enforced unique normalized code before multi-tenant registration is enabled.
5. **Existing live policies are admin/tailor oriented.** A supervisor role cannot be enabled by frontend changes alone.
6. **Authentication gateway origin:** current repository code defaults `APP_ORIGIN` to wildcard `*`. Production must configure a specific origin and reject unexpected browser origins; CORS is not a substitute for RLS.
7. **PIN contract mismatch:** helper/server use 10 digits while some App.jsx UI copy refers to 6 digits. Standardize the contract before wiring the login UI.
8. **No OTP:** synthetic email alias plus a confirmed Auth user does not verify mobile ownership. Do not advertise mobile verification or use it as secure account recovery.

## Safe reconciliation procedure

1. User confirms the intended development/test target (project ref, not just project display name).
2. Fetch that project's exact migration history, constraints, indexes, functions, grants, policies, triggers and table definitions.
3. Compare every local migration filename/version with remote `schema_migrations`; inspect source and remote schema diffs.
4. If a schema exists but history is missing, capture the actual remote schema into a reviewed baseline migration before any future push. Do not use migration repair unless the actual schema is proven to match the migration being marked.
5. On a fresh dev target, validate the complete migration chain in a disposable/local database first, then dry-run the push.
6. Create a new migration for unique normalized company code, supervisor roles/assignments, attendance, and job portal only after reviewing the target and access policies.
7. Run tests for admin, tailor self-only access, tenant A/B isolation, unauthorized supervisor access, duplicate company code races, and empty tenant signup.
8. Only after review and explicit approval, apply to the chosen development project. Production remains untouched.

## Out of scope
- No live database changes.
- No frontend auth changes.
- No migration history repair.
- No deployment or merge.
- No Inventory Management or Machine Management.
