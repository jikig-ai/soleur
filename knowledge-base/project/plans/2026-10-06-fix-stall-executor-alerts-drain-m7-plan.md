---
title: "fix(ci): executor-failure alerting for merge-queue-stall-check, stall-issue drain, and M7 flake hardening"
type: fix
date: 2026-10-06
slug: fix-stall-executor-alerts-drain-m7
branch: feat-one-shot-9513-9475-stall-m7
issue: 9513
closes: 9513 9475
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(ci): executor-failure alerting for merge-queue-stall-check, stall-issue drain, and M7 flake hardening

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Two tracked Oct 5–6 merge-queue/CI findings close in one change set. The
`merge-queue-stall-check.yml` executor runs blind: its dispatcher
(`cron-merge-queue-stall-dispatch.ts`) posts a green Sentry check-in for
"dispatched", so a red executor run alerts nobody, and its `merge-queue-stall`
issue filings outlive their target PRs by 12–24h. Independently, the
`test-all-runtime-ceiling.test.sh` row M7 (`three_bump` arm) was reported
flaky under load with no failing log captured; a 100-iteration loaded
reproduction attempt in this session produced zero failures, so the row gains
self-describing failure diagnostics and a wider real-elapsed margin instead of
a guessed fix.

## Problem Statement / Motivation

**#9513, gap 1 — a red executor run alerts nobody.** The Sentry monitor
`scheduled-merge-queue-stall-dispatch` is fed by the Inngest dispatcher, so a
green check-in means "dispatched", not "probe executed". The executor workflow
carries no `if: failure()` step, no Sentry step and no secrets by design, and
dispatched runs have `soleur-ai[bot]` as actor so GitHub's native failure mail
goes nowhere. ADR-270 item 10 records the gap and points here.

**#9513, gap 2 — stall filings do not drain.** The checker's `>45m` filings
accumulate: stall issues stayed open 12–24h after their target PRs merged
(three were verified merged and closed manually on 2026-10-06).

**#9475 — M7 flake.** Arm `three_bump` expects `declined_suites=2`; 6/6
isolated runs passed on an idle machine; no failing log exists, so the
elapsed-vs-bump race is a hypothesis, not a finding. The acceptance bar asks
for either a captured failing log or tightened diagnostics plus a documented
reproduction attempt.

## Research Insights

