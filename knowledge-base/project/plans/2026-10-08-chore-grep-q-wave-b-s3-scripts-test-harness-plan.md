---
title: "chore(ci): grep -q drain, Item B slice S3 (scripts/*.test.sh and scripts/test-all.sh, Ref #9217)"
date: 2026-10-08
slug: grep-q-wave-b-s3-scripts-test-harness
branch: feat-one-shot-grep-q-wave-b-s3-scripts-tests
issue: 9217
lane: cross-domain
type: chore
priority: p3-low
domain: engineering
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# chore(ci): grep -q drain, Item B slice S3 (scripts/*.test.sh and scripts/test-all.sh, Ref #9217)

## Enhancement Summary

**Deepened on:** 2026-10-08. **Gates run:** 4.6 user-brand impact (pass, `aggregate pattern`), 4.7 observability (pass; the `.test.sh` proxy hit on the suite-shaped-command condition is argued down with measurements under the 15 s cap: 12.9 s plain and 10.6 s in a Check 10-shaped `bwrap` at load 16), 4.8 PAT-shaped variables (none), 4.9 UI wireframe (no UI surface), 4.10 encryption posture (no store or connection), 4.11 guard contract (`lint-guard-contract.py`: 1 entry; adequacy read: the Assembly names the chokepoint and the first-match-wins order, not today's members), 4.12 scope check (one live section, no BLOCKED marker, split assessment justified), 4.5 network-outage (no trigger word in the Overview or Problem Statement), 4.55 downtime (no trigger). Cited issue, PR, label, rule-id and SHA facts re-verified live by a standard-tier sweep: no mismatch.
**Agents:** a learnings researcher and an advisor consult before drafting; plan review (simplicity, correctness, scope challenge); then test-design-reviewer, architecture-strategist and a standard-tier verify-the-negative and dropped-symbol sweep.

### Key improvements

1. **A live counterexample to the open-PR screen.** The verify-the-negative sweep found that #9772 now adds a negated early-exit pipe under `scripts/` (`scripts/ci-demand-census.test.sh:847`), which the planning-time screen had not seen; the claim is now point-in-time, re-run in Phase 0 and at PR-ready, and the consequence (that PR already exceeded the slack-0 ceiling) is stated.
2. **Guard matrix made discriminating.** The empty-table row now compares the count on the converted tree (458) with the base tree (588), because the listed sites are capped at 50; a base-complement row (130 sites) and a measured known-surviving-mutant row (a resurrected row plus a covering hit stays green) were added; the must-PASS rows need a landing check and a paired control.
3. **Observer mutants explained.** Three reader-side mutants cannot see a negated line whose upstream stages already fail under `pipefail`; the one such site (`web2-rebirth-recovery-check.test.sh:171`) is observed by a SUT-side mutant on both trees.
4. **Runner edit proven on its own bytes.** A selection and enumeration parity check (four path sets, 591 suite ids in the enumeration, identical; the split into `SUITE_COMMAND` and `SUITE_COMMAND_DECLINED` records follows each tree's diff and is not) and a must-FAIL row for line 669; `soleur:ship` Phase 4 is tied to its OWED check and ADR-242.
5. **Sequencing corrected:** S5 abuts S3's table hunk, S4 does not (decision-challenges item 21).

### New considerations

- A resurrected row together with a covering hit is a measured, uncovered hole until S7 or Item F; the legend and `_ts_re` keep a dead `test-*` clause; the S7 exit wording in the S1 plan is not met by the rows that remain.

Spec lacks valid lane: no spec.md exists for this branch, so lane defaulted to cross-domain (TR2 fail-closed).

## Overview

Slice S3 of Item B in the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). Pass 1 (#9632), Pass 2 (#9708), slice S1 (PR #9720, `f44463a7e9`, the codemod `scripts/grep-q-drain-codemod.py` and its selftest) and slice S2 (PR #9765, `f1497664ae`) are on `origin/main`. None of that is redone here.

S3 owns exactly two deferral rows of the guard `.claude/hooks/grep-q-pipe-guard.test.sh`: `scripts/*.test.sh` (128 lines, ceiling 128, mode `<=`) and `scripts/test-*` (2 lines, ceiling 2, mode `<=`). The glob `scripts/*.test.sh` crosses `/` (bash `[[ == ]]`), so it covers the top level, `scripts/followthroughs/` and `scripts/lib/`; the only file the second row owns is `scripts/test-all.sh`.

Unlike S1 and S2, **S3 takes both rows to zero** and deletes them. Every one of the 130 lines is converted from `producer | grep -q P` to `producer | grep -c ... >/dev/null P` (same exit status, reads to EOF, so the producer never takes SIGPIPE under `set -o pipefail`): 108 by the codemod (80 lines in 33 files by default, 28 lines in 9 more files that the codemod's whole-file R2 rule had held for reading and that were read here) and 22 by hand (4 `grep -m` displays, 17 executed-string lines the codemod classes as data, 1 line its producer screen refused by mistake). After the edit the guard has no row for `scripts/`, so any new early-exit pipe anywhere under it lands in "outside the deferral table", with no slack and no add-one-delete-one hole (S2 left five counted pins; S3 leaves none).

**Measured result of a full rehearsal on a scratch clone of `origin/main` `fd1c4d5cac`** (nothing committed in this repository): 130 line edits in 47 files plus the two deleted guard rows; `verify` prints `verified: 126`, `hand-edited: 4`, `unexplained: 0`; the guard prints 11 `DEFERRED:` lines (was 13) rc 0; the test-shaped total (sum of the seven test-shaped ceilings) falls 567 to 437; 13 of the 15 owning suites that carry a reviewed-suspect conversion or a hand edit were run on both sides and read identical (table below).

**What fires on merge.** Re-derived over the 48 edited files against the path filter of every `.github/workflows/*.yml` that has a `push` trigger (25 of 86 workflows; the derivation script and its output are in Research Insights): no path-filtered workflow matches, 0 of 48 each. Only the seven unfiltered push workflows run (`ci`, `codeql-main-alert-gate`, `secret-scan`, `skill-security-scan-corpus`, `skill-security-scan-postmerge`, `tenant-integration`, `vendor-pin-verify`), as they do on every merge. The S1 plan's "S3 fires nothing" holds. `scripts/test-all.sh` is in the diff but is on no filter, `plugins/soleur/**` is untouched (no plugin release), `apps/web-platform/**` is untouched (no web-platform release), `[skip-deploy-fix-apply]` is irrelevant and is not used.

**What does degrade: the local affected gate.** `scripts/test-all.sh` is one of the two files that ARE the gate's selection logic, so a diff containing it makes `--affected` run the full battery (`AFFECTED_FALLBACK reason=runner-changed`, measured on the rehearsal; the manifest weights say 91.4 min for the full battery, `knowledge-base/project/learnings/2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`). The documented lever, `--affected-scope=staged`, still selects 239 of 588 suites on this diff (measured). Decision made now, not at run time: no local `--affected` run is started for S3 (ADR-242 decision 10 describes the scope-aware lever; ADR-183 puts the full suite at ship, not at implementation exit). `soleur:ship` Phase 4 defaults to `--affected`, so it will meet the same `runner-changed` degrade: it is satisfied by its own "is the battery still OWED" check (#8247: CI's required `test` check verifies the byte-identical tree) and, if it insists on a local run, by the staged-scope lever run detached with an rc file and the stop condition fixed in advance (CI is the gate). The PR body states the `AFFECTED_FALLBACK` line verbatim, and the local evidence is the pair run of the owning suites, the runner-parity digests, the ratchet lane, the guard and the mutation battery.

**Honest scope.** All 47 files set `pipefail`, so the shape is live, but most of the 130 sites pipe a `printf`/`echo`/`sed`/`grep` value of a few lines into `grep`, which only races when the writer is unfinished at the reader's exit. This PR pays the ledger down and removes the last counted slack under `scripts/`: a new early-exit pipe in a spelling and extension the guard sees now lands in "outside the deferral table". The guard does not see every spelling or extension (structural map in `evidence.md`; Items D, E and F). It is not a flake fix and does not move any CI flake rate. One sub-class is worth naming because it fails open and not closed: 5 of the 17 executed-string lines (all in `web2-rebirth-recovery-check.test.sh`) are negated pipelines (`! producer | grep -q X` inside an `eval`-ed assertion that inherits `pipefail`; two more in `web2-luks-live-6931.test.sh` sit in a `bash -c` child that does not inherit it); if the producer takes SIGPIPE the pipeline status is 141, the `!` turns it into success, and the assertion "X is absent" passes with X present. Measured with a delayed writer (below): `! (echo 1; sleep 0.4; echo 2) | grep -q 1` prints 0 and the converted form prints 1.

## Research Reconciliation: brief and trackers vs measured reality

| Brief or tracker claim | Reality (command or file) | Plan response |
| --- | --- | --- |
| "S3 owns the guard rows `scripts/*.test.sh` (128 hits) and `scripts/test-*` (2 hits)" | Slice Register of the S1 plan (`knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md`, section `Slice Register`): `S3 = scripts/*.test.sh, the rest of scripts/test-*`, 130 hits / 47 files, "nothing" fires, "includes `scripts/followthroughs` (27) and `scripts/test-all.sh` (2; local `--affected` degrades to the full battery for that diff, stated in the PR body)". The tracker comments of 2026-10-08 12:07, 13:39 and 20:32 only say "S3 to S7" and that S3, S4 and S5 "can be cut now" after S2 | S3 owns those two rows and nothing else. S4 `tests/*`, S5 `plugins/soleur/*.test.sh` plus part of `apps/web-platform/*.test.sh`, S6 `apps/web-platform/infra/*.test.sh`, S7 the producer-side join are later PRs. The register's 130 / 47 is re-measured below: 130 lines, 47 files plus the guard |
| Lead's measurement: "POPULATION 588 lines in 132 files; ROW scripts/*.test.sh T0=82 X=1 data=18 suspect=32; ROW scripts/test-* suspect=2; WOULD-CHANGE 80 lines in 33 files; 53 QUEUE entries" | Re-run here on `fd1c4d5cac` (`python3 scripts/grep-q-drain-codemod.py apply --row 'scripts/*.test.sh' --row 'scripts/test-*'`, dry run, rc 0): identical, 53 QUEUE lines (34 suspect, 18 data, 1 X) | The three tiers the lead saw are all dispositioned below, none left counted |
| "the `scripts/test-*` row is suspect-only: decide from the code what is actually hit" | The row's only file is `scripts/test-all.sh` (`set -euo pipefail` at line 2). Its two hits are plain T0 shapes held only by the codemod's whole-file R2 rule because the file's comments name SIGPIPE at lines 753, 1716, 1906 and 2470: line 669 `git rev-parse --is-bare-repository 2>/dev/null \| grep -q true` (a runner start-up guard, one word of output) and line 6476 `printf '%s\n' "$_repo_fatal" \| grep -qE '^FATAL[[:space:]]+(head\|worktree)'` (the recovery text of the "a suite wrote to the live repository" fatal branch) | Converted with `--reviewed-suspect scripts/test-all.sh`. Not left as two counted pins: leaving them would cost nothing at runtime, but would keep a `=` row alive for a runner-only reason and S7's exit ("no glob row left") would still need it. The price is the local `--affected` fallback above, accepted and stated |
| "S1 plan: S3 touches scripts/test-all.sh, which degrades local `--affected` to the full battery" | True and measured: `bash scripts/test-all.sh --print-selection` on the rehearsal diff prints `AFFECTED_FALLBACK reason=runner-changed`, `selected=all of=all`. With the diff staged and `--affected-scope=staged` it prints `AFFECTED_RUNNER_IN_SCOPE reason=runner-changed` and `selected=239 of=588 ... fallback=none` | See "What does degrade" in the Overview. `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh` are edited only on the two named lines; the file's line count does not change (every edit is one line for one line) so no `test-all.sh:<line>` citation elsewhere moves |
| "open PRs touch some candidate files (#8626, #9745, #9753 touch scripts/*.test.sh files; several touch scripts/test-all.sh): intersect the exact edited-file list" | 48 open PRs at planning, 50 at deepen time (`gh pr list --state open --limit 300 --json number,title,isDraft,mergeStateStatus,files`). Intersection with the exact 48 edited paths: **#9745** (draft, `scripts/guard-vacuity-floor.test.sh`, hunk at line 798; S3 edits lines 907 and 908) and **#9772, #9640, #7390, #6778** (all drafts, `scripts/test-all.sh`, hunks at lines 5913, 5330, 344 and 290; S3 edits lines 669 and 6476). **#8626** and **#9753** touch other `scripts/*.test.sh` files (`lint-encryption-posture.test.sh`, `inngest-soak-6178.test.sh`, `check-deploy-script-parity.test.sh`, `compound-promote.test.sh`, `sweep-followthroughs.test.sh`, `lint-shell-trace-credential-refusal.test.sh`, `infra-config-activation-7220.test.sh`) that S3 does not edit | No hunk comes within three lines of an S3 edit, so no textual conflict is predicted. A semantic conflict (an open PR adding a new early-exit pipe under `scripts/`) was screened per PR with the guard's `PATTERN_V2` over the added lines of `gh pr diff` (it flags a synthetic `echo x \| grep -q y` and not the converted form). At planning it found none; **at deepen time it found one: #9772 (draft, WIP) now adds `scripts/ci-demand-census.test.sh:847`, `no_exit1() { ! grep -vE '^[[:space:]]*#' "$CENSUS" \| grep -qE '...'; }`**, a negated early-exit pipe (the fail-open shape). That PR already exceeds today's slack-0 ceiling (128 hits, ceiling 128, so the 129th hit fails `deferral ceiling exceeded`), so S3 does not create the conflict; it changes the failure text to "outside the deferral table" and removes any chance that the number is raised instead of the line converted. The screen is point-in-time: Phase 0 and the PR-ready step re-run it, any hit is named in the PR body and the tracker comment, and S3 does not touch another PR's file On a conflict at merge time the merge queue ejects the entry; this slice never re-syncs a BEHIND branch mid-flight and, on an ejection, rebases once, re-runs Phase 0 and Phase 3, and re-enters the queue |
| "derive which workflows fire on merge; the S1 plan said S3 fires no workflow, verify that" | Verified, see the derivation in Research Insights: 0 of 48 for all 18 path-filtered push workflows | The PR body's first line says exactly that; no release label beyond the series convention |
| "the pair-run base must be a real detached checkout of the base SHA, never a git archive; `ulimit -v 6000000` aborts vitest worker isolates" | Learning `2026-10-08-a-pair-run-needs-a-real-base-checkout-and-the-mandated-ulimit-aborts-vitest-on-both-sides.md`. `grep -l vitest` over the 47 files finds only `scripts/test-all.sh` (the runner, not a suite) and `scripts/test-contention.test.sh` (a comment); no edited suite starts a vitest worker | Pair run on a real clone at the base SHA, under the cap; Phase 0 re-greps for vitest and runs any suite that starts a worker without the cap, stating that in the table |
| "a `<=` row does not fail on slack, so a residual row becomes `=` as the LAST edit after conversion (the codemod refuses `--write` on `=` rows)" | Holds, but S3's residual is zero, not a pinned remainder. The guard's stale-deferral rule fails a row with no hits (`FAIL: stale deferral: scripts/*.test.sh has no hits left — delete its row`, measured on the rehearsal), so the end state is "row deleted", which the guard enforces without a mode flip | Phase order below: rows lowered (red), convert, delete `scripts/test-*` when the codemod reaches it, hand edits, idempotency dry run, delete the last row as the final edit. No `=` row is created |
| "the guard row comment must not overclaim" | S3 adds no comment: it deletes two table lines, and the header already says "A row whose subtree reaches zero is STALE and fails: the wave that converts a subtree deletes its row in the same PR" | The guard diff is exactly two deleted lines (AC-9 asserts `0 2` in `git diff --numstat`); nothing to overclaim |
| `apps/web-platform/*.test.sh` "currently reads 178 hits against a ceiling of 180 (slack 2)" (tracker comment of 2026-10-08 20:32) | Confirmed by the guard run here (`178 hits, ceiling 180, slack 2`) | Not touched; that row is S5's. Its slack is 2, not 0, so the series-wide "no slack" reading does not yet hold there; recorded in the NOT-fixed list |

## Research Insights

### Premise Validation

Checked 2026-10-08. Issues #9217, #7376, #6601, #7797, #9482, #9638, #9639 and #8659 are all OPEN. PRs #9720 (`f44463a7e9`) and #9765 (`f1497664ae`) are MERGED and ancestors of `origin/main` (`git merge-base --is-ancestor f1497664ae origin/main`). At planning start `origin/main` was `fd1c4d5cac` (PR #9775, an egress resolver change that touches none of the 48 files), the branch's merge-base; it has since moved to `d0b5d2e35b` (a docs-only ADR commit, `git diff --stat HEAD origin/main -- scripts .claude` is empty). Phase 0 merges it once and records the post-merge `git merge-base HEAD origin/main` as the SHA that `verify --base`, the pair-run base and the trigger derivation all use; if `origin/main` moves again before Phase 3, `verify` still takes that recorded SHA. The mechanism (a `grep -c ... >/dev/null` rewrite through the committed codemod) is in no rejected-alternatives table in `knowledge-base/engineering/architecture/decisions/` (ADR-119 uses the same rule as a design constraint). The idiom was re-probed with a delayed writer on this host (GNU grep 3.12) and inside `ubuntu:24.04` (GNU grep 3.11): `grep -q` prints 141, `grep -c ... >/dev/null` prints 0, a no-match input keeps rc 1, and the negated pair prints `neg-q: 0` (assertion passes with the text present) against `neg-c: 1`. No open PR touches the guard or the codemod (`jq` over the PR file lists).

### Property List and Cut List

Properties (each observable):

- P1. Every pipe-fed early-exit reader under `scripts/` (`*.test.sh` at any depth, and `scripts/test-all.sh`) is exit-status-identical to its original and drains its producer; no counted exception remains.
- P2. The guard, not a reader, fails on a new early-exit pipe anywhere under `scripts/` (no row owns the subtree) and fails on a resurrected row for a subtree with no hits (stale deferral). Not claimed: a row resurrected together with a hit it covers (`<= | 1` plus one new pipe) is green, measured; that stays a review-surface hole (matrix row 10).
- P3. A reviewer can mechanically confirm that the diff is only the transform plus an enumerated hand queue: `verify` reports `unexplained: 0`, and the 22 hand-converted lines are listed individually (`hand-edits.txt` for the 4 that are not a plain transform, `data-conversions.txt` for the 18 that are).
- P4. No converted suite changes its verdict (pair run, or a recorded reason it was not run).
- P5. The merge fires only what was predicted, predicted before the PR and observed after.

Mechanisms the ask names and what each buys: the codemod dry run (P1, P3), the guard's `DEFERRED:` lines and stale-deferral rule (P2), the evidence comment on #9217 (P5 and series accounting), the `ulimit` battery (mutation evidence for P2). All already exist on `origin/main`: the codemod and the guard are read, not extended.

**Cut List.**

| Cut | Buys | What already covers it |
| --- | --- | --- |
| An `apply --exec-strings` mode for the 17 executed-string lines and the 1 refused line (S1 deferred the mode "to a slice that has such sites"; S3 is the first with more than one) | converting the data tier mechanically | The same one-token transform applies to them and `verify` already counts them as verified; 18 lines in 8 files are cheaper to convert by a throwaway rewrite and list in `data-conversions.txt` than a tool mode that is deleted in S7. The classification is the part a tool cannot prove, and it is read in the table below |
| Fixing the codemod's producer-screen false positive on a quoted `sleep` | a more robust tool | One line (`test-all-orphan-log-retention.test.sh:82`), converted by hand and listed; the tool is deleted in S7 |
| A characterization row per converted site | rows that see a dropped `-x`, `-F` or `>/dev/null` | `verify` proves every other byte of a line unchanged; the S1 selftest holds one discrimination row per way the weaker form is satisfiable |
| A suite row for the four `grep -m` display lines | observing the here-string rewrite | All four sit inside failure-message text that only prints on a defect, so no row can reach them without breaking the suite on purpose. Evidence is one scratch run of old and new expression on a three-line input whose first match is on line 2 |
| File-exact residual rows | closing add-one-delete-one | No residual: the subtree is at zero, so a hit cannot move between files |
| Running `scripts/test-all.sh --affected` (full fallback, or staged scope at 239 suites) | a local copy of the CI gate | CI's required `test` check runs the full battery on the PR head; S2's affected run was stopped after about 1 h 45 min with no failure. Stated above, decided now |
| Editing `scripts/lib/test-affected-paths.sh` | hand-maintained edges | A changed test file selects itself; AC-5 reads `--print-selection` for the guard only |
| A permanent drain-probe row in the guard selftest | the idiom stays proven on the CI grep | S3 may not edit `SWEEP_PROBE_CHECKS` (S1 plan); Phase 0 runs the probe as a gate and S7's plan decides whether to pin it |

### Census (guard- and codemod-derived, 2026-10-08, `origin/main` `fd1c4d5cac`)

Commands: `bash .claude/hooks/grep-q-pipe-guard.test.sh` (rc 0), then `python3 scripts/grep-q-drain-codemod.py apply --row 'scripts/*.test.sh' --row 'scripts/test-*'` (dry run, rc 0).

| Quantity | Value |
| --- | --- |
| Rows before | `scripts/*.test.sh` 128 lines, ceiling 128, `<=`, slack 0; `scripts/test-*` 2 lines, ceiling 2, `<=`, slack 0 |
| Codemod population | 588 lines in 132 files (the guard's own pattern over the whole deferral table, comment and marker lines dropped; the two S3 rows hold 130 of them, so the rows' removal leaves 458); row `scripts/*.test.sh` hits T0 82, X 1, data 18, suspect 32; row `scripts/test-*` suspect 2 |
| Default dry run | WOULD-CHANGE 80 lines in 33 files; 53 QUEUE lines (34 suspect, 18 data, 1 X) |
| Suspect tier (34 hits, 32 lines, 9 files) | `sentry-issue-discover` 13 lines, `prod-version-drift-check` 10, `test-all.sh` 2, `guard-vacuity-floor` 2, and one each in `inngest-provision-unit-8562`, `inngest-zot-boot-7462`, `plugin-delivery-canary`, `test-all-affected`, `test-contention` |
| With the nine files passed to `--reviewed-suspect` | WOULD-CHANGE 28 more lines in those 9 files; QUEUE 22 lines: 4 `H-m` (`grep -m`), 17 data (stub heredocs, `eval`/`bash -c` strings, a stub body), 1 X |
| Producer screen | 1 refused as unbounded and it is a false positive: `test-all-orphan-log-retention.test.sh:82` is `printf '%s\n' "$wd_block" \| grep -q 'sleep "$_RUN_WD_POLL_S"'`; the word `sleep` is inside the quoted pattern and the producer is `printf` |
| Files setting `pipefail` | 47 of 47 (`grep -E 'set .*pipefail'` per file) |
| Suite wall time per side | about 11 min summed over the 30 of the 46 edited suites that have a measured row in `scripts/suite-durations.tsv` (673,942 ms; the other 16 have none, mostly `followthroughs` probes and small linters; the 47th file is the runner); the largest are `test-all-affected` 311 s, `test-contention` 138 s, `web2-rebirth` 72 s, `web2-rebirth-recovery-check` 35 s, `guard-vacuity-floor` 34 s |

### Trigger derivation (every `push` workflow against the 48 edited paths)

A throwaway script (not committed) loads every `.github/workflows/*.yml`, keeps those with a `push` trigger that can fire on `main` (25 of 86), and applies GitHub filter semantics (`*` stays inside a segment, `**` crosses `/`, `!` negates, patterns in order; `paths-ignore` the inverse) to each edited path. Sanity probe: `plugins/soleur/test/proc.test.sh`, `apps/web-platform/infra/server.tf` and `scripts/test-all.sh` together light `version-bump-and-release`, `web-platform-release`, `apply-web-platform-infra`, `apply-deploy-pipeline-fix` and `infra-validation` once each (1 of 3), so the matcher is not vacuous. Over the 48 edited paths: all 18 path-filtered workflows (`apply-*`, `cutover-inngest`, `deploy-docs`, `deploy-inngest-image`, `infra-validation`, `inngest-watchdog-restart-dispatch`, `mint-inngest-bootstrap-tag`, `registry-host-replace-dispatch`, `registry-zot-inventory`, `restart-inngest-server`, `validate-vector-config`, `version-bump-and-release`, `web-platform-release`, `zot-image-mirror`) match 0 of 48; the seven unfiltered ones match 48 of 48. Adding this PR's own plan, spec and learning paths under `knowledge-base/` changes nothing (0 of 51 for the filtered ones).

### Rehearsal (scratch clone of `origin/main`, no repository file touched)

`git clone --local --no-hardlinks` of this worktree into the session scratch directory, `git checkout -b rehearsal fd1c4d5cac`, then: `apply --row 'scripts/*.test.sh' --row 'scripts/test-*' --write` (80 lines, 33 files); the same with `--reviewed-suspect` for the nine files (28 lines, 9 files); 22 hand edits (4 here-strings, 18 one-token conversions); both rows deleted. Results: `git diff --stat`: 130 insertions and 130 deletions in 47 files under `scripts/`, plus 2 deletions in the guard; `verify --base fd1c4d5cac --hand-edits <4 entries>`: `verified: 126`, `hand-edited: 4`, `unexplained: 0`; the idempotency dry run (run with the base guard, before the rows go) `WOULD-CHANGE: 0 lines in 0 files`; the guard prints 11 `DEFERRED:` lines, `PASS: grep-q-zero-sweep-pass (1743 files swept; deferrals above)` and `PASS: grep-q-sweep-probe-pass`, rc 0; `bash -n` on all 47 files clean; `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`: 1476 scripts scanned, 0 new, 224 baselined; `bash scripts/lint-orphan-test-suites.sh`: none. The red-first edit (rows at `<= 22` and `<= 0`) was run on a second clone: both rows print `deferral ceiling exceeded` (128 hits against 22, 2 against 0), rc 1.

### Owning suites on the converted tree (rehearsal, `ulimit -v 6000000`, one at a time)

Thirteen of the 15 suites that carry a reviewed-suspect conversion or a hand edit (8 hand-edit files plus 9 reviewed-suspect files, `prod-version-drift-check` in both, minus `scripts/test-all.sh`, which is the runner and not a suite) were run on both sides during planning: branch = the rehearsal clone, base = a second clone checked out at `fd1c4d5cac`, each under `ulimit -v 6000000`, sequential within a side. All thirteen read the same rc (0) and the same result line. The two not yet run are `test-all-affected` (311 s of manifest weight) and `test-contention` (138 s); they and `test-all-group-affected` are Phase 3. Wall times are not comparable: the sides ran while the host load average moved between 9 and 40 and while the mutation batteries below ran.

| suite | base (rc, wall) | branch (rc, wall) | result line (identical on both sides) |
| --- | --- | --- | --- |
| `followthroughs/concierge-strand-754ee124-5733.test.sh` | 0, 1 s | 0, 1 s | concierge-strand-754ee124-5733: 13/13 passed |
| `followthroughs/inngest-provision-unit-8562.test.sh` | 0, 3 s | 0, 2 s | OK: all 28 exit-code checks correct |
| `followthroughs/inngest-zot-boot-7462.test.sh` | 0, 1 s | 0, 0 s | OK: all 17 exit-code checks correct |
| `followthroughs/web2-luks-live-6931.test.sh` | 0, 117 s | 0, 51 s | 86 passed, 0 failed |
| `guard-vacuity-floor.test.sh` | 0, 104 s | 0, 82 s | Total: 23 passed, 0 failed (23 assertions) |
| `lib/trusted-verdict.test.sh` | 0, 1 s | 0, 1 s | passed=13 failed=0 |
| `plugin-delivery-canary.test.sh` | 0, 6 s | 0, 5 s | Total: 126 passed, 0 failed (126 assertions) |
| `pre-push-ratchet-lane.test.sh` | 0, 13 s | 0, 9 s | === Results: 77 passed, 0 failed === |
| `prod-version-drift-check.test.sh` | 0, 54 s | 0, 36 s | Total: 163  Pass: 163  Fail: 0 |
| `sentry-issue-discover.test.sh` | 0, 0 s | 0, 1 s | 33 passed, 0 failed |
| `test-all-orphan-log-retention.test.sh` | 0, 83 s | 0, 79 s | === RESULT: 54 passed, 0 failed === |
| `watch-live-verify-pass.test.sh` | 0, 1 s | 0, 1 s | 7/7 passed |
| `web2-rebirth-recovery-check.test.sh` | 0, 151 s | 0, 30 s | all assertions and mutations passed |

### Classification of the 18 hand-converted lines before conversion

Three independent checks on the base tree (Phase 0 re-runs the second): (1) each line was read in context (table in Proposed Solution); (2) a repo-wide fixed-string search for each line's `grep -q...` fragment finds no other tracked file containing it (one generic fragment, `grep -q .`, also occurs in `apps/web-platform/infra/cron-egress-nftables.test.sh`, an unrelated suite), so no suite pins the text of any of the 18; (3) two mutants per site in the rehearsal (an inversion and a force-no-match, see the observer table in Phase 4 evidence) show which sites their suite actually reaches. A site that no suite reaches is still converted: the conversion is the transform `verify` proves, and the PR body lists the unreached sites.

### Suspect files read (R2 over-inclusion)

The codemod holds a whole file when its text names `sigpipe`, `EPIPE`, `false-FAIL` or `broken pipe`. Each of the nine was grepped for the words and the hit lines were read in context.

| File | Where it names the word | Verdict | Converted hits (lines) |
| --- | --- | --- | --- |
| `followthroughs/inngest-provision-unit-8562.test.sh` | line 249, a section header: the banned `${VAR:?}` form "would turn an unset secret into a daily false-FAIL" | comment only | 1 (line 251) |
| `followthroughs/inngest-zot-boot-7462.test.sh` | line 157, the same header | comment only | 1 (line 162) |
| `guard-vacuity-floor.test.sh` | line 1411, a comment "would false-fail correct suites" | comment only | 2 (907, 908) |
| `plugin-delivery-canary.test.sh` | line 156, the authoring rule "NEVER `producer \| grep -q PATTERN`" above a here-string helper | comment only; the converted hit (607) is a leading-pipe continuation whose previous line ends in a backslash | 1 |
| `prod-version-drift-check.test.sh` | line 481, a comment on an ordering pin that "false-FAILED" | comment only | 10 (6 plain, 4 `grep -m` displays by hand) |
| `sentry-issue-discover.test.sh` | line 6, a header comment "false-FAILing every ..." | comment only | 13 (two lines carry two hits) |
| `test-all-affected.test.sh` | lines 47 and 1369, authoring-rule comments | comment only | 1 (2706) |
| `test-contention.test.sh` | line 10, an authoring-rule comment | comment only | 1 (2218) |
| `test-all.sh` | lines 753, 1716, 1906, 2470, 4348, 4372, 5870, comments on SIGPIPE in neighbouring code | comment only; the two hits are 669 and 6476 | 2 |

None demonstrates the shape on purpose (no early-quitting-reader stub, no `# sigpipe-demo: intentional` candidate), so no marker is added and no counted pin is kept.

### Institutional learnings applied

- `knowledge-base/project/learnings/test-failures/2026-10-08-a-pair-run-needs-a-real-base-checkout-and-the-mandated-ulimit-aborts-vitest-on-both-sides.md`: the pair-run base is a real clone at the base SHA; vitest-spawning suites run without the cap.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-mechanical-rewrite-of-800-test-lines-needs-a-shell-aware-classifier-and-a-dry-run-that-names-what-it-refused.md`: classify before transform; this plan reads every refused line.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-diff-verifier-cannot-use-the-hunk-as-its-unit-because-adjacent-changed-lines-merge.md`: `verify` keys hand edits by exact base-side range, and refuses an entry that is wider than the edit (measured here: listing the 18 plain-transform data lines as hand edits made `verify` print `unexplained: 36`; they are not hand edits to `verify`).
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-ceiling-at-slack-zero-is-satisfied-by-moving-a-hit-between-two-files-and-a-file-exact-test-row-reads-as-production.md`: no file-exact rows; S3 avoids the hole by reaching zero.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-behavior-preserving-grep-conversion-needs-rows-that-see-discrimination.md`: rows before the rewrite; mutants killed only on their named FAIL text.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-test-replica-of-production-logic-keeps-the-shape-the-carrier-just-dropped.md`: a stub or replica can keep the shape; here the stubs are quoted-heredoc text and are converted in place.
- `knowledge-base/project/learnings/2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: any non-registration edit of `scripts/test-all.sh` degrades `--affected` to the full battery (91.4 min of manifest weight); decided up front.
- `knowledge-base/project/learnings/test-failures/2026-10-06-a-source-text-pin-over-a-file-is-a-pipe-into-grep-q-so-the-suite-that-pins-its-own-subject-is-in-the-class.md`: self-pinning suites are in the class (several of these 47 read their own subject).
- `knowledge-base/project/learnings/2026-09-25-the-errexit-model-must-be-judged-at-the-commands-position-and-every-text-channel-is-an-fp-vector.md`: the body of `bash -c '...'` and an `eval`-ed string runs in another shell, so those lines are code for that shell (the reason the 17 data lines are converted, not pinned).
- `knowledge-base/project/learnings/2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`: a mutant counts as killed only on its named FAIL text with rc 1.
- `knowledge-base/project/learnings/workflow-issues/2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md`: SIGPIPE shows only at real input scale; a pair run on small fixtures proves "no verdict change", never "the race is gone".

## Open Code-Review Overlap

88 open `code-review` issues were searched for the 48 edited paths and the codemod (two-stage `gh issue list --json` then standalone `jq --arg`). Three matches, all **Acknowledge** (different concern, no folding):

- #8800 (census sandbox shares inodes with the live repo) names `scripts/test-all-affected.test.sh`: sandbox ownership is untouched by a one-token flag rewrite on line 2706.
- #8659 (test suites replace test-helpers' composed EXIT trap) names `scripts/test-all.sh`: trap ownership is untouched.
- #7942 (mutation batteries named `*.mutation.sh`) names `scripts/test-all.sh`: registration naming is untouched.

None is folded in; none is deferred.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh`: delete two table lines, `'scripts/*.test.sh | <= | 128 | #9217'` and `'scripts/test-* | <= | 2 | #9217'`, as the last edit (in between they are lowered to `<= | 22` and `<= | 0` for the red step, and `scripts/test-*` is deleted as soon as the codemod reaches it). Nothing else: not `SWEEP_PROBE_CHECKS`, not a comment, not the header text, not any other row. Net diff at planning: 2 deletions, 0 insertions; review added the `scripts/` canaries to the real-table probe (see the evidence file).
- 42 test and runner files edited by the codemod (108 lines), all under `scripts/`. The 33 files of the default pass (each `scripts/<name>.test.sh`; the `followthroughs/` ones are `scripts/followthroughs/<name>.test.sh`): `actions-queue-health`, `battery-ref-guard`, `battery-tag-authorship-mutations`, `domain-model-drift`, `ensure-doppler`, `extract-api-spend`, `followthroughs/actions-queue-tail-8450`, `followthroughs/ghcr-read-retired-8036`, `followthroughs/git-data-reboot-evidence-landed-8210`, `followthroughs/inngest-luks-property-8296`, `followthroughs/inngest-zot-client-authz-6500`, `followthroughs/send-failed-alert-probe-8097`, `followthroughs/ship-merge-mergebase-verdict-8151`, `followthroughs/workspaces-plaintext-hold-9348`, `infra-config-red-alert`, `lint-dual-lockfile`, `lint-followthrough-varq-ban`, `lint-trap-tempfile-ownership`, `markdown-lint`, `measure-plan-sharp-edges-turns`, `pre-push-ratchet-lane`, `raise-tmp-tmpfs-ceiling`, `review-reminder-liveness`, `rule-metrics-aggregate`, `rules-loader-stamp-probe`, `skill-freshness-aggregate`, `tenant-dpa-register-guard`, `test-all-group-affected`, `test-all-orphan-log-retention`, `web-host-escrow-preflight`, `web2-rebirth-never-pooled`, `web2-rebirth`, `zot-restart-loop-alarm`. The nine reviewed-suspect files: `followthroughs/inngest-provision-unit-8562`, `followthroughs/inngest-zot-boot-7462`, `guard-vacuity-floor`, `plugin-delivery-canary`, `prod-version-drift-check`, `sentry-issue-discover`, `test-all-affected`, `test-contention` (each `.test.sh`) and `scripts/test-all.sh`.
- 8 files carry the 22 non-codemod edits; 5 of them are not in either codemod list: `followthroughs/concierge-strand-754ee124-5733`, `followthroughs/web2-luks-live-6931`, `lib/trusted-verdict`, `watch-live-verify-pass`, `web2-rebirth-recovery-check` (each `.test.sh`); the other three (`prod-version-drift-check`, `pre-push-ratchet-lane`, `test-all-orphan-log-retention`) are also in the codemod lists above.

The union is 47 files under `scripts/` plus the guard (48; the list is in the session scratch directory and in AC-2 as a command, not a pathspec).

Not touched, on purpose: `scripts/grep-q-drain-codemod.py` and the guard's selftest (S1; deleted in S7), `scripts/lib/test-affected-paths.sh`, `plugins/soleur/skills/work/SKILL.md` (and every other `SKILL.md`: the three `.md` fences that carry the shape, in `ship`, `merge-pr` and `postmerge`, are Item F), `.mcp.json` of the main checkout, and `scripts/followthroughs/watchdog-debounce-soak-9686.sh` (pre-staged by someone else; stage by explicit path, never `git add -A` or `git add .`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s3-scripts-tests/tasks.md`, `decision-challenges.md`, `hand-edits.txt` (4 entries, base-side line numbers, `verify` input) and `data-conversions.txt` (18 entries, the classification evidence). All four are written by this planning pass.
- One learning file under `knowledge-base/project/learnings/test-failures/` (candidate in AC-10), written at work time only if still non-obvious. No new `*.test.sh`: a new suite would fall into the covered floor scope and need a `run_suite` registration in `scripts/test-all.sh`, which is itself a runner edit.

## Problem Statement

The guard defers 130 test-harness sites under `scripts/` behind two `<=` ceilings that only a human lowers, so a new early-exit pipe under `scripts/` (584 of the 1,744 tracked files with a covered extension outside `knowledge-base/`, by `git ls-files`) can hide in slack the moment someone converts a site and forgets the number. Most of the bulk is the mechanical transform S1 built a tool for; the rest is 22 lines the tool declines for reasons that are individually checkable (a `-m` display, a quoted string that is executed, one false positive of the producer screen).

## Proposed Solution

### The conversion form

Unchanged from S1 and S2: `<producer> | grep -q<flags> ARGS` becomes `<producer> | grep -c<flags> >/dev/null ARGS` (`q` replaced by `c`, the redirect inserted immediately after the flag cluster). For stdin-only operands (every converted site; with a FILE operand `grep -c` exits 2 on a missing file where `-q` can exit 0, which is out of contract) the exit status equals `grep -q`'s (0 iff a line was selected, `-v` and empty input included; S1 checked 1,080 rows under bash and dash), it reads the whole stream so the producer never takes EPIPE (re-probed in Phase 0, including the negated arm), and it is valid in `/bin/sh`. The insertion `>/dev/null` contains no quote or expansion character, so it is safe inside a single-quoted, double-quoted or heredoc-quoted layer; that is why the 17 string-embedded lines can take the same transform without re-quoting.

### Disposition of every line that is not plain T0 (22 lines, re-read at file:line, base side)

| Site | Kind | Disposition | Observer |
| --- | --- | --- | --- |
| `followthroughs/concierge-strand-754ee124-5733.test.sh:59` | stub-heredoc | `printf '%s' "$*" \| grep -q -- '--repo jikig-ai/soleur' \|\| { ...; exit 64; }` inside the quoted-heredoc `gh` stub (the suite sets `pipefail`); converted | `grep -m 0` (force no-match) killed: `an operator PASS closes the tracker — wanted rc=0, got rc=2`; the `-vc` inversion survives |
| `lib/trusted-verdict.test.sh:57`, `:58` | stub-heredoc | the stub's `issue view` argument checks (`--json comments`, `--repo ...`), executed under the stub's own `set -uo pipefail`; converted | `grep -m 0` killed both at row 1 (`expected rc=0 with no verdict; got rc=2`); the `-vc` inversion survives both, because the stub's `$*` spans the multi-line jq expression and only its first line contains the pattern, so `-v` still selects a line (the branch is reached 60 times in a suite run, measured) |
| `watch-live-verify-pass.test.sh:34`, `:35`, `:38`, `:39` | stub-heredoc | four `printf '%s ' "$@" \| grep -q -- '--json ...'` branch selectors of the quoted-heredoc `gh` mock (`<<'MOCK'`); converted | both mutants killed on all four lines (first red rows `(c)`, `(b)`, `(c)`, `(c)` for the inversion; `(c)`, `(b)`, `(e)`, `(c)` for force-no-match) |
| `pre-push-ratchet-lane.test.sh:578` | stub-body | the argument of `stub()` that becomes an executed ratchet-lane member (`if env \| grep -qE "^(GIT_DIR\|...)="; then exit 1; fi`); converted | the `-vc` inversion killed (`FAIL: env scrub: rc=1`); force-no-match survives, by construction (the arm asserts the clean path) |
| `followthroughs/web2-luks-live-6931.test.sh:135`, `:255`, `:258` | eval-string | `expect "label" bash -c "..."` strings (T01 has two q-greps on one line, T39 is negated); converted. The child `bash -c` shell does not inherit `pipefail`, so these three are inert today and are converted for the ledger and the idiom | 135: both killed (`T01`); 255: inversion killed (`T39`), force-no-match survives (negated line); 258: both killed (`T40`) |
| `web2-rebirth-recovery-check.test.sh:119`, `:122`, `:123`, `:171`, `:173`, `:174` | eval-string | `as "label" '<expr>'` runs `eval "$2"` in a shell that set `pipefail` at line 6, so these are live; five are negated (`! ... \| grep -q`) and fail open on a SIGPIPE'd producer; converted | 119 and 173: both killed; 122, 123, 174: inversion killed, force-no-match survives (negated lines); **171: neither mutant is killed** (a negated line whose input holds no match, so both mutants leave it true) |
| `test-all-orphan-log-retention.test.sh:82` | X false positive | `&& printf '%s\n' "$wd_block" \| grep -q 'sleep "$_RUN_WD_POLL_S"'`: refused because `sleep` is inside the pattern; the producer is `printf`; the previous line of the same condition is already converted by the codemod; converted by hand | force-no-match killed (`FAIL: watchdog block must contain a polling loop`); the inversion survives (the block has other lines) |
| `prod-version-drift-check.test.sh:1691`, `:1697`, `:1723`, `:1788` | H-m | `$(printf '%s' "$X" \| grep -mN ... \| tr '\n' ';')` inside failure messages becomes `$(grep -mN ... <<<"$X" \| tr '\n' ';')` (no producer to signal). The producer was a `printf` of a variable, which cannot fail, so dropping it loses no exit status; a here-string turns empty input into one blank line, and none of the four patterns (`^  FAIL`, `^    (expected\|actual):`, `^  (FAIL\|PASS: B9 threshold)`) matches a blank line (scratch run on an empty value: old and new both print nothing) | none by construction (failure-branch display); scratch run of old and new expression on a three-line input whose first match is on line 2 |

So S3 removes 130 lines of 130; nothing is left counted and no marker is used.

### Ledger lowering

| Row | Before | After |
| --- | --- | --- |
| `scripts/*.test.sh` | `<=` 128 | deleted (0 hits) |
| `scripts/test-*` | `<=` 2 | deleted (0 hits) |
| the other eleven rows | unchanged | unchanged (`.claude/*.test.sh` 5, `tests/*` 181, `plugins/soleur/test/*` 5 `=`, `plugins/soleur/*.test.sh` 66, `apps/web-platform/*.test.sh` ceiling 180 with 178 hits, six production rows 23) |
| `DEFERRED:` lines printed | 13 | 11 |
| Test-shaped total (sum of the test-shaped ceilings: seven rows before, five after) | 567 | 437 |

Row order is semantic ("first match wins") but no remaining row can own a path under `scripts/` (`apps/web-platform/*.test.sh` and `plugins/soleur/*.test.sh` are broader globs that do not start with `scripts/`), which the matrix row 1 below measures.

### Phases

**Phase 0, re-measure and gate (read-only).** `git fetch origin main`; if `origin/main` is ahead of the branch, merge it once at the start (never mid-flight afterwards) and re-run everything below. (1) Gating probe on the dev host and in `docker run --rm ubuntu:24.04`: `bash -c 'set -o pipefail; (echo 1; sleep 0.4; echo 2) | grep -q 1; echo "q: $?"; (echo 1; sleep 0.4; echo 2) | grep -c 1 >/dev/null; echo "c: $?"; (echo 2; sleep 0.4; echo 3) | grep -c 1 >/dev/null; echo "nomatch: $?"; ! (echo 1; sleep 0.4; echo 2) | grep -q 1; echo "neg-q: $?"; ! (echo 1; sleep 0.4; echo 2) | grep -c 1 >/dev/null; echo "neg-c: $?"'`. It must print `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0` and `neg-c: 1` (measured on GNU grep 3.12 and 3.11); if `c` prints 141 stop. (2) Run the guard, keep the `DEFERRED:` lines; run the two-row `apply` dry run and diff its census and QUEUE against the tables above (any new queue entry stops the plan until read). (3) Re-run the trigger derivation over the union of the dry run's file list, `hand-edits.txt`, `data-conversions.txt` and the guard (expect 0 of 48 for every path-filtered workflow) and the open-PR intersection plus the added-hit screen. (4) `uptime`; if the load average exceeds the core count, the pair run's wall times are not comparable and the table says so. (5) `grep -l vitest` over the edited files: a suite that starts a worker runs without `ulimit -v`.

**Phase 1, red first.** Edit only the guard: `scripts/*.test.sh | <= | 22 | #9217` and `scripts/test-* | <= | 0 | #9217`. The guard must go RED on both (`has 128 hits, ceiling 22`, `has 2 hits, ceiling 0`, measured): that is the failing test the conversion has to satisfy (`cq-write-failing-tests-before`; the instrument is the existing guard, so there is no new test to write). The rows stay `<=` because `apply --write` refuses a `=` row and needs the rows to exist.

**Phase 2, convert.** Commit 1: guard rows lowered, `apply --row 'scripts/*.test.sh' --row 'scripts/test-*' --write` (80 lines), then the same with `--reviewed-suspect` for the nine files (28 lines), then delete the `scripts/test-*` row (it now has no hits and the guard says stale). The guard is green at `scripts/*.test.sh` 22 hits against ceiling 22. Commit 2: the 22 hand edits (the 18 one-token conversions by a throwaway rewrite that touches only the lines in `data-conversions.txt`, the 4 here-strings by hand), `hand-edits.txt`, then the idempotency dry run `apply --row 'scripts/*.test.sh'` (`WOULD-CHANGE: 0 lines in 0 files`), then delete the `scripts/*.test.sh` row as the LAST edit. Stage by explicit path.

**Phase 3, verify.** `python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s3-scripts-tests/hand-edits.txt` prints `verified: 126`, `hand-edited: 4`, `unexplained: 0`. The set of base-side lines changed outside the codemod passes equals `hand-edits.txt` union `data-conversions.txt` (22). `bash -n` on the 47 files; `git diff --numstat` equal insertions and deletions per file and `wc -l scripts/test-all.sh` unchanged. Pair run (below). Then `bash scripts/pre-push-ratchet-lane.sh` (detached, rc file, no foreground timeout shorter than its own bound), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`. `bash scripts/test-all.sh --print-selection` on the branch diff: record the `AFFECTED_FALLBACK reason=runner-changed` line. **Runner parity** (the one check CI's full battery cannot make, because it runs through the runner being edited): for the same synthetic path sets (`README.md`, one `scripts/*.test.sh`, `scripts/test-all.sh`, one `plugins/soleur/skills/**` path) `bash scripts/test-all.sh --print-selection --paths=<set>` and `bash scripts/test-all.sh --enumerate-commands all` on the base clone and on the branch print the same sorted `AFFECTED_*` lines and the same digest of the `SUITE_COMMAND` records (the `NOTE:` lines of the enumeration depend on whether the clone has an `origin/main` ref, so they are left out of the digest); the two edited lines (a bare-repository guard and a recovery-text branch) feed neither. Measured at planning on the rehearsal clone against a clone at `fd1c4d5cac`: the four path sets (582, 582, 2 and 583 `AFFECTED_*` lines) and the 591 `SUITE_COMMAND` records are identical.

**Pair run.** Base = a real clone of this repository checked out detached at the base SHA (`git clone --local --no-hardlinks --no-checkout`, `git checkout --detach <sha>`), never `git archive`. Branch = the worktree. Both sides sequential under `ulimit -v 6000000`, per-suite `timeout` = the larger of 300 s and four times the suite's `suite-durations.tsv` weight (so `test-all-affected` gets 1,245 s; `web2-rebirth-recovery-check` read 151 s on the base side under load at planning against a 35 s weight), cwd = the side's root, rc and result line compared. A timeout on both sides is `inconclusive`, never `identical`. A suite that needs `node_modules` runs on both sides with the worktree's linked in, or is `not run locally` with the reason. The 15 suites that carry a hand edit or a reviewed-suspect conversion (8 hand-edit files plus 9 reviewed-suspect files, `prod-version-drift-check` in both, minus the runner `scripts/test-all.sh`, which is not a suite) plus `test-all-group-affected` (the one runner-exercising suite not among them; `test-all-affected`, `test-all-orphan-log-retention` and `test-contention` already are) must read identical: 16 suites. The rest are `identical`, `not run locally` or `inconclusive` with the reason; CI is the gate.

**Phase 4, hand-applied mutation battery** (Guard Contract matrix plus the observer table) on scratch copies, one mutant at a time under `ulimit -v 6000000`, a green control first, the first red line recorded from printed output, restore check clean. The two runner lines get their own evidence (below).

**Phase 5, evidence and ship.** One learning file if still non-obvious; tracker comment on #9217 (before and after `DEFERRED:` table, the command behind each number, the NOT-fixed list); the ship tail. The PR body names which later work lowers the next rows (S4 `tests/*`, S5, S6, Item F for the `.md` carriers). Sequencing: the lines S3 deletes (445 and 446 of the guard) sit directly below `apps/web-platform/*.test.sh` (444, S5's ceiling line), so S5's hunk abuts S3's and conflicts; S4's `tests/*` line (439) is six lines away and merges cleanly, and S6 conflicts only if it edits the apps row. The tracker's 2026-10-08 20:32 comment says S3, S4 and S5 "can be cut now"; this narrows it to "S4 may run in parallel, S5 waits for S3" (decision-challenges item 21). The merge queue ejects rather than rebases, and no BEHIND branch is re-synced mid-flight. Paste the throwaway rewrite used for the 18 plain-transform lines (about 12 lines of Python: one regexp over the named base-side lines) into the #9217 evidence comment so S4 to S6 can reuse it for their own executed-string sites.

### The two runner lines (`scripts/test-all.sh`)

- Line 669, the bare-repository guard: observed by a scratch run from a bare repository (`git init --bare`; `bash <runner>` from inside it), old and new runner both print `ERROR: Cannot run tests from a bare repository root.` and exit 1 (measured). The must-FAIL row: with `-vc` on line 669 of a scratch copy, `bash scripts/test-all.sh --print-selection --paths=README.md` in a non-bare checkout prints that same `ERROR` line (measured), so any run of the runner reds. Run the shipped bytes, not retyped text: extract `sed -n 669p` and `sed -n 6476p` from the base clone and the branch file and run both extractions on the same inputs.
- Line 6476, the recovery text of the repository-boundary fatal: unobservable by construction (it prints only after a suite wrote to the live repository). Evidence is a scratch run of old and new expression over `FATAL head`, `FATAL worktree`, `FATAL config` and an empty value, identical exit status (Phase 4).

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Leave `scripts/test-all.sh` out and keep `scripts/test-* = 2` as counted pins | Avoids the `runner-changed` fallback, but keeps a `=` row alive for a runner-only reason, leaves two live `producer \| grep -q` lines in the file CI executes first, and S7's exit ("no glob row left") would still carry it. The fallback costs only a local gate that CI duplicates. Challengeable (decision-challenges item 1) |
| Keep the 17 data lines as counted pins (S2's posture for its five) | S2's pins pinned the text of a carrier (`.md` fences, mutation rows); these 17 are executed code, so a pin would be a lie about what the line is, and it would leave a `=` row that can be satisfied by add-one-delete-one |

## User-Brand Impact

- **If this lands broken, the user experiences:** a shell test suite under `scripts/` that stopped asserting what it names (a follow-through probe whose exit code makes the nightly sweeper act on a public tracker, the trusted-verdict matrix that stops a forged PASS from closing an issue, the production-version drift check, the CI test runner itself), so a regression in a verdict script or in the runner's start-up guard ships green; the visible symptom is a defect the suite exists to catch reaching a merged change, or, for the runner, every CI run failing at start.
- **If this leaks, the user's workflow is exposed via:** no secret or user data is read or written by the change; the exposure vector is a fail-open conversion that makes a security-adjacent assertion pass vacuously (a dropped `-x` or `-F`, an inverted `!`, a stub that stops refusing an unexpected call), in suites such as `web2-rebirth-recovery-check` (assertions that the passphrase never reaches stdout and that every Doppler call is a single-secret read) and `trusted-verdict`.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no conversion touches user data, 126 of 130 edits are one-token rewrites proved by `verify`, the 4 here-strings are display text on failure branches, and the 18 hand-converted lines are the same one-token transform, each read in context; not `none` because a systematic classifier or transform error would repeat across 47 suites, several of which guard verdicts and secret hygiene, and one edited file is the runner every CI job executes, so the section carries no `threshold: none` scope-out.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and merge_group run and prints PASS lines plus one DEFERRED line per row
  cadence: per PR and per merge_group run; run directly before each push
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no Sentry surface)
  fail_loud: a FAIL line naming the row and the exceeded, loose or stale ceiling, or the file and line outside the table, exit 1; an unreadable input, an empty derived population or a missing python3 prints UNRESOLVED and exits 3
failure_modes:
  - mode: a new early-exit pipe lands anywhere under scripts/
    detection: no row owns the subtree, so the hit reports "outside the deferral table"
    alert_route: required test check red on the PR
  - mode: a deleted row is put back with slack
    detection: a row with no hits fails "stale deferral ... delete its row"
    alert_route: required test check red on the PR
  - mode: a converted suite changes behavior
    detection: the suite's own result line compared base versus branch (recorded in the PR body) and the suite itself in CI
    alert_route: required test check red on the PR
  - mode: the runner's two converted lines misfire
    detection: the bare-repository guard fires on every run of the runner in a non-bare checkout; the fatal-branch text is covered only by the Phase 4 scratch run
    alert_route: every CI job that calls scripts/test-all.sh fails at start (loud), not silently
logs:
  where: CI job logs of the test check; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: grep-q-sweep-probe-pass
```

Detection note for preflight Check 10: one deterministic file, no build or network. The suite-shaped-command proxy (a `.test.sh` basename) fires on this command and is argued down by measurement. On 2026-10-08 on the converted rehearsal tree the guard took 12.9 s wall at a host load average of 15.9 (plain, under `ulimit -v 6000000`, rc 0) and 10.6 s inside a read-only `bwrap` with `env -i`, `PATH=/usr/local/bin:/usr/bin:/bin` and a tmpfs HOME (the Check 10 sandbox shape: `--ro-bind / /`, tmpfs `/var/tmp`, rc 0, `grep-q-sweep-probe-pass` printed once); its first, cold run on the base tree took 13.9 s at load 16.5. All of these are under the 15 s cap, but the margin is thin on a contended host (S2 measured 9.5 s at load 21), and AC-10 re-measures it after the edit. S3 removes two table rows, which only shortens the verdict loop. The block is the same command S1 and S2 declared.

## Guard Contract

### Guard 1 — the subtree `scripts/` after S3 has no deferral row

**Property.** After S3, no early-exit pipe into `grep` exists in any `*.sh`, `*.bash`, `*.bats`, `*.yml`, `*.yaml`, `*.tf`, `*.template` or `*.js` file under `scripts/`, and the guard goes red both when one is added and when a deleted row is put back.

**Assembly.** One population and one verdict: `scan_sweep <root>` (git grep over `SWEEP_PATHSPEC` with `PATTERN_V2`, comment and marker lines dropped) and `sweep_verdict` over `SWEEP_DEFERRALS`, plus the stale-deferral rule and the `DEFERRED:` print. The chokepoint is `scan_sweep`; the table is one array whose order is semantic (first match wins) and whose globs cross `/`. The property quantifies over every path under `scripts/` at any depth (top level, `followthroughs/`, `lib/`, a directory added next month), over every spelling `PATTERN_V2` matches (including the string-embedded and heredoc lines this slice converted, which the guard counts like any other line), and over both ways a row can be wrong (too tight is "exceeded", too loose or present with no hits is "stale"). The remaining rows cannot own a `scripts/` path (their globs start with another directory). The conversion tool (`apply`, `verify`) is a second reader of the same population, used as a parity check before any edit, never as a second ledger.

**Mutation matrix** (hand-applied on a scratch clone of the converted tree, one mutant at a time under `ulimit -v 6000000`, green control first; every "measured" cell was printed during planning on the rehearsal clone):

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `x="$(printf %s a)"; echo "$x" \| grep -q p` to `scripts/web2-rebirth.test.sh` (a path no remaining row can own) | RED rc 1: `pipe-into-early-exit-grep outside the deferral table (1 site(s))` (measured) |
| 2 | Revert one converted site: (a) `scripts/test-all.sh:669` back to `grep -q true`; (b) the hand-converted stub line `scripts/watch-live-verify-pass.test.sh:34` back to its `grep -q --` form | RED rc 1 for each: `outside the deferral table (1 site(s))` (measured; proves the conversion is tight against overshoot in the runner and in a hand-converted line) |
| 3 | Append a hit to two different files after a compliant first (`scripts/test-contention.test.sh` and `scripts/lib/trusted-verdict.test.sh`) | RED rc 1: `outside the deferral table (2 site(s))` (measured; a check that stops at the first member would read 1) |
| 4 | Put back the row `'scripts/*.test.sh \| <= \| 128 \| #9217'` (a lowering forgotten, a row resurrected with slack) | RED rc 1: `stale deferral: scripts/*.test.sh has no hits left — delete its row` (measured) |
| 5 | Put back the row `'scripts/test-* \| <= \| 2 \| #9217'` | RED rc 1: `stale deferral: scripts/test-* has no hits left` (measured) |
| 6 | Empty the table (`SWEEP_DEFERRALS=()`), the guard's own dispatch, on the converted tree and on the base tree | RED rc 1 on both: `outside the deferral table (458 site(s))` and `the derived sweep's own probe is broken` on the converted tree, `(588 site(s))` on the base tree (measured; the difference, 130, is S3's population; the listed sites are capped at 50, so the count and not the list is the discriminator) |
| 7 | Append a hit in a spelling the converted lines used (`printf '%s\n' "$x" \| grep -qF -- "$x"`) in a subdirectory file: (a) `scripts/followthroughs/ghcr-read-retired-8036.test.sh`, (b) `scripts/lib/trusted-verdict.test.sh` | RED rc 1 for each: `outside the deferral table (1 site(s))` (measured; the sweep, not a row glob, now carries the subdirectories) |
| 8 | Append a hit inside a quoted-heredoc stub line, the data class the guard counts like any other line (`if printf '%s ' "$@" \| grep -q -- "--json state"; then ...` to `scripts/watch-live-verify-pass.test.sh`) | RED rc 1: `outside the deferral table (1 site(s))` (measured; a data hit is a hit, so with no row it can neither hide nor be pinned) |
| 9 | The base content of the 47 files with both rows deleted (the complement of the conversion: every original shape visible with no row masking it) | RED rc 1: `outside the deferral table (130 site(s))` (measured on a clone at the base SHA) |
| 10 | Known surviving mutant: put the row back as `'scripts/*.test.sh \| <= \| 1 \| #9217'` and append one `\| grep -q` hit | GREEN rc 0 (measured: `DEFERRED: scripts/*.test.sh (1 hits, ceiling 1, mode <=, slack 0)`); the stale rule fires only at zero hits. Not covered; listed in Risks and the NOT-fixed list |

Harness rows. Suite edits that must go RED are rows 4 and 5 (a deleted row put back) and row 6 (the table emptied: the guard's own dispatch). Must-PASS inputs that differ from the canonical in a way the contract permits: a hit line carrying a trailing `# sigpipe-demo: intentional` (not counted, rc 0) and a line `x \| grep -cE >/dev/null -- "$p"` (a spelling no converted line used, rc 0). Each must-PASS row is only evidence if the mutation landed and the guard would have seen it: `git diff --numstat` shows exactly one added line in the target file, and a paired control appends the same line with `-q` and no marker (the old spelling), which goes RED at the same position (measured: row 1 is that control).

Anchor. The table lives in the file it protects, so one commit can move the table and the thing it protects together; this proves consistency, not integrity. What must also move for a weakening to pass: re-adding a row is a visible one-line diff in a file that is on the hook-suite registration, `verify` and the before/after `DEFERRED:` lines in the PR body and the tracker comment would disagree, and with no row at all there is nothing for a count to be moved between. The known hole that remains is the marker (`# sigpipe-demo: intentional` hides any line from the count and nothing caps its use per file), documented in the guard header and owned by Item F.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an engineering-internal CI-hygiene change with no product, marketing, legal, finance, sales or support surface. The engineering lens (classifier safety, ledger design, the runner edit) is carried by the plan-review panel.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Plan ONLY Item B slice S3 now (own plan): the guard rows `scripts/*.test.sh` (128 hits) and `scripts/test-*` (2 hits) in `.claude/hooks/grep-q-pipe-guard.test.sh`." [brief] | Overview, Census, Files to Edit, Phases | mapped |
| 2 | "Pass 1, Pass 2 and Item B slices S1 and S2 are DONE and merged (S2 = PR #9765, merge f1497664ae); do not redo them." [brief] | Premise Validation, Overview, Files to Edit (not touched list) | mapped |
| 3 | "S4 (`tests/*`), S5, S6, S7, Items D, E, F, G, I, H, the Wave A3 carriers and the #9638 and #9639 triage are LATER PRs, not this plan." [brief] | Research Reconciliation row 1, NOT-fixed list | mapped |
| 4 | "Per PR: evidence comment on the tracker (#9217), `Ref` not `Closes`, a plain NOT-fixed list, no [skip-deploy-fix-apply], nothing added to plugins/soleur/skills/work/SKILL.md." [brief] | Phase 5, AC-8, AC-10, AC-11 | mapped |
| 5 | "Run mutation batteries under `ulimit -v 6000000`, one mutant at a time." [brief] | Phase 4, Guard Contract, AC-6 | mapped |
| 6 | "Do not edit /data/git-repositories/jikig-ai/soleur outside this worktree; do not stage scripts/followthroughs/watchdog-debounce-soak-9686.sh." [brief] | Files to Edit (not touched list), Phase 2, AC-10 | mapped |
| 7 | "confirm what S3 owns; do not guess the slice boundaries" (tracker comments and the S1 Slice Register) [brief] | Research Reconciliation row 1 | mapped |
| 8 | "(a) ... decide from the code what is actually hit and how it must be handled" for `scripts/test-all.sh` and the suspect-only `scripts/test-*` row [brief] | Research Reconciliation rows 3 and 4, "The two runner lines", Alternatives row 1 | mapped |
| 9 | "(b) intersect the exact edited-file list with `gh pr list --state open --json number,files` and say what happens on a conflict" [brief] | Research Reconciliation row 5, AC-2 | mapped |
| 10 | "(c) derive which workflows fire on merge for the exact edited files ... verify" [brief] | Overview, Trigger derivation, AC-8, AC-11 | mapped |
| 11 | "(d) the S2 lessons: ... real detached checkout ... vitest ... `<=` row ... verify every causal sentence you write with a command; the guard row comment must not overclaim." [brief] | Pair run, Phase 0, Phase order, Research Reconciliation rows 7 to 9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Converting the 108 mechanical lines in 42 files with the S1 codemod | "Plan ONLY Item B slice S3 now" and the lead's dry run `apply --row 'scripts/*.test.sh' --row 'scripts/test-*'` | asked |
| Deleting the two rows | "the guard rows `scripts/*.test.sh` (128 hits) and `scripts/test-*` (2 hits)" | asked |
| Evidence comment on #9217, `Ref`, NOT-fixed list | "evidence comment on the tracker (#9217), `Ref` not `Closes`, a plain NOT-fixed list" | asked |
| Mutation battery | "Run mutation batteries under `ulimit -v 6000000`, one mutant at a time." | asked |
| Open-PR intersection, trigger derivation | "(b) open PRs touch some candidate files" and "(c) derive which workflows fire on merge" | asked |
| `--reviewed-suspect` for the nine files, including `scripts/test-all.sh` | "the `scripts/test-*` row is suspect-only: decide from the code what is actually hit" | asked |
| Converting the 18 plain-transform data and X lines by hand instead of keeping them as pins | "decide from the code what is actually hit and how it must be handled" | inferred — justification: the lines are executed code (stub heredocs, `eval`), so a counted pin would misdescribe them and would keep a `=` row open; the row going to zero is the series' stated exit |
| The four `grep -m` here-string rewrites | "start with ... the guard's DEFERRED: lines" (the S2 convention) | inferred — justification: `-m` is output-bearing and cannot take `-c`; each is a hit the guard counts |
| Phase 0 negated-arm drain probe | "verify every causal sentence you write with a command" | inferred — justification: the fail-open claim for `! ... \| grep -q` is causal and is measured in the same probe as the S2 gate |
| Deciding not to run `--affected` locally | "(a) S1 plan says S3 touches scripts/test-all.sh, which degrades local `--affected` to the full battery" | inferred — justification: the brief asks to decide what happens; a stop condition chosen at hour two is what S2 recorded as a session error |
| `hand-edits.txt`, `data-conversions.txt`, `tasks.md`, `decision-challenges.md` | "Only files under knowledge-base/project/{plans,specs}/ may be modified." | inferred — justification: `verify` consumes the first, the classification evidence is the second, `soleur:work` consumes the third, the headless contract persists taste decisions in the fourth |
| One learning file | "a plain NOT-fixed list" | inferred — justification: the series convention is one learning per non-obvious finding; AC-10 names the candidate and forbids filler |

### Split Assessment

- Subsystems touched: 3 — `scripts`, `.claude`, `knowledge-base`
- Planned files: about 54 (47 scripts files, the guard, four spec files, the plan, one learning) | Estimated changed lines: about 190 (130 one-line edits, 2 guard lines, about 50 lines of documents)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the file count crosses the threshold only because the 47 test files are one-line edits proved by one `verify` run; the series boundary (one deferral area per PR) is already the split, and cutting the area in two would put two PRs on the same two table lines.

## Acceptance Criteria

Pre-merge boxes are checkable on the final tree; post-merge boxes are executed by `soleur:postmerge` and the tracker comment, with no human step.

### Pre-merge (PR)

- [ ] AC-1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0, prints 11 `DEFERRED:` lines and none for `scripts/`; the eleven lines are byte-identical to the merge-base's other eleven (`diff` of the two `DEFERRED:` sets is exactly the two deleted lines); the test-shaped total is 437 (sum of the five remaining test-shaped ceilings), down from 567 (sum of the seven before), both sums pasted in the PR body, together with the two `deferral ceiling exceeded` lines of the Phase 1 red run (the failing test, which is otherwise never committed). If Phase 0 finds different counts, the AC carries the re-measured numbers.
- [ ] AC-2 `python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s3-scripts-tests/hand-edits.txt` prints `verified: 126`, `hand-edited: 4`, `unexplained: 0` after `git fetch origin main` (the base SHA is named in the PR body); the idempotency dry run before the last row goes prints `WOULD-CHANGE: 0 lines in 0 files`; `bash -n` passes on all 47 edited files; `git diff --numstat origin/main...HEAD -- scripts/` shows equal insertions and deletions (130 each) and `wc -l scripts/test-all.sh` is unchanged; the base-side lines changed outside the two codemod passes equal the entries of `hand-edits.txt` plus `data-conversions.txt` (22, compared by command, not by eye); the open-PR intersection list is pasted (expect #9745, #9772, #9640, #7390, #6778 by file, no hunk within three lines). `verify` proves the transform only, not that a converted line was code rather than data (that is the table read in this plan and AC-4).
- [ ] AC-3 The Phase 0 drain probe printed `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0` and `neg-c: 1` on the dev host's grep and inside `ubuntu:24.04`, with both outputs in the PR body.
- [ ] AC-4 The PR body carries the pair-run result: a one-sentence summary for the suites that read identical and one row for each suite that differed or needs a caveat. Per suite it states: identical rc and result line between the clone at the base SHA and the branch, or `not run locally` with the reason, or `inconclusive` (timeout both sides). The 16 suites named in Phase 3 (the 15 that carry a hand edit or a reviewed-suspect conversion plus `test-all-group-affected`) must read `identical`; `not run locally` and `inconclusive` are allowed only for the rest. CI's required test check is the stated gate for P4; the table adds the before/after comparison CI cannot make. A difference blocks the PR until explained. The body states that a pair run on small fixtures shows "no verdict change", not "the race is gone".
- [ ] AC-5 The runner-parity digests of Phase 3 (four selection path sets and the `SUITE_COMMAND` enumeration) are equal on the base clone and the branch (pasted); `bash scripts/pre-push-ratchet-lane.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` and `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new) pass; `bash scripts/test-all.sh --print-selection` on the branch diff prints `AFFECTED_FALLBACK reason=runner-changed` and that line is pasted in the PR body together with the sentence "`scripts/test-all.sh --affected` was not run: the diff edits the runner, so it would run the full battery (91.4 min of manifest weight), and CI's required test check is the gate".
- [ ] AC-6 The Guard 1 matrix was hand-applied on scratch copies after a green control, one mutant at a time under `ulimit -v 6000000`, each RED row killed by its named FAIL text with rc 1 (an rc 2, 126 or 127, or a crash, is an instrument failure and not a kill), the restore check clean (`git status` empty in the scratch copy), and the two must-PASS rows rc 0 with their landing check (`git diff --numstat` +1 in the target) and paired RED control; rows 1 to 9 are RED and row 10 is recorded as the surviving mutant.
- [ ] AC-7 The hand-edit observer table is in the PR body: for each of the 18 hand-converted plain-transform sites the result of swapping `-c` for `-vc` (killed with the first red line, or survived with the reason), for the four `-m` displays one scratch run of old and new expression on a three-line input whose first match is on line 2 with identical stdout, and for the two runner lines the bare-repository scratch run (old and new runner both rc 1 with the same text) and the `FATAL` pattern run. A surviving mutant is listed as unobserved by its suite and is not claimed as covered. Reader-side mutants cannot see a negated line whose upstream stages already fail under `pipefail` (the final reader only matters when the input holds a violation); for `web2-rebirth-recovery-check.test.sh:171` the observer is a SUT-side mutant (append `doppler run -- true` to the script under test), killed on the converted and the base tree with the same `FAIL no doppler run, no download, no insecure curl`. The four `-m` displays also get an empty-input and a no-match run. The pair run (AC-4) supports P4 only for the sites this table marks killed.
- [ ] AC-8 The PR body (authored by `soleur:ship` from the diff plus `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s3-scripts-tests/`) has as its first line that merging fires no path-filtered workflow (the trigger derivation output over the 48 files, 0 of 48 for each of the 18 filtered ones) and no plugin or web-platform release, apply or deploy; `Ref #9217` and never `Closes`; no `[skip-deploy-fix-apply]`; a `## Changelog` section; the NOT-fixed list under a heading that avoids the ship-gate deny tokens; the three acknowledged code-review issues; labels `semver:patch`, `type/chore`, `domain/engineering` (the series convention; no `app:web-platform`).
- [ ] AC-9 Untouched, each checked against the merge-base: `git diff --stat origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md scripts/grep-q-drain-codemod.py scripts/lib/test-affected-paths.sh` is empty; `git diff --numstat origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh` prints the two deleted rows plus the review-round canary lines in the real-table probe (amended at review: `git diff --numstat` shows 7 added and 8 removed lines, and `SWEEP_PROBE_CHECKS` and every other row are unchanged); no commit lists `scripts/followthroughs/watchdog-debounce-soak-9686.sh`; the main checkout's `.mcp.json` was not touched; no file outside this worktree and the session scratch directory was written.
- [ ] AC-10 One learning file (candidate: a codemod's `verify` counts a hand-converted plain-transform line as verified and refuses a hand-edit entry for it, and the stale-deferral rule makes "delete the row" the only terminal state of a row that reaches zero; and a reader-side mutant cannot see a negated line whose upstream stages already fail under `pipefail`), written only if still non-obvious at work time; `markdownlint-cli2` is clean on the plan, `tasks.md`, `decision-challenges.md` and the learning; the discoverability command is re-measured under the 15 s cap after the guard edit, plain and in a Check 10-shaped `bwrap`.

### Post-merge (automated)

- [ ] AC-11 `soleur:postmerge`: `gh run list --json workflowName,headSha,conclusion` for the merge SHA shows the seven unfiltered push workflows and none of the 18 path-filtered ones (no `version-bump-and-release`, `web-platform-release`, `apply-web-platform-infra`, `apply-deploy-pipeline-fix` or `infra-validation` run exists for that SHA), recorded as such; CI on main is green and the `test` job's suite total (the `of=N` figure in its `AFFECTED_SUMMARY`/enumeration line, or the ledger total) equals the previous main run's, so the runner edit did not shrink the battery; the files are verified at the merge SHA (`git show <sha>:.claude/hooks/grep-q-pipe-guard.test.sh \| grep -c "^  'scripts/"` prints 0, a count and not a `grep -q`).
- [ ] AC-12 Tracker comment on #9217 with the before and after `DEFERRED:` table, the per-tier counts, the command behind each number, and the NOT-fixed list; the `Filed:` line, Merge Danger (`Undo:` and `Blast Radius:`), Pipeline Tally, Changelog and Model Dissents sit in the PR body.

NOT fixed by S3 (stated in the PR body and the tracker comment): the other 437 test-shaped ceiling units (S4 `tests/*` 181; S5 and S6 `plugins/soleur/*.test.sh` 66 and `apps/web-platform/*.test.sh` 180, which is 178 hits with slack 2 and includes the infra suites; five data pins in `plugins/soleur/test/*`; five data lines in `.claude/*.test.sh`); the 23 wave A3 production sites; the producer-side join (S7); the guard's own blind spots (Item F: variable binary, flag order, wrappers such as `time`, `sh -c`, a subshell group or `rg`, split-line pipes, `| head`, the `.md` fences in `ship`, `merge-pr` and `postmerge` SKILL.md, `.ts`; the marker `# sigpipe-demo: intentional` accepted with trailing text or inside a string and not counted per row; no per-extension probe for `.bash`, `.bats` and `.yaml`); the codemod edge cases S1 listed and the producer screen's false positive on a quoted `sleep`; `verify`'s trust gaps (it cannot tell code from data); the local `--affected` fallback itself (S3 accepts it for one PR; it is a property of editing the runner); #8659, #8800 and #7942; #9638 and #9639; the dead `test-*` clause that remains in the guard header legend and in `_ts_re` once no `test-*` row exists (S7 cleanup list); the S7 exit ledger (after S3 the glob rows left are `.claude/*.test.sh` `<=` 5, `plugins/soleur/test/*` `=` 5, `tests/*`, `plugins/soleur/*.test.sh` and `apps/web-platform/*.test.sh`, so neither wording of the S1 plan's S7 exit, line 347 "no glob row left" or line 570 "except data-pin rows on wave A3 carriers", is met by them; S7's plan reconciles it); #9772's new `scripts/ci-demand-census.test.sh:847` (another PR's file, named in the PR body).

## Test Scenarios

- Given the rows at `<= | 22` and `<= | 0` before any edit, when the guard runs, then rc 1 with `has 128 hits, ceiling 22` and `has 2 hits, ceiling 0` (Phase 1 red).
- Given the 108 codemod edits applied, when the guard runs with `scripts/test-*` still present, then it prints `FAIL: stale deferral: scripts/test-* has no hits left`; with that row deleted it is green at 22 hits against ceiling 22.
- Given all 130 edits applied and both rows deleted, when the guard runs, then rc 0 and 11 `DEFERRED:` lines, none for `scripts/`.
- Given a row `scripts/*.test.sh | <= | 128` put back, when the guard runs, then `stale deferral` and rc 1.
- Given a writer that emits a second line after the first match and a negated pipeline, when it feeds `grep -c 1 >/dev/null` under `pipefail`, then the pipeline status is 0 and the negated form is 1; with `grep -q 1` they are 141 and 0.
- Given a three-line message whose first match is on line 2, when the old and the new `-m` display expressions run, then both print the same single line.
- Given the runner started inside a bare repository, when the old and the new `scripts/test-all.sh` run, then both print the same `ERROR: Cannot run tests from a bare repository root.` and exit 1.

## Risks and Sharp Edges

- **A classifier error converts data, and `verify` cannot see it** (a mis-converted data line still equals `transform(removed)`). Mitigations: the 18 data and X lines were read in context and listed; the nine suspect files were read at file:line; the pair run; the owning suites; the observer table. Hook-input fixtures are the worst case and none was found in this set.
- **The 18 hand-converted plain-transform lines are the least-observed edits.** Where the `-vc` swap survives (the suite never reaches the line, or the input has other lines so `-v` still selects one), the line is converted on the strength of the transform proof alone; the PR body lists those sites and does not claim a row sees them. Measured at planning with two mutants per site (a `-vc` inversion and a `grep -m 0` force-no-match, one at a time under the cap, restore check clean): 17 of the 18 sites are killed by at least one mutant; `web2-rebirth-recovery-check.test.sh:171` survives both and is listed in the PR body as unobserved. Nine more are killed by one mutant only (see the observer cells), which is also a statement about the other direction.
- **Known surviving mutant: a resurrected row with a covering hit** (matrix row 10). The guard fails a row only at zero hits, so `'scripts/*.test.sh | <= | 1'` plus one new pipe is green; the only barrier is review of the table diff. A guard line that forbids any deferral glob starting with `scripts/` would close it but is a guard insertion (AC-9 pins the guard diff at two deletions), so it is left to S7 or Item F (decision-challenges item 22).
- **The runner edit.** Two lines of the file every CI job executes first. Line 669 runs on every invocation in a non-bare checkout and would misfire loudly; line 6476 is in a branch that only runs after a repository-boundary violation and is covered only by the scratch run. A local `--affected` run is a full battery and is not run (decided above).
- **Merge-queue ejection.** Four draft PRs edit `scripts/test-all.sh` and one drafts `guard-vacuity-floor.test.sh` at distant hunks, so a textual conflict is not predicted; if the queue ejects the entry, rebase once, re-run Phase 0 and 3, re-enter. Never re-sync a BEHIND branch mid-flight. S4 and S5 are cut after this merges.
- **A pinned carrier text elsewhere.** None of the 47 files pins the text of an `.md` carrier (S2's `deploy-arm`/`ship-phase-7` case); Phase 0 re-greps the edited files for `SKILL.md` and `postmerge` citations on the converted lines.
- **Producers now run to EOF.** Wall time can rise where a producer is a full SUT run (`bash` and `python3` producers: a few lines). The pair run records per-suite wall time and the body lists any suite that grows noticeably; under load the spread exceeds any effect (S2 measured 40 to 141 s on one suite).
- **A failure message that quotes a command in backticks inside double quotes runs that command when the check fails** (S1 finding). Every battery runs under `ulimit -v 6000000`, and any new check text avoids backticks inside double quotes.
- **Verify the verifiers.** Every count in this plan was read from a command's output on `origin/main` `fd1c4d5cac` or on the rehearsal clones; read rc files, not completion notifications; do not start a second `git commit` while a hook is running; never `git add -A`.
- A plan whose `## User-Brand Impact` is empty, holds only `TBD`/`TODO`/placeholder text or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.

## Dependencies and References

- Tracker #9217 (this series); #7376, #6601 (related); #7797 (xtrace lint: comment only if a touched file enters its scope: `scripts/test-all.sh` is one of the four files the S1 plan named as in scope and exits 0 today, so the PR body adds one sentence if the lint is run); #9482 (only if a slice changes an ejection-class fact, expected in S7); #9638 and #9639 (not fixed).
- Merged: #9213, #9525, #9554, #9587, #9632, #9708, #9720 (S1, `f44463a7e9`), #9765 (S2, `f1497664ae`).
- Guard: `.claude/hooks/grep-q-pipe-guard.test.sh` (header, `SWEEP_DEFERRALS`, `SWEEP_PROBE_CHECKS`, `_ts_re`). Tool: `scripts/grep-q-drain-codemod.py`.
- Series plan: `knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md` (Slice Register, Producer-side join design); S2 plan `knowledge-base/project/plans/2026-10-08-chore-grep-q-wave-b-s2-plugin-test-harness-plan.md`.
- Workflow read for the trigger: every `.github/workflows/*.yml` with a `push` trigger; `scripts/test-all.sh` `--help` (RUNNER EDITS) for the fallback.
