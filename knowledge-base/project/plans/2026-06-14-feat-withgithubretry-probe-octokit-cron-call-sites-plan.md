---
title: Apply withGithubRetry to remaining probe-octokit cron call sites
type: feat
issue: 5230
branch: feat-one-shot-github-retry-probe-octokit-5230
lane: single-domain
date: 2026-06-14
brand_survival_threshold: none
---

# feat: Apply `withGithubRetry` to remaining probe-octokit cron call sites (drift-guard, oauth-probe, installation discovery)

♻️ **Tech-debt wiring sweep** — closes #5230 (`type/chore`, `priority/p3-low`, `deferred-scope-out`).

## Enhancement Summary

**Deepened on:** 2026-06-14
**Sections enhanced:** Premise Validation, Research Reconciliation, Acceptance Criteria, Sharp Edges, User-Brand Impact
**Deepen passes run:** halt-gates 4.6/4.7/4.8/4.9, precedent-diff gate 4.4, verify-the-negative pass 4.45.1, octokit-version contract check.

### Key Improvements (from deepen pass)
1. **Sensitive-path scope-out bullet added** — Files-to-Edit under `apps/web-platform/server/**` match the preflight Check-6 sensitive-path regex; the `threshold: none` declaration now carries the mandatory `threshold: none, reason: …` scope-out (without it, deepen-plan Phase 4.6 AND ship-time preflight Check 6 would both FAIL).
2. **Verify-the-negative confirmed all 3 load-bearing claims** against installed code (not memory): (a) AC6 — `httpError` test helper sets no `.cause`, so `isRetryableGithubError` returns `false` on plain 404/403, preserving no-retry; (b) Phase 3 orthogonality — `probeDriftGuard` *returns* `makeFailure("github_app_401")` rather than throwing, so `withGithubRetry` (thrown-error-only) never double-retries the handler-level 401 retry; (c) octokit 7.1.0 sets native `Error.cause`, matching the AC7 fixture shape.
3. **Precedent-diff gate (4.4) confirmed the individual-wrapper pattern** — `cron-stale-deferred-scope-outs.ts:241-260` wraps non-idempotent POST and sibling PATCH in SEPARATE `withGithubRetry` calls; the plan's AC4 + Sharp Edges already enforce this exactly.
4. **"Files to Create: None" validated** — `cron-stale-deferred-scope-outs.test.ts:288` documents that `withGithubRetry` passes a successful/non-retryable thunk straight through, so the two cron unit suites (mocking at the octokit boundary) stay green unmodified.

### New Considerations Discovered
- The single subtlety on exhaustion: when `GET /app` connect-timeouts and `withGithubRetry` exhausts, it rethrows → `probeDriftGuard` catch → no `.status` on a network error → `github_api_network` (unchanged terminal behavior, already in Test Scenarios).

## Overview

