# S4 evidence (work phase)

Base SHA `01d2b5a0d840d2ec5fc5b43851d1540726ea97cb`; branch HEAD at write time is the second S4 commit. Every line below was read from command output on this branch. The long local `--affected` gate, the ratchet-lane re-run, `guard-vacuity-floor`, the orphan and capture-exit lints and the markdown/discoverability re-measure were not run locally: the host sat at load 25 to 33, and CI's required `test` check runs the full battery on this head (the user's standing decision).

- Drain probe (host grep and `ubuntu:24.04`): `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1` on both.
- Red step: row lowered to `<= 26` gave `FAIL: deferral ceiling exceeded: tests/* has 181 hits, ceiling 26`, rc 1. After the codemod passes: `DEFERRED: tests/* (25 hits, ceiling 26 ...)`, rc 0. After all 181 lines: `0 hits`, `stale deferral`, rc 1, which is the signal to delete the row.
- Final guard: rc 0, 10 `DEFERRED:` lines, none for `tests/`, `grep-q-sweep-probe-pass`. Guard diff vs merge base: 6 added, 7 removed (the plan's rehearsal said 7 and 7; the row is the 7th removal).
- `verify --base 01d2b5a0d8`: `verified: 174`, `hand-edited: 7`, `unexplained: 0`. 23 files, 181 insertions and 181 deletions under `tests/`. The 26 base-side lines changed outside the codemod passes equal `hand-edits.txt` plus `data-conversions.txt` (compared by command).
- Trigger derivation: 18 path-filtered and 7 unfiltered push workflows; 0 of 30 edited paths match any filtered one.
- Fixed-fragment search of the 157 distinct fragments outside `knowledge-base/`: 4 generic lookalike hits in other suites, no pin of a `tests/` line.
- Pair run (real detached clone at the base SHA, `node_modules` linked, sequential, `ulimit -v 6000000`): 28 suites (23 owning, 5 adjacent), all 28 read identical rc and final line on both sides.
- Guard 1 matrix (scratch clone, green control first, `cmp` landing check, restore clean after every row): rows 1a to 1c, 2a to 2d, 3, 4, 5, 6a to 6h, 7, 8, 9, 10c, 10d, 11 killed with the named FAIL text; 6i, 10a, 10b GREEN as predicted; 10e, 12, 14, 15 (`.bash`, `.bats`, `.yaml`, `.template`) survive as predicted (known holes); row 13: `unexplained: 1` for both mutants.
- Observer table: 18 of 21 lines killed by at least one mutant; 1087, 1723, 1725 survive both mutants (unobserved by their suite); inversion survives on 182, 183, 184, 197, 198, 199, 206, 1718, 1721, 1727; `test-tmp-purge.sh:300` inversion killed, never-match survives; `test-audit-ruleset-bypass.sh:848` both killed.
- `-m` display: old and new expression print the same on a populated (first match on line 2), an empty and a no-match input.
- Line 1274 reverted alone: suite stops with rc 1 right after `T-mq-ctl5`, no summary line. W2 fixture line 2971 converted instead of marked: `=== 258 passed, 1 failed ===` (W2-control).
- Ratchet lane (`pre-push-ratchet-lane.sh`, 23 members): one red, `test-git-data-birth-readiness-gate` TIMEOUT at the 300 s cap under load 25 or more; its pair-run result is identical to base (259 passed). Not re-run locally; CI is the gate.
