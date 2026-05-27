---
title: "fix: stop Sentry alerts from firing on expected OAuth access_denied callbacks"
type: fix
date: 2026-05-27
lane: single-domain
brand_survival_threshold: none
---

# fix: Stop Sentry alerts from firing on expected OAuth access_denied callbacks

## Overview

The OAuth callback route at `apps/web-platform/app/(auth)/callback/route.ts` still triggers Sentry issue alerts (`auth-exchange-code-burst`, `auth-callback-no-code-burst`, and `auth-per-user-loop`) when a user denies OAuth consent (`?error=access_denied`), despite PR #4487 (commit `c38699c6`) downgrading the emission from `reportSilentFallback` (error level) to `warnSilentFallback` (warning level).

**Why the previous fix was insufficient:** `warnSilentFallback` still calls `Sentry.captureMessage` at `level: "warning"` (see `apps/web-platform/server/observability.ts:231`). Sentry issue alert rules with `EventFrequencyCondition` count ALL issue events regardless of level -- both `error` and `warning` level `captureMessage` calls create Sentry issues that increment the frequency counter. The downgrade from error to warning changed the Sentry dashboard classification but did NOT stop the events from being counted by the alert rules.

**Which alert rules fire:** The `auth-per-user-loop` rule (configured in `apps/web-platform/scripts/configure-sentry-alerts.sh:165-168`) filters only on `feature=auth` with no `op` filter, catching ALL auth events including `callback_provider_error`. The `auth-exchange-code-burst` and `auth-callback-no-code-burst` rules filter on specific ops (`exchangeCodeForSession` and `callback_no_code` respectively), but Sentry issue-grouping can merge events with different `op` values into the same issue -- once grouped, any event in the group increments the alert counter for any rule that matches the issue.

**Root cause:** User-cancelled OAuth consent (`access_denied`) is expected behavior per RFC 6749 section 4.1.2.1. Expected behavior should use structured logging only (`logger.info`), not Sentry emission at any level. The learning at `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md` already documents this principle: "Expected business-logic outcomes should use structured logging only."

**Proposed fix:** Split the `callback_provider_error` path into two sub-branches:
1. `access_denied` (user-cancel): `logger.info` only, no Sentry emission.
2. All other provider errors (`server_error`, `temporarily_unavailable`, `invalid_request`, `invalid_scope`, `unauthorized_client`, `unsupported_response_type`): Keep `warnSilentFallback` for provider-outage diagnostic value.

This mirrors the PR #4485 pattern (webhook no-grant path) which removed Sentry emission entirely for expected-state paths while keeping it for genuine error conditions.

## Research Reconciliation -- Spec vs. Codebase

| Spec/plan claim | Reality | Plan response |
|---|---|---|
| PR #4487 fix (downgrade to `warnSilentFallback`) resolves alert noise | `warnSilentFallback` still emits to Sentry (`captureMessage` at `level: "warning"`); Sentry alert rules count all events regardless of level | Split into `logger.info` (user-cancel) vs `warnSilentFallback` (provider error) |
| Alert rules `auth-exchange-code-burst` and `auth-callback-no-code-burst` match by `op` tag | `auth-per-user-loop` rule filters only on `feature=auth` (no `op` filter) -- catches all auth events. Sentry issue-grouping can also cause cross-op alert hits. | Fix the emission source (stop emitting to Sentry for `access_denied`), not the alert rules |
| Release `web-platform@0.102.0+00325db3` includes PR #4487 fix | Confirmed: `git merge-base --is-ancestor c38699c6 00325db3` returns true | Current production already has the downgrade; only the Sentry-emission-removal fix remains |

## User-Brand Impact

- **If this lands broken, the user experiences:** No change. The redirect to `/login?error=oauth_cancelled` is preserved. Only the Sentry emission is removed for user-cancel; the user-facing behavior is identical.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A. No data surface is affected. The change removes an observability emission for an expected condition.
- **Brand-survival threshold:** `none`

## Research Insights

