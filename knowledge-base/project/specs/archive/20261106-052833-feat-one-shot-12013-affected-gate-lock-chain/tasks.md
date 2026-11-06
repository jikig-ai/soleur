# Tasks: affected-gate lock chain (Ref #12013)

Plan: knowledge-base/project/plans/2026-11-05-perf-affected-gate-lock-chain-plan.md
Rulings: knowledge-base/project/specs/feat-one-shot-12013-affected-gate-lock-chain/decision-challenges.md

Order is the CTO-ruled order: F4, F1, F2(b), measurement. Write each phase's failing guard arm (and drive its mutation rows
RED against a copy) BEFORE the code. Editing `scripts/test-all.sh` makes this PR's own local gate the full battery; expect a
long run, do not raise `budget_seconds`.

## Phase 0 - Setup

- [x] 0.1 Re-read the plan's Guard Contract (9 / 5 / 10 mutation rows) and `scripts/test-all-parallel-scheduler.test.sh` structure
  (sandbox builder, arms A1-A8). Confirm `lane_tokens_for` / `lane_tokens_conflict` / `_pj_*` line anchors by content, not number.
- [x] 0.2 Confirm #12128 state (it edits `scripts/lib/test-affected-paths.sh`; this PR must not).
- [x] 0.3 Record the exact derived token set of the three replay arms: `_lane_derive` output must be exactly `lock:test-all`.

## Phase 1 - F4: budget kill reports a visible red (first)

- [x] 1.1 Tests first in `plugins/soleur/scripts/affected-tests.test.sh` (Guard 3 arms 1-10, harness rows H1/H2); run them RED.
- [x] 1.2 `scripts/test-all.sh`: sidecar append (`label<TAB>rc<TAB>epoch`, epoch from `${EPOCHSECONDS:-$(date +%s)}`, rc 1..127, label
  scrubbed, skip when `_pj_sig==1`) in `_pj_fmt_done` and in the serial tail of `run_suite` guarded by `_pj_mode==0`;
  `export -n SOLEUR_PJ_PROVISIONAL_FILE` next to `SOLEUR_TEST_JOBS`, plus a count arm mirroring the A8 demotion pin. The
  kill-induced-exit arm must run in both pool and serial modes (the serial arm has no `_pj_sig` trap; the epoch filter is its only protection).
- [x] 1.3 `plugins/soleur/scripts/affected-tests.sh`: `affected_mktemp provisional`, env hand-over in BOTH branches of the runner
  call, the `124|137` mapping (record rc `10#`, 1..127, epoch before `AFFECTED_DEADLINE`), header exit contract.
- [x] 1.4 `plugins/soleur/scripts/lib/affected-tests/common.sh` reason catalog; one row in `affected-gate-contract.md`.
- [x] 1.5 One grep over the consumers (`grok-pre-push-gate.sh`, review reference, `workflow-fidelity.test.ts`); state the result.
- [x] 1.6 Drive each Guard 3 mutation RED on a copy; control green first.

## Phase 2 - F1: conservative backfill

- [x] 2.1 Tests first in `scripts/test-all-parallel-scheduler.test.sh` (Guard 1 arms 1-9, H1/H2; release-file ordering, frozen
  launch-order fixture recorded from `main`, conflict-call count arm).
- [x] 2.2 `_pj_fill` one-pass rule (running skipped-token union + any-earlier-queued flag; slot and live checks first; reuse
  `lane_tokens_conflict`); `SOLEUR_PJ_FIFO=1` read once in `_pj_resolve_run_mode`; header doc only.
- [x] 2.3 `_pj_drain` fill-until-empty loop with a no-progress guard.
- [x] 2.4 Drive each Guard 1 mutation RED on a copy.

## Phase 3 - F2(b): replay arms

- [x] 3.1 Tests first in `scripts/lib/test-suite-lanes.test.sh` (Guard 2 arms 1-5, H1/H2).
- [x] 3.2 `scripts/lib/test-suite-lanes.sh`: `_lane_derive` split (behaviour of `lane_tokens_for` unchanged), three empty-token
  `lane_declare` entries with reasons.
- [~] 3.3 Concurrent-run audit of the three arms; record load and result (observation).

## Phase 4 - Measurement and ADR

- 4.1 Private checkout with its own git-common-dir (not the operator's `measure-clone-r1`; not a ship path); replay pick
  `7af192071d` at base `8cc167c2e3`; 2 cold readings + 1 `SOLEUR_PJ_FIFO=1` control, same session; record loadavg and heavy
  processes at start. Commit TSVs under `specs/feat-one-shot-12013-affected-gate-lock-chain/measurements/`.
- 4.2 ADR-242 amendment via `soleur:architecture`: backfill rule and knob, F2 override, sidecar contract and reason, measured
  table, lever-3 re-evaluation (measured cold-derive share vs 25 percent), follow-ups #12151 / #12152. Weights in the ledger only.
- 4.3 `bash plugins/soleur/test/c4-count-parity.test.sh`.

## Phase 5 - Ship

- 5.1 PR body `Ref #12013` (no Closes); measured gap stated; 600 s not claimed; operator leftover (delete
  `/data/git-repositories/jikig-ai/measure-clone-r1`) under "Needs you".
- 5.2 After merge: comment the result on #12013; leave it open.

## Execution notes (work phase)

- 2.1/2.4: the starvation arm of Guard 1 was removed. `_pj_submit` blocks while the pool is saturated, so the queue never holds an
  independent suite beside a token-ready head when a slot frees; an order-preserving head-last mutant survives and is equivalent.
  Head-first is pinned by the order-among-conflicting and barrier arms (a reordering head-last mutant reds both).
- 1.6/2.4/3: mutation rows driven RED on copies: Guard 3 M1/M2/M3/M6a/M6b/M9/M10 (gate side) and M4/M5/M7 plus the interrupted-run row
  (runner side; the interrupted-run guard line survives as defense in depth, the observable is pinned); Guard 1 M1/M2/M3/M4/M5/M8/M9/M10/M11;
  Guard 2 M1/M2/M3/M5.
- 3.3: the concurrent-run audit of the three arms is recorded with the measurement (the readings run them concurrently).
