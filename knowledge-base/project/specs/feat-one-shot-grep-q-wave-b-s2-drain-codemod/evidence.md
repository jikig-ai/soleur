# Evidence: grep -q drain, Item B slice S2

Source for the PR body and the tracker comment. Every number below was printed by the command named beside it on 2026-10-08, base `origin/main` 425ea0fc1f.

## Guard rows (`bash .claude/hooks/grep-q-pipe-guard.test.sh`, rc 0 both times)

| Row | Before | After |
|---|---|---|
| `plugins/soleur/test/*` | 140 hits, ceiling 140, mode `<=` | 5 hits, ceiling 5, mode `=`, slack 0 |
| the other twelve `DEFERRED:` lines | unchanged | byte-identical (`diff` of the two sets is exactly the one row) |
| test-shaped total (sum of the seven test rows) | 702 | 567 |

## Transform proof

**Units.** The guard counts lines (140 before, 5 after); the codemod census counts hits (144 hits on those 140 lines). The change is 131 codemod lines in 45 files plus 5 hand-edit lines in 4 files, with one line shared (`web-host-escrow-diagnose-workflow.test.sh:710`) and one file added by hand edits (`worktree-manager-porcelain-sigpipe.test.sh`): 131 + 5 - 1 = 135 lines, 45 + 1 = 46 files. `verify` reports 130 verified because the shared line counts as hand-edited.

`python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits <hand-edits.txt>`: `verified: 130`, `hand-edited: 5`, `unexplained: 0`. Idempotency dry run: `WOULD-CHANGE: 0 lines in 0 files`. `bash -n` clean on all 46 files. `git diff --numstat origin/main...HEAD -- plugins/soleur/test/`: 135 insertions, 135 deletions. `verify` proves the transform, not the classification (a data line converted by mistake still passes it).

## Drain probe (Phase 0 gate)

`bash -c 'set -o pipefail; (echo 1; sleep 0.4; echo 2) | grep -q 1; ...'` prints `q: 141`, `c: 0`, `nomatch: 1` on GNU grep 3.12 (dev host) and on GNU grep 3.11 inside `ubuntu:24.04`.

## Trigger derivation (46 files against every push-to-main workflow filter)

Among path-filtered workflows only `version-bump-and-release.yml` matches (46 of 46): one plugin patch release. `web-platform-release.yml`, `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` match nothing. The seven unfiltered push workflows (`ci`, `codeql-main-alert-gate`, `secret-scan`, `skill-security-scan-corpus`, `skill-security-scan-postmerge`, `tenant-integration`, `vendor-pin-verify`) run on every merge and are not caused by this change. Open-PR intersection with the 47 edited files (the 46 test files plus the guard): empty.

## Guard 1 mutation battery (scratch copy, one mutant at a time, `ulimit -v 6000000`, green control first, restore check clean)

| # | Mutation | Result |
|---|---|---|
| 1 | append one hit (`git-tripwire`) | KILLED: `has 6 hits, ceiling 5` |
| 2 | revert one converted site (`worktree-manager-atomic-config:280`) | KILLED: `has 6 hits, ceiling 5` |
| 3 | ceiling 6 over 5 hits, mode `=` | KILLED: `deferral ceiling is loose ... lower the ceiling to 5` |
| 3c | same edit, mode `<=` (control) | GREEN rc 0, which is why the row is `=` |
| 4 | S2 row swapped below `plugins/soleur/*.test.sh` | KILLED: `plugins/soleur/*.test.sh has 70 hits, ceiling 66` |
| 5 | empty `SWEEP_DEFERRALS` | KILLED: `outside the deferral table (590 site(s))` |
| 6 | hits in two files | KILLED: `has 7 hits, ceiling 5` |
| 7 | hit in a converted-line spelling | KILLED: `has 6 hits, ceiling 5` |
| 8 | remove one counted pin (`deploy-arm:676`), add a hit elsewhere | GREEN: add-one-delete-one, the known surviving mutant |

Axes this battery did not edit: the guard's pattern (`PATTERN_V2`), `SWEEP_PROBE_CHECKS`, and the `_ts_re` row-shape check (S1 and S7 own them).

## Hand-edit evidence

