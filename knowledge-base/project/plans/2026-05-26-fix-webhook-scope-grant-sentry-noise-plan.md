---
title: "fix: remove Sentry.captureMessage from no-grant path in GitHub webhook handler"
type: fix
date: 2026-05-26
lane: single-domain
brand_survival_threshold: none
---

# fix: Remove Sentry.captureMessage from no-grant path in GitHub webhook handler

## Enhancement Summary

**Deepened on:** 2026-05-26
**Sections enhanced:** 1 (plan review finding applied)
**Research agents used:** DHH, Kieran, Code Simplicity (3-agent panel; brand-survival threshold `none`)

### Key Improvements
1. Added test file (`github-route.test.ts`) to Files to Edit -- plan review (Kieran P0) caught that the existing test asserts `mockLogger.warn` and `mockSentryCaptureMessage` positive, both of which must be updated.
2. Added AC6 for test verification.
3. Added Phase 1.5 for test file update.

### Deepen-Plan Gates
- Phase 4.6 (User-Brand Impact): PASS -- section present, threshold `none`, no sensitive paths.
- Phase 4.7 (Observability): SKIP -- deletion-only change (removes 5 lines, changes 1 word); no new code/infra surface per plan Phase 2.9 skip condition.
- Phase 4.8 (PAT halt): PASS -- no PAT-shaped variables.
- Phase 4.4 (Precedent-diff): N/A -- no pattern-bound behaviors prescribed.
- Phase 4.5 (Network-outage): N/A -- no trigger patterns matched.
- AGENTS.md rule ID verification: `cq-silent-fallback-must-mirror-to-sentry` confirmed active.

## Overview

The GitHub webhook handler at `apps/web-platform/app/api/webhooks/github/route.ts` fires
`Sentry.captureMessage("GitHub webhook: no active scope_grant", { level: "warning" })`
on every webhook delivery where the founder has not granted the corresponding action class.
This is an expected, non-actionable condition -- the scope-grant gate is fail-closed by design
(Step 6 in the canonical comment block, lines 314-318). The Sentry emission generates ~600
warnings/day, drowning real signals (signature failures, DB errors, inngest.send failures)
and burning the $50/mo PAYG Sentry cap.

