---
category: infrastructure
tags: [supabase, gotrue, rate-limit, tenant-integration, ci]
date: 2026-05-19
---

# Supabase magiclink rate limit (dev) — tenant-integration ceiling

Use this runbook when CI's `tenant-integration` workflow fails with:

```
AuthApiError: Request rate limit reached
status: 429
code: "over_request_rate_limit"
```

mirrored from `mint.verify_otp_error` (`lib/supabase/tenant.ts` → `mintFounderJwt` → `verifyOtp`). This is GoTrue's per-IP token-verification ceiling, not a defect in test code.

## Why this exists

`mintFounderJwt` (`lib/supabase/tenant.ts`) issues a runtime JWT in two GoTrue admin steps:

1. `service.auth.admin.generateLink({type: "magiclink", ...})` — produces a hashed token. Counts against the **sign-ups/sign-ins** per-IP ceiling (because GoTrue treats the underlying admin operation as a sign-up shape).
2. `otpClient.auth.verifyOtp({token_hash, type: "email"})` — exchanges the hashed token for the signed JWT. Counts against the **token verifications** per-IP ceiling.

Each tenant-isolation suite ALSO calls `service.auth.admin.createUser(...)` once per synthetic founder (the `beforeAll` that seeds users) — another hit on the sign-ups/sign-ins per-IP ceiling.

Supabase exposes both ceilings under Authentication → Rate Limits. Defaults:

- **Rate limit for token verifications** — 30 requests / 5 min per IP address (= 360/hour).
- **Rate limit for sign-ups and sign-ins** — 30 requests / 5 min per IP address (= 360/hour).

The `tenant-integration` CI workflow runs ~18 `*.tenant-isolation.test.ts` suites. Each suite mints 1-2 JWTs after creating 1-2 founders. A single CI run therefore issues ~20-40 verifyOtps + ~20-40 admin.createUsers within ~30 seconds from a single GitHub Actions runner IP — easily over both defaults' 30-in-5-min ceiling.

The 429 manifests as a downstream `RuntimeAuthError(cause: jwt_mint)` for whichever suite drew the unlucky `verifyOtp` call. The underlying cause is visible via the `mirrorWithDebounce(... op: "mint.verify_otp_error" ...)` Sentry/Pino entry — without that mirror the wrapper hides the root cause (see `cq-silent-fallback-must-mirror-to-sentry`).

The "Rate limit for sending emails" setting (default 2/hour, disabled when SMTP isn't configured) does NOT apply here — `generateLink` with downstream `verifyOtp` consumes hashed tokens without dispatching email.

## Mitigation hierarchy

The fix layers from least to most invasive:

1. **Raise the dev per-IP ceilings (operational, fastest unblock).** Supabase dashboard → `dev` project → Authentication → Rate Limits. Bump BOTH:
   - **Rate limit for token verifications**: 30 → **150** requests / 5 min (= 1800/hour, 5× headroom).
   - **Rate limit for sign-ups and sign-ins**: 30 → **150** requests / 5 min.

   These settings are dashboard-only — not yet captured in Terraform. If a future operator resets the dev project, repeat this step from this runbook.
2. **429 retry-with-backoff in `mintFounderJwt`** — bounded retry on `code: over_request_rate_limit` (see `apps/web-platform/lib/supabase/tenant.ts`'s `getVerifyOtpRetryConfig` block). Smooths transient bursts (concurrent runs, prior-window residue) but cannot save you from steady-state ceiling exhaustion.
3. **Cross-suite mint sharing.** Refactor `*.tenant-isolation.test.ts` suites to share founders + mints via vitest `globalSetup` so total per-CI-run mint count drops to ~2. Larger refactor; warranted only if (1) + (2) prove insufficient.

The dashboard bump is reversible and risk-free for dev (the prd project has its own independent setting). The current dev values are recorded above for drift detection.

## Verification

After bumping the dashboard settings, re-run the failing CI workflow:

```bash
gh workflow run tenant-integration.yml --ref <branch>
```

A successful run confirms the ceilings are no longer the bottleneck. The `op: mint.verify_otp_error` mirror entries should disappear from CI stdout. If they reappear, check the Supabase dashboard for drift before assuming a code regression.

## Where this is referenced

- `apps/web-platform/test/helpers/mint-once.ts` — the per-suite cache helper. Its module-level comment links here so a future engineer hitting 429s finds this runbook from the code.
- `apps/web-platform/lib/supabase/tenant.ts` — the `mintFounderJwt` function whose `verifyOtp` call surfaces the 429 (after the diagnostic `mirrorWithDebounce`, PR #3984 commit `21d9a00c`). The retry-config block links here as the operational fallback when retries exhaust.

## Sharp edges

- **Per IP address, not per project.** Both ceilings count per-IP, so two CI runs from different GitHub Actions runners get independent budgets. The failure mode is bursting many calls from a SINGLE runner within the 5-minute window. Bumping per-IP also helps if a developer triggers the workflow locally against dev.
- **Two distinct settings, both load-bearing.** The verifyOtp 429 is the visible failure, but bumping only "token verifications" while leaving "sign-ups and sign-ins" at 30/5min means `admin.createUser` becomes the next bottleneck under the same workload. Bump both.
- **Dashboard drift.** If the dev project is recreated (or its settings reset), both limits revert to 30/5min. The first 429 after that drift looks identical to the original symptom — check the dashboard before assuming a code regression.
- **Prd is unaffected.** Production never runs `tenant-integration`; this runbook is dev-only. Do NOT raise the prd rate limits — their defaults are part of the rate-limit-as-defense-in-depth posture.
- **Not "sending emails".** The runbook predecessor pointed at "Rate limit for sending magic links" / "sending emails" — that setting governs SMTP dispatch, which our `generateLink + verifyOtp` flow doesn't touch. Don't bump it.
