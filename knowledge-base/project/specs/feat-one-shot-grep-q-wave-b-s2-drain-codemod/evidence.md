# Evidence: grep -q drain, Item B slice S2

Source for the PR body and the tracker comment. Every number below was printed by the command named beside it on 2026-10-08, base `origin/main` 425ea0fc1f.

## Guard rows (`bash .claude/hooks/grep-q-pipe-guard.test.sh`, rc 0 both times)

| Row | Before | After |
|---|---|---|
| `plugins/soleur/test/*` | 140 hits, ceiling 140, mode `<=` | 5 hits, ceiling 5, mode `=`, slack 0 |
| the other twelve `DEFERRED:` lines | unchanged | byte-identical (`diff` of the two sets is exactly the one row) |
| test-shaped total (sum of the seven test rows) | 702 | 567 |

## Transform proof

`python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits <hand-edits.txt>`: `verified: 130`, `hand-edited: 5`, `unexplained: 0`. Idempotency dry run: `WOULD-CHANGE: 0 lines in 0 files`. `bash -n` clean on all 46 files. `git diff --numstat origin/main...HEAD -- plugins/soleur/test/`: 135 insertions, 135 deletions. `verify` proves the transform, not the classification (a data line converted by mistake still passes it).

## Drain probe (Phase 0 gate)

`bash -c 'set -o pipefail; (echo 1; sleep 0.4; echo 2) | grep -q 1; ...'` prints `q: 141`, `c: 0`, `nomatch: 1` on GNU grep 3.12 (dev host) and on GNU grep 3.11 inside `ubuntu:24.04`.

## Trigger derivation (46 files against every push-to-main workflow filter)

Among path-filtered workflows only `version-bump-and-release.yml` matches (46 of 46): one plugin patch release. `web-platform-release.yml`, `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` match nothing. The six unfiltered push workflows (`ci`, `codeql-main-alert-gate`, `secret-scan`, `skill-security-scan-corpus`, `skill-security-scan-postmerge`, `tenant-integration`, `vendor-pin-verify`) run on every merge and are not caused by this change. Open-PR intersection with the 47 edited files: empty.

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

A pair run on small fixtures shows "no verdict change", not "the race is gone". The base side is a `git archive` of `origin/main`; seven suites that cannot run there (no `.git`) were re-run against a real detached checkout of the same SHA (see the learning file of this PR).

