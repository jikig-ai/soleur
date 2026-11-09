# Tasks: feat-one-shot-11544-monitor-required-wiring

Plan: `knowledge-base/project/plans/2026-11-08-feat-monitor-pr-checks-required-set-wiring-plan.md`
Refs: #11544 (monitor half only), #9927. PR body uses "Ref", never "Closes".

## Phase 0: Preflight (no edits)

- 0.1 Re-run the open code-review overlap query for the four Files-to-Edit paths; update the plan heading if a new scope-out appears.
- 0.2 Run the monitor suite once and record pass count and wall time (about 245 s); this fixes the new floor.
- 0.3 Run the three gates on the untouched tree (ratchet, fixture-env-adoption, grep-q-pipe-guard) and record green.

## Phase 1: Failing tests first

- 1.1 Add the W section to the monitor suite before the T7 block: resolver stub on `CI_HEAD_VERDICT_BIN` (replays the real `required` contract), `mkgate` helper (re-installs the argv-logging `gh` wrapper after every `mkqstub`).
  - 1.1.1 W1 happy path (with `--repo`), W2 hold (dwell 10, interval 10, max-polls 3)
  - 1.1.2 W3 to W5 gates, table-driven (auto-merge off, queue unknown, verdict not full-decided)
  - 1.1.3 W6 marker not exit code, W7 no marker and the timeout bound (detached `setsid sleep 8 &` holder that INHERITS stdout; a holder redirecting to /dev/null holds nothing), W8 timeout argv shape and absent binary
  - 1.1.4 W9 print-only (sentinel payload), W10 filter, candidate cap, decoy marker
  - 1.1.5 W11 budget shorter than the hold (default dwell), W12 unknown mid-hold keeps the hold and default resolver path, W13 seam validation
- 1.2 Run the suite: every W row red for the intended reason, T rows still green.

## Phase 2: Wiring in monitor-pr-checks.sh

- 2.1 Env seams `MONITOR_REQUIRED_DWELL_S`, `MONITOR_REQUIRED_TIMEOUT_S`, `MONITOR_REQUIRED_TIMEOUT_BIN` with exit-3 validation.
- 2.2 `read_required_set` (lazy `mktemp` file redirect, `-k 5 120`, prefix filter, candidate cap, one degraded line); `_cleanup` removes the file.
- 2.3 `blocked_since=""` next to `n=0; prev_sig=""; queue_seen=0`, the loop-top reset, and the BLOCKED arm (gates, `ci_verdict`, hold, feasibility check, carry-through of unknown reads, terminal with read).
- 2.4 Header and `--help` text.
- 2.5 W rows green; full suite green.

## Phase 3: Docs

- 3.1 `ready-run-wait.md`: one prose paragraph and one clause; no fenced block touched.
- 3.2 `ci-head-verdict.sh`: header comment, two lines.
- 3.3 Run `ci-head-verdict.test.sh` (R11, L1, L2), `monitor-lock.test.sh`, `sync-pr-behind.test.sh`.

## Phase 4: Gates and mutation checks

- 4.1 Ratchet, fixture-env-adoption, grep-q-pipe-guard; `bash -n`; shellcheck if installed.
- 4.2 Mutation checks (11 rows in the plan) on a scratch copy of the suite cut to the preamble plus the W section; each reverted after seeing the named row red.
- 4.3 Set the anti-vacuity floor to the exact measured count.
- 4.4 AC-9 scope diff against the merge-base with a positive control.
- 4.5 `technical-ruling-gate.sh --branch` and markdownlint on plan, tasks and decision-challenges.

## Phase 5: Ship

- 5.1 PR body: `Ref #11544`, `Ref #9927`, `## Changelog`, CTO row rendered. One comment on #11544 recording that the CLEAN-and-armed variant was descoped and that the Phase 7 poll remains.
- 5.2 CI (merge_group `test` leg) is the authority if the local affected-tests gate cannot finish under contention.
