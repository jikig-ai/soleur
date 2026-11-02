# Tasks — feat-one-shot-10724-mutation-survivor

Plan: `knowledge-base/project/plans/2026-10-22-test-scan-hidden-join-mutant-survivor-plan.md`
Issue: #10724 — kill the `scan-hidden-join-and-find-per-scan` mutant deterministically.
Sole file edited: `plugins/soleur/test/ci-pr-affected-replay.test.sh`. Zero SUT diff (AC5).

## Phase 1 — Deterministic instrument in `row_scan_ops`

- 1.1 In the embedded Python of `row_scan_ops()` (~lines 955-1050), add the `_SeqProbe` (non-list sequence: `__len__` + `__getitem__` counting slices + `__iter__` counting, no `__getattr__` delegation) and `_SetProbe` (set subclass counting `__iter__` only) classes per the plan's Proposed Solution block.
- 1.2 In `traced()`, immediately after `idx = m.PathIndex(tracked)`, install `idx.paths, idx.tracked = _SeqProbe(idx.paths), _SetProbe(idx.tracked)`; after the `m.scan_text(idx, text)` call, read `idx.paths.hits + idx.tracked.hits` and append a named-fixture entry to `bad[]` on any nonzero count.
- 1.3 Verify RED on the mutant before GREEN: build a mutant copy of `scripts/ci-pr-affected-replay.py` applying the `scan-hidden-join-and-find-per-scan` edit (line 2543's old→new), run `row_scan_ops` against it via `SUT=<copy>`, and confirm the row exits non-zero naming the materialization — repeat 5x (deterministic, no clock).
- 1.4 Verify GREEN on pristine: run `row_scan_ops` against the real SUT; probe hits must be 0 across every fixture.
- 1.5 Update the instrument prose in the same edit: header block ~lines 27-28, the three-instrument comment ~lines 947-952, and the `pass` text ~line 1056 — name all four instruments (ops, line events, materialization probe, CPU time).

## Phase 2 — Battery extension + floors

- 2.1 Append two `mutate` rows immediately after the `scan-hidden-join-and-find-per-scan` block (~line 2544), verbatim from the plan: `scan-hidden-sorted-tracked-per-scan` (`"\n".join(sorted(index.tracked))`) and `scan-hidden-tuple-paths-per-scan` (`tuple(index.paths)`), both on `row_scan_ops`.
- 2.2 Re-measure and bump literals in the same commit: `FLOOR_MUTANTS` 298 → 300, `FLOOR_ASSERTIONS` 712 → measured value after the suite run (expected +3: two `mutant … is killed` passes plus any added control; measure, do not guess). Update the trailing comments that document the arithmetic.
- 2.3 Confirm `SITES_MUTATE` reconciliation holds: `grep -c '^mutate '` equals `MUT_RUN` at runtime (the file's own invariant prints a FATAL otherwise).

## Phase 3 — Verification & ship checks

- 3.1 Full suite: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` → `mutants killed 300 of 300`, `N passed, 0 failed`, exit 0.
- 3.2 Zero-SUT-diff check: `git diff origin/main...HEAD -- scripts/ci-pr-affected-replay.py` is empty (AC5).
- 3.3 Negative-control spot check: a scratch copy of the row with the probe-install line commented out must let the join mutants survive (proves the instrument is load-bearing — Guard Contract row 3).
- 3.4 `npx markdownlint-cli2` clean on plan + tasks.md + decision-challenges.md; commit artifacts (`docs: create plan and tasks for feat-one-shot-10724-mutation-survivor` pattern used for plan artifacts; implementation commits per `soleur:work`).

## Notes

- Collision watch: PR #10851 edits this file at old ~2114/`row_rt_*`, ~2668 and ~2740 plus the SUT; keep edits inside the regions named in the plan's Files to Edit; if the sibling merges first, re-anchor by content (`row_scan_ops()`, the `mutate` block tail, the `FLOOR_` literals) and re-measure floors on the merged file.
- Outstanding: the two `pending - assumed` rows in `decision-challenges.md` need a real `soleur:engineering:cto` spawn (the ship gate `technical-ruling-gate.sh` fails until each reads `Ruled by CTO agent, <date>: …`).
