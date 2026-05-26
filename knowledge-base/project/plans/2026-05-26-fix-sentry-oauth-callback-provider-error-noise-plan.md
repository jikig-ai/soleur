---
title: "fix: downgrade OAuth callback provider-error Sentry emission from error to warning"
type: fix
date: 2026-05-26
lane: single-domain
brand_survival_threshold: none
---

# fix: Downgrade OAuth callback provider-error Sentry emission from error to warning

## Overview

The OAuth callback route at `apps/web-platform/app/(auth)/callback/route.ts` line 82 calls `reportSilentFallback(null, { feature: "auth", op: "callback_provider_error", ... })` when a user denies OAuth consent (clicks "Cancel" on the Google/GitHub consent screen) or when the provider returns any `error=` query parameter. `reportSilentFallback` emits at Sentry `error` level, which generates unnecessary noise for what is an expected, user-initiated flow.

The Sentry event (ID: `b3c2837d09ae4583a78d9d487a250a78`, 2026-05-26 13:00 CEST) confirms this fires in production with `error=access_denied` -- the standard OAuth 2.0 response when a user cancels consent (RFC 6749 section 4.1.2.1).

**Root cause:** PR #3126 (`67e21b29`) introduced the provider-error classification branch to prevent user-cancel from being conflated with system failure. The `reportSilentFallback` call was correctly added for observability but at the wrong severity: `reportSilentFallback` emits at `error` level (Sentry + pino), whereas user-initiated cancellation is expected behavior that belongs at `warning` level via `warnSilentFallback`.

**Same class as PR #4485:** The just-merged webhook fix (`bcb2bd4c`) removed Sentry emission entirely from the no-grant path because that path is the default state (fail-closed by design). The OAuth callback provider-error path is analogous but not identical: unlike the no-grant path (which fires on every webhook delivery for ungranted action classes, ~600/day), the OAuth provider-error path fires only when a user actively cancels consent. The signal has diagnostic value (e.g., detecting a sudden spike in cancellations could indicate a provider-side configuration problem), so downgrading to `warnSilentFallback` is more appropriate than removal.

**Decision: `warnSilentFallback` (not removal).**
- `access_denied` (user clicked Cancel) is expected. Error-level is wrong.
- `server_error` / `temporarily_unavailable` (provider outage) are unexpected. Warning-level is appropriate since the user is already redirected with a helpful message.
- Both buckets route through the same `classifyProviderError` → `reportSilentFallback` path. Splitting the Sentry emission by bucket would add complexity for marginal benefit -- a warning-level Sentry event for a provider outage is still visible in dashboards.
- `warnSilentFallback` preserves both Sentry visibility (at warning level, not error) and pino structured logging, so ops can still query/alert on spikes.

## User-Brand Impact

- **If this lands broken, the user experiences:** No change. The redirect to `/login?error=oauth_cancelled` or `/login?error=oauth_failed` is preserved. Only the Sentry emission level changes.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A. No data surface is affected. The change modifies an observability emission, not a security guard or data path.
- **Brand-survival threshold:** `none`

## Research Insights