- **`warnSilentFallback` implementation** (`observability.ts:211-241`): Calls `Sentry.captureMessage(message, { level: "warning", tags, extra })`. This creates a Sentry issue that is counted by `EventFrequencyCondition` alert rules regardless of the `level` field.
- **`auth-per-user-loop` alert rule** (`configure-sentry-alerts.sh:165-168`): `EventUniqueUserFrequencyCondition` with `value: 3, interval: 5m` filtering only on `feature=auth`. This is the most likely alert to fire on `callback_provider_error` events since it has no `op` filter.
- **`classifyProviderError` returns bucket, not raw error code**: The function at `provider-error-classifier.ts:34-46` returns `"oauth_cancelled"` for `access_denied` and `"oauth_failed"` for everything else. The bucket is already available in the callback route to discriminate user-cancel from provider-error.
- **PR #4485 precedent** (`knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md`): Removed Sentry emission entirely from the webhook no-grant path because that path is the default state. The OAuth `access_denied` path is analogous -- user-cancel is expected.
- **`cq-silent-fallback-must-mirror-to-sentry` skip clause** (`observability.ts:126-130`): "Skip this helper when the error is EXPECTED (CSRF reject, rate-limit hit, first-time 404)." User-cancelled OAuth consent is expected.
- **Existing test coverage** (`callback-route-branches.test.ts:104-129`): The `test.each` block tests `access_denied` -> `mockWarnSilentFallback`. This must be updated to assert `mockWarnSilentFallback` is NOT called for `access_denied`, but IS called for `server_error` etc.

## Observability

```yaml
liveness_signal:
  what: "Sentry auth-per-user-loop and auth-exchange-code-burst issue alert rules"
  cadence: "continuous (event-driven)"
  alert_target: "operator email via IssueOwners+ActiveMembers"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf"

error_reporting:
  destination: "Sentry web-platform project via SENTRY_DSN (warning level for provider errors, none for user-cancel)"
  fail_loud: "Provider-side errors (server_error, temporarily_unavailable) still emit warnSilentFallback; user-cancel emits logger.info only"

failure_modes:
  - mode: "access_denied events stop appearing in pino structured logs"
    detection: "logger.info is still present; grep pino stdout for op:callback_provider_error"
    alert_route: "Better Stack log aggregator query"
  - mode: "provider outage (server_error) events stop appearing in Sentry"
    detection: "warnSilentFallback is preserved for non-access_denied bucket; Sentry dashboards still show feature:auth op:callback_provider_error"
    alert_route: "auth-per-user-loop alert rule fires on warning-level provider-error events"

logs:
  where: "container stdout (pino structured JSON)"
  retention: "Better Stack retention policy"

discoverability_test:
  command: "grep -c 'warnSilentFallback\\|logger.info' apps/web-platform/app/\\(auth\\)/callback/route.ts"
  expected_output: "Both helpers appear: warnSilentFallback for provider-errors, logger.info for user-cancel"
```

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/app/(auth)/callback/route.ts` | Split the `callback_provider_error` emission: (1) When `providerErrorBucket === "oauth_cancelled"`, emit `logger.info` only (no Sentry). (2) When `providerErrorBucket !== "oauth_cancelled"` (provider-side errors), keep `warnSilentFallback`. |
| `apps/web-platform/test/app/auth/callback-route-branches.test.ts` | (1) Split the `test.each` block: `access_denied` row asserts `mockWarnSilentFallback` NOT called and `mockLoggerInfo` IS called. Other rows (`server_error`, `temporarily_unavailable`, `invalid_scope`) assert `mockWarnSilentFallback` IS called. (2) Update "unrecognized `?error=`" test to assert `mockWarnSilentFallback` (unknown errors are `oauth_failed` bucket, not user-cancel). (3) Update "refererHost" test (uses `?error=access_denied`) to assert `logger.info` NOT `mockWarnSilentFallback`. |

## Files to Create

None.

## Do NOT Change

- The redirect logic (`return noStoreRedirect(...)`) -- the user-facing behavior is correct.
- The `classifyProviderError` or `isKnownProviderErrorCode` functions -- the classification logic is correct.
- The `providerErrorCode` sanitization (lines 79-81) -- the Sentry tag cardinality guard is correct (it is still relevant for the `warnSilentFallback` path on provider errors).
- The `callback_no_code` branch (line 249) -- this is a different code path that correctly uses `reportSilentFallback` at error level.
- The `exchangeCodeForSession` error branch (line 153) -- system failure that correctly uses `reportSilentFallback`.
- The Sentry alert rules or their Terraform definitions -- the fix is at the emission source, not the alert configuration.
- `apps/web-platform/lib/auth/provider-error-classifier.ts` -- classification logic is correct.

## Open Code-Review Overlap

`#3739: review: extract reportSilentFallbackWithUser helper` -- touches `server/observability.ts` but targets the `withIsolationScope+setUser` duplication pattern (11 sites), which is a different concern from this fix. The callback provider-error call at line 85 does NOT use `withIsolationScope` (no userId is available before code exchange). **Disposition: Acknowledge** -- no overlap with the specific call site being modified.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `grep -n "logger.info" apps/web-platform/app/\(auth\)/callback/route.ts` shows a `logger.info` call on the `access_denied` / `oauth_cancelled` branch with `op: "callback_provider_error"` context.
- [ ] **AC2:** `grep -n "warnSilentFallback" apps/web-platform/app/\(auth\)/callback/route.ts` still shows a `warnSilentFallback` call for the non-`oauth_cancelled` provider error branch.
- [ ] **AC3:** The `access_denied` test case in `callback-route-branches.test.ts` asserts that `mockWarnSilentFallback` was NOT called (`.not.toHaveBeenCalled()` or `.toHaveBeenCalledTimes(0)`).
- [ ] **AC4:** The `server_error`, `temporarily_unavailable`, and `invalid_scope` test cases assert `mockWarnSilentFallback` IS called with `op: "callback_provider_error"`.
- [ ] **AC5:** The bare-`/callback` test still asserts `mockReportSilentFallback` with `op: "callback_no_code"` (unchanged).
- [ ] **AC6:** Tests pass: `apps/web-platform/node_modules/.bin/vitest run apps/web-platform/test/app/auth/callback-route-branches.test.ts apps/web-platform/test/lib/auth/callback-error-mapping.test.ts apps/web-platform/test/lib/auth/callback-route-no-substring-match.test.ts apps/web-platform/test/lib/auth/provider-error-classifier.test.ts apps/web-platform/test/lib/auth/provider-error-classifier-no-substring-match.test.ts`.
- [ ] **AC7:** TypeScript compiles: `npx tsc --noEmit --project apps/web-platform/tsconfig.json`.

