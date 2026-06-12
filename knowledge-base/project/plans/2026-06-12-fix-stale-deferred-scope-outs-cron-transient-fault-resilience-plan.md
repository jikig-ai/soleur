---
title: "fix: stale-deferred-scope-outs cron pages on a single transient GitHub fault"
type: fix
date: 2026-06-12
branch: feat-one-shot-cron-stale-deferred-scope-outs-error-checkin
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# 🐛 fix: stale-deferred-scope-outs cron pages the operator on a single transient GitHub fault

## Symptom

Sentry web-platform Crons monitor `scheduled-stale-deferred-scope-outs`
(monitor.id `87e37238-6e05-4507-af82-ff10f70ccfe4`) fired a high-priority
**"An error check-in was detected"** alert.

- Last successful check-in: `2026-06-11T12:00:05+00:00`
- First failure: `2026-06-12 ~12:00 UTC` (Sentry issue
  `9f3c3ad091424b2aa5fbdb3d0b4914f7`, incident `5468023`),
  `environment=production`, `level=error`.
- Monitor config: `failure_issue_threshold = 1` (a single error check-in
  opens the issue), `recovery_threshold = 1`, `checkin_margin_minutes = 30`,
  `max_runtime_minutes = 10`, `schedule = 0 12 * * *`.

The cron succeeded 06-11 and failed once 06-12. A standing
permission/wiring bug would have failed 06-11 too, so the trigger is a
**transient** upstream GitHub fault on 06-12 (a single 401/403/429/5xx blip),
not a regression in the cron's own logic.

## Confirmed root-cause control-flow finding (verified against current code)

