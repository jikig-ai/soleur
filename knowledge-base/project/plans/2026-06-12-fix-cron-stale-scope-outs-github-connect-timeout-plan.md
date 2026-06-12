---
type: bug-fix
lane: single-domain
brand_survival_threshold: none
sentry_issue: 448a4173f90a436382c4396371927796
---

# 🐛 fix: Make `cron-stale-deferred-scope-outs` GitHub calls resilient to transient connect timeouts

## Enhancement Summary

**Deepened on:** 2026-06-12
**Agents used:** architecture-strategist (correctness), framework-docs-researcher (octokit/undici runtime semantics against installed node_modules), code-simplicity-reviewer (YAGNI).

### Key improvements from the deepen pass

1. **P0 correctness gap caught & fixed.** The original plan assumed reusing `isRetryable` would classify the connect timeout. framework-docs verified against installed `@octokit/request`/`@octokit/request-error` that octokit wraps the undici error in a `RequestError` (`HttpError`, `status:500`) with the `UND_ERR_CONNECT_TIMEOUT` code buried at `.cause.cause` — so top-level `isRetryable` MISSES it and the fix would silently not work. Plan now adds `isRetryableGithubError` (a cause-chain walk) and the regression test AC4 seeds octokit's *real* thrown shape, not a bare `TypeError`.
2. **Idempotency over-claim corrected (P1).** The comment POST is non-idempotent; the plan no longer claims idempotency the code lacks, documents the pre-existing double-comment-on-replay window, and tracks it as follow-up F2 (not folded in).
3. **Simplified per YAGNI.** Dropped the `withGithubRetry` `opts` param (no caller uses it), reused the existing `MAX_RETRIES`/`BASE_DELAY_MS` constants (hoisted to the leaf, one source of truth) instead of new `DEFAULT_*` duplicates, re-anchored the helper's justification on existing inline-loop de-duplication, and collapsed redundant test ceremony (single helper-test home + cron integration tests).

### Research Insights

- **octokit error shape (verified, installed):** connect timeout → `RequestError{ name:"HttpError", status:500, message:"fetch failed", cause: TypeError{ message:"fetch failed", cause:{ code:"UND_ERR_CONNECT_TIMEOUT" } } }`. Source: `node_modules/@octokit/request/dist-src/fetch-wrapper.js` (catch block wraps + sets `requestError.cause = error`, hardcodes status 500), `node_modules/@octokit/request-error/dist-src/index.js` (does NOT copy `.code` to top level). Versions: `@octokit/core@7.0.6`, `@octokit/app@16.1.2`, `@octokit/request-error@7.0.2`.
- **No default retry plugin (verified):** `@octokit/core` and `@octokit/app` `getInstallationOctokit()` wire NO `@octokit/plugin-retry` — confirmed in `node_modules/@octokit/core/dist-src/index.js` and `@octokit/app/dist-src/get-installation-octokit.js`. The codebase's `github-retry.ts` is the only transient defense, and it was not on the octokit path.
- **Budget precedent (Phase 4.4 precedent-diff):** `MAX_RETRIES=2 / BASE_DELAY_MS=1_000` is canonical across `github-api.ts:23-24` (`fetchWithRetry`) and `probe-octokit.ts:41-42` (`createProbeOctokit` 401 path). No novel pattern; `withGithubRetry` reuses it.
- **Scheduled-work check (Phase 4.4):** not a new cron — modifying an existing Inngest function (42 `cron-*` functions present); Inngest precedent (ADR-033) already satisfied. No GH-Actions-cron consideration.
- **Network-outage checklist (Phase 4.5):** NOT triggered as an infra/SSH outage — this is an L7 application-layer transient connect timeout fixed with code-level retry, not an SSH/firewall/DNS diagnosis. The L3→L7 firewall checklist (`hr-ssh-diagnosis-verify-firewall`) does not apply (no server, no SSH, no egress-IP allowlist in scope).

## Overview

Production Sentry issue `448a4173f90a436382c4396371927796` (web-platform, prod, release `web-platform@0.122.9`, `handled: yes`, feature tag `pino-mirror`, runtime node v22.22.1) fired:

```
Connect Timeout Error (attempted address: api.github.com:443, timeout: 10000ms)
TypeError: fetch failed
```