**Root cause:** The original PR-H (#3244) Phase 3 implementation treated no-grant as a
degraded condition requiring observability parity with the error paths. In practice, the
no-grant path is the *default state* for any action class the founder hasn't opted into --
it is structurally identical to the `logger.info` at line 321-325 for unsupported events,
not to the `Sentry.captureException` calls on DB errors or inngest.send failures.

## User-Brand Impact

- **If this lands broken, the user experiences:** No user-facing change. The 200 response and fail-closed behavior are preserved. The only observable difference is reduced Sentry noise.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A -- no data surface is affected. The change removes an observability emission, not a security guard.
- **Brand-survival threshold:** `none`

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/app/api/webhooks/github/route.ts` | (1) Downgrade `logger.warn` at lines 330-333 to `logger.info`. (2) Remove the `Sentry.captureMessage(...)` block at lines 334-338. |
| `apps/web-platform/test/server/webhooks/github-route.test.ts` | Update test at lines 172-183: (1) Change `mockLogger.warn` assertion to `mockLogger.info`. (2) Replace `mockSentryCaptureMessage` assertion with `expect(mockSentryCaptureMessage).not.toHaveBeenCalled()`. |

## Files to Create

None.

## Do NOT Change

- The `return NextResponse.json({ received: true })` at line 339 -- the 200 response is correct (fail-closed by design; GitHub would retry 5xx indefinitely).
- The Stripe webhook handler (`app/api/webhooks/stripe/route.ts`) -- it already only logs without Sentry emission for its equivalent no-grant paths.
- Any other `Sentry.captureMessage`/`captureException` calls in `route.ts` -- those cover real error conditions:
  - Line 112: secret unset (error)
  - Line 124: signature verification failed (error)
  - Line 162: dedup insert DB error (exception)
  - Line 184: dedup release failure (exception)
  - Line 247: founder lookup DB error (exception)
  - Line 304: inngest.send push failure (exception)
  - Line 374: inngest.send dispatch failure (exception)

## cq-silent-fallback-must-mirror-to-sentry Applicability

The no-grant path is NOT a silent fallback. The `cq-silent-fallback-must-mirror-to-sentry`
rule (AGENTS.rest.md) explicitly exempts "expected 4xx (CSRF, rate-limit, first-time 404,
pass-through)." The no-grant path returns 200 and is expected behavior by design -- the
founder simply hasn't granted the action class. No DB error is swallowed, no fallback data
is substituted, no degraded condition is masked. The `logger.info` downgrade preserves
structured-log observability (pino stdout) for any future debugging while removing the
Sentry noise.

## Open Code-Review Overlap

None.

## Acceptance Criteria

- [x] **AC1:** `grep -c "Sentry.captureMessage" apps/web-platform/app/api/webhooks/github/route.ts` returns 2 (secret-unset + signature-failed; the no-grant captureMessage is removed).
- [x] **AC2:** `grep -n "logger.info" apps/web-platform/app/api/webhooks/github/route.ts | grep "no active scope_grant"` returns exactly 1 match (the downgraded log line).
- [x] **AC3:** `grep -c "Sentry.captureException" apps/web-platform/app/api/webhooks/github/route.ts` returns 5 (unchanged -- dedup-insert, dedup-release, founder-lookup, inngest-send-push, inngest-send).
- [x] **AC4:** The `return NextResponse.json({ received: true })` immediately after the no-grant block is preserved.
- [x] **AC5:** TypeScript compiles without errors: `npx tsc --noEmit --project apps/web-platform/tsconfig.json`.
- [x] **AC6:** Test passes: the scope-grant gate test at `github-route.test.ts:172` asserts `mockLogger.info` (not `.warn`) and `expect(mockSentryCaptureMessage).not.toHaveBeenCalled()`.

## Test Scenarios

- Given a webhook delivery for an action class the founder has not granted, when the handler processes it, then it returns 200, logs at `info` level, and does NOT emit to Sentry.
- Given a webhook with an invalid signature, when the handler processes it, then it returns 401 AND emits `Sentry.captureMessage` at error level (unchanged).
- Given a webhook where the DB errors on founder lookup, when the handler processes it, then it returns 500 AND emits `Sentry.captureException` (unchanged).

## Implementation Phases

### Phase 1: Edit route.ts (two changes)

1. **Downgrade logger.warn to logger.info** at lines 330-333:
   - Change `logger.warn(` to `logger.info(`
   - The structured log fields (`founderId`, `actionClass`, `deliveryId`) and message string remain identical.

2. **Remove the Sentry.captureMessage block** at lines 334-338:
   - Remove the 5 lines from `Sentry.captureMessage("GitHub webhook: no active scope_grant", {` through the closing `});`.
   - The `return NextResponse.json({ received: true });` at line 339 remains.

### Phase 1.5: Update test file

1. In `apps/web-platform/test/server/webhooks/github-route.test.ts` at lines 172-183:
   - Update the test description from `"logs + Sentry fire"` to `"logs at info level; no Sentry emission"`.
   - Change `expect(mockLogger.warn).toHaveBeenCalled()` (line 178) to `expect(mockLogger.info).toHaveBeenCalled()`.
   - Replace the `expect(mockSentryCaptureMessage).toHaveBeenCalledWith(...)` assertion (lines 179-182) with `expect(mockSentryCaptureMessage).not.toHaveBeenCalled()`.

### Phase 2: Verify

1. Run `npx tsc --noEmit --project apps/web-platform/tsconfig.json` to confirm no type errors.
2. Run AC1-AC5 verification commands.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Loss of observability for genuine grant misconfiguration | Low | Low | `logger.info` preserves the structured log in pino stdout. If a founder reports missing webhook-driven actions, the log is searchable by `founderId` + `actionClass`. The no-grant state is the default for any unused action class -- it is not a misconfiguration. |
| Sentry alert rule depends on this message | Low | Low | Verified: the message "GitHub webhook: no active scope_grant" is a warning-level captureMessage, not an exception. Sentry alert rules typically fire on exceptions or error-level events. The removal reduces noise without affecting error-level alerting. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- observability noise reduction in a single webhook handler.

## Context

- **PR-H (#3244):** Original Phase 3 implementation that introduced the GitHub webhook handler.
- **Sentry impact:** ~600 warnings/day at current webhook volume; projected to grow linearly with GitHub App installations.
- **Stripe webhook parity:** The Stripe webhook handler at `app/api/webhooks/stripe/route.ts` uses `Sentry.captureMessage` only for signature verification failure (line 95) and `Sentry.captureException` for DB/processing errors -- it does NOT emit Sentry warnings for expected business-logic paths, confirming the pattern fix here.

## References

- `apps/web-platform/app/api/webhooks/github/route.ts:314-339` -- the scope-grant gate block
- `apps/web-platform/app/api/webhooks/stripe/route.ts` -- canonical Stripe webhook for pattern comparison
- AGENTS.rest.md `cq-silent-fallback-must-mirror-to-sentry` -- exemption clause for expected conditions