## Test Scenarios

- Given a user who cancels OAuth consent (`?error=access_denied`), when the callback route processes it, then it redirects to `/login?error=oauth_cancelled`, emits `logger.info` with context, and does NOT emit `warnSilentFallback` or `reportSilentFallback`.
- Given a provider server error (`?error=server_error`), when the callback route processes it, then it redirects to `/login?error=oauth_failed` and emits `warnSilentFallback` (NOT `logger.info`-only).
- Given a provider temporarily_unavailable error, when the callback route processes it, then it emits `warnSilentFallback`.
- Given a bare `/callback` with no params, when the route processes it, then it emits `reportSilentFallback` at error level (unchanged).
- Given a valid `?code=`, when `exchangeCodeForSession` fails, then it emits `reportSilentFallback` at error level (unchanged).

## Implementation Phases

### Phase 1: Split provider-error emission in callback route

**File:** `apps/web-platform/app/(auth)/callback/route.ts`

Replace the single `warnSilentFallback` call on the `providerErrorBucket` branch (currently line 85) with a conditional:

```typescript
if (providerErrorBucket === "oauth_cancelled") {
  // User clicked Cancel at the consent screen — expected behavior.
  // Structured log only; no Sentry emission (the alert rules count
  // ALL captureMessage events regardless of level, and user-cancel
  // is not actionable). See learning 2026-05-26-sentry-captureMessage-
  // on-expected-paths-creates-alert-noise.md.
  logger.info(
    {
      feature: "auth",
      op: "callback_provider_error",
      providerErrorCode,
      bucket: providerErrorBucket,
      urlPath: pathname,
      refererHost,
      origin,
    },
    `OAuth provider returned error=${providerErrorCode}`,
  );
} else {
  // Provider-side failure (server_error, temporarily_unavailable, etc.)
  // — unexpected, warrants Sentry visibility for operator dashboards.
  warnSilentFallback(null, {
    feature: "auth",
    op: "callback_provider_error",
    message: `OAuth provider returned error=${providerErrorCode}`,
    extra: {
      providerErrorCode,
      bucket: providerErrorBucket,
      urlPath: pathname,
      refererHost,
      origin,
    },
  });
}
```

