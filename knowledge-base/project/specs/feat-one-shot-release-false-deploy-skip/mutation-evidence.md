# Mutation evidence — resolve-target empty-lookup fix

Run once at work time (2026-09-24) against commit 4e0e6ccbba in a detached scratch worktree. Each row restores the tree to HEAD, applies the mutation(s) with `mutate.py` (exit 3 = anchor absent = NOT LANDED), proves it landed by diffing the PyYAML-extracted `resolve-target` checkout + `resolve` steps against the pristine file, then runs both suites. Bracketed ids are the rows present in each suite's `FAILURES`.

| row | mutation(s) | landed | CONTROL | decision suite | invariants suite |
|---|---|---|---|---|---|
| BASELINE |  | region lines changed: 0; suite: 0 | pass | decision rc=0 [] | invariants rc=0 [] |
| G1-M1 | G1-M1 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L1 L1b L6 L6b L8 L8b ] | invariants rc=1 [G9 ] |
| G1-M2 | G1-M2 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L6 L6b ] | invariants rc=0 [] |
| G1-M3 | G1-M3 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L1 L1b L2 L2b L2c L2d L6 L6b L8 L8b S1b ] | invariants rc=0 [] |
| G1-M4 | G1-M4 | region lines changed: 2; suite: 0 | pass | decision rc=1 [A1 A1b A2 A2b F1 F2 F3 F4 F5 F6 L2 L2b L2c L2d L3 L3c L3d L6b L7 L7b S1b S2 X1 X1b X2 X2b ] | invariants rc=0 [] |
| G1-M5 | G1-M5 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L1 L1b L8 L8b ] | invariants rc=1 [P1 ] |
| G1-M6 | G1-M6 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L1b L5 L8b L9 S1 ] | invariants rc=0 [] |
| G1-M7 | G1-M7 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L8 L8b ] | invariants rc=0 [] |
| G1-M8 | G1-M8 | region lines changed: 1; suite: 0 | pass | decision rc=0 [] | invariants rc=1 [P2 ] |
| G2-M1 | G2-M1 | region lines changed: 2; suite: 0 | pass | decision rc=1 [L2 L2b L2c L2d S1b ] | invariants rc=0 [] |
| G2-M2 | G2-M2 | region lines changed: 2; suite: 0 | pass | decision rc=1 [A2 A2b L3 L3b L3c L3d X2 X2b ] | invariants rc=1 [G8 ] |
| G2-M3 | G2-M3 | region lines changed: 2; suite: 0 | pass | decision rc=1 [A2 ] | invariants rc=0 [] |
| G2-M4 | G2-M4 | region lines changed: 2; suite: 0 | pass | decision rc=1 [X2 X2b ] | invariants rc=0 [] |
| G2-M5 | G2-M5 | region lines changed: 2; suite: 0 | pass | decision rc=1 [X2 X2b ] | invariants rc=0 [] |
| G2-M6 | G2-M6 | region lines changed: 2; suite: 0 | pass | decision rc=1 [X2 X2b ] | invariants rc=0 [] |
| G2-M7 | G2-M7 | region lines changed: 2; suite: 0 | pass | decision rc=1 [A1c A2b ] | invariants rc=0 [] |
| H1+G1-M5 | H1 G1-M5 | region lines changed: 2; suite: 1+/1- | pass | decision rc=0 [] | invariants rc=1 [P1 ] |
| H3+G2-M3 | H3 G2-M3 | region lines changed: 2; suite: 1+/2- | pass | decision rc=1 [A2 ] | invariants rc=0 [] |
| H5 | H5 | region lines changed: 0; suite: 0+/1- | pass | decision rc=1 [L1b L5 L8b L9 S1 ] | invariants rc=0 [] |

**Readings.** Every Guard 1 (M1–M8) and Guard 2 (M1–M7) mutation is killed by the row the plan named (L1, L6, L1, L7, P1+L1, S1, L8, P2; L2, L3, A2, X2 ×3, A2b), with CONTROL passing in every row. H1: hardcoding the pathspec in the harness makes G1-M5 invisible to the decision suite (rc 0); only P1 still sees it, which is why the harness reads the YAML. H5: dropping the `cd` into the fixture clone flips S1/L5/L9 without any workflow mutation. **H3 deviated from the plan:** reverting `get()` to `head -1` and dropping the one-verdict count did NOT revive G2-M3, because A2's exact `rc -eq 1` assertion kills it independently (the mutant ends rc 0). The count assertion is therefore a second, not a sole, kill for that mutant.
