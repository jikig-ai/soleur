---
title: "fix: add retry-on-401 to createAppJwtOctokit()"
type: fix
date: 2026-05-27
lane: single-domain
brand_survival_threshold: none
---

# fix: add retry-on-401 to createAppJwtOctokit()

## Overview

PR #4498 hardened `createProbeOctokit()` and `generateInstallationToken()` in `apps/web-platform/server/github/` with retry-on-401 to handle transient GitHub JWT verification failures ("A JSON web token could not be decoded"). The same file's `createAppJwtOctokit()` was missed -- it creates a bare `@octokit/app` `App` instance and returns `app.octokit` without any retry wrapper. The drift-guard cron (`cron-github-app-drift-guard.ts`) calls `createAppJwtOctokit()` in its "drift-check" step; when the JWT 401 fires, the error propagates to the outer catch which records `github_api_network` and does NOT retry. Sentry error at `2026-05-27T00:00:01Z` confirms this path fired in production.

## Problem Statement / Motivation

`@octokit/auth-app` does NOT internally retry JWT decode 401 errors. GitHub occasionally returns "A JSON web token could not be decoded" on valid JWTs due to replication delay or transient verification issues. The retry pattern (wait 1s, mint a fresh `App` instance, try again) is already proven in two sibling functions in the same file. The gap in `createAppJwtOctokit()` means the drift-guard cron fails with `github_api_network` on these transient errors, filing a `ci/guard-broken` issue and paging the operator for a self-healing condition.

## Proposed Solution

Add the same retry-on-401 wrapper to `createAppJwtOctokit()` that `createProbeOctokit()` already uses:

1. Extract the current body into an inner `attempt()` async function
2. Call `attempt()` in a try/catch
3. On 401, log a warning, sleep 1s, retry with a fresh `App` instance via a second `attempt()` call
4. On non-401 errors, rethrow

This matches `createProbeOctokit()` lines 57-79 exactly.

## User-Brand Impact