- **`reportSilentFallback` (line 82):** Calls `Sentry.captureMessage` at `level: "error"` via `observability.ts:194`. This is the production source of event `b3c2837d09ae4583a78d9d487a250a78`.
- **`warnSilentFallback` (same module):** Calls `Sentry.captureMessage` at `level: "warning"` via `observability.ts:232`. Same signature, same structured logging, same tag vocabulary -- only the severity differs.
- **Existing test coverage:** `callback-route-branches.test.ts` lines 93-122 test the provider-error branch with `test.each` for `access_denied`, `server_error`, `temporarily_unavailable`, `invalid_scope`. The test asserts `mockReportSilentFallback` is called with `op: "callback_provider_error"`. This must be updated to assert `mockWarnSilentFallback`.
- **`cq-silent-fallback-must-mirror-to-sentry` applicability:** The docstring at `observability.ts:127-130` says "Skip this helper when the error is EXPECTED (CSRF reject, rate-limit hit, first-time 404)." User-cancelled OAuth consent is expected. The `warnSilentFallback` downgrade preserves the Sentry mirror at a lower severity, which is a middle ground: the event is still observable but does not inflate error-level dashboards.
- **PR #4485 learning:** `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md` documents the pattern. Key insight: "Sentry.captureMessage at warning level should be reserved for conditions that require operator attention. Expected business-logic outcomes should use structured logging only." The OAuth callback differs because `server_error`/`temporarily_unavailable` DO warrant operator attention at warning level.

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/app/(auth)/callback/route.ts` | (1) Add `warnSilentFallback` to the import from `@/server/observability` (line 14). (2) Replace `reportSilentFallback` with `warnSilentFallback` at line 82. |
| `apps/web-platform/test/app/auth/callback-route-branches.test.ts` | (1) Add `mockWarnSilentFallback` to the `vi.hoisted` block. (2) Add `warnSilentFallback: mockWarnSilentFallback` to the `vi.mock("@/server/observability")` block. (3) Update the 4 provider-error test cases to assert `mockWarnSilentFallback` instead of `mockReportSilentFallback`. (4) Update the "unrecognized ?error=" test to use `mockWarnSilentFallback`. (5) Update the "refererHost" test to use `mockWarnSilentFallback`. (6) Update the "searchParamKeys" test -- this tests the bare-/callback path which uses `reportSilentFallback` with `op: "callback_no_code"` (NOT the provider-error branch), so it should remain unchanged. Verify this test still asserts `mockReportSilentFallback`. |

## Files to Create

None.

## Do NOT Change

- The redirect logic (line 97: `return noStoreRedirect(...)`) -- the user-facing behavior is correct.
- The `classifyProviderError` or `isKnownProviderErrorCode` functions -- the classification logic is correct.
- The `providerErrorCode` sanitization (lines 79-81) -- the Sentry tag cardinality guard is correct.
- The `callback_no_code` branch (line 246) -- this is a different code path (bare `/callback` with no params), which is an unexpected condition that correctly uses `reportSilentFallback` at error level.
- The `exchangeCodeForSession` error branch (line 150) -- this is a system failure that correctly uses `reportSilentFallback` at error level.
- The `ensureWorkspaceProvisioned` Sentry calls (lines 316-345) -- these cover real error conditions with `withIsolationScope`.
- Any `warnSilentFallback`/`reportSilentFallback` calls in other files.

## Open Code-Review Overlap

`#3739: review: extract reportSilentFallbackWithUser helper` -- touches `server/observability.ts` but targets the `withIsolationScope+setUser` duplication pattern (11 sites), which is a different concern from this fix. The callback provider-error call at line 82 does NOT use `withIsolationScope` (no userId is available before code exchange). **Disposition: Acknowledge** -- no overlap with the specific call site being modified.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `grep -c "warnSilentFallback" apps/web-platform/app/\(auth\)/callback/route.ts` returns 2 (the import line + the provider-error call site).
- [ ] **AC2:** `grep -c "reportSilentFallback" apps/web-platform/app/\(auth\)/callback/route.ts` returns 6 (down from 7; the remaining 6 are: exchangeCodeForSession error, getUser-null, callback-no-code, user-upsert-error, workspace-provisioning-error, and the import line which now also imports warnSilentFallback).
- [ ] **AC3:** `grep -n "warnSilentFallback" apps/web-platform/app/\(auth\)/callback/route.ts` shows the import at line 14 and the call at approximately line 82.
- [ ] **AC4:** The provider-error test cases in `callback-route-branches.test.ts` assert `mockWarnSilentFallback` (not `mockReportSilentFallback`) with `op: "callback_provider_error"`.
- [ ] **AC5:** The bare-/callback test (`"bare /callback (no params)"`) still asserts `mockReportSilentFallback` with `op: "callback_no_code"` (unchanged).
- [ ] **AC6:** Tests pass: `apps/web-platform/node_modules/.bin/vitest run apps/web-platform/test/app/auth/callback-route-branches.test.ts apps/web-platform/test/lib/auth/callback-error-mapping.test.ts apps/web-platform/test/lib/auth/callback-route-no-substring-match.test.ts apps/web-platform/test/lib/auth/provider-error-classifier.test.ts apps/web-platform/test/lib/auth/provider-error-classifier-no-substring-match.test.ts`.
- [ ] **AC7:** TypeScript compiles: `npx tsc --noEmit --project apps/web-platform/tsconfig.json`.

