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

mirrored from `mint.verify_otp_error` (`lib/supabase/tenant.ts` → `mintFounderJwt` → `verifyOtp`). This is GoTrue's per-project magiclink generation ceiling, not a defect in test code.

## Why this exists

`mintFounderJwt` (`lib/supabase/tenant.ts`) issues a runtime JWT by calling `service.auth.admin.generateLink({type: "magiclink", ...})` followed by `verifyOtp(...)`. Both steps consume GoTrue's magiclink budget. The dev Supabase project has a default ceiling of **30 magiclinks/hour**.

The `tenant-integration` CI workflow runs ~18 `*.tenant-isolation.test.ts` suites. Each suite's `beforeAll` mints 1-2 JWTs against the dev project (one per synthetic founder). A single CI run therefore burns 20-40 mints — at or above the default ceiling — and any concurrent run within the same hour pushes it over.

The 429 manifests as a downstream `RuntimeAuthError(cause: jwt_mint)` for whichever suite drew the unlucky `verifyOtp` call. The underlying cause is visible via the `mirrorWithDebounce(... op: "mint.verify_otp_error" ...)` Sentry/Pino entry — without that mirror the wrapper hides the root cause (see `cq-silent-fallback-must-mirror-to-sentry`).

## Mitigation hierarchy

The fix layers from least to most invasive:

1. **Raise the dev rate limit (operational, fastest unblock).** Supabase dashboard → `dev` project → Authentication → Rate Limits → "Rate limit for sending magic links". Bump to **360/hour** (12× headroom over default). This setting is dashboard-only — not yet captured in Terraform.
2. **429 retry-with-backoff in `mintFounderJwt`.** Smooths transient bursts (concurrent runs, prior-hour residue) but cannot save you from steady-state ceiling exhaustion. See the `over_request_rate_limit` branch in `mintFounderJwt`.
3. **Cross-suite mint sharing.** Refactor `*.tenant-isolation.test.ts` suites to share founders + mints via vitest `globalSetup` so total per-CI-run mint count drops to ~2. Larger refactor; warranted only if (1) + (2) prove insufficient.

The dashboard bump is reversible and risk-free for dev (the prd project has its own independent setting). If a future operator resets the dev project's rate limits to defaults, this runbook is the recovery path.

## Verification

After bumping the dashboard setting, re-run the failing CI workflow:

```bash
gh workflow run tenant-integration.yml --ref <branch>
```

A successful run confirms the ceiling is no longer the bottleneck. The PR mirror entries (`op: mint.verify_otp_error`) should disappear from CI stdout.

## Where this is referenced

- `apps/web-platform/test/helpers/mint-once.ts` — the per-suite cache helper. Its module-level comment links here so a future engineer hitting 429s finds this runbook from the code.
- `apps/web-platform/lib/supabase/tenant.ts` — the `mintFounderJwt` function whose `verifyOtp` call surfaces the 429 (after the diagnostic `mirrorWithDebounce`, PR #3984 commit `21d9a00c`).

## Sharp edges

- **Per-IP vs per-instance.** GoTrue's magiclink rate limit applies per project, not per IP. Multiple PRs running tenant-integration concurrently share the same ceiling. Schedule integration runs serially (the existing `concurrency:` block in `tenant-integration.yml` already enforces this within the same branch — cross-branch contention remains).
- **Dashboard drift.** If the dev project is recreated (or its settings reset for any reason), the limit reverts to 30/h. The first 429 after that drift looks identical to the original symptom — check the dashboard before assuming a code regression.
- **Prd is unaffected.** Production never runs `tenant-integration`; this runbook is dev-only. Do NOT raise the prd rate limit — its default is part of the rate-limit-as-defense-in-depth posture.
