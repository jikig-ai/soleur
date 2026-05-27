---
module: web-platform/auth
date: 2026-05-27
problem_type: best_practice
component: authentication
symptoms:
  - "Recurring Sentry alerts (auth-exchange-code-burst, auth-callback-no-code-burst) on expected OAuth access_denied"
  - "Alerts continued after PR #4487 downgraded reportSilentFallback to warnSilentFallback"
root_cause: config_error
resolution_type: code_fix
severity: medium
tags: [sentry, observability, alert-noise, oauth, access-denied, warning-level]
synced_to: []
---

# Sentry warning-level captureMessage still triggers EventFrequencyCondition alert rules

## Problem

After PR #4487 downgraded the OAuth `access_denied` callback emission from `reportSilentFallback` (error level) to `warnSilentFallback` (warning level), Sentry alerts continued firing. Two alerts triggered on 2026-05-27 at 07:00 and 08:00 CEST (IDs `4ec8f51d` and `d2e86815`).

## Root Cause

`warnSilentFallback` calls `Sentry.captureMessage(message, { level: "warning" })` (see `observability.ts:231`). Sentry `EventFrequencyCondition` alert rules count ALL issue events regardless of `level` — both `error` and `warning` level `captureMessage` calls create Sentry issues that increment the frequency counter. The `auth-per-user-loop` alert rule filters only on `feature=auth` with no `op` filter, catching all auth events including `callback_provider_error`.

Downgrading from error to warning changed the Sentry dashboard classification but did NOT stop events from being counted by alert rules.

## Solution

Split the provider-error emission path in `apps/web-platform/app/(auth)/callback/route.ts`:

1. `access_denied` (user-cancel, `oauth_cancelled` bucket): `logger.info` only — no Sentry emission
2. All other provider errors (`server_error`, `temporarily_unavailable`, etc.): keep `warnSilentFallback`

Updated tests in `callback-route-branches.test.ts` to verify cross-channel exclusion (access_denied asserts `mockWarnSilentFallback.not.toHaveBeenCalled()`; provider errors assert `mockLoggerInfo.not.toHaveBeenCalled()`).

## Key Insight

Downgrading Sentry emission level (error → warning) does NOT reduce alert noise. Sentry alert rules count events, not severity. The only way to stop an expected-behavior path from triggering alerts is to remove Sentry emission entirely and use structured logging (`logger.info`) for operational visibility. This is the second instance of this pattern — see also `best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md` (webhook no-grant path, PR #4485).

## Session Errors

1. **Vitest CWD mismatch.** Ran vitest from bare repo root instead of `apps/web-platform/`, producing "Cannot find package" error. Recovery: re-ran with correct CWD (`cd apps/web-platform && ./node_modules/.bin/vitest run`). **Prevention:** Work skill should always run vitest from the app root when the test path is relative to the app package.

## See Also

- `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md` (same pattern, webhook context)
- PR #4487 (insufficient downgrade fix)
- PR #4485 (precedent: webhook no-grant path removal)