thrown from `POST /api/inngest` inside the Inngest cron function `cron-stale-deferred-scope-outs` (`fnId=soleur-runtime-cron-stale-deferred-scope-outs`, `stepId=step`), at 2026-06-12 14:01:36 CEST, `inngest.run_id=01KTXV83HTYR8K8SG77T0JKCJC`.

### Root cause

The cron's sweep makes outbound `octokit.request(...)` calls to `api.github.com` (issue search, comment, close) plus an installation-discovery call inside `createProbeOctokit()`. **None of these octokit calls go through a transient-retry wrapper** — the `@octokit/core` / `@octokit/app` clients minted by `createProbeOctokit()` carry no retry plugin, and the canonical `fetchWithRetry` in `server/github-api.ts` is only used by the MCP-tool raw-`fetch` path, not by octokit. So undici's default 10 s connect timeout (`UND_ERR_CONNECT_TIMEOUT`, surfaced by Node's `fetch` as `TypeError: fetch failed`) on a single transient api.github.com blip propagates straight up.

The escalation path that produced the Sentry event:

- If the timeout lands inside `createProbeOctokit()` (the `GET /repos/{owner}/{repo}/installation` discovery call), it is NOT a 401, so `createProbeOctokit`'s 401-only retry loop does not retry — it `captureAndRethrow`s (warn-level) and rethrows. The rethrow exits `step.run("sweep-…")` → caught by the handler's outer `try/catch` → `reportSilentFallback(...)` at `error` level (the `handled: yes` Sentry event) → heartbeat status=error → `throw` → Inngest retry.
- If the timeout lands inside `fetchCandidates` / the per-issue comment-or-close `octokit.request(...)` calls, the search/discovery path has no per-call retry; `fetchCandidates` is outside the per-issue try/catch so a timeout there aborts the whole sweep the same way. (The per-issue comment/close try/catch already swallows-and-continues, so a timeout on those advances past one issue — but it still emits one `error`-level mirror per failed issue.)

`step.run` memoizes the step's **return value** across Inngest replays, but a throw is not memoized — the whole step re-executes on retry. Inngest `retries: 1` (2 total attempts) means a transient blip often succeeds on attempt 2, yet attempt 1 has already emitted an `error`-level Sentry event. **A single transient connect timeout escalates to an operator-paging error even though the system self-heals.**

### The fix (minimal, precedent-aligned)

Wrap the octokit calls in an in-step transient-retry loop using a **cause-chain-aware** transient classifier built on the existing `isRetryable` from `apps/web-platform/server/github-retry.ts`. Add a tiny shared `withGithubRetry(fn)` helper to `github-retry.ts` (reusing the canonical `MAX_RETRIES=2` / `BASE_DELAY_MS=1_000` budget — 1 s, 2 s — shared with `fetchWithRetry` and `createProbeOctokit`'s 401 path) and route the sweep's octokit calls through it. A transient connect timeout is then absorbed (retried in-step, exponential backoff) and never reaches the handler's error-level mirror.

> **⚠️ P0 correctness gap caught at deepen-plan (do NOT skip).** `octokit.request(...)` does **not** rethrow the raw undici `TypeError: fetch failed` on a connect timeout. Verified against installed `@octokit/request@dist-src/fetch-wrapper.js` + `@octokit/request-error@dist-src/index.js`: octokit **wraps** it in a `RequestError` (`.name === "HttpError"`, **`.status === 500` hardcoded**), copies the cause's message so `.message === "fetch failed"`, and stores the original error at `.cause` (whose own `.cause` carries `code: "UND_ERR_CONNECT_TIMEOUT"`). `RequestError` does NOT copy `.code` to the top level. So the existing `isRetryable(err)` — which keys on `err instanceof TypeError && err.message === "fetch failed"` OR a top-level `err.code` — **MISSES this error entirely**: the thrown object is a `RequestError`, not a `TypeError`, with no top-level `.code` and a non-retryable-looking `.status` of 500. **A naive reuse of `isRetryable` would silently not retry the exact Sentry error.** The fix MUST classify via a cause-chain walk (see Phase 1 `isRetryableGithubError`). This is the single most important change in this plan.

This is strictly a resilience addition. It does NOT change the sweep's semantics, counters, dry-run behavior, replay-safety guards (I7), or the Inngest `retries: 1` outer policy (which remains as a last-resort net for a sustained outage that exhausts the in-step budget).

> **Idempotency caveat (P1, from architecture review).** The per-issue **comment POST is non-idempotent** — every POST creates a new comment. The file header's I5 "already closed" tolerance covers the close PATCH, NOT the comment. This fix strictly *reduces* the throw frequency that triggers an Inngest-level replay (so it reduces double-comment risk), but does not eliminate a pre-existing double-comment window: if the comment succeeds and a later **un-caught** throw escapes the whole `step.run` (e.g. the `fetchCandidates` search exhausts its retry budget — that call is OUTSIDE the per-issue try), Inngest `retries: 1` re-runs the sweep, the still-`is:open` issue re-surfaces (not short-circuited by the `state === "closed"` guard), and gets commented a second time. This plan does NOT claim to close that window (it is pre-existing); it is tracked as a follow-up (see Follow-ups). Per-call wrapping (vs whole-sweep wrapping) is the correct granularity precisely because whole-sweep retry would re-comment EVERY already-commented issue on each attempt.

### Why not just downgrade the Sentry level?

The related learning (`2026-06-08-handled-error-sentry-event-from-fail-closed-mirror-is-severity-not-crash.md`) shows that a `handled: yes` error event from a recovered fail-closed path is sometimes a pure severity-calibration bug. Here the user explicitly asked for **resilience** (retry-in-step), which is strictly better: it removes the failure entirely for the transient case rather than re-labelling it. A severity split is a fallback consideration (see Phase 2 / Alternatives), not the primary fix.

## Premise Validation

- **Cited Sentry issue `448a4173…`**: described as a connect-timeout from `cron-stale-deferred-scope-outs`. Confirmed by reading the function source — it makes exactly the api.github.com calls described, none wrapped in transient retry. Premise holds.
- **Function source path**: `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` exists on this branch and matches the description. Confirmed.
- **"already inside a retryable step?"**: The GitHub calls ARE inside `step.run("sweep-…")`, but `step.run` only memoizes a successful return — it does not retry a throw beyond the function-level `retries: 1`. There is no per-call transient retry. So the GitHub call is in a *step* but not *retry-protected against transient connect timeouts*. Premise (that a resilience fix is needed) holds.
- **Sibling cron precedent**: `cron-github-app-drift-guard.ts` and `cron-oauth-probe.ts` use the same `createProbeOctokit()` and have the same gap (no per-call octokit transient retry) — they are out of scope for this fix (the Sentry issue named only the stale-scope-outs cron) but the shared helper added here is reusable by them later (noted as a follow-up, not folded in — see Open Code-Review Overlap).
- **Capability claim self-check**: `isRetryable` in `github-retry.ts` verified by Read to classify `UND_ERR_CONNECT_TIMEOUT` and `TypeError: fetch failed` — the exact reported error class. No assumption.
- No external GitHub issues/PRs cited by reference in the task. No ADR mechanism to reconcile (retry/backoff is an idiom, not an architectural decision).

## Research Reconciliation — Spec vs. Codebase

| Spec/Task claim | Codebase reality | Plan response |
| --- | --- | --- |
| "wrap the fetch in an Inngest step so it gets step-level retries" | The call is already inside `step.run`; Inngest step retries are governed by function-level `retries: 1`, and a throw re-runs the whole step (not the single call). Step-level retry alone still emits one error-level mirror per failed attempt before Inngest retries. | Add **in-step** transient retry around the octokit calls so the transient is absorbed before it can throw out of the step. Keep `retries: 1` as the outer net. |
| "add explicit retry/backoff + a sane timeout" | Codebase has a classifier (`github-retry.ts isRetryable`) + backoff idiom (`fetchWithRetry`, `createProbeOctokit`). BUT `isRetryable` keys on the TOP-LEVEL error; octokit buries the undici code under a `RequestError.cause.cause` chain, so `isRetryable` alone MISSES the connect timeout (P0, deepen-plan). undici's 10 s connect timeout is already a "sane" per-attempt timeout; the gap is retry classification, not timeout length. | Add `isRetryableGithubError` (cause-chain walk over `isRetryable`) + `withGithubRetry` wrapper (1 s/2 s, 3 attempts). Do NOT lengthen the per-attempt connect timeout (retrying a fresh connection beats waiting on a dead one). |
| "consistent with how other crons call GitHub" | Other crons use `createProbeOctokit()` with no per-call retry — there is no existing per-call octokit-retry precedent to copy; the precedent is the raw-`fetch` `fetchWithRetry`. | Establish the helper in the shared leaf `github-retry.ts` (where `isRetryable` already lives) so it is the new shared precedent. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is an operator-only platform cron that auto-closes stale `deferred-scope-out` GitHub issues in `jikig-ai/soleur`. A regression would at worst leave the stale-scope-out backlog un-drained for a day (next cron fire recovers) or, if the retry wrapper were misimplemented, re-introduce the same Sentry noise.

**If this leaks, the user's data is exposed via:** N/A — the cron touches only operator-owned GitHub issue metadata (issue numbers, titles, labels). No founder/user data, no Supabase, no PII, no secrets are read or written by the changed code path. `createProbeOctokit` is explicitly the synthetic-probe, non-audit-writer client (see its file header).

**Brand-survival threshold:** none — operator-internal automation, no user-facing surface, no regulated-data surface.

- `threshold: none, reason: the changed files under apps/web-platform/server/** match the preflight Check-6 sensitive-path regex by directory, but the code touches only GitHub-issue metadata on the operator's own repo via the synthetic-probe (non-audit-writer) Octokit — no founder/user data, no auth flow, no schema/migration/secret — and a worst-case bug only delays a janitorial backlog sweep by one daily cron cycle.`

Note: two edited paths (`apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`, `apps/web-platform/server/github-retry.ts`) DO match the canonical sensitive-path regex `^apps/web-platform/(server|…)` by prefix, so the `threshold: none` declaration above carries the mandatory scope-out reason (deepen-plan Phase 4.6 Step 2 / preflight Check 6). The match is purely path-prefix; the actual data surface is operator-internal GitHub-issue metadata.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Shared classifier + retry helper exist.** `apps/web-platform/server/github-retry.ts` exports BOTH `isRetryableGithubError(err)` (cause-chain walk, bounded depth 5) AND `withGithubRetry<T>(fn: () => Promise<T>): Promise<T>` (no `opts` param) that retries up to 2 times (3 total attempts, 1 s/2 s) **only** when `isRetryableGithubError(err)` is true, rethrowing otherwise. The budget constants `MAX_RETRIES`/`BASE_DELAY_MS` are defined in this leaf (hoisted from `github-api.ts`) and imported by `fetchWithRetry` — no `DEFAULT_*` duplicates. Verify: `git grep -n "export function withGithubRetry\|export function isRetryableGithubError" apps/web-platform/server/github-retry.ts` returns 2 hits; `git grep -nc "MAX_RETRIES = 2" apps/web-platform/server/github-retry.ts apps/web-platform/server/github-api.ts` shows the literal defined once (in the leaf).
- [x] **AC2 — Sweep search is wrapped.** In `cron-stale-deferred-scope-outs.ts`, the `octokit.request("GET /search/issues", …)` call inside `fetchCandidates` is routed through `withGithubRetry`. Verify by reading: the call is inside `withGithubRetry(() => octokit.request("GET /search/issues", …))`.
- [x] **AC3 — Per-issue comment + close are wrapped (separately).** The `POST …/comments` and `PATCH …/issues/{issue_number}` calls in `sweepStaleScopeOuts` are each routed through `withGithubRetry` as **two separate** wrapped calls (NOT one wrapper around both — that would re-POST the comment on a close-timeout retry). The existing per-issue try/catch (swallow-and-continue + `reportSilentFallback`) is preserved as the terminal net AFTER the retry budget is exhausted.
- [x] **AC4 — Transient connect timeout no longer escalates (regression test for the Sentry issue).** A new test seeds `octokitRequestSpy` to throw, on the FIRST `GET /search/issues` attempt, **the error shape octokit actually throws** — a `RequestError`-like object: `Object.assign(new Error("fetch failed"), { name: "HttpError", status: 500, cause: Object.assign(new TypeError("fetch failed"), { cause: { code: "UND_ERR_CONNECT_TIMEOUT" } }) })` — and resolve on the SECOND. Assert: (a) the sweep completes successfully, (b) `reportSilentFallbackSpy` is NOT called for the transient, (c) the candidate list reflects the second response. **Do NOT seed a bare `TypeError` — that does not match production and would let the test pass while `isRetryableGithubError` still misses the real wrapper.** (The `isRetryableGithubError` cause-chain classification itself is unit-tested directly in `github-api-retry.test.ts` per AC8 — this AC4 is the cron-integration regression.)
- [x] **AC5 — Non-retryable errors still surface.** A test seeds a non-retryable error (`Object.assign(new Error("Forbidden"), { name: "HttpError", status: 403 })`) on the comment path and asserts `withGithubRetry` does NOT retry (spy called once for that request) and the existing `reportSilentFallback` mirror with `op: "issue_write_403"` still fires — resilience does not mask the genuine `issues:write`-missing 403 discriminator (#4189). (A 403 has no transient cause in its chain → `isRetryableGithubError` returns false → rethrown on attempt 1.)
- [x] **AC6 — Sustained outage still reaches the handler net** (fold into the cron test, not a separate scenario). Seed a retryable error (RequestError-wrapped, as AC4) on ALL attempts of the first `GET /search/issues`; assert the handler's outer catch fires `reportSilentFallback` with `op: "sweep"`, heartbeat `ok: false`, and the handler rethrows (Inngest retry preserved). The "exhaust 3 then rethrow" mechanics are a `withGithubRetry` property covered directly in the helper unit tests (AC8); this AC only confirms the cron wiring.
- [x] **AC7 — No duplicated undici-code list.** The cron does not hand-roll a transient classifier; it imports `withGithubRetry`. Verify: `git grep -n "UND_ERR_CONNECT_TIMEOUT" apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` returns 0 hits.
- [x] **AC8 — Helper unit tests + typecheck + suite green.** New direct unit tests in `apps/web-platform/test/github-api-retry.test.ts` cover `isRetryableGithubError` (RequestError-wrapped UND_ERR_CONNECT_TIMEOUT at depth 2 → true; bare 403 RequestError → false; cycle-safe) and `withGithubRetry` (retryable-then-success, non-retryable-immediate-rethrow, exhaust-3-then-rethrow) using `vi.useFakeTimers()`. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts test/github-api-retry.test.ts` passes.

### Post-merge (operator)

- None. `apps/web-platform/**` change deploys via the existing `web-platform-release.yml` path-filtered pipeline on merge to main (container restart + Inngest function re-sync are handled by the pipeline). No migration, no Terraform, no Doppler secret. The fix is verified live by the next daily cron fire (`0 12 * * *`) producing a clean Sentry heartbeat and no recurrence of issue `448a4173…`.

## Implementation Phases

### Phase 1 — Add the cause-chain classifier + `withGithubRetry` to the shared leaf (`github-retry.ts`)

Two additions next to `isRetryable` / `delay`. **First**, a cause-chain-aware classifier (this is the P0 fix — see the warning in Overview). octokit wraps the undici error in a `RequestError`, so `isRetryable` must be applied to each link of the `.cause` chain, not just the top-level error:

```ts
// apps/web-platform/server/github-retry.ts (appended)

/**
 * Cause-chain-aware transient classifier. octokit.request() wraps a connect
 * timeout in a RequestError (name "HttpError", status 500) whose `.cause` is
 * the raw `TypeError: fetch failed`, whose own `.cause` carries
 * `{ code: "UND_ERR_CONNECT_TIMEOUT" }`. Top-level `isRetryable` MISSES that
 * wrapper (not a TypeError, no top-level `.code`). Walk the cause chain so the
 * undici code / "fetch failed" is found wherever octokit buried it.
 * Bounded depth (5) guards against a self-referential cause cycle.
 */
export function isRetryableGithubError(err: unknown): boolean {
  let cur: unknown = err;
  for (let depth = 0; depth < 5 && cur != null; depth++) {
    if (isRetryable(cur)) return true;
    cur = (cur as { cause?: unknown }).cause;
  }
  return false;
}

/**
 * Run `fn`, retrying ONLY on transient network errors (isRetryableGithubError)
 * with exponential backoff (reuses the canonical MAX_RETRIES / BASE_DELAY_MS
 * budget below). Non-retryable errors (4xx auth, shape, a genuine GitHub 5xx
 * with no transient cause) and the final attempt's error rethrow immediately.
 * Wrap octokit.request() calls in crons so a single api.github.com
 * connect-timeout does not escalate to Sentry.
 */
export async function withGithubRetry<T>(fn: () => Promise<T>): Promise<T> {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt < MAX_RETRIES && isRetryableGithubError(err)) {
        await delay(BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      throw err;
    }
  }
  throw new Error("withGithubRetry: unreachable"); // loop returns or rethrows
}
```

**Budget constants (single source of truth).** Hoist `MAX_RETRIES = 2` and `BASE_DELAY_MS = 1_000` into this leaf (they currently live privately in `github-api.ts:23-24`) and have `fetchWithRetry` import them, so the 1 s/2 s budget is defined ONCE. Do NOT introduce new `DEFAULT_*` constants (the simplicity review flagged that as triplication). Verify `github-api.ts` still compiles after the import swap.

**No `opts` parameter.** Every call site in this PR uses the defaults; a configurable signature is YAGNI. If a future caller needs a different budget, widen then.

Keep the leaf logger-free (dependency-free; callers own observability via their existing catch + `reportSilentFallback`). This preserves the no-cycle property.

> **Subtlety:** octokit's wrapper sets `.status = 500`. Do NOT add a "retry on status>=500" arm — that would also retry genuine GitHub 5xx responses (which octokit ALSO surfaces as `RequestError` with the real status), broadening scope beyond the connect-timeout bug. The cause-chain walk is precise: it retries only when a real undici/timeout code is present in the chain. A genuine 500 with no transient cause is correctly NOT retried.

### Phase 2 — Route the sweep's octokit calls through `withGithubRetry`

In `cron-stale-deferred-scope-outs.ts`:

1. Import: `import { withGithubRetry } from "@/server/github-retry";` (the cron needs only `withGithubRetry`; `isRetryableGithubError` is internal to the helper).
2. In `fetchCandidates`, wrap the search request:
   ```ts
   const res = await withGithubRetry(() =>
     octokit.request("GET /search/issues", { q, per_page: SEARCH_PER_PAGE, page }),
   );
   ```
3. In `sweepStaleScopeOuts`, wrap the comment and close requests **inside** the existing per-issue `try` (so the existing `catch` remains the terminal net after the retry budget is spent):
   ```ts
   await withGithubRetry(() =>
     octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", { … }),
   );
   await withGithubRetry(() =>
     octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", { … }),
   );
   ```
   Do NOT alter the `err.status === 403 → "issue_write_403"` discriminator — a 403 is non-retryable so `withGithubRetry` rethrows it on the first attempt straight into the existing catch (AC5).

No change to `createProbeOctokit()` itself in this PR (its installation-discovery 401 retry is a separate concern; widening it to all-transient is a candidate follow-up but out of the Sentry issue's named scope). The sweep already calls `createProbeOctokit()` inside `step.run` — if the discovery call times out, the existing outer-handler catch + Inngest `retries: 1` still nets it; folding discovery-retry in would broaden the diff beyond the minimal fix. **Decision: scope to the sweep's own octokit calls** (the calls the Sentry stack most directly implicates) and note the discovery-path follow-up below.

### Phase 3 — Tests

Extend `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts` (existing scaffolding: `octokitRequestSpy` + `reportSilentFallbackSpy` + `makeStep`):

- AC4: `octokitRequestSpy.mockRejectedValueOnce(Object.assign(new TypeError("fetch failed"), {}))` then `.mockResolvedValueOnce({ data: { items: [...] } })` for the search; assert sweep succeeds, no `reportSilentFallback`. Add a variant where the first rejection carries `code: "UND_ERR_CONNECT_TIMEOUT"`.
- AC5: comment path rejects with `{ status: 403 }`; assert single attempt + `op: "issue_write_403"` mirror.
- AC6: search rejects on all 3 attempts with a retryable error; assert `op: "sweep"` mirror + heartbeat `ok: false` + handler rethrow.

Optionally add a focused `withGithubRetry` unit test to `apps/web-platform/test/github-api-retry.test.ts` (co-located with the existing `github-api`/`github-retry` tests) covering: retryable-then-success, non-retryable-immediate-rethrow, exhaust-then-rethrow, backoff-delay-count. Use fake timers (`vi.useFakeTimers()`) so the 1 s/2 s backoff does not slow the suite.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in for monitor "scheduled-stale-deferred-scope-outs" (postSentryHeartbeat at end of handler)
  cadence: daily (cron "0 12 * * *")
  alert_target: Sentry Crons monitor missed/error check-in (existing sentry_cron_monitor.scheduled_stale_deferred_scope_outs in apps/web-platform/infra/sentry/cron-monitors.tf)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (reportSilentFallback → captureException, level=error, feature tag "cron-stale-deferred-scope-outs"; transient blips now absorbed by withGithubRetry and never reach this)
  fail_loud: true (sustained outage still rethrows → Inngest retry exhaustion is visible; heartbeat posts ok:false)
failure_modes:
  - mode: transient api.github.com connect timeout (UND_ERR_CONNECT_TIMEOUT / "fetch failed")
    detection: absorbed by withGithubRetry in-step; only a SUSTAINED outage exhausting 3 attempts surfaces
    alert_route: Sentry feature=cron-stale-deferred-scope-outs op=sweep (error) + Sentry Crons missed/error check-in
  - mode: issues:write-missing 403 on comment/close
    detection: non-retryable → rethrown on first attempt into existing per-issue catch
    alert_route: Sentry feature=cron-stale-deferred-scope-outs op=issue_write_403 (error)
  - mode: per-issue 410/422 (archived / invalid transition)
    detection: existing per-issue catch swallow-and-continue; counter delta (total vs closed)
    alert_route: Sentry feature=cron-stale-deferred-scope-outs op=comment-and-close (error)
logs:
  where: pino structured logs (logger.info/warn) mirrored to Sentry breadcrumbs; fn="cron-stale-deferred-scope-outs"
  retention: per existing Sentry/pino-mirror retention (unchanged)
discoverability_test:
  command: "Inngest dashboard: send event cron/stale-deferred-scope-outs.manual-trigger with { data: { dry_run: true } }; confirm clean heartbeat in Sentry Crons monitor scheduled-stale-deferred-scope-outs (NO ssh)"
  expected_output: "monitor shows an ok check-in; no new error event for issue 448a4173… on a transient-blip run"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — operator-internal infrastructure/tooling resilience change. No Product/UI surface (no files under `components/**`, `app/**/page.tsx`, or any UI-surface path). No marketing, legal, finance, sales, support, or product implications.

## Infrastructure (IaC)

Skip — no new infrastructure. The change edits only `apps/web-platform/server/**` TypeScript (already-provisioned runtime). The existing `sentry_cron_monitor.scheduled_stale_deferred_scope_outs` Terraform resource and the Inngest function registration are unchanged. Deploys via the existing path-filtered `web-platform-release.yml` pipeline on merge.

## GDPR / Compliance

Skip — no regulated-data surface. The changed code path issues GitHub-API calls against the operator's own `jikig-ai/soleur` repo via the synthetic-probe (non-audit-writer) Octokit; it reads/writes only issue metadata (numbers, titles, labels). No schema, migration, auth flow, API route, `.sql`, Supabase, PII, or external-LLM call is touched. None of the (a)–(d) expansion triggers fire (no LLM on session data, threshold is `none`, no new learnings/specs reader, no new artifact-distribution surface).

## Open Code-Review Overlap

`## Files to Edit` = [`apps/web-platform/server/github-retry.ts`, `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`, `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`, `apps/web-platform/test/github-api-retry.test.ts`].

Run at plan time:
```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# then jq --arg path <each file> ... contains($path)
```
Disposition: **None pre-verified in this planning pass (offline-safe).** The implementer MUST run the two-stage `gh issue list … --json` then standalone `jq --arg` check at the start of `/work` for each of the 4 file paths. If any open `code-review` scope-out names `github-retry.ts` or the stale-scope-outs cron, fold in (same PR, `Closes #N`) or acknowledge with a one-line rationale. If none, record `None`.

## Follow-ups (deferred, tracked)

- **F1 — `createProbeOctokit()` transient-retry widening + sibling crons.** Apply `withGithubRetry` / `isRetryableGithubError` to `cron-github-app-drift-guard.ts` and `cron-oauth-probe.ts` (same octokit-no-retry gap) and widen `createProbeOctokit`'s installation-discovery retry beyond 401-only to all transient causes. Deferred because the Sentry issue named only `cron-stale-deferred-scope-outs`; widening now would inflate the diff and blast radius. **Action at `/work`:** file a GitHub issue (verify label via `gh label list` first) titled "Apply withGithubRetry to remaining probe-octokit cron call sites (drift-guard, oauth-probe, installation discovery)", re-eval trigger = "next api.github.com connect-timeout Sentry event from those fnIds".
- **F2 — Non-idempotent auto-close comment (architecture review P1).** The comment POST can double-fire if the comment succeeds, a later un-caught throw escapes `step.run`, and Inngest re-runs the sweep (the still-`is:open` issue re-surfaces). This window is **pre-existing** (not introduced by this fix; the fix reduces its frequency). Minimal future guard: before POSTing, check the issue's recent comments for the `COMMENT_BODY` sentinel and skip if present. **Action at `/work`:** file a tracking issue (re-eval trigger = "any operator report of duplicate auto-close comments, or a `comment-and-close` Sentry op spike"). Do NOT fold into this PR — it is orthogonal to the connect-timeout fix.

## Test Scenarios

All retryable setups use octokit's **real thrown shape** (a `RequestError`-like object with `name:"HttpError"`, `status:500`, and the undici code at `.cause.cause.code`) — never a bare `TypeError` (see AC4 rationale). Helper-property scenarios live in `github-api-retry.test.ts`; cron-integration scenarios in the cron test.

| Scenario | Home | Setup | Expected |
| --- | --- | --- | --- |
| Classifier: wrapped connect-timeout → retryable | helper test | `RequestError{cause: TypeError{cause:{code:UND_ERR_CONNECT_TIMEOUT}}}` | `isRetryableGithubError` returns true (depth-2 walk) |
| Classifier: bare 403 → not retryable | helper test | `RequestError{status:403}`, no transient cause | returns false |
| Classifier: cycle-safe | helper test | object whose `.cause` points to itself | returns false, no hang (depth bound) |
| Helper: retryable-then-success | helper test | fn rejects retryable once, resolves | resolves with 2nd value, 1 backoff (fake timers) |
| Helper: non-retryable immediate rethrow | helper test | fn rejects 403 | rethrows on attempt 1, 0 backoff |
| Helper: exhaust-then-rethrow | helper test | fn rejects retryable ×3 | rethrows after 3 attempts, 2 backoffs |
| Cron: transient search recovers (AC4 regression) | cron test | search rejects retryable once, resolves | sweep succeeds, 0 `reportSilentFallback`, candidates from 2nd response |
| Cron: genuine 403 on comment (AC5) | cron test | comment rejects `RequestError{status:403}` | single attempt, `op:"issue_write_403"` mirror, sweep continues |
| Cron: sustained search outage (AC6) | cron test | search rejects retryable ×3 | `op:"sweep"` mirror, heartbeat ok:false, handler rethrows |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with threshold `none` + a non-empty reason (operator-internal automation).
- **`isRetryable` alone does NOT match octokit's thrown error.** Verified against installed `@octokit/request`/`@octokit/request-error`: `octokit.request(...)` wraps a connect timeout in a `RequestError` (`name:"HttpError"`, `status:500`), copies the cause message (`.message === "fetch failed"`), and buries the original `TypeError` + `{code:"UND_ERR_CONNECT_TIMEOUT"}` under `.cause.cause`. `isRetryable` keys on the TOP-LEVEL error (`instanceof TypeError` / top-level `.code`) and MISSES it. `withGithubRetry` MUST use `isRetryableGithubError` (cause-chain walk). A naive `isRetryable`-only reuse compiles, passes a bare-`TypeError` test, and silently fails in prod — this is the load-bearing correctness point.
- `withGithubRetry`/`isRetryableGithubError` build on the SHARED `isRetryable` — do not hand-roll a second undici-code list in the cron (AC7). The codebase already has a mild duplication between `github-retry.ts isRetryable` and `send-with-retry.ts isTransientFetchError`; do not add a third copy.
- Do NOT add a `status >= 500` retry arm to `withGithubRetry` to "simplify" classification — octokit also surfaces genuine GitHub 5xx as `RequestError` with the real status, so a status-based arm would over-retry real server errors. The cause-chain walk is precise.
- The per-issue retry wrapping goes INSIDE the existing per-issue `try` so the existing swallow-and-continue catch (and its `op: "issue_write_403"` / `op: "comment-and-close"` discriminator) stays the terminal net once the retry budget is exhausted. A 403 is non-retryable → rethrown on attempt 1 → lands in that catch unchanged.
- Typecheck for this package is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT `npm run -w apps/web-platform typecheck` (the repo root declares no `workspaces`).
- Tests run under vitest; the new test file path must match the node project glob `test/**/*.test.ts` (the existing test already satisfies this). Use `vi.useFakeTimers()` for the `withGithubRetry` backoff so the suite does not actually sleep 1 s/2 s.
- Do NOT lengthen undici's per-attempt connect timeout — retrying a fresh connection beats waiting longer on a dead socket. The fix is retry-count, not timeout-length.
