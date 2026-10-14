# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-27-fix-oauth-callback-access-denied-sentry-alert-noise-plan.md
- Status: complete

### Errors
None

### Decisions
- The previous fix (PR #4487, downgrading `reportSilentFallback` to `warnSilentFallback`) was insufficient because `warnSilentFallback` still emits to Sentry via `captureMessage` at warning level, and Sentry `EventFrequencyCondition` alert rules count ALL events regardless of level
- The `auth-per-user-loop` alert rule filters only on `feature=auth` (no `op` filter), so it catches `callback_provider_error` events including user-cancel
- The fix splits the provider-error branch: `access_denied` (user-cancel) uses `logger.info` only (no Sentry emission), while all other provider errors keep `warnSilentFallback` for diagnostic value
- This mirrors the PR #4485 pattern (webhook no-grant path) which removed Sentry emission entirely for expected-state conditions
- Test mock wiring requires adding `mockLoggerInfo` to `vi.hoisted` block and wiring it through the logger factory

### Components Invoked
- soleur:plan
- soleur:deepen-plan
