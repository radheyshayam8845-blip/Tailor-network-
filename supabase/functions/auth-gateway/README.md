# Mobile + 10-digit PIN auth gateway

This Edge Function uses a synthetic internal email alias for Supabase Auth. It does **not** send or verify SMS OTPs, so do not describe the mobile number as verified. Add an OTP verification flow before enabling sensitive account recovery or mobile-number changes.

## Required Supabase Edge Function secrets

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server-side only; never put this in a VITE_ variable)
- `APP_ORIGIN` (recommended: exact deployed app origin; do not leave wildcard CORS in production)

## Required database migration

Apply `supabase/migrations/20261020170000_mobile_pin_login_rate_limit.sql` before deploying this function. It adds a private-to-clients attempt limiter.

## Deploy and configure

1. Set the secrets in Supabase Edge Function settings.
2. Deploy function `auth-gateway`.
3. Apply the new migration in a reviewed deployment workflow.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Vercel project environment variables.
5. Wire the existing LoginPage registration and login handlers to `registerCompanyAccount` and `loginWithMobilePin` in a separate UI integration commit.

Do not enable production auth until the UI integration, build checks, rate-limit checks, and signup/login smoke tests have passed.