| suite | base rc | branch rc | base s | branch s | verdict |
|---|---|---|---|---|---|
| auto-close-scanner | 0 | 0 | 0 | 1 | identical |
| check-red-on-main | 0 | 0 | 2 | 2 | identical |
| ci-e2e-skip-anchors | 0 | 0 | 0 | 1 | identical |
| ci-path-gating | 0 | 0 | 0 | 0 | identical |
| claude-code-action-auth | 0 | 0 | 1 | 1 | identical |
| generate-kb-index | 0 | 0 | 1 | 1 | identical |
| git-tripwire | 0 (archive: vitest arm skipped, no node_modules) | 1 | 1 | 3 | identical when compared like for like: the unmodified base content run in the worktree under the same ulimit is 24 passed, 1 failed (node V8 crash in the vitest arm), the branch is 24 passed, 1 failed under it and 25 of 25 without it [hand edit] |
| go-session-gates | 0 | 0 | 77 | 141 | identical [hand edit or reviewed-suspect] |
| hook-input-classification-mutation | 0 | 0 | 0 | 86 | identical (base re-run on a real checkout: rc 0) |
| issue-flow-measure | 0 | 0 | 0 | 0 | identical [hand edit or reviewed-suspect] |
| lane-frontmatter | 0 | 0 | 0 | 1 | identical |
| lint-distribution-content | 0 | 0 | 0 | 0 | identical |
| main-health-monitor-workflow | 0 | 0 | 4 | 4 | identical [hand edit or reviewed-suspect] |
| operator-9321-stages | 0 | 0 | 76 | 67 | identical |
| operator-ack-guard | 0 | 0 | 119 | 132 | identical |
| operator-agent-runnable | 0 | 0 | 27 | 32 | identical (base re-run on a real checkout: rc 0) |
| operator-digest-provision | 0 | 0 | 0 | 0 | identical |
| operator-digest-skill | 0 | 0 | 0 | 0 | identical |
| operator-digest-workflow | 0 | 0 | 1 | 0 | identical |
| operator-stage-approval-hook | 0 | 0 | 11 | 12 | identical |
| pr-fanout-ledger | 0 | 0 | 56 | 43 | identical |
| preflight-check10-suite-integrity | 0 | 0 | 0 | 65 | identical (base re-run on a real checkout: rc 0) |
| proc | 0 | 0 | 5 | 4 | identical (base re-run on a real checkout: rc 0) |
| regenerate-shard-manifest | 0 | 0 | 4 | 3 | identical |
| render-c4-model | 1 | 1 | 23 | 19 | identical |
| required-checks-canonical-parity | 0 | 0 | 0 | 0 | identical [hand edit or reviewed-suspect] |
| required-checks-merge-group-coverage | 0 | 0 | 11 | 11 | identical |
| resolve-debt | 0 | 0 | 1 | 2 | identical |
| reusable-release-caller-permissions | 0 | 0 | 0 | 0 | identical |
| roadmap-reconcile | 0 | 0 | 7 | 6 | identical [hand edit or reviewed-suspect] |
| scripts-shard-manifest | 0 | 0 | 1 | 1 | identical |
| scripts-shard-runtime-coverage | 0 | 0 | 4 | 5 | identical [hand edit or reviewed-suspect] |
| scripts-shard-totality | 0 | 0 | 5 | 9 | identical (base re-run on a real checkout: rc 0) |
| ship-battery-owed | 0 | 0 | 2 | 18 | identical (base re-run on a real checkout: rc 0) |
| ship-phase-7-poll-fixtures | 0 | 0 | 130 | 132 | identical [hand edit or reviewed-suspect] |
| sync-pr-behind | 0 | 0 | 21 | 19 | identical [hand edit or reviewed-suspect] |
| terraform-drift-sentry-leg | 0 | 0 | 1 | 1 | identical |
| unkept-promise-hook | 0 | 0 | 3 | 2 | identical |
| vendor-drift-workflow | 0 | 0 | 0 | 1 | identical |
| web-host-escrow-diagnose-workflow | 0 | 0 | 7 | 7 | identical [hand edit or reviewed-suspect] |
| workflow-run-deploy-invariants | 0 | 0 | 3 | 5 | identical (base re-run on a real checkout: rc 0) |
| worktree-manager-atomic-config | 0 | 0 | 1 | 1 | identical |
| worktree-manager-bare-in-dotgit-layout | 0 | 0 | 2 | 1 | identical |
| worktree-manager-heal-stale-branch | 0 | 0 | 13 | 13 | identical |
| worktree-manager-porcelain-sigpipe | 0 | 0 | 2 | 2 | identical [hand edit or reviewed-suspect] |
| worktree-manager-stale-lock-diag | 0 | 0 | 6 | 5 | identical |

Wall time: `go-session-gates` read 77 s on base and 141 s on the branch in the pair run; two further alternating re-runs read 83 s / 81 s and 40 s / 100 s. The run-to-run spread (40 to 141 s) is larger than any effect, so no change in suite wall time is claimed or ruled out. No other suite moved by more than a few seconds.

## Affected gate (`bash scripts/test-all.sh --affected`): stopped by decision, CI is the gate

Selection: `AFFECTED_SUMMARY selected=251 of=582 always_on=148 edge=103 fallback=none`. The run was stopped by hand (SIGTERM, rc 143) after about 1 h 45 min at roughly 470 of 582 registrations processed, with 987 `[ok]` lines, no `[KILLED]` and no real `[FAIL]` (the three `[FAIL]` lines are suites' own deliberate self-test lines). It was stopped because CI's required `test` context runs the full battery on the PR head, so a longer local run adds no gate. This is not a green affected run and is not claimed as one; the local evidence is the pair run, the ratchet lane (`verdict=PASS members=23 red=0`), the guard and the mutation battery above.