The prior fix for Sentry issue `448a4173f90a436382c4396371927796` (`cron-stale-deferred-scope-outs` connect-timeout resilience, #5227) introduced two shared primitives in `apps/web-platform/server/github-retry.ts`:

- `isRetryableGithubError(err)` — a cause-chain-aware transient classifier that walks `octokit.request()`'s wrapped `RequestError → TypeError("fetch failed") → { code: UND_ERR_CONNECT_TIMEOUT }` chain (bounded depth 5) and returns true ONLY when a real undici/timeout code or `"fetch failed"` TypeError is present anywhere in the chain. Deliberately does NOT retry on `status >= 500` (genuine GitHub 5xx must surface).
- `withGithubRetry(fn)` — runs `fn`, retrying ONLY on `isRetryableGithubError` with exponential backoff (1 s, 2 s; 3 total attempts via the canonical `MAX_RETRIES=2` / `BASE_DELAY_MS=1_000` budget). Non-retryable errors and the final attempt's error rethrow immediately. Logger-free by design.

That PR wired only `cron-stale-deferred-scope-outs.ts` (the sole cron the originating Sentry issue named). This sweep extends the same in-step transient-retry to the three remaining probe-octokit consumers, exactly as enumerated in #5230:

1. `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — wrap its 5 `octokit.request()` calls.
2. `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` — wrap its 9 `octokit.request()` calls.
3. `apps/web-platform/server/github/probe-octokit.ts` — widen `createProbeOctokit()`'s installation-discovery retry from **401-status-only** to **401-OR-`isRetryableGithubError`**, so a transient connect-timeout on the App-JWT discovery call retries instead of escalating.

This is purely a wiring sweep — the shared helper already exists and is tested (`apps/web-platform/test/github-api-retry.test.ts`). No new dependencies, no infra, no schema, no UI.

## Premise Validation

All three premises in #5230 hold, with one path correction:

- **Cited helper `server/github-retry.ts`** — exists; `withGithubRetry` + `isRetryableGithubError` confirmed at `apps/web-platform/server/github-retry.ts:77,98`. ✔
- **`createProbeOctokit()` retry is 401-only** — confirmed at `probe-octokit.ts:146-164`: the loop retries only when `status === 401`, captures-and-rethrows on any non-401. ✔ (This is the widening target.)
- **Path correction** — the issue/arguments name the cron files as `server/cron-*.ts`; their actual paths are `server/inngest/functions/cron-*.ts` (they were migrated to Inngest under TR9 PR-3/PR-4). The symbol `createProbeOctokit` lives in `server/github/probe-octokit.ts`, not `github-retry.ts`. Recorded in §Research Reconciliation. No premise is stale — files exist, just relocated.
- **No external premises beyond the above** (no blocking issues/PRs cited).

## Research Reconciliation — Spec vs. Codebase

| Issue/argument claim | Codebase reality | Plan response |
| --- | --- | --- |
| File `server/cron-github-app-drift-guard.ts` | Lives at `server/inngest/functions/cron-github-app-drift-guard.ts` | Use the real path throughout. |
| File `server/cron-oauth-probe.ts` | Lives at `server/inngest/functions/cron-oauth-probe.ts` | Use the real path throughout. |
| Shared helper in `server/github-retry.ts` | Correct; `createProbeOctokit` is in `server/github/probe-octokit.ts` | Import `withGithubRetry`/`isRetryableGithubError` from `@/server/github-retry`. |
| "route octokit.request() calls through withGithubRetry" | Drift-guard has **9** call sites; oauth-probe has **5**; some are non-idempotent POSTs | Wrap each call **individually**, NOT in one wrapper per block — see Sharp Edges (non-idempotent re-POST hazard, precedent `cron-stale-deferred-scope-outs.ts:236-260`). |
| "widen createProbeOctokit retry to all transient causes" | Current retry is `status === 401` only; existing tests assert **no retry on 404 / 403** | Widen to `status === 401 || isRetryableGithubError(err)` — preserves the 404/403 no-retry invariant (plain HttpErrors carry no transient cause chain) while adding connect-timeout coverage. |

## User-Brand Impact

**If this lands broken, the user experiences:** a synthetic-probe / drift-guard cron that either (a) over-retries a genuine auth/permission failure (delaying the `[ci/auth-broken]` tracking issue the operator relies on) or (b) double-files a tracking issue / double-comments because a non-idempotent POST was re-issued on a sibling-call retry. Both are operator-facing noise on the `jikig-ai/soleur` ops repo, not an end-user data path.

**If this leaks, the user's data is exposed via:** N/A — these crons emit only synthetic-probe diagnostics (HTTP status, GitHub request-id, clock skew) already redacted/strip-log-injected at the existing emission sites. This change touches retry control flow only; it adds no new emission, no new secret materialization, no new external call.

**Brand-survival threshold:** `none` — internal ops tooling resilience improvement. §Domain Review confirms infrastructure/tooling-only.

- `threshold: none, reason:` the edited files sit under `apps/web-platform/server/**` (matching the preflight Check-6 sensitive-path regex) but the change is retry control-flow only — no schema, migration, auth flow, API route, secret, or `.sql` surface is added or altered, and no new data-emission path is introduced.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — drift-guard wiring.** Every `octokit.request(...)` call in `cron-github-app-drift-guard.ts` is wrapped in `withGithubRetry(() => octokit.request(...))`, wrapped **individually** (one wrapper per call, never one wrapper around a multi-request sequence). Verify: `git grep -c 'withGithubRetry(() =>' apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` returns `9`, and `git grep -c 'octokit.request' apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` returns `9` (every call site wrapped). The two counts must be equal.
- [x] **AC2 — oauth-probe wiring.** Every `octokit.request(...)` call in `cron-oauth-probe.ts` is wrapped individually. Verify: `git grep -c 'withGithubRetry(() =>' apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` returns `5` and matches the `octokit.request` count (`5`).
- [x] **AC3 — import added to both crons.** Both cron files import `withGithubRetry` from `@/server/github-retry`. Verify: `git grep -l 'import { withGithubRetry } from "@/server/github-retry"' apps/web-platform/server/inngest/functions/cron-oauth-probe.ts apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` lists both files.
- [x] **AC4 — non-idempotent POSTs are NOT grouped under one retry wrapper.** In each cron, no single `withGithubRetry(...)` lexically contains more than one `octokit.request(`. Manual + grep verify: there is no `withGithubRetry` callback body spanning two `octokit.request(` calls (each POST comment, POST issue, and PATCH is its own wrapper).
- [x] **AC5 — `createProbeOctokit` retry widened.** `probe-octokit.ts`'s discovery retry condition is `status === 401 || isRetryableGithubError(err)` (not 401-only). Verify: `git grep -n 'isRetryableGithubError' apps/web-platform/server/github/probe-octokit.ts` returns ≥1 hit AND `probe-octokit.ts` imports `isRetryableGithubError` from `@/server/github-retry`.
- [x] **AC6 — existing 404/403 no-retry invariant preserved.** The two existing tests `does NOT retry on 404` and `does NOT retry on 403` in `probe-octokit-retry.test.ts` still pass unchanged (a plain HttpError with no `.cause` chain returns `false` from `isRetryableGithubError`, so the widened condition does not retry them).
- [x] **AC7 — new test: `createProbeOctokit` retries on transient connect-timeout cause.** Add a test that rejects the discovery `mockRequest` with an octokit-shaped `RequestError` whose `.cause` chain carries `{ code: "UND_ERR_CONNECT_TIMEOUT" }` (status 500), then resolves on the next attempt; assert `MockApp`/`mockRequest` called twice and the call succeeds. Confirms the widening retries a connect-timeout the old 401-only path would have captured-and-rethrown immediately.
- [x] **AC8 — typecheck green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [x] **AC9 — targeted suites green.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts test/server/inngest/cron-oauth-probe.test.ts test/server/inngest/cron-github-app-drift-guard.test.ts test/github-api-retry.test.ts` exits 0.

### Post-merge (operator)

- [ ] None. This is a code-only change deployed by the existing `web-platform-release.yml` container restart on merge to `main` touching `apps/web-platform/**`. No migration, secret, or vendor-dashboard step. **Automation: the PR merge IS the deploy.**

## Implementation Phases

### Phase 0 — Preconditions (read-only)

- Confirm `withGithubRetry` + `isRetryableGithubError` signatures at `apps/web-platform/server/github-retry.ts:77,98` (done — see Overview).
- Confirm the canonical individual-wrapper precedent at `cron-stale-deferred-scope-outs.ts:236-260` (done — comment explicitly documents "Two SEPARATE withGithubRetry wrappers (NOT one around both)" to avoid re-POSTing on close-timeout retry).
- Re-read `probe-octokit-retry.test.ts:267-282` to confirm the 404/403 no-retry tests use plain `httpError(...)` (no `.cause`), so the widened condition leaves them green (done).

### Phase 1 — Widen `createProbeOctokit` discovery retry (`probe-octokit.ts`)

`cq-write-failing-tests-before`: write AC7's failing test first, then implement.

1. Add `isRetryableGithubError` to the existing import from `@/server/github-retry` (the file does not yet import from it — add a new import line: `import { isRetryableGithubError } from "@/server/github-retry";`).
2. In the retry loop (`probe-octokit.ts:146-164`), change the non-retry guard. Current:
   ```ts
   const status = (err as { status?: number }).status;
   // Non-401: not the transient JWT-replication class — capture + rethrow now.
   if (status !== 401) captureAndRethrow(err, i + 1);
   ```
   New:
   ```ts
   const status = (err as { status?: number }).status;
   // Retry the transient JWT-replication 401 class AND any transient network
   // cause octokit buried in the error chain (connect timeout / ECONNRESET).
   // Anything else (404/403/non-transient 5xx) captures + rethrows now.
   if (status !== 401 && !isRetryableGithubError(err)) captureAndRethrow(err, i + 1);
   ```
3. Update the `log.warn` message + header comment (`probe-octokit.ts:34-40`) so they no longer say "401-only" — note both the JWT-replication-401 class AND the transient-network-cause class are now retried. Keep `PROBE_JWT_MAX_RETRIES` / `PROBE_JWT_BASE_DELAY_MS` as the local budget (do NOT swap to `withGithubRetry` here — `createProbeOctokit` must mint a fresh `App`/JWT per attempt, which `withGithubRetry`'s single-thunk shape cannot express; the local loop is load-bearing).
4. Add AC7's transient-cause test to `probe-octokit-retry.test.ts` (a `httpErrorWithCause` helper that sets `.cause = { code: "UND_ERR_CONNECT_TIMEOUT" }`).

**Sharp edge:** do NOT replace the whole loop with `withGithubRetry`. The loop re-constructs `App` (fresh JWT) on every attempt — that fresh-JWT-per-retry behavior is the entire point of the 401 retry (JWT-replication lag). `withGithubRetry(fn)` calls the same `fn` thunk each attempt; a thunk that closes over one `App` instance would replay a stale JWT. The minimal correct change is the guard-condition widening only.

### Phase 2 — Wrap `cron-oauth-probe.ts` octokit calls (5 sites)

1. Add `import { withGithubRetry } from "@/server/github-retry";`.
2. Wrap each `octokit.request(...)` individually:
   - L490 `GET /search/issues` (dedup search) — idempotent read.
   - L499 `POST .../comments` (comment on existing failure issue) — **non-idempotent**, own wrapper.
   - L510 `POST .../issues` (file new failure issue) — **non-idempotent**, own wrapper.
   - L528 `POST .../comments` (green recovery comment) — **non-idempotent**, own wrapper.
   - L537 `PATCH .../issues/{n}` (close on recovery) — idempotent.
3. Each wrap is `await withGithubRetry(() => octokit.request(...))`. The surrounding `handleTrackingIssue` already runs inside the handler's `step.run("issue-handling")` catch, which owns the `issue_write_403` discriminator — `withGithubRetry` rethrows a non-retryable 403 on attempt 1, so the discriminator is preserved.

### Phase 3 — Wrap `cron-github-app-drift-guard.ts` octokit calls (9 sites)

1. Add `import { withGithubRetry } from "@/server/github-retry";`.
2. Wrap each `octokit.request(...)` individually:
   - **In `probeDriftGuard`:** L334 `GET /app`, L442 `GET /app/installations` — both idempotent reads. Wrap each.
   - **In `handleFailureIssue`:** L572 `GET /search/issues` (read), L580 `POST .../comments` (**non-idempotent**), L591 `POST .../issues` (**non-idempotent**), L603 `GET /search/issues` (read), L609 `POST .../comments` (**non-idempotent**), L618 `PATCH .../issues/{n}` (idempotent).
   - **In `handleLeakIssue`:** L635 `POST .../issues` (**non-idempotent**).
3. **Interaction with the existing handler-level `github_app_401` retry** (`cron-github-app-drift-guard.ts:714-732`): the handler ALREADY retries `probeDriftGuard` once on a `github_app_401` failure-mode (a 1 s sleep + fresh `createAppJwtOctokit`). That retry is **status-driven** (it inspects the returned `DriftResult.failureMode`, not a thrown error). `withGithubRetry` around `GET /app` only fires on a *thrown transient network error* — a real 401 is caught inside `probeDriftGuard` (L337-358) and returned as a `DriftResult`, never thrown. So the two retry layers are orthogonal: `withGithubRetry` absorbs connect-timeouts that previously threw out of `probeDriftGuard` (landing in the handler's `catch` → `github_api_network`); the handler-level retry still handles the auth-401-disambiguation case. No double-retry of the same failure class. Document this in a code comment at the `GET /app` wrap site.

### Phase 4 — Verify

1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC8).
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts test/server/inngest/cron-oauth-probe.test.ts test/server/inngest/cron-github-app-drift-guard.test.ts test/github-api-retry.test.ts` (AC9, AC6, AC7).
3. Run the AC1–AC5 greps and confirm counts.

### Research Insights (deepen pass)

**Precedent-diff (gate 4.4) — canonical individual-wrapper pattern:**

```ts
// cron-stale-deferred-scope-outs.ts:241-260 — the load-bearing precedent.
// POST (non-idempotent) and PATCH (idempotent) get SEPARATE wrappers so a
// PATCH-timeout retry never re-POSTs the comment:
await withGithubRetry(() =>
  octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", { ... }),
);
await withGithubRetry(() =>
  octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", { ... }),
);
```

This is the exact shape Phases 2 and 3 replicate. No precedent gap — the pattern is established and tested.

**octokit error contract (verified against installed `@octokit/request-error@7.1.0`):** octokit wraps a `fetch failed` TypeError using the native `Error.cause` chain. `isRetryableGithubError` (`github-retry.ts:77-84`) walks `.cause` to depth 5 and returns true only when a real undici code / `"fetch failed"` TypeError is present. The AC7 fixture (`.cause = { code: "UND_ERR_CONNECT_TIMEOUT" }`) models the real chain. A plain `httpError(msg, 404)` (test helper sets only `.status`/`.name`, no `.cause`) returns `false` → AC6 no-retry preserved.

**Cron unit-suite passthrough (validated):** `cron-stale-deferred-scope-outs.test.ts:288` documents that `withGithubRetry` passes a non-retryable / successful thunk straight through. The drift-guard and oauth-probe handler tests mock `createProbeOctokit`/octokit at the boundary and assert request shapes; wrapping in `withGithubRetry` is transparent to them on the success path. Confirms "Files to Create: None."

## Files to Edit

- `apps/web-platform/server/github/probe-octokit.ts` — widen discovery retry guard to `status === 401 || isRetryableGithubError(err)`; add import; update header comment + log message (Phase 1).
- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — add import; wrap 5 octokit calls individually (Phase 2).
- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` — add import; wrap 9 octokit calls individually; add the orthogonal-retry comment at the `GET /app` site (Phase 3).
- `apps/web-platform/test/server/github/probe-octokit-retry.test.ts` — add AC7's transient-connect-timeout-cause retry test (Phase 1.4).

## Files to Create

- None. (Existing test files are extended, not created. The cron handler unit tests `cron-oauth-probe.test.ts` / `cron-github-app-drift-guard.test.ts` mock `createProbeOctokit`/octokit at the boundary and assert request shapes; `withGithubRetry` passes a successful thunk straight through, so those suites stay green without modification — verified against the same pass-through assertion in `cron-stale-deferred-scope-outs.test.ts:288`.)

## Open Code-Review Overlap

None. (No open `code-review`-labelled issue names `probe-octokit.ts`, `cron-oauth-probe.ts`, or `cron-github-app-drift-guard.ts`. #5230 itself is the `deferred-scope-out` this PR closes.)

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-ins for monitor slugs "scheduled-oauth-probe" + "scheduled-github-app-drift-guard"
  cadence: hourly (both crons run `0 * * * *`)
  alert_target: Sentry Crons missed-check-in alert (existing, unchanged)
  configured_in: apps/web-platform/infra (sentry_cron_monitor terraform resources, pre-existing)
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (existing catch blocks in both crons + createProbeOctokit's captureAndRethrow)
  fail_loud: true — a retry that ultimately exhausts still rethrows; the existing step.run catch mirrors to Sentry exactly as today
failure_modes:
  - mode: transient connect-timeout absorbed by withGithubRetry (success after retry)
    detection: no Sentry event (this is the intended improvement — the timeout no longer escalates)
    alert_route: none (suppressed-by-design); Inngest step succeeds
  - mode: transient connect-timeout exhausts 3 attempts
    detection: existing reportSilentFallback in the cron's step.run catch (op=handleTrackingIssue / handleIssue / probeOauth / probeDriftGuard)
    alert_route: Sentry error event (unchanged from today)
  - mode: createProbeOctokit discovery exhausts retry (401 or transient)
    detection: warnSilentFallback at probe-octokit.ts captureAndRethrow (op="create-probe-octokit:app-jwt", carries attempts count + GitHub diag)
    alert_route: Sentry warning event (unchanged shape; `attempts` now reflects transient-cause retries too)
logs:
  where: Inngest step logs + pino structured logs (existing log.warn in createProbeOctokit retry loop)
  retention: Inngest + Better Stack (existing, unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts test/github-api-retry.test.ts"
  expected_output: "all tests pass; AC7 transient-cause retry test green confirms the widened path fires"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal ops-tooling resilience change (retry wiring) on synthetic-probe crons. No Product/UX surface (no file under `components/**`, `app/**/page.tsx`, or any UI-surface path), no Finance/Legal/Marketing/Sales/Support/Operations implication. GDPR gate (Phase 2.7): no regulated-data surface touched (no schema, migration, auth flow, API route, `.sql`); none of triggers (a)-(d) fire (no new LLM/external-API processing, threshold is `none`, no new learnings-reading cron, no new distribution surface) — skipped. IaC gate (Phase 2.8): no new server/service/secret/cron/vendor — the crons already exist; skipped.

## Test Scenarios

| Scenario | Expectation |
| --- | --- |
| `createProbeOctokit` discovery throws RequestError with `UND_ERR_CONNECT_TIMEOUT` cause, then succeeds | Retries (fresh App/JWT), succeeds on attempt 2 (AC7 — NEW behavior) |
| `createProbeOctokit` discovery throws plain 404 HttpError (no cause) | No retry, rethrows immediately (AC6 — preserved) |
| `createProbeOctokit` discovery throws plain 403 HttpError (no cause) | No retry, rethrows immediately (AC6 — preserved) |
| `createProbeOctokit` discovery throws plain 401 ("could not be decoded") | Retries (existing JWT-replication path — preserved) |
| oauth-probe / drift-guard octokit call hits a successful response | `withGithubRetry` passes the thunk through on attempt 1; existing unit-test request-shape assertions unchanged |
| drift-guard `GET /app` hits a connect-timeout | `withGithubRetry` retries in-step; if it succeeds, no Sentry escalation (the fix); if it exhausts, rethrows into the handler `catch` → `github_api_network` (unchanged terminal behavior) |
| drift-guard close-path retry on a PATCH timeout | PATCH (idempotent) retried safely; the preceding POST comment is in its OWN wrapper, so it is NOT re-issued (AC4 — non-idempotent safety) |

## Sharp Edges

- **Non-idempotent re-POST hazard (load-bearing).** Wrapping multiple `octokit.request()` calls in ONE `withGithubRetry` would re-issue a non-idempotent POST (file issue / comment) if a *later* call in the block timed out and triggered a retry of the whole thunk. The canonical precedent (`cron-stale-deferred-scope-outs.ts:236-260`) documents this explicitly and wraps each request separately. AC4 enforces it. This is the single most important correctness constraint of this PR.
- **`createProbeOctokit` must NOT be migrated to `withGithubRetry`.** Its retry loop re-constructs `App` (fresh JWT) per attempt — `withGithubRetry`'s single-thunk shape would replay a stale JWT closed over the first `App`. Only widen the loop's non-retry guard condition. (Phase 1 sharp edge.)
- **Handler-level `github_app_401` retry is orthogonal** to `withGithubRetry`. The former is status-driven on a returned `DriftResult`; the latter fires only on a *thrown* transient network error. A real 401 is returned (not thrown) from `probeDriftGuard`, so the two layers never double-retry the same failure. (Phase 3 sharp edge.)
- **`isRetryableGithubError` is precise, not status-based.** It does NOT retry on `status >= 500` alone — it walks the `.cause` chain for a real undici/timeout code. So widening to `|| isRetryableGithubError(err)` does NOT start retrying genuine GitHub 5xx; it only adds the buried-connect-timeout class. This is what keeps AC6 (404/403 no-retry) and the "no over-retry of real server errors" property intact.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with a non-empty reason (internal ops tooling; no sensitive-path surface) — satisfied.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Migrate `createProbeOctokit`'s whole loop to `withGithubRetry` | Rejected — breaks fresh-JWT-per-attempt (see Sharp Edges). |
| One `withGithubRetry` wrapper per logical block (search+post+patch) | Rejected — re-POSTs non-idempotent calls on retry (AC4 / Sharp Edges). |
| Add a `status >= 500` retry arm while we're here | Rejected — out of scope and explicitly warned against in `github-retry.ts:71-75` (over-retries genuine GitHub 5xx). |
| Defer drift-guard, do only oauth-probe + discovery | Rejected — #5230 names all three; the helper exists; the marginal diff for the third file is small and the blast radius identical. |

**Deferred items:** none. No "Out of Scope" carve-outs requiring tracking issues.
