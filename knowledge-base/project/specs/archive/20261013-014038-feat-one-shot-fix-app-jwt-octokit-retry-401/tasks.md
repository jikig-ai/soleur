# Tasks: fix-app-jwt-octokit-retry-401

## Phase 1: Core Implementation

- [x] 1.1 Read `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` and locate `step.run("drift-check", ...)` call site (lines 714-719)
- [x] 1.2 Add retry-on-`github_app_401` logic inside the `step.run("drift-check")` callback: after `probeDriftGuard()` returns, check if `firstResult.failureMode === "github_app_401"`; if so, log warning via `logger.warn({ fn: "cron-github-app-drift-guard" }, "github_app_401 on drift-check -- retrying once after 1s")`, sleep 1s, create fresh `createAppJwtOctokit()`, re-run `probeDriftGuard()`
- [x] 1.3 Use `logger.warn()` (handler's Inngest logger, in closure scope), NOT `log.warn()` (module-scoped from probe-octokit.ts, not importable)
- [x] 1.4 Verify TypeScript compiles: `./node_modules/.bin/tsc --noEmit`

## Phase 2: Testing

- [x] 2.1 Add test: "transient github_app_401 retries once and self-heals" -- use stateful call-count mock on `octokitRequestSpy` (first `GET /app` throws 401, second returns healthy); assert `failureMode === ""`, `leakDetected === false`, `logger.warn` called with `github_app_401`, heartbeat `?status=ok`
- [x] 2.2 Verify existing "github_app_401 -> ci/auth-broken label" test (line 285) still passes -- it now triggers retry (1s sleep) but persistent 401 still returns `github_app_401`
- [x] 2.3 Run full drift-guard test suite: `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`

## Phase 3: Verification

- [x] 3.1 Confirm `createAppJwtOctokit()` has exactly 1 production caller: `grep -rn "createAppJwtOctokit" apps/web-platform/ --include="*.ts" | grep -v test | grep -v "export async function"`
- [x] 3.2 Verify `tsc --noEmit` passes
- [x] 3.3 Verify all drift-guard tests pass
