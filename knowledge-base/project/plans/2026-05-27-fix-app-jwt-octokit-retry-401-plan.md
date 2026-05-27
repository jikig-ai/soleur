---
title: "fix: add retry-on-401 to createAppJwtOctokit()"
type: fix
date: 2026-05-27
lane: single-domain
brand_survival_threshold: none
deepened: 2026-05-27
---

# fix: add retry-on-401 to createAppJwtOctokit()

## Enhancement Summary

**Deepened on:** 2026-05-27
**Sections enhanced:** 4 (Proposed Solution, Implementation Phases, Test details, Risks)
**Research agents used:** SDK source inspection, precedent-diff, caller-site grep

### Key Improvements
1. Corrected the fix location: retry belongs in `cron-github-app-drift-guard.ts` (call site), NOT in `probe-octokit.ts` (`createAppJwtOctokit()` itself). The `App` constructor is synchronous; the 401 fires later during `probeDriftGuard()`'s `octokit.request("GET /app")` call, which is caught internally and returned as `failureMode: "github_app_401"` -- never thrown.
2. Fixed the log call: `logger.warn(...)` (handler's Inngest logger, in closure scope) instead of `log.warn(...)` (module-scoped logger from `probe-octokit.ts`, not importable from the handler file).
3. Added concrete test implementation details: stateful `octokitRequestSpy` mock using call-count tracking, plus impact analysis on the existing "github_app_401" test (now sees TWO 401 throws, not one).

### New Considerations Discovered
- The `@octokit/app` `App` constructor is synchronous (verified against installed `node_modules/@octokit/app/dist-src/index.js:52`). JWT minting is lazy via `createAppAuth` auth strategy -- fires only on first `octokit.request()`.
- `createAppJwtOctokit()` is called from exactly 1 production site (`cron-github-app-drift-guard.ts:715`). No other callers need similar treatment.
- The test mock returns the same `octokitRequestSpy` for both first and retry `createAppJwtOctokit()` calls, so the transient 401 test must use call-count-based stateful mock logic.

## Overview

PR #4498 hardened `createProbeOctokit()` and `generateInstallationToken()` in `apps/web-platform/server/github/` with retry-on-401 to handle transient GitHub JWT verification failures ("A JSON web token could not be decoded"). The same file's `createAppJwtOctokit()` was missed -- it creates a bare `@octokit/app` `App` instance and returns `app.octokit` without any retry wrapper. The drift-guard cron (`cron-github-app-drift-guard.ts`) calls `createAppJwtOctokit()` in its "drift-check" step; when the JWT 401 fires, `probeDriftGuard()` catches it and returns `failureMode: "github_app_401"` -- but the handler does NOT retry. The failure is recorded, a `ci/guard-broken` issue is filed, and the operator is paged for a self-healing condition. Sentry error at `2026-05-27T00:00:01Z` confirms this path fired in production.

## Problem Statement / Motivation

`@octokit/auth-app` does NOT internally retry JWT decode 401 errors. GitHub occasionally returns "A JSON web token could not be decoded" on valid JWTs due to replication delay or transient verification issues. The retry pattern (wait 1s, mint a fresh `App` instance, try again) is already proven in two sibling functions in the same file. The gap means the drift-guard cron's `step.run("drift-check")` returns `github_app_401` on transient errors, filing a `ci/guard-broken` issue and paging the operator for a condition that would self-heal on next hourly tick.

## Proposed Solution

Add retry-on-401 logic in the drift-guard handler's `step.run("drift-check")` callback. When `probeDriftGuard()` returns `failureMode === "github_app_401"`, retry once after 1s with a fresh `createAppJwtOctokit()` call (fresh JWT). This is the correct location because:

1. `createAppJwtOctokit()` itself is synchronous -- the `App` constructor does not make any network calls (verified against installed `@octokit/app/dist-src/index.js:52`). JWT minting is lazy via `createAppAuth` and fires only on first `octokit.request()`.
2. `probeDriftGuard()` catches the 401 internally (line 339) and returns `makeFailure("github_app_401", ...)` -- it does NOT throw.
3. The retry must check the returned `failureMode`, not catch an exception.

This matches the 1s-delay pattern from `createProbeOctokit()` and `generateInstallationToken()`.

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
| `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` | Add retry-on-`github_app_401` logic inside `step.run("drift-check")` callback (lines 714-719): check `firstResult.failureMode`, retry with fresh `createAppJwtOctokit()` after 1s delay |
| `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` | Add test: transient 401 (first `GET /app` call 401, second healthy) results in `failureMode: ""`; verify existing persistent-401 test still passes |

## Files to Create

None.

## Open Code-Review Overlap

None.

## Implementation Phases

### Phase 1: Add retry-on-`github_app_401` in drift-check step

**File:** `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`

**Why the retry belongs HERE, not in `createAppJwtOctokit()`:**
- The `@octokit/app` `App` constructor is synchronous (verified: `node_modules/@octokit/app/dist-src/index.js:52` -- `this.octokit = new Octokit(octokitOptions)`). JWT minting is lazy via `createAppAuth` auth strategy and fires only on first `octokit.request()`.
- `probeDriftGuard()` catches the 401 from `GET /app` internally (line 339: `if (e.status === 401)`) and returns `makeFailure("github_app_401", ...)` -- it does NOT throw.
- Therefore, the retry must check the returned `failureMode`, not catch an exception.

In `cron-github-app-drift-guard.ts` lines 714-719, change:

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
  logger.warn(
    { fn: "cron-github-app-drift-guard" },
    "github_app_401 on drift-check — retrying once after 1s",
  );
  await new Promise((r) => setTimeout(r, 1_000));
  const { octokit: retryOctokit } = await createAppJwtOctokit();
  return await probeDriftGuard({
    octokit: retryOctokit as unknown as Octokit,
    logger,
  });
});
```

**Critical detail -- `logger.warn()` not `log.warn()`:** The handler's `logger` parameter (Inngest logger, destructured at line 702) is in closure scope inside `step.run()`. The module-scoped `log` from `probe-octokit.ts` is not exported and not importable from the handler file. Use `logger.warn({ fn: "cron-github-app-drift-guard" }, "...")` to match the convention used at line 402 for the suppression warning.

**Inngest step.run() safety:** The entire callback runs as one atomic unit. Inngest memoizes step results via deterministic replay; if the step already ran, Inngest replays the result without re-executing. The retry (1s sleep + second probe) all happens within a single step execution, well within the 30s default step timeout.

### Phase 2: Add tests

**File:** `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`

#### Test 1: Transient 401 retries and self-heals

**Mock strategy:** The test infrastructure uses a shared `octokitRequestSpy` returned by both `createAppJwtOctokitSpy` and used inside `probeDriftGuard()`. Both the first and retry `createAppJwtOctokit()` calls return the same spy. For transient 401, the mock must be stateful: throw 401 on the first `GET /app` call, return healthy on the second.

```typescript
it("transient github_app_401 retries once and self-heals", async () => {
  let getAppCallCount = 0;
  octokitRequestSpy.mockImplementation(async (route: string) => {
    if (route === "GET /app") {
      getAppCallCount++;
      if (getAppCallCount === 1) {
        const err = new Error("A JSON web token could not be decoded") as Error & { status?: number };
        err.status = 401;
        throw err;
      }
      return { status: 200, data: healthyAppResponse, headers: {} };
    }
    if (route === "GET /app/installations") {
      return {
        status: 200,
        data: healthyInstallationsResponse.data,
        headers: healthyInstallationsResponse.headers,
      };
    }
    if (route === "GET /search/issues") {
      return { data: { items: [] } };
    }
    return { data: {} };
  });
  const { cronGithubAppDriftGuardHandler } = await importHandler();
  const step = makeStep();
  const out = await cronGithubAppDriftGuardHandler({ step, logger });
  expect(out.failureMode).toBe("");
  expect(out.leakDetected).toBe(false);
  // Retry warning was logged
  expect(logger.warn).toHaveBeenCalledWith(
    expect.objectContaining({ fn: "cron-github-app-drift-guard" }),
    expect.stringContaining("github_app_401"),
  );
  // Sentry heartbeat is OK (transient healed)
  const fetchSpy = globalThis.fetch as unknown as ReturnType<typeof vi.fn>;
  expect(findHeartbeatStatus(fetchSpy)).toBe("ok");
});
```

#### Test 2: Persistent 401 still reports failure after retry

The existing "github_app_401 -> ci/auth-broken label" test (line 285) already mocks ALL `GET /app` calls to throw 401. After the retry logic is added, this test should still pass -- `probeDriftGuard()` returns `github_app_401` on both attempts, and the handler reports the second result. Verify the existing test continues to pass unchanged.

#### Impact on existing test (line 285)

The existing test mocks `octokitRequestSpy` to always throw 401 on `GET /app`. With the retry logic, the handler will:
1. First probe: `probeDriftGuard()` catches 401, returns `github_app_401`
2. Handler detects `github_app_401`, logs warning, sleeps 1s, retries
3. Second probe: `probeDriftGuard()` catches 401 again, returns `github_app_401`
4. Handler returns `github_app_401` / `ci/auth-broken`

The test assertion `expect(out.failureMode).toBe("github_app_401")` still passes. The 1s sleep adds latency to this test but is acceptable for correctness.

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
| Existing 401 test slowed by 1s | The persistent-401 test now triggers the retry path (1s sleep). Acceptable for test correctness |

### Precedent-Diff

Two sibling retry-on-401 patterns exist in the codebase:

| Location | Mechanism | Delay |
|----------|-----------|-------|
| `probe-octokit.ts:70-78` (`createProbeOctokit`) | try/catch on `attempt()`, check `.status === 401`, retry | 1s |
| `github-app.ts:489-496` (`generateInstallationToken`) | Check `response.status === 401`, retry `mintAndExchange()` | 1s |

Both create a FRESH auth context on retry (new `App` instance or new `createAppJwt()` call). The proposed fix mirrors this: fresh `createAppJwtOctokit()` on retry, same 1s delay. No novel pattern.

**Structural difference:** The two sibling patterns catch/check at the point of the API call. This fix checks the RETURNED `failureMode` from `probeDriftGuard()` because the 401 is caught internally and surfaced as a classified result, not an exception. This is architecturally consistent -- the retry logic lives at the level that understands the result semantics.

## References

- PR #4498: `fix(auth): harden GitHub App JWT auth with retry-on-401 across both token paths` (merged 2026-05-26, verified via `gh pr view 4498 --json state,mergedAt`)
- `apps/web-platform/server/github/probe-octokit.ts:57-79`: existing `createProbeOctokit()` retry pattern
- `apps/web-platform/server/github-app.ts:489-496`: existing `generateInstallationToken()` retry pattern
- `apps/web-platform/node_modules/@octokit/app/dist-src/index.js:52`: `App` constructor synchronous (lazy auth via `createAppAuth` strategy)
- Sentry error: `HttpError: A JSON web token could not be decoded` at `2026-05-27T00:00:01Z`
- `createAppJwtOctokit()` caller audit: exactly 1 production site at `cron-github-app-drift-guard.ts:715` (verified via `grep -rn "createAppJwtOctokit" apps/web-platform/ --include="*.ts"`)
