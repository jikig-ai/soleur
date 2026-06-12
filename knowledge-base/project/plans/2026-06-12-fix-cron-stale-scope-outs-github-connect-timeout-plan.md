---
type: bug-fix
lane: single-domain
brand_survival_threshold: none
sentry_issue: 448a4173f90a436382c4396371927796
---

# 🐛 fix: Make `cron-stale-deferred-scope-outs` GitHub calls resilient to transient connect timeouts

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

Wrap the octokit calls in an in-step transient-retry loop using the **existing canonical classifier** `isRetryable` from `apps/web-platform/server/github-retry.ts` — which already classifies exactly this error (`UND_ERR_CONNECT_TIMEOUT`, `TypeError: fetch failed`, `TimeoutError`, `ECONNRESET`, etc.). Add a tiny shared `withGithubRetry(fn)` helper to `github-retry.ts` (MAX_RETRIES=2, BASE_DELAY 1 s → 1 s, 2 s — the same budget as `fetchWithRetry` and `createProbeOctokit`'s 401 path) and route the sweep's octokit calls through it. A transient connect timeout is then absorbed (retried in-step, exponential backoff) and never reaches the handler's error-level mirror.

This is strictly a resilience addition. It does NOT change the sweep's semantics, counters, dry-run behavior, replay-safety guards (I7), or the Inngest `retries: 1` outer policy (which remains as a last-resort net for a sustained outage that exhausts the in-step budget).

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
| "add explicit retry/backoff + a sane timeout" | Codebase has a canonical classifier (`github-retry.ts isRetryable`) + backoff idiom (`fetchWithRetry`, `createProbeOctokit`). undici's 10 s connect timeout is already a "sane" per-attempt timeout; the gap is retry, not timeout length. | Reuse `isRetryable`; add a `withGithubRetry` wrapper (1 s/2 s backoff, 3 total attempts). Do NOT lengthen the per-attempt connect timeout (retrying a fresh connection beats waiting longer on a dead one). |
| "consistent with how other crons call GitHub" | Other crons use `createProbeOctokit()` with no per-call retry — there is no existing per-call octokit-retry precedent to copy; the precedent is the raw-`fetch` `fetchWithRetry`. | Establish the helper in the shared leaf `github-retry.ts` (where `isRetryable` already lives) so it is the new shared precedent. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is an operator-only platform cron that auto-closes stale `deferred-scope-out` GitHub issues in `jikig-ai/soleur`. A regression would at worst leave the stale-scope-out backlog un-drained for a day (next cron fire recovers) or, if the retry wrapper were misimplemented, re-introduce the same Sentry noise.

**If this leaks, the user's data is exposed via:** N/A — the cron touches only operator-owned GitHub issue metadata (issue numbers, titles, labels). No founder/user data, no Supabase, no PII, no secrets are read or written by the changed code path. `createProbeOctokit` is explicitly the synthetic-probe, non-audit-writer client (see its file header).

**Brand-survival threshold:** none — operator-internal automation, no user-facing surface, no regulated-data surface. The diff touches `apps/*/server/inngest/functions/` and `apps/*/server/github-retry.ts`; neither is a sensitive path under preflight Check 6 (no schema/migration/auth/API-route/`.sql`). Reason for `none`: the changed code only issues GitHub-API calls against the operator's own repo and mirrors transient failures to Sentry; a worst-case bug delays a janitorial backlog sweep by one daily cron cycle.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Shared retry helper exists.** `apps/web-platform/server/github-retry.ts` exports `withGithubRetry<T>(fn: () => Promise<T>, opts?): Promise<T>` that retries `fn` up to 2 times (3 total attempts) with exponential backoff (1 s, 2 s) **only** when `isRetryable(err)` is true, and rethrows immediately on any non-retryable error or after exhausting the budget. Verify: `git grep -n "export function withGithubRetry" apps/web-platform/server/github-retry.ts` returns 1 hit.
- [ ] **AC2 — Sweep search is wrapped.** In `cron-stale-deferred-scope-outs.ts`, the `octokit.request("GET /search/issues", …)` call inside `fetchCandidates` is routed through `withGithubRetry`. Verify by reading: the call is inside `withGithubRetry(() => octokit.request("GET /search/issues", …))`.
- [ ] **AC3 — Per-issue comment + close are wrapped.** The `POST …/comments` and `PATCH …/issues/{issue_number}` calls in `sweepStaleScopeOuts` are each routed through `withGithubRetry` (so a transient blip on comment-or-close retries in-step before falling into the existing per-issue `catch`). The existing per-issue try/catch (swallow-and-continue + `reportSilentFallback`) is preserved as the terminal net AFTER the retry budget is exhausted.
- [ ] **AC4 — Transient connect timeout no longer escalates (new test).** A new unit test seeds `octokitRequestSpy` to throw a `TypeError` with `message === "fetch failed"` (and a variant with `code: "UND_ERR_CONNECT_TIMEOUT"`) on the FIRST `GET /search/issues` attempt and resolve on the SECOND. Assert: (a) the sweep completes successfully, (b) `reportSilentFallbackSpy` is NOT called for the transient, (c) the candidate list reflects the second (successful) response. This is the regression test for the Sentry issue.
- [ ] **AC5 — Non-retryable errors still surface.** A test seeds a non-retryable error (e.g. `{ status: 403 }`) on the comment/close path and asserts `withGithubRetry` does NOT retry (spy call count == 1 for that issue's first failing request) and the existing `reportSilentFallback` mirror with `op: "issue_write_403"` still fires — i.e. resilience does not mask the genuine `issues:write`-missing 403 discriminator (#4189).
- [ ] **AC6 — Sustained outage still reaches the handler net.** A test seeds a retryable error on ALL attempts of the sweep's first `GET /search/issues`; assert the helper exhausts 3 attempts then rethrows, the handler's outer catch fires `reportSilentFallback` with `op: "sweep"`, the heartbeat posts `ok: false`, and the handler rethrows (Inngest retry preserved).
- [ ] **AC7 — `isRetryable` not duplicated.** The new helper imports `isRetryable` from the same module; no new copy of the undici-code list is introduced in `cron-stale-deferred-scope-outs.ts`. Verify: `git grep -n "UND_ERR_CONNECT_TIMEOUT" apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` returns 0 hits.
- [ ] **AC8 — Typecheck + tests green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts test/github-api-retry.test.ts` passes (existing + new cases).

### Post-merge (operator)

- None. `apps/web-platform/**` change deploys via the existing `web-platform-release.yml` path-filtered pipeline on merge to main (container restart + Inngest function re-sync are handled by the pipeline). No migration, no Terraform, no Doppler secret. The fix is verified live by the next daily cron fire (`0 12 * * *`) producing a clean Sentry heartbeat and no recurrence of issue `448a4173…`.

## Implementation Phases

### Phase 1 — Add `withGithubRetry` to the shared leaf (`github-retry.ts`)

Append a wrapper next to `isRetryable` / `delay`. Mirror the budget of `fetchWithRetry` (MAX_RETRIES=2, BASE_DELAY_MS=1_000):

```ts
// apps/web-platform/server/github-retry.ts (appended)

const DEFAULT_MAX_RETRIES = 2;      // 3 total attempts
const DEFAULT_BASE_DELAY_MS = 1_000; // 1s, 2s

/**
 * Run `fn`, retrying ONLY on transient network errors (isRetryable) with
 * exponential backoff. Non-retryable errors (4xx, auth, shape) and the final
 * attempt's error rethrow immediately. Use to wrap octokit.request() calls in
 * crons so a single api.github.com connect-timeout does not escalate to Sentry.
 */
export async function withGithubRetry<T>(
  fn: () => Promise<T>,
  opts: { maxRetries?: number; baseDelayMs?: number } = {},
): Promise<T> {
  const maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES;
  const baseDelayMs = opts.baseDelayMs ?? DEFAULT_BASE_DELAY_MS;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt < maxRetries && isRetryable(err)) {
        await delay(baseDelayMs * 2 ** attempt);
        continue;
      }
      throw err;
    }
  }
  // Unreachable: loop returns or the final attempt rethrows.
  throw new Error("withGithubRetry: retry loop fell through");
}
```

Keep it logger-free (the leaf is dependency-free; callers own observability via their existing catch + `reportSilentFallback`). This preserves the leaf's no-cycle property.

### Phase 2 — Route the sweep's octokit calls through `withGithubRetry`

In `cron-stale-deferred-scope-outs.ts`:

1. Import: `import { withGithubRetry } from "@/server/github-retry";`
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

- **`createProbeOctokit()` transient-retry widening** + applying `withGithubRetry` to the sibling crons `cron-github-app-drift-guard.ts` and `cron-oauth-probe.ts` (same octokit-no-retry gap). Deferred because the Sentry issue named only `cron-stale-deferred-scope-outs`; widening now would inflate the diff and blast radius beyond the reported bug. **Action at `/work`:** file a GitHub issue (label `code-review` or `chore`, verify label exists via `gh label list` first) titled "Apply withGithubRetry to remaining probe-octokit cron call sites (drift-guard, oauth-probe, installation discovery)" with re-eval trigger = "next api.github.com connect-timeout Sentry event from those fnIds".

## Test Scenarios

| Scenario | Setup | Expected |
| --- | --- | --- |
| Transient search timeout, recovers | search rejects once (`TypeError: fetch failed`), then resolves | sweep succeeds, 0 `reportSilentFallback`, candidates from 2nd response |
| Transient via undici code | search rejects once (`code: UND_ERR_CONNECT_TIMEOUT`), then resolves | same as above |
| Transient comment timeout, recovers | comment rejects once retryable, then resolves; close resolves | issue closed, counter advances, 0 mirror |
| Genuine 403 on close | close rejects `{ status: 403 }` (non-retryable) | single attempt, `op: "issue_write_403"` mirror, sweep continues |
| Sustained search outage | search rejects retryable on all 3 attempts | 3 attempts, rethrow, `op: "sweep"` mirror, heartbeat ok:false, handler rethrows |
| Dry-run unaffected | `dry_run: true`, search resolves | candidates listed, no comment/close calls, no retries needed |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled with threshold `none` + a non-empty reason (operator-internal automation).
- `withGithubRetry` must classify via the SHARED `isRetryable` — do not hand-roll a second undici-code list in the cron (AC7). The codebase already has a mild duplication between `github-retry.ts isRetryable` and `send-with-retry.ts isTransientFetchError`; do not add a third copy.
- The per-issue retry wrapping goes INSIDE the existing per-issue `try` so the existing swallow-and-continue catch (and its `op: "issue_write_403"` / `op: "comment-and-close"` discriminator) stays the terminal net once the retry budget is exhausted. A 403 is non-retryable → rethrown on attempt 1 → lands in that catch unchanged.
- Typecheck for this package is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT `npm run -w apps/web-platform typecheck` (the repo root declares no `workspaces`).
- Tests run under vitest; the new test file path must match the node project glob `test/**/*.test.ts` (the existing test already satisfies this). Use `vi.useFakeTimers()` for the `withGithubRetry` backoff so the suite does not actually sleep 1 s/2 s.
- Do NOT lengthen undici's per-attempt connect timeout — retrying a fresh connection beats waiting longer on a dead socket. The fix is retry-count, not timeout-length.
