---
module: web-platform/webhooks
date: 2026-05-26
problem_type: observability_misconfiguration
component: sentry_integration
symptoms:
  - "~600 Sentry warnings/day from expected no-grant webhook path"
  - "Alert fatigue drowning real error signals (signature failures, DB errors)"
  - "$50/mo Sentry PAYG cap consumed by non-actionable warnings"
root_cause: expected_condition_treated_as_warning
severity: medium
tags: [sentry, observability, alert-noise, webhook, scope-grant]
synced_to: []
---

# Sentry captureMessage on expected paths creates alert noise

## Problem

The GitHub webhook handler at `apps/web-platform/app/api/webhooks/github/route.ts` fired `Sentry.captureMessage("GitHub webhook: no active scope_grant", { level: "warning" })` on every delivery where the founder hadn't granted the corresponding action class. This is expected, fail-closed behavior — the handler returns 200 OK without dispatching to Inngest.

The Sentry emission generated ~600 warnings/day (100 events in 2 hours on 2026-05-26), distributed across `engineering.pr_review_pending` (66%), `engineering.ci_failed` (29%), and `triage.p0p1_issue` (5%). All from a single founder who installed the GitHub App but hadn't opted into processing those event types.

## Root Cause

The original PR-H (#3244) implementation treated the no-grant path as a degraded condition requiring Sentry observability parity with the error paths. In practice, the no-grant path is the *default state* for any action class the founder hasn't opted into — structurally identical to ignoring unsupported event types, not to DB errors or dispatch failures.

## Solution

1. Removed `Sentry.captureMessage` from the no-grant path entirely
2. Downgraded `logger.warn` to `logger.info` — expected behavior, not a warning
3. Updated test to assert `mockLogger.info` and `expect(mockSentryCaptureMessage).not.toHaveBeenCalled()`
4. Fixed stale header comment at line 19 that still referenced "log + Sentry" for no-grant

The 5 remaining Sentry calls in the file cover real error conditions: secret unset, signature verification failure, dedup DB errors, founder lookup errors, and inngest.send failures.

## Key Insight

`Sentry.captureMessage` at warning level should be reserved for conditions that require operator attention. Expected business-logic outcomes (fail-closed gates, opt-out states, unsupported event types) should use structured logging only. The Stripe webhook handler already followed this pattern — `logger.info` without Sentry for expected no-grant paths.

The `cq-silent-fallback-must-mirror-to-sentry` rule explicitly exempts expected conditions. The no-grant path is not a silent fallback — no DB error is swallowed, no fallback data is substituted, no degraded condition is masked.

## Prevention

Before adding `Sentry.captureMessage` to a new code path, ask: "Is this condition actionable? Would an operator need to do something when this fires?" If the answer is "no, this is expected behavior," use `logger.info` instead.

## Session Errors

1. **Sentry API token name mismatch** — Tried `SENTRY_TOKEN` (from deployment-verification-agent docs), actual Doppler key is `SENTRY_AUTH_TOKEN`. Recovery: listed all Sentry secrets via `doppler secrets | grep -i sentry`. **Prevention:** Grep Doppler for the service name pattern before assuming a token variable name.

2. **Vitest binary path discovery** — Multiple failed attempts at `./node_modules/.bin/vitest` and `../../node_modules/.bin/vitest` from different CWDs. Actual path: `apps/web-platform/node_modules/.bin/vitest` (workspace-local install). Recovery: `find . -maxdepth 5 -path '*/node_modules/.bin/vitest'`. **Prevention:** In monorepo worktrees, always `find` for the binary first rather than guessing relative paths.

3. **AC2 grep multi-line miss** — Plan's AC2 command `grep -n "logger.info" ... | grep "no active scope_grant"` returned empty because the method name and message string are on different lines. Recovery: used `grep -B2` to match across lines. **Prevention:** When writing AC verification commands, test them against the expected post-edit file structure, not against the assumption that the search terms are on the same line.

## Tags
category: best-practices
module: web-platform/webhooks
