---
title: "fix: remove Sentry.captureMessage from no-grant path in GitHub webhook handler"
branch: feat-one-shot-fix-webhook-scope-grant-sentry-noise
lane: single-domain
---

# Tasks

## Phase 1: Core Implementation

- [ ] 1.1 Open `apps/web-platform/app/api/webhooks/github/route.ts`
- [ ] 1.2 Downgrade `logger.warn` to `logger.info` at lines 330-333 (change method name only; preserve structured fields and message string)
- [ ] 1.3 Remove the `Sentry.captureMessage("GitHub webhook: no active scope_grant", {...});` block at lines 334-338 (5 lines)
- [ ] 1.4 Verify the `return NextResponse.json({ received: true });` on the line after the removed block is preserved
- [ ] 1.5 Update test at `apps/web-platform/test/server/webhooks/github-route.test.ts:172-183`: change `mockLogger.warn` to `mockLogger.info`, replace `mockSentryCaptureMessage` positive assertion with `.not.toHaveBeenCalled()`
- [ ] 1.6 Update test description from `"logs + Sentry fire"` to `"logs at info level; no Sentry emission"`

## Phase 2: Verification

- [ ] 2.1 Run `npx tsc --noEmit --project apps/web-platform/tsconfig.json` -- must pass with zero errors
- [ ] 2.2 Run `grep -c "Sentry.captureMessage" apps/web-platform/app/api/webhooks/github/route.ts` -- expect 2
- [ ] 2.3 Run `grep -n "logger.info" apps/web-platform/app/api/webhooks/github/route.ts | grep "no active scope_grant"` -- expect 1 match
- [ ] 2.4 Run `grep -c "Sentry.captureException" apps/web-platform/app/api/webhooks/github/route.ts` -- expect 5

## Phase 3: Commit & PR

- [ ] 3.1 Commit with message `fix(webhook): remove Sentry noise from expected no-grant path`
- [ ] 3.2 Push and open PR