- `roadmap-reconcile.test.sh:274`: control 109 passed; with `grep -vc` instead: `FAIL: SIGTERM mid-fetch ends the run (expected [143] got [2])`, 108 passed 1 failed.
- The two `grep -m1` displays (`git-tripwire:124`, `web-host-escrow-diagnose-workflow:710`), old and new expression on a three-line input whose first match is on line 2: identical output (`unset GIT_TEMPLATE_DIR && x` and `g2`).
- `worktree-manager-porcelain-sigpipe.test.sh`: the stub-git line carries `# sigpipe-demo: intentional` (not counted; the suite passes 0 failed on both sides), the A6 banner is reworded and its assertion is unchanged.

## Ratchets and linters (all rc 0)

`bash scripts/pre-push-ratchet-lane.sh`: `verdict=PASS members=23 red=0`. `bash scripts/guard-vacuity-floor.test.sh`: 23 passed, 0 failed. `bash scripts/lint-orphan-test-suites.sh`: none. `python3 scripts/lint-shell-capture-exit.py --baseline ...`: 0 new findings, 224 baselined. `bash scripts/test-all.sh --print-selection`: the grep-q guard is `AFFECTED_SELECTED` (declared edge).

## Pair run (pristine base vs branch, sequential, `timeout 150`, `ulimit -v 6000000`)

A pair run on small fixtures shows "no verdict change", not "the race is gone". All 46 suites were run on both sides; 38 read the same rc and the same result line on the first pass. The eight that differed (seven archive-failed suites and `git-tripwire`) are explained below, together with two same-rc suites whose numbers need a caveat. The 11 suites that carry a hand edit or a reviewed-suspect conversion (4 hand-edit files plus 7 suspect files) all read identical.

| suite | base | branch | like-for-like verdict |
|---|---|---|---|
| `hook-input-classification-mutation`, `operator-agent-runnable`, `preflight-check10-suite-integrity`, `proc`, `scripts-shard-totality`, `ship-battery-owed`, `workflow-run-deploy-invariants` | rc 1, 2 or 128 on the `git archive` side (no `.git`, no `node_modules`) | rc 0 | identical once the base is re-run on a real detached checkout of `425ea0fc1f`: rc 0 and the same result line on both sides (13 pass/13 rows; 46 assertions; 38 checks; 61; "All tests passed"; "ALL TESTS PASSED"; 80/80) |
| `git-tripwire` | rc 0 (archive side: vitest arm skipped, no `node_modules`) | rc 1 | identical like-for-like: the unmodified base content run in the worktree under the same cap is 24 passed, 1 failed (the vitest worker isolate aborts under `ulimit -v`); the branch is 24/1 under the cap and 25 of 25 without it |
| `render-c4-model` | rc 1 | rc 1 | identical: AC5 fails the same way on both sides (`likec4 export` dies with `Illegal instruction (core dumped)` under the cap); not investigated further |
| `go-session-gates` | 77 s | 141 s | wall time only; two alternating re-runs read 83 s / 81 s and 40 s / 100 s, so the spread (40 to 141 s) is larger than any effect and no change is claimed or ruled out |

Wall times for the seven archive-failed suites are not comparable (the archive side aborted in seconds). A like-for-like re-run of two of them in one tree read `hook-input-classification-mutation` 99 s base / 112 s branch and `preflight-check10-suite-integrity` 72 s / 78 s, so the conversion did not slow them. Apart from those, no suite moved by more than a few seconds.

## Affected gate (`bash scripts/test-all.sh --affected`): stopped by decision, CI is the gate

Selection: `AFFECTED_SUMMARY selected=251 of=582 always_on=148 edge=103 fallback=none`. The run was stopped by hand (SIGTERM, rc 143) after about 1 h 45 min at roughly 470 of 582 registrations processed, with 987 `[ok]` lines, no `[KILLED]` and no real `[FAIL]` (the three `[FAIL]` lines are suites' own deliberate self-test lines). It was stopped because CI's required `test` context runs the full battery on the PR head, so a longer local run adds no gate. This is not a green affected run and is not claimed as one; the local evidence is the pair run, the ratchet lane (`verdict=PASS members=23 red=0`), the guard and the mutation battery above.
