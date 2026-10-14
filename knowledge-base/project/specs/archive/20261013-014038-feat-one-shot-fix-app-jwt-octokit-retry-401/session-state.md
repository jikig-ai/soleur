# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-27-fix-app-jwt-octokit-retry-401-plan.md
- Status: complete

### Errors
None

### Decisions
- The retry belongs in `cron-github-app-drift-guard.ts` (the call site), NOT in `probe-octokit.ts` (`createAppJwtOctokit()` itself), because the `@octokit/app` `App` constructor is synchronous and JWT minting is lazy -- the 401 fires later during `probeDriftGuard()`'s `octokit.request("GET /app")` call, which is caught internally and returned as `failureMode: "github_app_401"` (never thrown).
- Use `logger.warn()` (Inngest handler logger, in closure scope) instead of `log.warn()` (module-scoped from `probe-octokit.ts`, not importable from the handler file).
- The retry checks the returned `failureMode` string (result-based), not a caught exception (exception-based), because `probeDriftGuard()` catches the 401 internally and classifies it.
- The transient-401 test uses a stateful call-count mock on `octokitRequestSpy` because both first and retry `createAppJwtOctokit()` calls return the same mock object.
- The existing persistent-401 test (line 285) still passes unchanged after the retry logic is added -- it now triggers the retry path (adding 1s latency) but the final result is the same.

### Components Invoked
- `soleur:plan` -- created initial plan and tasks
- `soleur:deepen-plan` -- deepened with SDK source verification, precedent-diff, test implementation details, and corrected the fix location and logger usage
