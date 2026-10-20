# Auth Gateway safe test plan

## Safety boundary

- Run unit tests on `test/auth-gateway-safe-tests` and a non-production preview only.
- Do not apply Supabase migrations, deploy any Edge Function, deploy to production, merge a PR, or use real customer accounts.
- Never paste service-role keys, PINs, access tokens, or refresh tokens into logs or test fixtures.
- Integration tests must use a dedicated non-production Supabase project with test-only credentials and synthetic mobile numbers. If no isolated project is available, stop at unit tests and static review.
- Current mobile + PIN flow does not verify ownership of the mobile number. Do not describe it as SMS/OTP verified.

## Automated unit tests

Run locally or in CI from the repository root:

```sh
deno test --allow-read supabase/functions/auth-gateway/tests/security_test.ts
```

Coverage includes:
- mobile and PIN shape (exactly ten ASCII digits; leading zero preserved);
- company-code trim/uppercase and allowed characters/length;
- missing APP_ORIGIN fails closed;
- matching origin accepted and spoofed/foreign origins rejected;
- expected internal auth alias format.

## Non-production integration test matrix

Use only an isolated Supabase test project. Configure Edge Function secrets there, not in client variables. Keep `SUPABASE_SERVICE_ROLE_KEY` server-side only.

| Case | Safe test action | Expected result |
|---|---|---|
| OPTIONS preflight | Send OPTIONS to test endpoint | 200/2xx and CORS headers for configured origin |
| Wrong origin | POST with `Origin: https://evil.example` | 403; no auth identity/company/profile created |
| Missing origin config | Test function with APP_ORIGIN unset in isolated environment | 500 generic configuration error |
| Wrong HTTP method | GET endpoint | 405 |
| Invalid JSON | POST malformed JSON | 400 generic invalid request |
| Unsupported action | Valid mobile/PIN shape with unknown action | 400 |
| Mobile validation | 9 digits, 11 digits, letters, Unicode digits | 400; no RPC or auth write |
| PIN validation | Short/long/non-digit PIN | 400; no RPC or auth write |
| Invalid company code | Too short/long, whitespace, underscore | 400; no auth identity/company/profile created |
| Valid registration | One synthetic mobile + unique company code | 201; exactly one auth user, company, and admin profile |
| Duplicate mobile | Attempt registration again with same synthetic mobile | Generic 400; no extra company/profile |
| Duplicate company code | New synthetic mobile, existing company code with different letter case | Generic 400; no orphan auth user or company/profile |
| Signup limiter | Use a fresh synthetic mobile; make 5 registration attempts, then a 6th within one hour | first five are allowed to reach downstream validation/registration; sixth returns 429. Use isolated DB and verify counter behavior |
| Signup limiter outage | In test-only setup, simulate RPC failure | 503; no auth user/company/profile created |
| Login success | Valid test user mobile/PIN | 200 with session and matching profile |
| Login failure | Wrong PIN | 401 with generic error; no session returned |
| Login limiter | Use isolated test mobile and exceed configured limit | 429; no session returned |
| Login limiter outage | Simulate login limiter RPC failure | 503; no session returned |
| Missing profile | Test-only fixture: auth user without profile | 403; session/token is not returned |
| Tenant isolation | Login as Factory A; try to read/update Factory B data through the app/API | denied by RLS/policies; no cross-company data disclosed |
| Secret exposure | Inspect browser bundle, network responses, logs | service-role key and PIN must never appear |

### Important notes

- Do not run destructive limiter tests against production; counters and locks are persistent.
- The exact limit/reset behavior should be asserted in a dedicated test database using the migration under review, not inferred from HTTP status alone.
- Registration rollback must be checked in the isolated project for failures after auth-user creation and after company creation.
- Case-insensitive company-code uniqueness is enforced by the database migration in the candidate branch; unit tests alone cannot prove the index works.
- For each integration case, record status code, sanitized response, and before/after row counts. Do not record credentials or tokens.
- If testing requires a migration or Edge Function deployment, apply/deploy only to the explicitly isolated test project after confirming its project ID. Do not target the configured production project.

## Exit criteria

- Unit tests pass in CI.
- Security review confirms all writes use server-side service-role access only and the key is never exposed to browser code.
- Integration matrix passes in an isolated test project.
- RLS tenant-isolation checks pass.
- No production migration, production deployment, or PR merge occurs as part of this test phase.
