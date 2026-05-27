# Tasks: fix-app-jwt-octokit-retry-401

## Phase 1: Core Implementation

- [ ] 1.1 Read `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` and locate `step.run("drift-check", ...)` call site (lines 714-718)
- [ ] 1.2 Add retry-on-401 logic: after `probeDriftGuard()` returns, check if `firstResult.failureMode === "github_app_401"`; if so, log warning via `logger.warn()`, sleep 1s, create fresh `createAppJwtOctokit()`, re-run `probeDriftGuard()`
- [ ] 1.3 Verify TypeScript compiles: `./node_modules/.bin/tsc --noEmit`

## Phase 2: Testing

- [ ] 2.1 Add test: "transient github_app_401 retries and self-heals" -- mock `octokitRequestSpy` to 401 on first `GET /app`, healthy on second; assert `failureMode === ""`
- [ ] 2.2 Verify existing "github_app_401 -> ci/auth-broken label" test still passes (persistent 401 now hits retry path too)
- [ ] 2.3 Run full drift-guard test suite: `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`

## Phase 3: Verification

- [ ] 3.1 Verify no other callers of `createAppJwtOctokit()` need similar treatment: `grep -rn "createAppJwtOctokit" apps/web-platform/ --include="*.ts"`
- [ ] 3.2 Verify `tsc --noEmit` passes
- [ ] 3.3 Verify all drift-guard tests pass
