# Tasks — feat-one-shot-10862-norun-investigation

Plan: `knowledge-base/project/plans/2026-11-08-ci-s4-replay-norun-cause-hardening-plan.md`
Issue: #10862 | PR: #12377

## Phase 1 — Cause receipt

- [x] 1.1 Re-run the discriminating reads and write `receipts/cause.md` (H4 verdict,
  per-hypothesis dispositions, embedded command output; the ejections-listing residual named).

## Phase 2 — ci_runs corroboration + tests

- [x] 2.1 `scripts/ci-pr-affected-replay.py`: `head_sha_runs`, `corroborating_runs`,
  `ci_runs -> (runs, via)`; `cmd_collect` records `runs_via`; docstring `not-evaluable` line.
- [x] 2.2 Test suite: `ONCE_` stub arm + `fx_once`; fixtures (a)-(f); assertions incl.
  `runs_via`, REQ counts; mutate rows (drop-corroboration, wrong-sha-run, swallow-error);
  `DECLARED_TOTAL` updated.
- [x] 2.3 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` green.

## Phase 3 — Runbook

- [x] 3.1 `ci-pr-affected-activation.md` §4: corroborated `no-run` semantics + `runs_via`.

## Phase 4 — Evidence re-run + receipts

- [x] 4.1 `collect --commits 300 --chunk I/4 --base origin/main` (4 parallel chunks).
- [x] 4.2 `ejections --commits 300 --base origin/main`.
- [x] 4.3 `aggregate --expect-commits 300 --out replay-summary.txt`; `verdict --a fail
  --b unmeasured --c unmeasured --d unmeasured` → `NO-GO criterion-failed` (bound arm).
- [x] 4.4 Commit receipts under `receipts/rerun/` (commands, summary, window meta, histograms).

## Phase 5 — Verify before ready

- [x] 5.1 `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 on this branch
  (`exit=0 reason=pass`; accept row folded into the commit carrying the literal it covers).
- [x] 5.2 Live smoke: `collect --commits 2` resolves units with `runs_via` set.