- **If this lands broken, the user experiences:** False "ci/guard-broken" issue filed on the operator repo + Sentry alert noise + Resend email for a transient condition that would self-heal on next cron tick (hourly)
- **If this leaks, the user's data / workflow / money is exposed via:** N/A -- no user data involved; this is operator-owned platform infrastructure code
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: operator-only synthetic probe infrastructure; no founder-facing surface touched`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-github-app-drift-guard"
  cadence: hourly (0 * * * *)
  alert_target: Sentry issue + Resend ops email
  configured_in: apps/web-platform/infra/sentry.tf (sentry_cron_monitor.scheduled_github_app_drift_guard)

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN
  fail_loud: reportSilentFallback logs "probeDriftGuard threw" + files ci/guard-broken issue

failure_modes:
  - mode: "Transient GitHub JWT 401 on createAppJwtOctokit()"
    detection: "Sentry error 'HttpError: A JSON web token could not be decoded' + ci/guard-broken issue filed"
    alert_route: "operator via Sentry + Resend email"
  - mode: "Persistent GitHub JWT 401 (App credentials actually rotated/revoked)"
    detection: "Two consecutive 401s -- retry fails, ci/guard-broken issue filed"
    alert_route: "operator via Sentry + Resend email"

logs:
  where: pino structured logs (probe-octokit child logger) -> Vercel log drain
  retention: 30 days (Vercel default)

discoverability_test:
  command: "gh api repos/jikig-ai/soleur/issues -q '.[] | select(.title | contains(\"drift-guard\")) | .title' --paginate | head -5"
  expected_output: "no open ci/guard-broken issues (empty output = healthy)"
```

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/server/github/probe-octokit.ts` | Add retry-on-401 wrapper to `createAppJwtOctokit()` matching `createProbeOctokit()` pattern |
| `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` | Add test: `createAppJwtOctokit` 401 on first call retries and succeeds on second; add test: persistent 401 still propagates |

## Files to Create

None.

## Open Code-Review Overlap

None.

## Implementation Phases

### Phase 1: Add retry-on-401 to createAppJwtOctokit()

**File:** `apps/web-platform/server/github/probe-octokit.ts`

Refactor `createAppJwtOctokit()` (lines 102-110) from:

```typescript
export async function createAppJwtOctokit(): Promise<{
  octokit: InstanceType<typeof App>["octokit"];
}> {
  const app = new App({
    appId: readEnv(APP_ID_ENV),
    privateKey: readEnv(PRIVATE_KEY_ENV),
  });
  return { octokit: app.octokit };
}
```

To the retry-on-401 pattern matching `createProbeOctokit()` (lines 57-79):

```typescript
export async function createAppJwtOctokit(): Promise<{
  octokit: InstanceType<typeof App>["octokit"];
}> {
  function attempt() {
    const app = new App({
      appId: readEnv(APP_ID_ENV),
      privateKey: readEnv(PRIVATE_KEY_ENV),
    });
    return { octokit: app.octokit };
  }

  try {
    return attempt();
  } catch (err) {
    const status = (err as { status?: number }).status;
    if (status !== 401) throw err;
    log.warn("401 on App JWT auth — retrying once after 1s");
    await new Promise((r) => setTimeout(r, 1_000));
    return attempt();
  }
}
```

**Key difference from `createProbeOctokit()`:** `createAppJwtOctokit()` does NOT make any API requests itself -- the `App` constructor and `app.octokit` property access are synchronous. The 401 error fires later when the CALLER uses `app.octokit.request(...)` (e.g., `GET /app` inside `probeDriftGuard()`). Therefore, the retry must happen at the call site in `cron-github-app-drift-guard.ts`, NOT inside `createAppJwtOctokit()` itself.

**Revised approach:** The retry belongs in `cronGithubAppDriftGuardHandler()` at the `step.run("drift-check", ...)` call site (lines 714-718), wrapping the `createAppJwtOctokit()` + `probeDriftGuard()` sequence. Specifically:

1. When `probeDriftGuard()` throws with `.status === 401`, retry the entire drift-check step body (fresh `createAppJwtOctokit()` + fresh `probeDriftGuard()` call) after a 1s delay.
2. This mirrors the effective behavior: a fresh `App` instance mints a fresh JWT, and the retry gives GitHub's JWT verification pipeline time to propagate.

However, examining the existing code more carefully:

- `probeDriftGuard()` already catches 401 from `GET /app` internally (lines 338-345) and returns `makeFailure("github_app_401", ...)` rather than throwing.
- The outer catch in `cronGithubAppDriftGuardHandler()` (lines 721-737) catches exceptions that escape `probeDriftGuard()` -- these are NOT the 401 from `GET /app`.
- The Sentry error "A JSON web token could not be decoded" fires during the `App` constructor's internal JWT minting OR during the first `app.octokit.request()` call.

**Root cause re-analysis:** The `@octokit/auth-app` `App` instance lazily mints the JWT when `app.octokit` is first used for a request. The 401 "A JSON web token could not be decoded" fires when `octokit.request("GET /app")` is called inside `probeDriftGuard()`. This is caught by `probeDriftGuard()`'s own try/catch (line 337) which returns `github_app_401` -- it does NOT throw. So the outer handler correctly records the failure mode.

The issue is: `probeDriftGuard()` records the failure but does NOT retry. The fix should be: **add retry-on-401 inside `createAppJwtOctokit()` that makes a test request to verify the JWT works**, or **add retry logic around the `probeDriftGuard()` call in the handler when the result is `github_app_401`**.

**Final approach (simplest, matching the ticket description):** Wrap the `createAppJwtOctokit()` + `probeDriftGuard()` call in the "drift-check" step with a retry when the result is `github_app_401`:

In `cron-github-app-drift-guard.ts` lines 714-718, change:

```typescript
result = await step.run("drift-check", async (): Promise<DriftResult> => {
  const { octokit } = await createAppJwtOctokit();
  return await probeDriftGuard({
    octokit: octokit as unknown as Octokit,
    logger,
  });
});
```

To:

```typescript
result = await step.run("drift-check", async (): Promise<DriftResult> => {
  const { octokit } = await createAppJwtOctokit();
  const firstResult = await probeDriftGuard({
    octokit: octokit as unknown as Octokit,
    logger,
  });
  if (firstResult.failureMode !== "github_app_401") return firstResult;

  // Retry once on transient JWT 401 — fresh App instance mints a new JWT.
  log.warn("github_app_401 on drift-check — retrying once after 1s");
  await new Promise((r) => setTimeout(r, 1_000));
  const { octokit: retryOctokit } = await createAppJwtOctokit();
  return await probeDriftGuard({
    octokit: retryOctokit as unknown as Octokit,
    logger,
  });
});
```

This is the correct fix because:
1. The 401 is caught and classified by `probeDriftGuard()` as `github_app_401` -- it never throws
2. The retry creates a fresh `App` instance (fresh JWT) and re-runs the full probe
3. If the retry also 401s, the persistent failure is correctly reported
4. Matches the 1s-delay pattern from `createProbeOctokit()` and `generateInstallationToken()`

### Phase 2: Add tests

**File:** `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`

Add two test cases:

1. **Transient 401 retries and self-heals:** Mock `octokitRequestSpy` to return 401 on first `GET /app` call, then healthy on second. Assert `failureMode === ""` (success) and heartbeat `?status=ok`.

2. **Persistent 401 still reports failure:** Mock `octokitRequestSpy` to always return 401 on `GET /app`. Assert `failureMode === "github_app_401"` and heartbeat `?status=error`. This is already covered by the existing "github_app_401 -> ci/auth-broken label" test, but verify it still passes after the retry logic is added (the existing test should now report after TWO 401s, not one).

**Note on import for `log`:** The `cron-github-app-drift-guard.ts` handler file needs access to the `log` logger from `probe-octokit.ts`. Since `log` is module-scoped and not exported, the retry log line should use the handler's own `logger` argument instead. This keeps the change self-contained.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `createAppJwtOctokit()` call site in `cronGithubAppDriftGuardHandler()` retries on `github_app_401` result with a fresh `App` instance after 1s delay
- [ ] AC2: Retry creates a NEW `App` instance (not reusing the original) so a fresh JWT is minted
- [ ] AC3: Non-401 failure modes from `probeDriftGuard()` are NOT retried (only `github_app_401`)
- [ ] AC4: Persistent 401 (both attempts fail) still reports `github_app_401` / `ci/auth-broken`
- [ ] AC5: Test passes: transient 401 (first call 401, second call healthy) results in `failureMode: ""`
- [ ] AC6: Test passes: persistent 401 results in `failureMode: "github_app_401"`
- [ ] AC7: Existing drift-guard tests continue to pass: `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`
- [ ] AC8: TypeScript compiles: `./node_modules/.bin/tsc --noEmit`
- [ ] AC9: No new dependencies added

### Post-merge (operator)

- [ ] AC10: Monitor Sentry for "A JSON web token could not be decoded" errors from `cron-github-app-drift-guard` over the next 48 hours; transient occurrences should no longer file `ci/guard-broken` issues. Verification: `gh api repos/jikig-ai/soleur/issues -q '.[] | select(.title | contains("drift-guard")) | .title' --paginate | head -5`

## Test Scenarios

- Given the drift-guard cron fires and `GET /app` returns 401 transiently, when `probeDriftGuard()` returns `github_app_401`, then the handler retries with a fresh `createAppJwtOctokit()` after 1s and the second probe succeeds with `failureMode: ""`
- Given the drift-guard cron fires and `GET /app` returns 401 persistently (both attempts), when both probes return `github_app_401`, then the handler reports `github_app_401` / `ci/auth-broken` as before
- Given the drift-guard cron fires and `GET /app` returns a non-401 error (e.g., 500), when `probeDriftGuard()` returns `github_api_http`, then the handler does NOT retry

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change to operator-owned synthetic probe.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Retry adds 1s latency to every transient 401 | Acceptable: cron runs hourly, 1s is negligible vs. the false-alarm cost |
| Inngest step timeout on the retry | `step.run()` timeout is 30s default; 1s delay + second probe is well within budget |
| Retry masks a genuine credential rotation | After retry, a persistent 401 is still reported as `github_app_401` / `ci/auth-broken` |

## References

- PR #4498: `fix(auth): harden GitHub App JWT auth with retry-on-401 across both token paths` (merged 2026-05-26)
- `apps/web-platform/server/github/probe-octokit.ts:57-79`: existing `createProbeOctokit()` retry pattern
- `apps/web-platform/server/github-app.ts:489-496`: existing `generateInstallationToken()` retry pattern
- Sentry error: `HttpError: A JSON web token could not be decoded` at `2026-05-27T00:00:01Z`