## Test Scenarios

- Given a user who cancels OAuth consent (`?error=access_denied`), when the callback route processes it, then it redirects to `/login?error=oauth_cancelled` and emits `warnSilentFallback` (NOT `reportSilentFallback`).
- Given a provider server error (`?error=server_error`), when the callback route processes it, then it redirects to `/login?error=oauth_failed` and emits `warnSilentFallback`.
- Given a bare `/callback` with no params, when the route processes it, then it emits `reportSilentFallback` at error level (unchanged).
- Given a valid `?code=`, when `exchangeCodeForSession` fails, then it emits `reportSilentFallback` at error level (unchanged).

## Implementation Phases

### Phase 1: Edit callback route (two changes)

1. **Update import** at line 14:
   - Change `import { reportSilentFallback } from "@/server/observability";`
   - To `import { reportSilentFallback, warnSilentFallback } from "@/server/observability";`

2. **Replace call** at line 82:
   - Change `reportSilentFallback(null, {` to `warnSilentFallback(null, {`
   - The arguments (feature, op, message, extra) remain identical.

### Phase 2: Update test file

1. **Add mock** in `vi.hoisted` block (around line 8):
   - Add `mockWarnSilentFallback: vi.fn(),` to the returned object.

2. **Add to mock module** in `vi.mock("@/server/observability")` block (around line 14):
   - Add `warnSilentFallback: mockWarnSilentFallback,` to the returned object.

3. **Update provider-error test cases** (the `test.each` block around line 93):
   - Change `expect(mockReportSilentFallback).toHaveBeenCalledTimes(1)` to `expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1)`.
   - Change `const [, opts] = mockReportSilentFallback.mock.calls[0]` to `const [, opts] = mockWarnSilentFallback.mock.calls[0]`.

4. **Update "unrecognized ?error=" test** (around line 124):
   - Change `const [, opts] = mockReportSilentFallback.mock.calls[0]` to `const [, opts] = mockWarnSilentFallback.mock.calls[0]`.

5. **Update "refererHost" test** (around line 152):
   - Change `const [, opts] = mockReportSilentFallback.mock.calls[0]` to `const [, opts] = mockWarnSilentFallback.mock.calls[0]`.

6. **Verify the "searchParamKeys" test** (around line 168) -- this tests the bare-/callback path (`makeRequest` with 25 params but no `error=`), which falls through to the `callback_no_code` branch and uses `reportSilentFallback`. This test must remain unchanged.

### Phase 3: Verify

1. Run the test suite (AC6).
2. Run TypeScript compile check (AC7).
3. Run AC1-AC5 verification commands.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Provider outage (`server_error`) becomes harder to spot | Low | Low | `warnSilentFallback` still emits to Sentry at warning level AND to pino structured logs. Sentry dashboards can filter by `feature=auth` + `op=callback_provider_error`. A spike in provider errors is detectable via either surface. |
| Confusion about which helper to use for future callback branches | Low | Low | The callback route's inline comment at line 67 already explains the branch semantics. The downgrade is consistent with the learning at `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md`. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- observability severity adjustment in a single auth callback route.

## Context

- **Sentry event ID:** `b3c2837d09ae4583a78d9d487a250a78` (2026-05-26 13:00 CEST, level: error)
- **PR #3126 (`67e21b29`):** Introduced the provider-error classification branch.
- **PR #4485 (`bcb2bd4c`):** Same-class fix for the webhook no-grant path (removed Sentry emission entirely).
- **Learning:** `knowledge-base/project/learnings/best-practices/2026-05-26-sentry-captureMessage-on-expected-paths-creates-alert-noise.md`

## References

- `apps/web-platform/app/(auth)/callback/route.ts:67-98` -- the provider-error branch
- `apps/web-platform/server/observability.ts:164-203` -- `reportSilentFallback` (error level)
- `apps/web-platform/server/observability.ts:211-241` -- `warnSilentFallback` (warning level)
- `apps/web-platform/lib/auth/provider-error-classifier.ts` -- provider error classification logic
- `apps/web-platform/test/app/auth/callback-route-branches.test.ts` -- test coverage for callback route branches
