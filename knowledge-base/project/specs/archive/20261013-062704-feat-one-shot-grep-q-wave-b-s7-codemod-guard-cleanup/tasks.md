# Tasks: S7a codemod and guard cleanup (tracker #9217, Ref only)

Plan: knowledge-base/project/plans/2026-10-11-chore-grep-q-wave-b-s7-codemod-guard-cleanup-plan.md

## Phase 0 Red first

- 0.1 In a clean checkout (empty `git status --porcelain`), add the new probe rows M1 to M14 to a scratch copy of the guard and run it under `ulimit -v 6000000`; record each FAIL reason in evidence.md.

## Phase 1 Rows (D2)

- 1.1 Replace the two glob rows with six file-exact `=` rows (1, 4, 1, 1, 1, 2).
- 1.2 `_ts_re`: drop the `scripts/(lib/)?test-*` alternative; add the glob-free `.test.sh` and `^plugins/soleur/test/` exact-path alternatives; keep the glob alternatives and the `tests_rows` check.
- 1.3 Set `GATED_TEST_ROWS` to the six exact paths in table order; update the row commentary (rename cost, stale-row wording).
- 1.4 Guard prints twelve `DEFERRED:` lines; production rows unchanged.

## Phase 2 Test canaries (D3)

- 2.1 Add `SWEEP_TEST_CANARIES` (nine tracked paths after review) with a pinned count and the selection rule comment.
- 2.2 Add one probe check listing the real tree with `SWEEP_PATHSPEC` (rc above 1 is UNRESOLVED, exit 3); message says "canary moved: update SWEEP_TEST_CANARIES, not the sweep".

## Phase 3 Wiring pins (D4)

- 3.1 Add one probe check for the anchored `sweep_main ... || sweep_rc=$?` and `sweep_fold "$sweep_rc"` statements, patterns anchored at column 0; message names protects, expects, fix.

## Phase 4 Deletion (D1)

- 4.1 `git rm scripts/grep-q-drain-codemod.py`; delete base guard lines 1051 to 1391.
- 4.2 Recompute `SWEEP_PROBE_CHECKS` from the file; run the guard.

## Phase 5 Wording (D5)

- 5.1 Rewrite header and row commentary to the S7a state; add the one-line recompute command; do not say the series is finished.

## Phase 6 Evidence and ship

- 6.1 Run mutation rows M1 to M14 and harness rows H1 to H6 one at a time under `ulimit -v 6000000` on a scratch clone; record results in evidence.md.
- 6.2 Cheap repo-global lints (plan AC-8).
- 6.3 decision-challenges.md; learning if a non-obvious finding occurs.
- 6.4 PR body per AC-9; `soleur:ship`; tracker comment per AC-10.
