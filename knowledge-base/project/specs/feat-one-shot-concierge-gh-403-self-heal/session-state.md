# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-08-fix-concierge-gh-403-self-heal-hardening-plan.md
- Status: complete

### Errors
None. Domain-leader/research Task-agent spawn unavailable in planning env; deepen-plan gates + precedent-diff / verify-the-negative run inline. security-sentinel/data-integrity-guardian/architecture-strategist triad deferred to /soleur:plan-review + /soleur:review (mandatory at single-user-incident threshold).

### Decisions
- Premise was substantially stale: PR #4946 (merged, da138f1dc) already added the self-heal + entitlement gate, reportSilentFallback wrap, mint-time observability, and reproduce harness. Re-scoped to 3 verified residual bugs.
- Bug A: membership probe collapses transient 5xx/network/timeout into "not a member" (github-app.ts:560); AbortSignal.timeout throw uncaught in findRepoOwnerInstallationForUser → entitled member 403s on a flaky probe. Fix: 3-value outcome (member/not-member/indeterminate) + retry on indeterminate, fail-closed.
- Bug B: skipped-promotion decision emits nothing queryable (log.info is breadcrumb-only). Route skips through reportSilentFallback (captureMessage) with storedInstallationId/owner/probe-outcome/effectiveInstallationId.
- Bug C: GH_403_PROMPT_DIRECTIVE self-contradicts — forbids re-consent then sanctions "ask user to confirm the app is installed" (exact screenshot behavior). Delete that clause; AC6 punctuation-safe negative match.
- Failing tests first; extends github-app-mint-observability.test.ts + cc-dispatcher-gh-403-directive.test.ts + 1 new test file. hr-github-app-auth-not-pat enforced. verifyInstallationOwnership (:330) out of scope (connect-time, not dispatch 403). Threshold single-user incident → requires_cpo_signoff.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan; Bash/Read/Edit/Write/ToolSearch
