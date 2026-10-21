# Step 6 — Restore canonical login migration chain (repository-only)

## Scope and safety
This branch changes GitHub files only. It does not apply SQL, alter Supabase migration history, deploy an Edge Function, or modify any live database. Selected remote project remains `hvsgcrnvlwsjydbyhsmx`.

## Changes proposed
1. Restore the exact original `20261020144123_mobile_pin_login_rate_limit.sql` from the repository's `stage-2.2/auth-gateway-hardening` branch.
2. Restore the exact original `20261020144259_fix_login_rate_limit_mobile_validation.sql` from that same branch.
3. Remove `20261020170000_mobile_pin_login_rate_limit.sql` from this branch. This file was absent from remote migration history and redefines `consume_login_attempt` without the explicit `p_mobile is null` guard found in the live function and the canonical `20261020144259` migration. Keeping it as a later pending migration could regress validation.

## Expected reconciliation after review
- Repository migration versions: `20261020141622`, `20261020144123`, `20261020144259`.
- Remote migration history versions: `20261020141622`, `20261020144123`, `20261020144259`.
- This aligns timestamps and preserves original SQL rather than inventing or rewriting historical migrations.

## Deliberately not included
The historical branch also contains `20261020150000_signup_rate_limit_company_code.sql`, which is not present in the current remote migration history. The current `main` Edge Function does not call `consume_signup_attempt`, and live metadata did not show `auth_signup_attempts` or the normalized company-code unique index. That migration is therefore not restored in this PR; it needs a separate decision/review as an unapplied feature, not as a repair to already-applied login history.

## Validation notes
- Canonical source file SHAs recovered from `stage-2.2/auth-gateway-hardening`:
  - `20261020144123_mobile_pin_login_rate_limit.sql`: `5e52c450ea5827dfb3658dd22ff4ea59efad0ffc`
  - `20261020144259_fix_login_rate_limit_mobile_validation.sql`: `ad8de4f44d1f16accf7b2f83b650619deec6cd2d`
- Live `public.consume_login_attempt(text)` explicitly rejects null or non-10-digit mobile values.
- Do not run `supabase db push`, `migration repair`, or any production/development database write as part of this PR.
- Inventory Management and Machine Management remain excluded.