Read of `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
(at this branch) confirms the control-flow claim in the task brief:

1. The Sentry `error` check-in is posted by `postSentryHeartbeat({ ok: !sweepFailed, … })`
   at `cron-stale-deferred-scope-outs.ts:327-334`. `ok` is `false` only when
   `sweepFailed === true`.
2. `sweepFailed` is set `true` **only** in the `catch` at line 313-322, which
   wraps `step.run("sweep-stale-deferred-scope-outs", …)`. That step does two
   throwing things:
   - `const octokit = await createProbeOctokit();` (line 304)
   - `sweepStaleScopeOuts({ octokit, … })` → `fetchCandidates({ octokit, cutoffIso })`
     → `await octokit.request("GET /search/issues", …)` (line 126).
3. **Per-issue write failures do NOT set `sweepFailed`.** The comment/close
   `try/catch` at lines 227-268 catches per-issue 403/410/422, mirrors via
   `reportSilentFallback`, and *continues the loop* — the counter does not
   advance but `sweepFailed` stays `false`. So the missing-`issues:write` 403
   class is **not** the trigger (confirmed; matches the brief's diagnostic
   constraint #1).
4. Therefore the only paths that flip the monitor to `error` are
   **`createProbeOctokit()`** and **the `GET /search/issues` call**.

### The two throwing paths, and their current resilience

| Path | Current resilience | Gap |
|---|---|---|
| `createProbeOctokit()` (`probe-octokit.ts:116-167`) | 401-only retry: 3 total attempts, 1s/2s backoff (`PROBE_JWT_MAX_RETRIES = 2`). Any non-401 (403/429/5xx) **breaks immediately** via `captureAndRethrow` at line 152. | A transient **429 (secondary-rate-limit) or 5xx** on installation discovery throws on the first occurrence — no retry. A 401 *after* the 3-attempt budget also throws. |
| `GET /search/issues` (`cron-stale-deferred-scope-outs.ts:126`) | **None.** Bare `await octokit.request(…)` inside `fetchCandidates`. | Any transient (401/403/429/5xx) on the search call throws immediately, flipping `sweepFailed=true`. This is the **most exposed** surface — the search call has zero retry wrapping. |

### The second, independent bug: the heartbeat pages *before* Inngest retries

The function is registered with `retries: 1`
(`cron-stale-deferred-scope-outs.ts:368`), i.e. **2 total attempts**. But the
handler's own logic posts the `status=error` heartbeat at the *end of every
failed attempt* (line 327-334) and only then rethrows (line 339) to trigger
Inngest's retry. So on a first-attempt transient that the retry would have
recovered:

- **attempt 0**: sweep throws → `sweepFailed=true` → heartbeat POSTs
  `status=error` → **Sentry monitor flips to error, issue opens, operator
  paged** → rethrow.
- **attempt 1** (Inngest retry): sweep succeeds → heartbeat POSTs `status=ok`
  → monitor recovers.

The operator was paged by a fault that the very next attempt fixed. **The
heartbeat-on-first-failure timing is itself a bug**, independent of (and
compounding) the missing retry on the search/auth path.

Inngest exposes `ctx.attempt` (zero-indexed) and `ctx.maxAttempts` in the
function context (verified: `node_modules/inngest/types.d.ts:420-431`; already
consumed by sibling handlers e.g. `cron-bug-fixer.ts`). The current handler
destructures only `{ step, logger, event }` (`HandlerArgs` in `_cron-shared.ts:92-100`)
and never reads `attempt` — so it cannot currently distinguish "first failed
attempt, retry pending" from "final attempt, genuinely failed".

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (Soleur's sole
user for this cron) continues receiving high-priority Sentry pages for
transient GitHub blips that self-heal on retry — alert fatigue that erodes
trust in the monitor and risks a *real* persistent failure being ignored as
"probably another transient."

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this
change touches only an internal operator-owned cron over the `jikig-ai/soleur`
repo via the synthetic-probe Octokit (no founder data, no audit-ledger writes
per `probe-octokit.ts` header). No PII, no regulated-data surface.

**Brand-survival threshold:** `none`. Reason: the cron operates exclusively on
operator-owned GitHub issues via platform-synthetic traffic; a failure is an
operator-visibility/alert-quality concern, not a single-user data or money
incident. The diff touches no sensitive path (no schema/migration/auth/API
route — only an Inngest cron handler + its test + a probe-octokit retry helper).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality | Plan response |
|---|---|---|
| "exception in createProbeOctokit() OR the /search/issues call — NOT the per-issue close path" | Confirmed exactly (see control-flow finding above). | Harden both throwing paths; leave per-issue path unchanged. |
| "createProbeOctokit — 401 retries then throws" | Confirmed: 401-only, 3 attempts, `captureAndRethrow` on non-401. | Widen the retryable class to include 429/secondary-rate-limit/5xx (transient), keep 403/404/malformed as immediate-throw (permanent). |
| "Inngest's existing `retries: 1` … does the error check-in fire on the first failed attempt even though Inngest will retry?" | **Yes — confirmed bug.** Heartbeat posts `error` on attempt 0 before the retry. | Gate the `error` heartbeat on the final attempt (`attempt >= maxAttempts-1`); on non-final failed attempts skip the error POST and just rethrow to let Inngest retry. |
| "#5199 tracks 9 deferred crons; this cron is NOT one of them" | Confirmed: #5199 is OPEN, titled "restore the 9 crons still deferred after Tier-2 boundary". `cron-stale-deferred-scope-outs` is a *live* migrated cron (PR #4457), not deferred. | Independent failure; no restoration-work coupling. |
| Parallel worktree `feat-one-shot-restore-tier2-deferred-crons-5199` may edit `_cron-shared.ts` | `_cron-shared.ts` carries `postSentryHeartbeat`, the TIER2/allowlist lists, and `HandlerArgs`. | Keep `_cron-shared.ts` edits **minimal**: only widen `HandlerArgs` to optionally expose `attempt`/`maxAttempts`. Do the retry-class logic in `probe-octokit.ts` + the cron handler, not in shared lists. |

## Goal

A single transient GitHub API fault (401-after-budget / 403-secondary-rate-limit
/ 429 / 5xx) on either the auth path or the search path MUST NOT flip the Sentry
monitor to `error` / page the operator — while a genuinely persistent failure
(fault on every Inngest attempt, or a permanent 404/malformed-config) still does.

## Approach (two independent, complementary fixes)

Both fixes are needed; either alone is insufficient.

### Fix A — gate the `error` heartbeat on the final Inngest attempt (primary)

This is the smallest, most robust fix and directly addresses the "page before
retry" bug. It makes the cron resilient to *any* transient that recovers on
retry, regardless of which call threw.

- Widen `HandlerArgs` (`_cron-shared.ts`) to optionally surface Inngest's
  `attempt?: number` and `maxAttempts?: number` (both optional — keeps every
  other handler and the existing tests, which pass neither, compiling and
  green). This is the *only* `_cron-shared.ts` edit (merge-conflict-minimal vs.
  the parallel worktree).
- In `cronStaleDeferredScopeOutsHandler`, destructure `attempt` and
  `maxAttempts`. Compute `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`.
  - When the sweep throws on a **non-final** attempt: do **not** post the
    `error` heartbeat. Still call `reportSilentFallback` (so the transient is
    visible in Sentry as a warning-class event for forensics) and rethrow to
    trigger Inngest's retry. Crucially, **do not POST `ok` either** — posting
    `ok` on a failed-but-will-retry attempt would mask a genuine persistent
    failure. The correct behavior is: emit no monitor check-in on a non-final
    failed attempt (Inngest's retry will produce the authoritative check-in).
    The `checkin_margin_minutes = 30` grace window comfortably covers the
    1s/2s/Inngest-retry latency, so skipping the intermediate check-in does not
    risk a "missed" alert.
  - When the sweep throws on the **final** attempt: post `error` (current
    behavior) and rethrow.
  - When the sweep succeeds: post `ok` (current behavior).

  This preserves the existing default for any caller that passes no `attempt`
  (legacy/test path → `attempt=0, maxAttempts=1` → `isFinalAttempt=true` →
  behaves exactly as today: error on failure). Real Inngest fires pass
  `attempt`/`maxAttempts`, so production gets the new "retry-aware" behavior.

### Fix B — bounded retry on the throwing operations (defense in depth)

Even with Fix A, recovering on a *separate* Inngest attempt re-runs the whole
sweep (re-clones nothing here, but re-issues the search + re-mints the token).
A tight in-attempt retry around the genuinely transient operations recovers
faster (sub-second) and reduces the chance of *both* Inngest attempts hitting
the same rate-limit window.

- **Search path** (`fetchCandidates` in `cron-stale-deferred-scope-outs.ts`):
  wrap the `octokit.request("GET /search/issues", …)` in a small bounded
  retry-with-backoff that retries on **transient** status (`429`, `403` with a
  `retry-after`/`x-ratelimit-remaining: 0` secondary-rate-limit signature, `5xx`,
  and transient `401`) and **immediately rethrows** permanent ones (`404`,
  `422`, malformed). Mirror the existing budget idiom (`MAX_RETRIES = 2`,
  `BASE_DELAY_MS = 1000` → 1s, 2s) already used in `probe-octokit.ts:41-42` and
  cited as "the canonical backoff idiom in server/github-api.ts".
- **Auth path** (`createProbeOctokit` in `probe-octokit.ts`): widen the
  retryable class from **401-only** to **401 + 429/secondary-rate-limit + 5xx**,
  keeping non-transient statuses (403-non-rate-limit, 404, malformed) as
  immediate `captureAndRethrow`. Extract a small `isTransientGitHubStatus(err)`
  predicate so both the auth path and the search path share one definition of
  "transient" (single source of truth; testable in isolation).

  Note the `_cron-shared.ts:mintInstallationToken` and `cron-oauth-probe.ts`
  also call `createProbeOctokit()`, so widening its retry class benefits those
  callers too — this is a net improvement, not a regression (the new retries
  only fire on transient faults that previously threw). Confirm no caller
  *depends* on `createProbeOctokit` throwing immediately on 429/5xx (grep:
  `git grep -n "createProbeOctokit" apps/web-platform/server` — all callers
  treat a throw as a hard failure, so faster recovery is strictly better).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [ ] `git grep -n "createProbeOctokit(" apps/web-platform/server` — enumerate
  every caller (expected: `cron-stale-deferred-scope-outs.ts`,
  `cron-oauth-probe.ts`, `_cron-shared.ts:mintInstallationToken`,
  `cron-github-app-drift-guard.ts` indirectly via `createAppJwtOctokit`? — verify).
  Confirm none relies on immediate-throw-on-429/5xx.
- [ ] Confirm `ctx.attempt` / `ctx.maxAttempts` field names against
  `node_modules/inngest/types.d.ts` (verified at plan time: `attempt: number`
  line 427, `maxAttempts?: number` line 431).
- [ ] Confirm the test runner: `apps/web-platform/vitest.config.ts` collects
  `test/**/*.test.ts` (node env). The existing test lives at
  `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
  — extend it in place (it is already on the include glob).

