# Step 9 — Supabase Integration Readiness Audit

Checked read-only on 2026-10-21. This report records the observed state; it does not apply migrations, deploy functions, or change production data.

## Current state

| Area | Observed state | Meaning |
|---|---|---|
| Production Supabase project `hvsgcrnvlwsjydbyhsmx` | Active/healthy | Project is reachable. |
| Production migration history | `20261020141622`, `20261020144123`, `20261020144259` | The signup security migration `20261020150000_signup_rate_limit_company_code` is not recorded as applied. |
| Public schema | 11 tables: companies, profiles, invitations, lines, workers, operations, styles, dept_allocations, work_entries, subscription_invoices, auth_login_attempts | Base schema exists; Inventory and Machine Management are absent as requested. |
| RLS | Enabled on all 11 observed tables | RLS is on, but policy correctness still needs integration tests. |
| RLS policies | Company-scoped admin policies exist on operational tables; tailor-specific policies exist for invitations/work entries/workers | This is a good baseline, not proof that every cross-tenant access path is safe. |
| Security advisor | INFO finding: `auth_login_attempts` has RLS enabled with no policies | Likely intended to be server/service-role-only; verify grants and service-role-only access explicitly. |
| Edge Functions | No Edge Functions returned for production project | Frontend `src/lib/auth.js` invokes `auth-gateway`; live login/registration is not ready until the function is deployed and configured. |
| Test project `ftoiimdfxvlmrkiloguu` | Active/healthy, but zero migrations and zero public tables | It is not yet a usable isolated test database. |

## Release blockers

1. **Do not claim live auth works yet.** The app invokes `auth-gateway`, but no deployed production Edge Function was returned by the read-only listing.
2. **Do not claim signup rate limiting is active.** The signup migration is in the repository/merged PR, but its version is missing from production migration history.
3. **Do not apply the signup migration straight to production.** First run the canonical migration chain and signup migration in an isolated test database, then execute the pgTAP tests and review any duplicate company codes.
4. **Do not enable the frontend against production until auth and RLS tests pass.** Browser code must use only the publishable/anon key; never expose a service-role key.
5. **Keep localStorage mock data out of the source of truth.** Real worker, style, operation, line, invitation, and work-entry data must be read/written through Supabase with server-enforced tenant access.

## Safe next sequence

- Provision/prepare an isolated test database without creating paid branches unless the exact cost has been shown and explicitly accepted.
- Apply the canonical migration files in timestamp order to that test database.
- Run `supabase/tests/signup_security.test.sql` and add RLS isolation tests for two separate companies, supervisor/worker permissions, and tailor-owned work entries.
- Verify `auth-gateway` configuration and required environment secrets without printing secret values.
- Deploy the Edge Function only after explicit approval, then test signup, login, lockout (HTTP 429), service failure (HTTP 503), sign-out, and tenant isolation.
- Connect one low-risk module first (Style Management read/write), then Operations + piece rate, Worker Management, and Daily Work Details.
- Keep Inventory Management and Machine Management excluded.

## Validation boundary

This is based on read-only project metadata, migration history, table definitions, RLS policy catalog, security advisor output, and repository source. No production migration, Edge Function deployment, auth-user creation, or data mutation was performed for this audit.