- **Dispatcher file:** `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts`
  mints a short-lived `actions:write` installation token, POSTs
  `workflow_dispatch` for `merge-queue-stall-check.yml`, and posts the
  heartbeat. The `actions:write` grant also reads the Actions API — the
  runs-list endpoint `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs`
  is reachable with the token it already holds (no new secret, no grant
  widening, per the issue's preferred fix).
- **Executor file:** `.github/workflows/merge-queue-stall-check.yml` has
  `permissions: contents:read + issues:write`. `gh issue view <pr#> --json
  state` returns `OPEN|CLOSED|MERGED` for a PR number under the existing grant
  (verified live: `gh issue view 9571 --json state` → `MERGED`), so the drain
  needs **no permission widening**.
- **Drain precedent:** `.github/workflows/scheduled-actions-queue-health.yml`
  "Auto-resolve queue-health issues when healthy" is the sweep to mirror:
  label-scoped `gh issue list --json` (never `--search`, the index lags),
  `-L 50` bound with a cap-hit `::notice::`, serial `gh issue close` with
  `|| true`, and fail-open dedupe whose `gh` stderr reaches `::error::` only
  through `LC_ALL=C tr -cd '\40-\176' | head -c 300`. The `gh --jq` embedded
  jq does not forward `--arg` (#9533) — all filtering runs in standalone jq.
- **Test harnesses:** `plugins/soleur/test/merge-queue-stall-check.test.sh`
  (PyYAML structural assertions + a `gh` stub that executes the real step
  bodies; `EXPECTED_PASSES=51` floor) and
  `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts`
  (vitest; Octokit mocked at `@octokit/core`, `postSentryHeartbeat` and
  `reportSilentFallback` spied, replaying-step fake for Inngest memoization).
- **M7 mechanics:** `_elapsed_s` at suite entry = `EPOCHSECONDS -
  _RUN_START_EPOCH + bump`. The bump fixture writes 120 deterministically
  before the next entry reads, so the only wall-clock-dependent window is the
  runner preamble between `_RUN_START_EPOCH` (test-all.sh:4007) and the first
  `run_suite` call. If real elapsed reaches the 60s ceiling before
  `bumpfixture`'s entry, `declined_suites` reads 3, not 2 — the reachable
  contention shape. `declined_suites=1` or `0` is mechanically unreachable on
  this code path (the bump file persists once written; the counter cannot
  under-count). A truncated/no-marker failure needs the runner to die before
  the epilogue (OOM/kill) — covered by diagnostics, not by fixture tuning.
- **M7 environment (task (a), re-derived):** the sandbox arm splices out the
  registration region between `tc_acquire "test-all"` and `tc_epilogue`, so
  the 2026-10-05 merges (ff423af67d, f372c32ba1) — pure suite registrations —
  cannot reach the arm. The arm runs `env -u CI TEST_GROUP=all`, which arms
  `_AFFECTED=1` (the local default): the affected pre-pass DOES execute inside
  the sandbox, but `lib/test-affected-paths.sh` is not copied, so
  `_AFF_LIB_OK=0` → `_aff_fallback=index-missing` → degraded full mode →
  `_aff_ready` stays 0 → every fixture registration reaches the ceiling check.
  The pre-pass sits before `_RUN_START_EPOCH`, so it cannot inflate measured
  elapsed either. The `--affected` derivation changes (#9422 read-recorder
  10-03, #9477 10-04, #9552 registration-only re-classification 10-06) do not
  alter the arm's verdict path.
- **Reproduction attempt (task (b), documented):** 100 loaded iterations —
  50 pinned to cores 0-1 under 12 CPU burners + 4 `ps`-spam loops on the same
  cores, 50 spread machine-wide under 32 burners at `nice -10` — produced
  `declined_suites=2 rc=3` on every run. Zero reproductions.
- **Premise Validation:** #9513 OPEN (no closed-by PRs); #9475 OPEN; merged
  PR #9571 links both issues by citation only (closes #9429/#9533); merged PR
  #9511 *filed* #9513; no OPEN PR on the same scope; no duplicate open issue;
  no sibling worktree on either defect noun. ADR-270 item 10 tracks the exact
  gap. Verified `gh issue view` returns `MERGED` for a merged PR number.
- **Property List (Phase 0.6b):**
  1. A `conclusion != success` executor run produces an error-status check-in
     on the dispatcher-fed monitor (pages via the #9511 routing).
  2. A dispatched run still not `completed` after ~10 min (runner-wait gap)
     produces an error-status check-in.
  3. An open `merge-queue-stall` issue whose title's `PR #N` is not `OPEN`
     self-closes on the next sweep.
  4. The next M7 failure prints its own evidence (arm rc, bump state, log).
  5. The M7 arm's real-elapsed window is wide enough that plausible CPU
     contention cannot decline `bumpfixture`.
- **Cut List:** none — no existing mechanism covers any property: the monitor
  only sees check-ins (property 1/2 need a producer), the queue-health sweep
  closes on verdict not on target-PR state (property 3), and M7's current
  failure line prints `RUNTIME_CEILING|declined` greps that are empty exactly
  on the failure shapes that matter (property 4).

## Proposed Solution

### Part A — dispatcher-side executor-conclusion check (#9513 gap 1)

Add a `check-previous-run` step to `cronMergeQueueStallDispatchHandler`,
inside the existing `actions:write` token's scope, **before** the dispatch
step so the newest listed run is deterministically the previous tick's:

- `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs?per_page=5`
  (no `event` filter — a schedule-fallback or manual red run is equally
  unalarmed; the endpoint accepts the file basename like the dispatch POST).
- Verdict on the newest run: `status == "completed"` → `conclusion ==
  "success"` is `ok`, any failure-class conclusion
  (`failure|timed_out|cancelled|startup_failure|action_required|stale`) is
  `failed`; `status != "completed"` → `stuck` when `created_at` is older than
  ~11 min (past the workflow's own 10-min timeout; the ~10-min tick means the
  previous run is judged at ~t+10 and a merely-late run never false-pages),
  else `pending`; an empty list is `none`; an Octokit error is `unknown`.
- `failed`/`stuck`/`unknown` → `reportSilentFallback` (run id, conclusion,
  `html_url` in `extra`, token redacted) **and** the heartbeat posts
  `ok:false`; `ok`/`pending`/`none` → the heartbeat posts `ok: dispatch.ok`.
- The step never throws (verdict `unknown` on error), keeping replay
  semantics identical to the existing dispatch step. Result gains a
  `previousRun` field; `ok` stays the dispatch verdict — the function
  succeeded at dispatching *and* at reporting the failure it found.

### Part B — stall-issue drain (#9513 gap 2)

A new `Drain stale stall issues` step in `merge-queue-stall-check.yml`,
`if: always()` after the detect step (an aborted detect run must not skip
the drain), same job, same `issues:write` grant:

- Label-scoped `gh issue list --state open -L 50 --label merge-queue-stall
  --json number,title` (fail-open: a list failure prints sanitized
  `::error::` and skips the sweep; never `gh --jq --arg`).
- Standalone jq extracts `issue_number \t pr_number` via
  `capture("PR #(?<pr>[0-9]+) pending")` — the constant title shape the
  detect step files; unmatched titles are skipped, not closed.
- Per pair: `gh issue view <pr> --json state` → close only when `state` is a
  non-empty value other than `OPEN` (`CLOSED` covers closed-unmerged,
  `MERGED` covers merged; a failed or empty read keeps the issue — fail
  toward keeping).
- `-L 50` cap-hit `::notice::`; serial `gh issue close … || true` with a
  comment naming the target PR state and the run URL.

### Part C — M7 fixture margin + self-describing failure (#9475)

- Raise the `three_bump` arm's ceiling/bump pair from 60/120 to 300/360 (new
  synthesized `bump360.sh` fixture): the property under test — every later
  suite declined, counter does not saturate — is unchanged; the real-elapsed
  margin a contended preamble must exceed to decline `bumpfixture` grows 5×.
  The strict `declined_suites=2` assertion stays.
- On M7 failure, dump the arm's rc, the bump file's path + contents, and the
  arm log (bounded tail) so the next failure self-describes from CI output
  alone — today the grep-printed lines are exactly what is absent on a
  crashed arm, which is why no failing log exists.

## Technical Considerations

- **Replay safety:** all new dispatcher logic lives inside `step.run`
  (memoized); nothing outside a step can repeat on Inngest replays.
- **Token scope:** `actions:write` already reads the runs endpoint — no
  permission change on the mint, no new secret, consistent with the issue's
  "secretless" requirement and the runner's no-secrets posture.
- **No `${{ }}` inside run bodies:** the workflow suite asserts
  `has_expr_in_run | not` — drain env values pass via the `env:` block.
- **No `continue-on-error`:** the suite asserts none anywhere; the drain uses
  `if: always()` (different mechanism — failure still fails the job, the
  drain just isn't skipped).
- **Title-shape coupling:** the drain keys on the same `PR #N pending`
  anchor the detect step files and the dedupe awk matches — one canonical
  title shape, three consumers.
- **ADR-270 consistency:** the check stays in the trigger layer (Inngest),
  execution stays in the runner — the dispatch-hybrid shape the ADR scoped
  is preserved; no new ADR is needed (no ownership/trust boundary moves).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Executor-side heartbeat step in the workflow | Would put Sentry secrets into a runner that deliberately holds none — the issue's explicitly dispreferred route; breaks the runner's no-secrets posture. |
| `if: failure()` notify step in the workflow | Same secrets problem, and `if: failure()` never fires on a `timed_out`/startup red — the exact class that matters. |
| Event-filtered runs list (`event=workflow_dispatch` only) | A schedule-fallback or manually-dispatched red run is equally unalarmed; the unfiltered newest-run check covers both at zero cost. |
| `gh pr view` for the drain state read | Needs `pull-requests: read`, a grant widening; `gh issue view` returns `MERGED`/`CLOSED`/`OPEN` under the existing `issues:write` grant (verified). |
| Accept `declined_suites>=2` on M7 | Widens the row without evidence for which mechanism flakes; the strict `=2` stays and the plausible mechanism (real elapsed ≥ ceiling pre-bump) is closed by the margin raise instead. |
| Per-suite elapsed reset for the arm | Would change the ceiling's semantic baseline (`_RUN_START_EPOCH` is the run's age, not the suite's) — the fixture must not redefine the property. |

## Implementation Phases

### Phase 1 — Failing tests first (TDD)

1. Extend `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts`:
   - The Octokit mock routes by endpoint: the runs-list GET returns a
     canned `workflow_runs` array per arm; the dispatch POST returns 204.
   - New arms: previous `conclusion=failure` → `reportSilentFallback` +
     `ok:false` heartbeat + result still `ok:true`; `stuck` (status
     `in_progress`, `created_at` > 11 min ago) → same loud path; `pending`
     (queued, fresh) → ok heartbeat; `none` (empty list) → ok heartbeat;
     runs-list GET throws → `unknown` → report + `ok:false` heartbeat;
     replay arm proving one check call across replays.
   - Existing arms updated for the added GET (call counts, call order:
     check GET before dispatch POST).
2. Extend `plugins/soleur/test/merge-queue-stall-check.test.sh`:
   - `gh` stub gains `issue view` (serves `--json state` per number) and
     `issue close` (records closes).
   - New behavioural arms executed against the real drain step body:
     merged target → issue closed; open target → kept; missing/unparseable
     title → kept; `gh issue view` failure → kept (fail-toward-keeping);
     list failure → fail-open `::error::`, no closes; cap notice at bound.
   - Structural rows: drain step exists with `if: always()`, no
     `continue-on-error`, no `${{ }}` in its run body, `-L 50` bound present.
   - Bump `EXPECTED_PASSES` for the added rows.
3. Run both suites → RED (the check step and drain step do not exist yet).

### Phase 2 — Dispatcher check (Part A)

- Implement `check-previous-run` per Part A, inside the existing mint +
  dispatch flow; update the header's Liveness paragraph (a green check-in
  now means "dispatched AND the previous executor run was not red/stuck").
- Re-run the vitest suite → GREEN.

### Phase 3 — Drain step (Part B)

- Add the `Drain stale stall issues` step to
  `.github/workflows/merge-queue-stall-check.yml` per Part B.
- Re-run the workflow suite → GREEN.

### Phase 4 — M7 hardening (Part C)

- Add `bump360.sh` fixture, map `three_bump` to it, raise the arm's ceiling
  to 300, and replace the M7 failure line with the self-describing dump.
- Re-run `scripts/test-all-runtime-ceiling.test.sh` → GREEN (all 23 arms).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` — add `check-previous-run` step + heartbeat verdict composition + header liveness paragraph.
- `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts` — endpoint-routed Octokit mock, new verdict arms, updated call-order assertions.
- `.github/workflows/merge-queue-stall-check.yml` — add the `Drain stale stall issues` step (`if: always()`).
- `plugins/soleur/test/merge-queue-stall-check.test.sh` — `gh` stub `issue view`/`issue close`, drain behavioural + structural rows, `EXPECTED_PASSES` bump.
- `scripts/test-all-runtime-ceiling.test.sh` — `bump360.sh` fixture, `three_bump` ceiling 300, M7 self-describing failure dump.

## Files to Create

- None. (The `bump360.sh` fixture is synthesized inside the test's
  `build_sandbox`, like `bump.sh` — not a committed file.)

## Explicitly NOT in this diff

- No secrets, env vars, or grants added anywhere — the executor runner stays
  secretless; the dispatcher's mint keeps `actions:write` pinned to this repo.
- No `terraform apply`, no `apply-*` workflow dispatch, no infra mutation.
- No change to `STALL_THRESHOLD_MINUTES`, `MAX_ENTRIES_TO_BUILD`, the queue
  GraphQL query, the issue-filing path, or the dispatch cadence.
- No `pull-requests` permission widening.
- No new registered suites (both test files already run in the battery).

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator either gets
  paged for a healthy executor (false page fatigue) or keeps missing red
  runs and stale stall issues (status quo). No end-user surface exists.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing new — the runs-list read and issue-state read travel over the
  existing GitHub API edge with the existing grants; no user data is
  touched, stored, or emitted beyond run ids and issue numbers the repo
  already files.
- **Brand-survival threshold:** none
- threshold: none, reason: internal CI observability and test-harness change
  with no user data, credentials handling beyond the existing token mint, or
  user-facing surface.

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in on monitor scheduled-merge-queue-stall-dispatch — ok when the dispatch POST succeeded AND the previous executor run was not red/stuck/unreadable; error otherwise
  cadence: every 10 minutes (crontab "*/10 * * * *"), checkin margin 30 minutes
  alert_target: cron_monitor_failure alert workflow → org email (routed by #9511, detector 2359391)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (existing monitor) and apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts (SENTRY_MONITOR_SLUG)
error_reporting:
  destination: Sentry project soleur-web-platform via reportSilentFallback (feature cron-merge-queue-stall-dispatch, ops dispatch-workflow / check-previous-run); token-mint failures via the Inngest sentry-correlation middleware tagged inngest.fn_id
  fail_loud: Sentry issue "merge-queue-stall-dispatch <op> failed" with the installation token redacted; error-status check-in on the monitor
failure_modes:
  - mode: executor run concludes failure/timed_out/cancelled/startup_failure/action_required/stale
    detection: check-previous-run verdict failed → reportSilentFallback + error check-in
    alert_route: Sentry issue stream + monitor email
  - mode: dispatched run still non-completed ~11+ min after creation (runner-wait gap)
    detection: check-previous-run verdict stuck → reportSilentFallback + error check-in
    alert_route: Sentry issue stream + monitor email
  - mode: runs-list read itself fails (API fault, grant drift)
    detection: verdict unknown → reportSilentFallback + error check-in
    alert_route: Sentry issue stream + monitor email
  - mode: dispatcher stops firing (cron trigger lost, Inngest outage)
    detection: missed check-in after the 30-minute margin; scheduled-inngest-health pages the substrate outage itself
    alert_route: monitor email
logs:
  where: pino logger lines from the Inngest function to Better Stack via stdout; GitHub Actions run history; drain step ::notice::/::error:: lines in the workflow run log
  retention: Better Stack plan retention; GitHub Actions run history 90 days
discoverability_test:
  command: curl -fsS --max-time 10 "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/merge-queue-stall-check.yml/runs?per_page=1"
  expected_output: workflow_runs
```

## Guard Contract

### Guard 1 — executor-conclusion alerting (dispatcher check)

**Property.** Whenever the newest prior `merge-queue-stall-check.yml` run is
red (failure-class conclusion) or stuck (non-completed past the job's own
timeout), the next dispatcher tick emits an error-status check-in plus a
Sentry report — never a silent ok check-in.

**Assembly.** Exactly one production path feeds the monitor:
`cronMergeQueueStallDispatchHandler`'s `sentry-heartbeat` step. The
`check-previous-run` step is the chokepoint every verdict flows through; the
runs-list GET is the single read. There is no second alerting channel the
verdict could bypass (the workflow holds no Sentry secrets by design).

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Newest run `conclusion: "failure"` | RED — heartbeat must be `ok:false` + report fired |
| Newest run `status: "in_progress"`, `created_at` 20 min old | RED — `stuck` must page |
| `stuck` boundary off by one tick (threshold set above 10 min, e.g. 25 min) | RED — the ~10-min-old prior run must be `stuck`, not `pending` |
| Runs-list GET rejected (403/500) | RED — `unknown` must page (blind check is a failed check) |
| check-previous-run deleted from the heartbeat's `ok` composition | RED — a red executor reads green |

**Harness rows.** must-PASS non-canonical: `conclusion: "success"` (fresh
dispatch succeeds, ok heartbeat — differs from every RED fixture); `status:
"queued"` created 30 s ago (a legitimately starting run is `pending`, not
`stuck` — the boundary must not page healthy). must-RED harness row: a stub
that makes the runs GET throw proves the `unknown` path fires rather than
silently passing.

**Anchor.** The verdict reads the live GitHub Actions API — the check and
the thing it checks live on opposite sides of the API; a commit editing the
verdict table cannot fake a live conclusion.

### Guard 2 — stall-issue drain (executor sweep)

**Property.** An open `merge-queue-stall` issue whose filed `PR #N` is no
longer open is closed by the next sweep; an issue whose PR is still open —
or whose title carries no `PR #N pending` anchor, or whose state read fails —
is never closed by it.

**Assembly.** Every `merge-queue-stall`-labelled open issue, enumerated by
the label-scoped `gh issue list` (the chokepoint the filed title and the
dedupe anchor already share); one close decision per issue through the
`gh issue view --json state` read.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Target PR `MERGED` | issue closed (property holds) |
| Target PR `OPEN` | issue kept — a false close is the failure this row exists to catch |
| Title lacks the `PR #N pending` anchor | issue kept (hand-filed/renamed titles are not drained) |
| `gh issue view` fails for the target | issue kept — drain fails toward keeping, not closing |
| `gh issue list` itself fails | `::error::` + zero closes (fail-open sweep, retries next run) |

**Harness rows.** must-PASS non-canonical: an issue with `state=OPEN` target
kept while a `MERGED` sibling closes in the same sweep (the close decision
is per-issue, not per-verdict like the queue-health sweep). must-RED harness
row: a `gh` stub that makes `issue close` record its args proves the close
actually fires on the merged arm rather than the suite passing on a no-op.

**Anchor.** The drain compares a live issue list against a live PR-state
read — a commit weakening either read cannot fake the other side.

## Scope Check

### Ask Mapping

| Ask | Plan coverage |
|---|---|
| #9513 gap 1: dispatcher checks previous dispatched run's conclusion, error-status check-in, secretless | Phase 2 + Guard 1 (unfiltered runs list — superset of "dispatched only"; no secrets, no grant widening) |
| #9513 gap 2: self-close drain mirroring the queue-health label sweep conventions | Phase 3 + Guard 2 |
| #9475 (a): re-derive whether M7's environment changed | Research Insights §M7 environment (derived: registration splices exclude the merges; affected pre-pass degrades to full via index-missing and precedes `_RUN_START_EPOCH`) |
| #9475 (b): ~50-iteration loaded reproduction | Research Insights §reproduction attempt (100 iterations, two load shapes, zero failures) |
| #9475: tighten failure diagnostics if no repro | Phase 4 (self-describing M7 failure dump + margin hardening) |
| `Closes #9513` and `Closes #9475` in the PR body | ship-phase deliverable |

### Plan-Item Provenance

| Item | Source |
|---|---|
| `check-previous-run` step + verdict table | Issue #9513's stated preferred fix ("the dispatcher checks the previous dispatched run's conclusion through the actions:write token it already holds") |
| `stuck` verdict (>11 min non-completed) | Issue's "which also covers the runner-wait gap" + workflow `timeout-minutes: 10` |
| Unfiltered runs list | inferred — a schedule-fallback red run is the same alert gap (stated as a superset deviation) |
| Drain step, `if: always()`, `-L 50`, sanitized `::error::` | Issue's "mirroring the queue-health label sweep" |
| `gh issue view` for target state | inferred — equivalent read under existing grants (verified); `gh pr view` rejected as a grant widening |
| ceiling 300 / bump 360 | inferred — closes the one reachable contention shape (real elapsed ≥ ceiling before `bumpfixture`) without weakening the property |
| Self-describing M7 failure dump | Issue's "make sure the arm log is preserved/dumped on failure" |

### Split Assessment

Both issues are CI/workflow maintenance touching the same stall-check
subsystem plus one test file — one PR is appropriate (single reviewer
context, one CI cycle). The dispatcher check and the drain are separable but
jointly close one issue; the M7 row is independent but trivially small.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200) contains no
issue whose body names any of the five files to edit.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI observability and test-harness
change.

## Architecture Decision (ADR/C4)

None required. The change extends the existing dispatch-hybrid pattern
(ADR-030/ADR-033/ADR-270): the dispatcher already holds the `actions:write`
edge to GitHub, the executor already runs secretless — no ownership,
tenancy, substrate, or trust boundary moves. C4: checked — the GitHub
Actions API edge is already modeled for this function's dispatch call; no
new external actor, system, container, or relationship is introduced.

## Acceptance Criteria

### Functional Requirements

- FR1: `cronMergeQueueStallDispatchHandler` performs a `check-previous-run`
  step before dispatching, calling
  `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs` with the
  existing `actions:write` token.
- FR2: newest prior run `conclusion` in
  `failure|timed_out|cancelled|startup_failure|action_required|stale` →
  `reportSilentFallback` (run id/conclusion/url in `extra`, token redacted)
  and the heartbeat posts `ok:false`.
- FR3: newest prior run `status != "completed"` with `created_at` older than
  11 minutes → verdict `stuck` → same report + `ok:false` heartbeat; a
  younger non-completed run → `pending` → heartbeat `ok: dispatch.ok`.
- FR4: runs-list GET failure → verdict `unknown` → report + `ok:false`
  heartbeat; the step never throws.
- FR5: empty `workflow_runs` → `none` → heartbeat `ok: dispatch.ok`.
- FR6: the drain step (`if: always()`) enumerates open `merge-queue-stall`
  issues via label-scoped `gh issue list --json` (no `--jq --arg`), extracts
  `PR #N` via standalone-jq `capture("PR #(?<pr>[0-9]+) pending")`, and
  `gh issue close`s the issue only when `gh issue view <pr> --json state`
  returns a non-empty state ≠ `OPEN`.
- FR7: drain failures fail toward keeping: list failure → sanitized
  `::error::` + no closes; state-read failure or unparseable title → that
  issue kept; `gh issue close` failure → `|| true` continue.
- FR8: `-L 50` bound on the drain enumeration with a cap-hit `::notice::`.
- FR9: M7 arm ceiling/bump raised to 300/360 with a synthesized `bump360.sh`
  fixture; the `declined_suites=2` assertion is unchanged.
- FR10: on M7 failure the row prints the arm rc, the bump file path and
  contents, and a bounded tail of the arm log.

### Non-Functional Requirements

- NFR1: no new secrets, grants, or permissions anywhere; the workflow keeps
  exactly `contents:read + issues:write`; the mint keeps
  `permissions: {actions: "write"}`.
- NFR2: no `continue-on-error` and no `${{ }}` interpolation inside any
  `run:` body (suite-pinned invariants).
- NFR3: all new dispatcher logic inside `step.run` (replay-safe).
- NFR4: the `three_bump` arm still exits `rc=3` with `declined_suites=2` on a
  healthy run — margin change does not alter verdict semantics.
- NFR5: `EXPECTED_PASSES` in `merge-queue-stall-check.test.sh` updated to
  the new exact count; the vitest suite's request-call assertions updated
  for the added GET.

### Quality Gates

- `bash scripts/test-all-runtime-ceiling.test.sh` — all arms green.
- `bash plugins/soleur/test/merge-queue-stall-check.test.sh` — all rows
  green at the new pass floor.
- `cd apps/web-platform && <repo's vitest invocation for>
  test/server/inngest/cron-merge-queue-stall-dispatch.test.ts` — green.
- `bash scripts/test-all.sh --affected` green before push.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- AT1 (vitest): runs GET → newest `conclusion=failure` → heartbeat `ok:false`
  + one `reportSilentFallback` with the run's id/conclusion/url; result
  `ok:true`; dispatch POST still fired.
- AT2 (vitest): newest `status=in_progress` 20 min old → `ok:false` +
  report; newest `status=queued` 30 s old → `ok:true`; empty list →
  `ok:true`; GET throws → `ok:false` + report.
- AT3 (vitest): replay fake — three handler passes produce exactly one runs
  GET, one dispatch POST, one heartbeat.
- AT4 (workflow suite): drain arms via `gh` stub — merged → closed; open →
  kept; title without anchor → kept; view-fail → kept; list-fail →
  `::error::` + no closes.

### Regression Tests

- Existing dispatcher arms (mint scope, dispatch params, transient retry,
  mint-failure heartbeat, replay) updated for the added GET and still green.
- Existing workflow-suite arms (file/dedupe/position filter/null queue)
  unchanged and green.
- M7 + the full ceiling suite green at the new margin; the mutation battery
  unchanged and green.

### Edge Cases

- Previous run `conclusion: "skipped"`/`"neutral"` → treated as ok-class
  (not a red run).
- A manually dispatched run mid-flight → `pending`, judged next tick.
- Drain sees >50 labelled issues → cap notice, remainder drains next sweep.
- An issue titled `… PR #1 pending` vs PR #12 — the `pending` suffix in the
  anchor prevents prefix collision (same trap the dedupe anchor documents).

### Integration Verification

- Post-merge: the next dispatcher tick posts one check-in whose status
  reflects `dispatch.ok && previousRun in {ok,pending,none}` — observable in
  the monitor's check-in history and the pino log line.
- Drain dry evidence: the stub-driven suite arms prove the close path; a
  real drain is observable in the next workflow run log when a stale
  `merge-queue-stall` issue exists.

## Success Metrics

- A deliberately failed `merge-queue-stall-check.yml` run produces an
  error-status check-in + Sentry issue within one tick (~10 min).
- Open `merge-queue-stall` issues self-close within one sweep (~10 min) of
  their target PR leaving `OPEN`.
- Zero M7 flakes attributable to the pre-first-suite elapsed window
  (300 s margin vs 60 s); any residual failure prints rc + bump + log tail.

## Dependencies & Risks

- **False-page risk:** a persistent executor failure now pages every 10 min
  (same cadence class as the queue-health UNDER_ASSIGNED page — accepted by
  design; the monitor routing is #9511's). Mitigant: `pending`/`none` never
  page.
- **Boundary risk:** the 11-min `stuck` threshold sits just above the job's
  own 10-min timeout, so a merely-late run is never paged; a genuinely stuck
  run pages at most one tick late.
- **API-shape risk:** the runs-list `workflow_id` accepts the file basename
  (same endpoint family as the dispatches POST — pinned by a suite row).
- **TDD risk:** the vitest mock must route by endpoint; a single
  `requestSpy` serving both calls would pass vacuously — the mock keys on
  the endpoint string, and call-order is asserted.
- **Drain risk:** a bad `capture` could close nothing (fail-safe) or, worse,
  the wrong issue — the anchor includes the literal ` pending` suffix and
  the state read is per-target, so a malformed title cannot reach a close.

## Sharp Edges

- `gh --jq` does not forward `--arg` (#9533) — every `--arg`-bearing filter
  runs in standalone jq downstream of `--json`.
- No `grep -q` inside pipelines feeding a verdict (pipefail early-exit
  class); greps read files or standalone variables.
- `gh issue view` on a PR number returns `MERGED`/`CLOSED`/`OPEN` — do not
  substitute `gh pr view` (grant widening) or the issues API `state` alone
  where `MERGED` must be distinguished (it need not be here).
- The check runs **before** dispatch deliberately: afterward, the just-POSTed
  run races into the list and "previous" becomes ambiguous.
- `EXPECTED_PASSES` is an exact floor — adding rows without bumping it reds
  the suite; bumping it without rows is the vacuity it exists to catch.
- The M7 failure dump must include the arm's `rc` — a `137` (OOM-kill) reads
  differently from a clean `3`.
- A plan whose `## User-Brand Impact` section omits the threshold or
  scope-out fails deepen-plan Phase 4.6 — both are present above.

## References & Research

- Issue bodies: #9513 (two gaps), #9475 (M7 flake + repro guidance).
- `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts` (dispatcher, heartbeat, dispatch step).
- `.github/workflows/merge-queue-stall-check.yml` (executor, filing shape, permissions).
- `.github/workflows/scheduled-actions-queue-health.yml` (the sweep/dedupe conventions to mirror).
- `plugins/soleur/test/merge-queue-stall-check.test.sh`, `apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts` (harnesses to extend).
- `scripts/test-all-runtime-ceiling.test.sh` + `scripts/test-all.sh` lines ~1600-1690, ~3350-3760, ~4000-4410, ~6380-6513 (M7 mechanics, affected pre-pass, ceiling state, epilogue).
- ADR-270 item 10 (the tracked gap); #9511 (monitor routing); #9533 (`gh --jq --arg` non-forwarding); #9525 (pipefail early-exit class); #9454 (threshold vs timeout).
- Merges re-derived for task (a): ff423af67d, f372c32ba1 (registrations only), 333d07691f, a72890adae, 2cfef66506 (affected derivation; sandbox-inert via index-missing).