### Phase 1 — RED: failing regression tests (write first per cq-write-failing-tests-before)

Extend `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
(reuse its existing `vi.mock` scaffolding for `createProbeOctokit` +
`reportSilentFallback`; add a heartbeat spy). New cases:

- [ ] **A1 (Fix A — non-final attempt does not page):** mock the sweep to throw
  (e.g. `octokitRequestSpy` on `GET /search/issues` throws a `{ status: 500 }`).
  Invoke the handler with `{ step, logger, attempt: 0, maxAttempts: 2 }`.
  Assert: the handler **rethrows** (so Inngest retries) AND the Sentry heartbeat
  was **not** POSTed with `status=error` (assert via a `postSentryHeartbeat` spy
  / a `fetch` spy: no `error` check-in). `reportSilentFallback` IS called
  (forensic visibility preserved).
- [ ] **A2 (Fix A — final attempt still pages):** same throw, invoke with
  `{ attempt: 1, maxAttempts: 2 }`. Assert: heartbeat POSTed with
  `ok=false`/`status=error`, then rethrows.
- [ ] **A3 (Fix A — legacy/no-attempt path unchanged):** same throw, invoke with
  `{ step, logger }` (no `attempt`). Assert: behaves as today → error heartbeat
  + rethrow (backward-compat for the existing call shape).
- [ ] **B1 (Fix B — transient search 429 then success → single ok, no throw):**
  `octokitRequestSpy` for `GET /search/issues` rejects once with `{ status: 429 }`
  then resolves with items on the second call. Invoke (final-attempt context).
  Assert: sweep does NOT throw, result is the recovered candidate set, heartbeat
  POSTed `ok`. (This is the brief's named acceptance case.)
- [ ] **B2 (Fix B — transient auth 429 then success):** `createProbeOctokitSpy`
  rejects once with `{ status: 429 }` then resolves. (If the retry lives inside
  `createProbeOctokit`, this case belongs in a `probe-octokit` unit test instead
  — see B4.) Assert recovery with no thrown sweep.
- [ ] **B3 (Fix B — permanent 404 still throws):** `GET /search/issues` rejects
  with `{ status: 404 }`. Assert: retry does NOT fire (immediate rethrow), sweep
  throws → (on final attempt) error heartbeat. Persistent failures still surface.
- [ ] **B4 (probe-octokit unit, optional new file):** if the auth-path retry is
  added in `probe-octokit.ts`, add/extend a `probe-octokit` test asserting
  429/5xx now retry (previously 401-only). Mirror the existing `App`/octokit
  mock convention if a probe-octokit test exists; otherwise scope this to the
  cron handler test via the `createProbeOctokitSpy`.

Run RED: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
— confirm the new cases fail against current code.

### Phase 2 — GREEN: implement Fix A (heartbeat gating)

- [ ] `_cron-shared.ts`: add `attempt?: number; maxAttempts?: number;` to
  `HandlerArgs` (both optional). No other `_cron-shared.ts` change.
- [ ] `cron-stale-deferred-scope-outs.ts`: destructure `attempt`, `maxAttempts`
  in `cronStaleDeferredScopeOutsHandler`. Compute
  `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`. Restructure the
  `sweepFailed` → heartbeat → throw block so:
  - on success → `ok` heartbeat (unchanged);
  - on failure + non-final attempt → `reportSilentFallback` (already present) +
    **skip the heartbeat POST entirely** + rethrow;
  - on failure + final attempt → `error` heartbeat + rethrow (unchanged).
  Keep the inline comments explaining the retry-aware timing (`hr-observability-layer-citation`).

### Phase 3 — GREEN: implement Fix B (bounded transient retry)

- [ ] `probe-octokit.ts`: extract `isTransientGitHubStatus(err): boolean`
  (exported for reuse + test). Transient = `401` (existing JWT-replication
  class) ∪ `429` ∪ secondary-rate-limit `403` (detect via
  `err.response.headers["retry-after"]` present OR
  `x-ratelimit-remaining === "0"`) ∪ `5xx`. Widen the `createProbeOctokit` retry
  loop from `status !== 401` to `!isTransientGitHubStatus(err)` for the
  immediate-rethrow branch. Keep the same 3-attempt / 1s,2s budget.
- [ ] `cron-stale-deferred-scope-outs.ts` `fetchCandidates`: wrap the
  `octokit.request("GET /search/issues", …)` per page in a bounded
  retry-with-backoff (2 retries, 1s/2s) using the **same**
  `isTransientGitHubStatus` predicate (import from `probe-octokit.ts`). Permanent
  statuses rethrow immediately; transient ones retry; budget-exhaustion rethrows
  (so a persistent fault still reaches `sweepFailed`). Preserve the existing
  pagination logic (the retry wraps the single request, not the page loop).

### Phase 4 — Verify GREEN + full suite

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
  (+ the probe-octokit test if added) — all green.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — typecheck
  clean (note: `npm run -w … typecheck` aborts; the in-package `tsc` is the
  canonical form per repo learnings).
- [ ] Run the broader cron test cohort to catch any `HandlerArgs` widening
  fallout: `./node_modules/.bin/vitest run test/server/inngest/`.

### Phase 5 — Re-verification (document; do NOT run during planning)

Per the brief, after the fix merges and deploys, re-verify by firing the
manual-trigger from inside this worktree:

```bash
# Dry-run first (lists candidates without commenting/closing):
bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  cron/stale-deferred-scope-outs.manual-trigger --data '{"dry_run": true}'
# Then a real fire to confirm an ok heartbeat lands:
bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  cron/stale-deferred-scope-outs.manual-trigger
```

Confirm in Sentry that the monitor returns to `ok` (recovery_threshold = 1, so
one ok check-in clears the incident). No Terraform change is required — the
monitor config (margins/thresholds) is correct; the bug was in the handler, not
the monitor sizing.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: New test A1 proves a non-final Inngest attempt that throws does NOT
  post a `status=error` Sentry check-in (no operator page) and rethrows so
  Inngest retries.
- [ ] AC2: New test A2 proves a final-attempt throw DOES post `status=error`
  (persistent failure still pages).
- [ ] AC3: New test A3 proves the no-`attempt` (legacy/test) call shape behaves
  exactly as before (error heartbeat on failure) — backward-compat.
- [ ] AC4: New test B1 proves a transient `429` on `GET /search/issues` followed
  by success yields a single `ok` heartbeat and no thrown sweep (the brief's
  named acceptance case).
- [ ] AC5: New test B3 proves a permanent `404` on the search call is NOT
  retried and still surfaces (sweep throws on final attempt → error).
- [ ] AC6: `isTransientGitHubStatus` is a single shared predicate used by BOTH
  the auth path (`createProbeOctokit`) and the search path (`fetchCandidates`);
  a unit assertion covers `{401,429,5xx,secondary-403}=true` and
  `{403-plain,404,422}=false`.
- [ ] AC7: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] AC8: `_cron-shared.ts` diff is limited to the `HandlerArgs` `attempt?`/`maxAttempts?`
  additions (minimize merge-conflict surface vs. the parallel
  `feat-one-shot-restore-tier2-deferred-crons-5199` worktree).
- [ ] AC9: PR body uses `Ref` (not `Closes`) for any tracking-issue link — there
  is no GitHub issue for this Sentry incident; the resolution is the merged code
  + the post-deploy heartbeat recovery, so do not auto-close anything.

### Post-merge (operator — automatable, run in /work or ship)

- [ ] AC10: After deploy (the `web-platform-release.yml` pipeline restarts the
  container on merge to main touching `apps/web-platform/**`, syncing the new
  function), fire the manual-trigger dry-run via `trigger-cron/scripts/trigger.sh`
  and confirm an `ok` heartbeat (automatable via the trigger script + Sentry API
  read — NOT operator dashboard-watching, per `hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] AC11: Confirm the Sentry monitor incident `5468023` clears to `ok`
  (recovery_threshold=1) after the next successful check-in.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal backend/cron resilience fix.
No UI surface (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`
in Files to Edit → Product/UX Gate = NONE, mechanical override did not fire). No
regulated-data surface (probe-octokit is synthetic operator-owned traffic with
no audit-ledger writes; no schema/migration/auth/API-route → GDPR gate skipped).
No new infrastructure (the Sentry monitor Terraform is unchanged; no
SSH/systemd/secret/vendor/cron creation → IaC gate skipped).

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in (heartbeat POST) for monitor scheduled-stale-deferred-scope-outs
  cadence: daily 0 12 * * * UTC (+ manual-trigger fires)
  alert_target: Sentry monitor 87e37238-6e05-4507-af82-ff10f70ccfe4 (failure_issue_threshold=1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf:432 (unchanged); emitted by postSentryHeartbeat in _cron-shared.ts
error_reporting:
  destination: Sentry via reportSilentFallback (error) on final-attempt sweep failure; warnSilentFallback/reportSilentFallback (warning/forensic) on transient/non-final failures
  fail_loud: true on persistent failure (final attempt error check-in pages); intentionally quiet on self-healing transients
failure_modes:
  - mode: persistent GitHub auth failure (every attempt 401-after-budget/403/404)
    detection: createProbeOctokit throws on every Inngest attempt → final-attempt error heartbeat
    alert_route: Sentry monitor error check-in (operator paged)
  - mode: persistent search failure (404/malformed every attempt)
    detection: fetchCandidates rethrows permanent status → final-attempt error heartbeat
    alert_route: Sentry monitor error check-in
  - mode: transient GitHub fault (single 401/429/5xx) that recovers
    detection: in-attempt retry OR Inngest retry recovers; no error check-in posted
    alert_route: forensic-only (reportSilentFallback warning event in Sentry; no page)
logs:
  where: pino structured logs (logger.info/warn) inside the handler + sweep; reportSilentFallback mirrors to Sentry
  retention: per existing Sentry/Better Stack retention (unchanged)
discoverability_test:
  command: bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh cron/stale-deferred-scope-outs.manual-trigger --data '{"dry_run": true}'
  expected_output: dry-run completes; ok heartbeat for scheduled-stale-deferred-scope-outs visible in Sentry Crons (no ssh)
```

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
  — Fix A (attempt-gated heartbeat in the handler) + Fix B (search-path retry in
  `fetchCandidates`).
- `apps/web-platform/server/github/probe-octokit.ts` — Fix B (widen retry class
  via shared `isTransientGitHubStatus`; export the predicate).
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — add
  `attempt?: number; maxAttempts?: number;` to `HandlerArgs` (ONLY this change).
- `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
  — new regression cases A1–A3, B1, B3, and the `isTransientGitHubStatus` unit
  assertion (AC6).

## Files to Create

- (Optional) `apps/web-platform/test/server/github/probe-octokit.test.ts` — only
  if no probe-octokit test exists and B2/B4 are better expressed as a unit test
  there. Otherwise none.

## Non-Goals / Out of Scope

- No change to the per-issue comment/close error handling (confirmed not the
  root cause).
- No change to the Sentry monitor Terraform config (margins/thresholds are
  correct).
- No restoration coupling with #5199 (independent failure).
- No change to the `0 12 * * *` schedule or `retries: 1` policy (the page-timing
  fix makes `retries: 1` sufficient; we are not raising the retry count).

## Open Code-Review Overlap

**None.** Checked at plan time: `gh issue list --label code-review --state open`
returned 63 open issues; `jq`-matched each against the four edited file
basenames (`cron-stale-deferred-scope-outs.ts`, `probe-octokit.ts`,
`_cron-shared.ts`) — zero matches. No open scope-out touches these files.

Note: `createProbeOctokit` has ~10 callers across the cron cohort
(`cron-bug-fixer`, `cron-oauth-probe`, `cron-kb-template-health`,
`cron-github-app-drift-guard`, `mintInstallationToken`, etc.). Widening its
retry class is a net improvement for all of them (each treats a throw as hard
failure → faster transient recovery). No caller depends on immediate-throw on
429/5xx (verified by Phase 0 grep at plan time).

## Risks & Mitigations

- **Risk:** skipping the heartbeat on a non-final failed attempt could, in
  theory, let a missed check-in slip past the `checkin_margin_minutes` window if
  the Inngest retry is slow. **Mitigation:** the margin is 30 min; Inngest's
  retry + 1s/2s backoff is well under that. A non-final attempt that fails and is
  *not* retried (e.g. the process dies) would still miss the check-in and alert
  via the missed-check-in path — so we do not lose the "genuinely dead" signal.
- **Risk:** widening `createProbeOctokit`'s retry class affects other callers
  (`cron-oauth-probe`, `mintInstallationToken`). **Mitigation:** the new retries
  fire only on transient statuses that previously threw — strictly faster
  recovery, no behavior change on permanent faults. Verified via Phase 0 caller
  grep.
- **Risk:** `secondary-rate-limit 403` detection heuristic (retry-after /
  x-ratelimit-remaining headers) could misclassify a permanent 403 as transient
  and burn the retry budget. **Mitigation:** budget is only 2 retries (≤3s
  total); a permanent 403 without the rate-limit headers is treated as permanent
  and rethrows immediately. Worst case is a 3s delay on a genuine permanent 403,
  which still surfaces.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — this plan's threshold is `none` with a
  one-sentence reason (sensitive-path carve-out satisfied).
- The `HandlerArgs` widening MUST keep `attempt`/`maxAttempts` **optional** —
  every other cron handler and the existing tests pass neither; making them
  required would break compilation across the whole cron cohort.
- Inngest `attempt` is **zero-indexed**; with `retries: 1` there are 2 attempts
  (0 and 1) and `maxAttempts` is 2. `isFinalAttempt` must be
  `attempt >= maxAttempts - 1`, not `attempt >= maxAttempts`.
