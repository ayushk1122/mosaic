# Supabase

**Owner:** Engineering
**Status:** Local reproducibility foundation

## Purpose

This directory versions the Mosaic database schema so a fresh local database can recreate the live Mosaic-dev contract without copying production data.

## Layout

- `config.toml` — local Supabase CLI configuration
- `migrations/20261012180000_baseline.sql` — squashed schema captured from Mosaic-dev on 2026-10-16 (tables, functions, RLS, storage buckets/policies, grants), including `save_document` pursuit↔node role moves and the foreign-key covering indexes from the beta-readiness review
- `migrations_archive/` — earlier partial migration files kept for history; not applied by `supabase db reset`
- `tests/` — SQL regression tests for local `supabase test db`

## Local workflow

Requires Docker Desktop and the Supabase CLI (`~/.local/bin/supabase` or equivalent).

```sh
export PATH="$HOME/.docker/bin:$HOME/.local/bin:$PATH"
cd /path/to/mosaic
supabase start
supabase db reset
supabase test db
```

`scripts/ci.sh` runs the unit tests plus a local database reset/test when Docker is available.

## Hosted project

**Current repository fact:** The linked hosted project remains Mosaic-dev (`dnejxyohyzpwfjmnnarq`). A separate staging project is deferred until Apple Developer Program / pre-production work.

When applying later migrations to Mosaic-dev, prefer additive files under `migrations/` and apply them through the usual migration path. Do not re-apply the baseline to a database that already has the historical migration versions.

## Auth providers (Mosaic-dev dashboard)

After pulling onboarding work, configure the hosted project manually:

1. **Authentication → Providers → Email:** enable Email sign-up and **password** sign-in. In **Email templates → Magic Link**, include the OTP token (for example `Your code is {{ .Token }}`) so the app can verify with `/auth/v1/verify` using `type: email`.
2. **Authentication → Providers → Phone:** enable Phone and attach Twilio (or another SMS provider). Set rate limits appropriately for beta.
3. **Authentication → Providers → Apple:** enable Apple and configure the iOS bundle identifier for Sign in with Apple.
4. **Authentication → Rate limits:** review OTP send and verify limits for email and SMS.
5. **Google** remains enabled; OAuth and OTP sign-ups still pass through onboarding when `onboarded_at` is null unless the sign-up form already called `complete_onboarding`.

Local development uses Mailpit (`http://127.0.0.1:54324`) for email OTP and `[auth.sms.test_otp]` in `config.toml` for fixed SMS codes.
