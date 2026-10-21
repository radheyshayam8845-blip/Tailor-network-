# Step 3 — Authentication and tenant-security audit

**Status:** Read-only live review plus test scaffolding. No database DDL, auth accounts, secrets, or deployment changed.
**Branch:** `stage-3/auth-tenant-security-review`
**Product exclusions:** Inventory Management and Machine Management remain out of scope.

## Live target comparison

Two Supabase projects are connected:
- `tailor-network-test` (`ftoiimdfxvlmrkiloguu`): querying `pg_class` returned no tables in `public` or `private`; migration history was empty. Treat as an empty/uninitialized target, not proof that it is the intended project.
- `radheyshayam8845-blip's Project` (`hvsgcrnvlwsjydbyhsmx`): live catalog shows 10 app tables plus `auth_login_attempts`; RLS is enabled on all 11. Three migrations are recorded.

**No project was changed.** Confirm which project is the intended development/test target before any migration is applied.

## Verified findings

1. **RLS is enabled** on `companies`, `profiles`, `invitations`, `lines`, `workers`, `operations`, `styles`, `dept_allocations`, `work_entries`, `subscription_invoices`, and `auth_login_attempts` in the project with the existing migrations.
2. **Supervisor cannot work with current role policies.** Live `profiles_role_check` permits only `admin` and `tailor`. The `profiles_check` constraint also assumes admin has a company and tailor has a global ID with no company. The helper `private.my_company()` resolves only admin profiles. Adding a supervisor row to the UI alone would fail or provide no company scope.
3. **No department assignment/permission table exists.** Current RLS grants admin-wide access to company data; there is no database-enforced per-line supervisor permission.
4. **Auth gateway CORS defaults to wildcard.** `supabase/functions/auth-gateway/index.ts` uses `APP_ORIGIN ?? "*"`. Production configuration should require an explicit allowed origin and reject unexpected browser origins. CORS is not a replacement for authentication/RLS, but wildcard default is not a safe production default.
5. **Company code uniqueness is not enforced in the checked schema.** `companies.company_code` is nullable and lacks a unique constraint. Signup can race on the same code unless the database owns this rule.
6. **Auth UI contract mismatch remains.** `src/lib/auth.js` validates exactly 10-digit mobile and PIN. The existing App.jsx login comments/UI mention a 6-digit PIN in places. The Edge Function validates a 10-digit PIN. These need one consistent contract and tests.
7. **No OTP is sent.** The gateway uses an internal alias `<mobile>@mobile.auth.tailornetwork.invalid` and marks that synthetic email confirmed. Do not present this as proof that the user owns the mobile number; account recovery needs a separate verified process.
8. **Migration history mismatch:** the repo migration list and two live projects differ. Reconcile schema, constraints, policies, grants and migration history before running a new migration.

## Safe implementation order

1. Lock down which Supabase project is the development target.
2. Set a specific `APP_ORIGIN` secret for the deployed app; remove wildcard fallback and add exact-origin handling, while allowing non-browser requests only if explicitly designed.
3. Add a database uniqueness rule for normalized company code after auditing existing duplicates/nulls. Keep signup normalization in the Edge Function and database constraint as the final authority.
4. Design role membership without relying on a single `profiles.role` value to express every capability. Add a company-scoped supervisor assignment to a line and a fixed permission vocabulary.
5. Update `private.my_company()` / helper functions and policies together with supervisor membership checks. Every update policy must constrain both old-row access and new-row values.
6. Add attendance and job portal tables only with tenant-scoped FKs, grants and RLS; do not expose private company/profile data through job listing endpoints.
7. Wire App.jsx to `registerCompanyAccount`, `loginWithMobilePin`, `signOut`, and session restoration; remove the frontend mock identity only after backend-backed screens and tests exist.
8. Run the baseline pgTAP test in `supabase/tests/step3_security_baseline.test.sql`, then add negative tenant A/B and supervisor allow/deny tests before considering any migration.

## Stop conditions

- Do not apply a migration until the intended target project is explicitly confirmed and the actual schema is reconciled.
- Do not place the Supabase service-role key in browser code or frontend environment variables.
- Do not clear user LocalStorage or delete mock collections until a migration/retention plan and backend cutover are tested.
- Do not merge or deploy this branch without review and explicit approval.