### Phase 2: Update test file

**File:** `apps/web-platform/test/app/auth/callback-route-branches.test.ts`

1. **Add `mockLoggerInfo`** to the `vi.hoisted` block and wire it into the logger mock.

2. **Split the `test.each` block** (currently lines 104-129):
   - Separate `access_denied` into its own test case that asserts:
     - `mockWarnSilentFallback` NOT called (`.not.toHaveBeenCalled()`)
     - `mockReportSilentFallback` NOT called
     - `mockLoggerInfo` called with `op: "callback_provider_error"` context
     - Redirect still goes to `/login?error=oauth_cancelled`
   - Keep `server_error`, `temporarily_unavailable`, `invalid_scope` in a `test.each` that asserts `mockWarnSilentFallback` IS called.

3. **Update "refererHost" test** (line 182): This test uses `?error=access_denied`. Change its assertion from `mockWarnSilentFallback` to `mockLoggerInfo` for the refererHost check.

4. **Verify "searchParamKeys" test** (line 202): This tests the bare-`/callback` path (no `error=` param), which correctly uses `reportSilentFallback`. This test must remain unchanged.

5. **Verify "unrecognized `?error=`" test** (line 132): This sends `?error=user@example.com`, which `classifyProviderError` maps to `"oauth_failed"` (not `"oauth_cancelled"`). This should assert `mockWarnSilentFallback` IS called (unknown errors are provider-side, not user-cancel). Update if needed.

### Phase 3: Verify

1. Run the test suite (AC6).
2. Run TypeScript compile check (AC7).
3. Run AC1-AC5 verification commands.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Loss of `access_denied` spike visibility | Low | Low | `logger.info` preserves the structured log in pino/Better Stack. An operator can query for `op:callback_provider_error` + `bucket:oauth_cancelled` in logs. A spike in user cancellations is more likely a UX or consent-screen issue, not a system failure. |
| Provider outage signal diluted by remaining alert noise | Low | Low | Provider errors (`server_error`, etc.) still emit `warnSilentFallback` to Sentry. The `auth-per-user-loop` rule will still fire on genuine provider outages. |
| Test refactor introduces false negatives | Low | Medium | The split test structure makes assertions more explicit. Each branch has its own test with dedicated mock assertions. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- observability emission adjustment in a single auth callback route.

## Context

- **Sentry event IDs (today, 2026-05-27):** `4ec8f51d324747f1bb8bfc5c84ab5906` (07:00 CEST), `d2e86815ab4341c59f6ec7198b2c24fb` (08:00 CEST)
- **Alert rules:** `auth-exchange-code-burst`, `auth-callback-no-code-burst` (per user report; likely also `auth-per-user-loop` which has no `op` filter)
- **PR #4487 (`c38699c6`):** Previous fix that downgraded `reportSilentFallback` to `warnSilentFallback` -- insufficient because Sentry still counts warning-level events.
- **PR #4485:** Same-class fix for webhook no-grant path -- removed Sentry emission entirely.
- **Learning:** `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md`
- **Release:** `web-platform@0.102.0+00325db3` (includes PR #4487)

## References

- `apps/web-platform/app/(auth)/callback/route.ts:70-100` -- the provider-error branch
- `apps/web-platform/server/observability.ts:211-241` -- `warnSilentFallback` (still emits to Sentry at warning level)
- `apps/web-platform/server/observability.ts:164-203` -- `reportSilentFallback` (error level)
- `apps/web-platform/lib/auth/provider-error-classifier.ts` -- provider error classification logic
- `apps/web-platform/scripts/configure-sentry-alerts.sh:165-168` -- `auth-per-user-loop` rule (no `op` filter)
- `apps/web-platform/test/app/auth/callback-route-branches.test.ts` -- test coverage for callback route branches
