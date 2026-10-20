# Stage 2.1 — Demo-data removal and auth cutover

## Status
Review-only implementation plan. This change does not delete production data, deploy code, apply migrations, or merge any pull request.

## Findings from App.jsx
- Demo mode is enabled by default because `TWES_PROD_HOSTS` is an empty list.
- `MOCK_DB` contains a hardcoded sample admin, companies, owners, workers, styles, operations, and work entries.
- A current-month seeder adds sample work entries unconditionally.
- Several other demo seeders add sample accounts/invitations when demo mode is on.
- `twe_mock_v2` and `twe_state_v7` restore saved local mock data; hiding demo buttons alone will not remove these records.
- Login/register UI still uses the legacy local/mock flow and is not yet connected end-to-end to Supabase auth helpers.

## Safe implementation sequence
1. Wire the login and company-registration UI to the server-side Supabase `auth-gateway` and require a valid Supabase session before showing tenant data.
2. Add a clean, empty initial state for new tenants; load company-scoped data from Supabase RLS-protected tables only.
3. Remove the demo login buttons and all demo seed functions, including the unconditional current-month work-entry seeder.
4. Stop restoring mock records from `twe_mock_v2` / `twe_state_v7`. During cutover, clear only these known app-owned demo keys after the user signs out or after the new authenticated flow is in place; do not clear unrelated localStorage keys.
5. Remove hardcoded sample records from `MOCK_DB` once all dependent screens use the real backend. Do not blank arrays prematurely: many screens currently depend on this object, and doing so before the backend cutover could break the app.
6. Validate with build checks and smoke tests: new company signup, mobile+10-digit PIN login, logout, session restore, duplicate mobile, rate limiting, and tenant A/B isolation.
7. Review RLS and Edge Function behavior before any production deployment.

## Product constraints
- Mobile number: exactly 10 digits.
- Login PIN: exactly 10 digits.
- Do not claim a phone number is verified; there is no SMS/OTP flow yet.
- No Inventory Management or Machine Management modules.
- New production accounts must start with no sample company/worker/style/operation/work-entry records.
- Do not merge or deploy without explicit user approval.
