---
title: "chore(ci): grep -q drain, Item B slice S4 (tests/*, Ref #9217)"
date: 2026-10-09
slug: grep-q-wave-b-s4-tests-dir
branch: feat-one-shot-grep-q-wave-b-s4-tests-dir
issue: 9217
lane: cross-domain
type: chore
priority: p3-low
domain: engineering
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# chore(ci): grep -q drain, Item B slice S4 (tests/*, Ref #9217)

## Enhancement Summary

**Deepened on:** 2026-10-09. **Gates run:** 4.6 user-brand impact (pass, `aggregate pattern`), 4.7 observability (pass; command first token `bash` is allowlisted, `expected_output` is a literal, and the suite-shaped-command proxy on a `.test.sh` basename is argued down with measurements under the 15 s cap: 10.3 to 11.0 s plain at load 11, 8.7 to 10.0 s in a Check 10-shaped `bwrap`, 12.2 s in an independent run at load 13.8), 4.8 PAT-shaped variables (none), 4.9 UI wireframe (no UI surface), 4.10 encryption posture (no store, no `.tf`/cloud-init/migration in the edit list), 4.11 guard contract (`lint-guard-contract.py`: 1 entry; adequacy read: the Assembly names the chokepoint `scan_sweep`, the first-match-wins table and the probe, not today's members), 4.12 scope check (one live section, three subsections, no `unmapped`, no BLOCKED marker), 4.5 network-outage (no trigger word in Overview or Problem Statement), 4.55 downtime (no trigger). Cited SHAs resolved live and are ancestors of `origin/main`; cited PR numbers and the three labels verified; the one rule id cited exists; the S1 plan's "only S1 and S7 edit `SWEEP_PROBE_CHECKS`" and ADR-119's no-pipe constraint re-read.
**Agents:** a learnings researcher before drafting; plan review (simplicity, correctness, overengineering); then a test-design review of the guard matrix.

### Key improvements

1. **A coupling the transform cannot see.** `test-audit-ruleset-bypass.sh:1274` is a `sed -E` expression matched against converted line 848 and must land; a plain token would also put `/` inside an `s///`. Hand edit, observed (reverting it alone stops the suite with rc 1 after `T-mq-ctl5`).
2. **A detector fixture the Slice Register misdescribed.** `test-git-data-birth-readiness-gate.sh:2971-2974` are the seeded positive control of the suite's own W2 detector, not probes of the guard's pattern; converting one fails `W2-control` (measured), so they take the guard's marker.
3. **Canaries that bite, measured both ways.** Seven planted paths (15 total). On the S3-form guard (row deleted, no canary) excluding `tests` and a resurrected `tests/* <= 1` row plus a covering hit are both GREEN; with the canaries they are RED. The correctness review found `tests/scripts/fixtures/` uncovered; a seventh canary closes it. Two test-shaped holes are measured and listed (matrix rows 6i and 14).
4. **Whole hit set pair-run.** All 23 owning suites and 5 adjacent ones read the same rc and final line on a real detached base clone and on the rehearsal; the ratchet lane is green once its base is the real `origin/main`.
5. **Commit boundary fixed.** The sed expression moves into the codemod commit so no commit leaves a red suite.

### New considerations

- A previously masked negative assertion (10 live negated sites) can surface as red at scale in CI; the small-fixture pair run cannot show it.
- S4 and S5 both edit the probe's `real_want` line and the pinned literal; the second to merge rebases once.

Spec lacks valid lane: no spec.md exists for this branch, so lane defaulted to cross-domain (TR2 fail-closed).

## Overview

Slice S4 of Item B in the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). Pass 1 (#9632), Pass 2 (#9708), S1 (#9720, `f44463a7e9`, the codemod `scripts/grep-q-drain-codemod.py`), S2 (#9765, `f1497664ae`) and S3 (#9788, `e7c64c42dc`) are on `origin/main` (`git merge-base --is-ancestor e7c64c42dc HEAD` is true). None of that is redone here.

S4 owns exactly one deferral row of `.claude/hooks/grep-q-pipe-guard.test.sh`: `tests/*` (181 lines, ceiling 181, mode `<=`, slack 0; line 439). The glob crosses `/` (bash `[[ == ]]`), so it owns every swept path under `tests/` at any depth. Measured with `git ls-files tests`: 202 tracked paths under `tests/scripts` (including `lib/` and `fixtures/`), 3 each under `tests/commands`, `tests/hooks` and `tests/fixtures`, and `tests/conftest.py`; by extension 117 `.sh`, 83 `.json`, 5 `.py`, 4 `.jq`, 3 `.md`. The guard sweeps `.sh .bash .bats .yml .yaml .tf .template .js` only, so **the row can only ever hold `.sh` files** (no `.ts`, no `.js`, no vitest or bun file exists under `tests/`; `grep -E 'vitest|bun test'` over the 23 hit files finds nothing). The 181 lines sit in 23 files: 20 in `tests/scripts/` (171 lines) and 3 in `tests/commands/` (10 lines); `tests/hooks/`, `tests/fixtures/`, `tests/scripts/lib/` and `tests/scripts/fixtures/` hold no hit today. All 23 set `pipefail` at top level.

Like S3 and unlike S1 and S2, **S4 takes its row to zero and deletes it**: 181 lines in 23 files go to zero counted sites. 174 are the plain one-token transform `producer | grep -q P` to `producer | grep -c ... >/dev/null P` (155 by the codemod: 76 by default, 79 more in six files after the comment that makes the codemod hold each was read; 19 by a throwaway rewrite of stub-script lines), 3 are hand edits that change the shape (a `grep -m1` display to a here-string, a `grep -qc` cluster the codemod refuses, a `sed` mutation expression that has to follow the converted line it targets) and 4 are **kept on purpose and marked** (`# sigpipe-demo: intentional`): they are the seeded positive control of a detector inside `test-git-data-birth-readiness-gate.sh`, so converting them would blind that detector. After the edit the guard has no row for `tests/`, so any new early-exit pipe anywhere under it lands in "outside the deferral table" with no slack.

**Lesson carried from S3** (learning `2026-10-09-deleting-the-last-deferral-row-for-a-subtree-removed-the-only-witness-that-the-sweep-reaches-it.md`): while a `<=` row existed, excluding its subtree from `SWEEP_PATHSPEC` made the row stale and failed the guard; with the row deleted nothing notices, and `SWEEP_FLOOR=1400` against 1762 swept files leaves about 360 files of slack. Measured here on the converted tree with the S3-form guard (no row, no S4 canaries): excluding `tests/commands`, and excluding all of `tests`, both stay green (rc 0). So the same PR plants one violating file under each shape the deleted row owned, in the guard's real-table probe, and mutation-proves them both ways (an excluded subtree; a resurrected row plus a covering hit, which was green on the S3-form guard: rc 0 measured).

**Measured result of a full rehearsal on a scratch clone of the branch base `71c0bac35f`, re-applied on `origin/main` `01d2b5a0d8`** (nothing committed in this repository): 181 line edits in 23 files plus 7 insertions and 7 deletions in the guard (the row, the canaries); `verify` prints `verified: 174`, `hand-edited: 7`, `unexplained: 0` (on both bases); the guard prints 10 `DEFERRED:` lines (was 11) rc 0 with `grep-q-sweep-probe-pass`; the test-shaped ceiling total falls 437 to 256 (`5 + 5 + 66 + 180`); all 23 owning suites plus 5 adjacent suites read the same rc and the same final line on a real detached clone at the base SHA and on the branch (tables below).

**What fires on merge.** Re-derived over the 24 edited paths against the path filter of every `.github/workflows/*.yml` that has a `push` trigger (25 of 86 workflows; script and output in Research Insights): all 18 path-filtered workflows match 0 of 24; only the seven unfiltered push workflows run (`ci`, `codeql-main-alert-gate`, `secret-scan`, `skill-security-scan-corpus`, `skill-security-scan-postmerge`, `tenant-integration`, `vendor-pin-verify`), as on every merge. The S1 plan's "S4 fires nothing" holds. `plugins/soleur/**` is untouched (no plugin release), `apps/web-platform/**` is untouched (no web-platform release or apply), `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh` are untouched (no runner edit, so no runner-parity check and no `AFFECTED_FALLBACK`), and `[skip-deploy-fix-apply]` is irrelevant and not used. Web Platform Release's `workflow_run` arm on a green `ci` does start and takes its clean skip (it did for S1 to S3); Post-Merge Monitor starts and filters on a `[bot-fix]` title.

**Local gate, decided now.** Because the runner is not edited, `bash scripts/test-all.sh --print-selection --paths=<24 paths>` on `origin/main` `01d2b5a0d8` with the rehearsal applied prints `AFFECTED_SUMMARY selected=168 of=587 always_on=111 edge=57 fallback=none`: `--affected` would not degrade to the full battery here. It is still **not run**: the user decided that when CI reruns everything the long local `--affected` is skipped, and CI's `test` legs run `bash scripts/test-all.sh <group>` over the whole battery (`.github/workflows/ci.yml` lines 1013, 1047, 1215, 1323). The local evidence is the pair run of the 23 owning suites and 5 adjacent ones, the ratchets, the guard and the mutation battery. `soleur:ship` Phase 4 meets the same decision: it is satisfied by its own "is the battery still OWED" check (CI's required `test` check verifies the byte-identical tree).

**Honest scope.** All 23 files set `pipefail`, so the shape is live in 162 of the 181 lines (the 19 stub lines run in child scripts that set no `pipefail`), but most of the 181 sites pipe a `printf`/`echo` of a variable or a small `grep` output into `grep`, which only races when the writer is unfinished at the reader's exit. 11 of the converted lines are negated pipelines (`! producer | grep -q X`; 10 live, one in an inert stub), where a SIGPIPE'd producer turns "X is absent" into a pass instead of a failure (measured: `neg-q: 0` against `neg-c: 1`). This PR pays the ledger down and removes the last counted slack under `tests/`; it is not a flake fix and moves no CI flake rate. The guard does not see every spelling or extension (Items D, E, F); the marker it honours hides any line from the count and nothing caps its use per file (4 more lines now use it).

## Research Reconciliation: brief and trackers vs measured reality

| Brief or tracker claim | Reality (command or file) | Plan response |
| --- | --- | --- |
| "the guard row `tests/*` (181 hits, ceiling 181, mode <=)" | `bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0 prints `DEFERRED: tests/* (181 hits, ceiling 181, mode <=, slack 0, #9217)`. The codemod counts hits: `ROW tests/* (hits) H-m=1 T0=76 data=24 suspect=81` = 182 hits on 181 lines (`test-registry-restore-from-ghcr.sh:1124` carries two) | Ledger numbers are lines, tool numbers are hits; both are quoted with their unit |
| S1 Slice Register: "S4 `tests/*` 181 / 23 files, nothing fires; `test-registry-restore-from-ghcr.sh` (35) and `test-dev-suite-mutex.sh` (30) are the large files; `test-git-data-birth-readiness-gate.sh:2971-2974` are probe functions that pin the guard's own pattern (H-data)" (`knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md`, `Slice Register`) | 181 lines / 23 files confirmed (`cut -d: -f1 \| sort -u \| wc -l` over the guard's own population = 23); file sizes confirmed (35 and 30). Correction: lines 2971-2974 do not pin the guard's pattern; they are the **seeded positive control of that suite's own W2 detector** (`W2_PATTERN` at line 2913 is a copy of the guard's `PATTERN`; the `_w2_sweep` function sweeps `tests/scripts/lib/`; `W2-control` demands at least 4 flagged lines in the seeded copy) | Converting them would drop the control to 0 flagged and fail `W2-control`; they keep the shape and take the marker (hand edit) |
| "`tests/*` is a glob that crosses `/`: list the subdirectories it owns and whether any is outside what a plain transform is safe for" | Hit files: `tests/scripts/` 20 (171 lines), `tests/commands/` 3 (10 lines). Owned but hit-free today: `tests/hooks/` (3 `.sh`), `tests/scripts/lib/` (W2-pinned to zero), `tests/scripts/fixtures/` (2 `.sh`), `tests/fixtures/` (no swept file), top level (`conftest.py` is `.py`, not swept). No `.ts`/`.js`/`.yml` file | The plain transform is safe for 174 lines. Not safe by plain transform: 1 sed string coupled to a converted line, 4 detector fixture lines, 1 `-m` display, 1 `-qc` cluster (7, all hand edits) |
| "Start with `apply --row 'tests/*'` as a dry run" | Re-run here on the branch base (rc 0): POPULATION 458 lines in 85 files (whole table); default WOULD-CHANGE 76 lines in 16 files; QUEUE 106 entries (81 suspect, 24 data, 1 H-m) in 8 distinct files. With the six suspect files passed to `--reviewed-suspect`: WOULD-CHANGE 155 lines in 22 files, QUEUE 26 lines (24 data, 1 H-m, 1 X) | Every queue line is read at file:line below; the six suspect files are read at the comment that holds them |
| "suspect files that need `--reviewed-suspect`" | Six: `test-audit-ruleset-bypass`, `test-registry-pull-path-health`, `test-registry-restore-from-ghcr`, `test-sentry-alert-live-fidelity`, `test-supabase-logs-query`, `test-tmp-purge` (all `tests/scripts/*.sh`); each holds only because a comment names SIGPIPE or false-fail | Read below; none demonstrates the shape on purpose, so none gets a marker and none keeps a counted pin |
| "decide from the code what is actually hit (data vs code, the grep -m display shapes, executed strings)" | Data tier = 24 lines: 19 are inert stub-script lines in heredocs (code run as child scripts that set no `pipefail`), 4 are the W2 fixture, 1 is a `sed` expression string matched against another converted line. `-m` display: exactly 1 (`test-git-data-rung2-evidence-capture.sh:934`). `X`: 1 (`test-tmp-purge.sh:300`, `-qc`) | Dispositions in "Disposition of every line that is not plain T0" |
| "open PRs touch some candidate files: intersect the exact edited-file list" | 46 open PRs at planning, 44 at the last re-check (`gh pr list --state open --limit 300 --json number,title,isDraft,mergeStateStatus,files`); intersection with the 24 paths: **#9784** only (draft; `tests/scripts/test-inngest-host-dark-gate.sh`, hunks at base lines 862-997 and 1961; S4 edits line 823). #6778 also touches `tests/` (`test-infra-validate-gate-verdict.sh`) but not a file S4 edits | No textual conflict predicted. Semantic screen (below): #9784 adds three new early-exit pipes under `tests/` |
| "derive which workflows fire on merge; `tests/**` may be in some filter" | No push path filter matches any of the 24 edited paths: 18 path-filtered push workflows match 0 of 24 each (sanity probe lights 5 of 18 on a known-matching set). Three of them (`apply-github-infra`, `apply-sentry-infra`, `apply-web-platform-infra`) do name `tests/scripts/lib/*.jq` files (4 paths: `destroy-guard-filter.jq`, `destroy-guard-filter-sentry.jq`, `sentry-alert-projection.jq`, `destroy-guard-filter-web-platform.jq`); S4 edits no `.jq` and no `lib/` file | First PR-body line says exactly that |
| "pair-run base must be a real detached clone with node_modules linked on both sides, under `ulimit -v 6000000`; suites that start vitest run without the cap" | No edited suite starts vitest (above). The 23 owning suites total 460 s on the base side and 440 s on the branch (summed walls, load 3 to 11), so the whole hit set is run, not a subset | Pair run covers all 23 owning suites and 5 adjacent ones |
| "compare suite ids for runner parity (only if `scripts/test-all.sh` or the affected index is edited)" | Neither is edited (`git diff --name-only` over the rehearsal lists 23 test files and the guard) | No runner-parity check; the S3 digests do not apply. A runner edit by a sibling PR is out of scope |
| `origin/main` moved since the branch was initialised | Five commits (`01d2b5a0d8` #9804 test-all fast tier, `98940f9265`, `23aa2aaf86`, `21eeaa78d2`, `f911a78934`); `git diff --quiet 71c0bac35f origin/main -- <file>` is true for all 24 edited paths and `git diff --name-only 71c0bac35f origin/main` lists no `tests/` or guard path; it does change `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh` | Phase 0 merges `origin/main` once; the rehearsal was re-applied on `01d2b5a0d8` (cherry-pick clean, `verified: 174`, guard rc 0, 10 `DEFERRED:` lines) |

## Research Insights

### Premise Validation

Checked 2026-10-09. Issues #9217, #7376, #6601, #7797, #9482, #9638, #9639 and #8659 are all OPEN (`gh issue view <n> --json state`). PRs #9720, #9765 and #9788 are MERGED (`f44463a7e9`, `f1497664ae`, `e7c64c42dc`). Draft PR #9801 is this branch. The mechanism (a `grep -c ... >/dev/null` rewrite through the committed codemod, then deleting the row) is in no rejected-alternatives table of `knowledge-base/engineering/architecture/decisions/` (ADR-119 uses the rule as a design constraint). The idiom was re-probed with a delayed writer on this host (GNU grep 3.12) and in `ubuntu:24.04` (GNU grep 3.11): `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1` on both. `gh pr list` over open PRs finds none touching the guard or the codemod.

### Property List and Cut List

Properties (each observable):

- P1. Every pipe-fed early-exit reader under `tests/` (any depth, any swept extension) is exit-status-identical to its original and drains its producer, except the four fixture lines whose shape is the point and which carry the marker; no counted exception remains.
- P2. The guard, not a reader, fails on a new early-exit pipe anywhere under `tests/` (no row owns the subtree), on a deleted row put back (stale deferral), on a resurrected row together with a covering hit, and on the sweep losing any of the subtrees the row owned.
- P3. A reviewer can mechanically confirm that the diff is only the transform plus an enumerated hand queue: `verify` reports `unexplained: 0`; the 7 hand edits are in `hand-edits.txt` and the 19 plain-transform stub lines in `data-conversions.txt`.
- P4. No converted suite changes its verdict (pair run on a real base clone, or a recorded reason it was not run).
- P5. The merge fires only what was predicted, predicted before the PR and observed after.

Mechanisms the ask names and what each buys: the codemod dry run (P1, P3), the guard's `DEFERRED:` lines and stale-deferral rule (P2), the real-table canaries (P2, the S3 lesson), the evidence comment on #9217 (P5, series accounting), the `ulimit` battery (mutation evidence for P2). All exist on `origin/main`: the codemod and the guard logic are read, not extended; the guard gains data (seven canary names and one literal), not a new check.

**Cut List.**

| Cut | Buys | What already covers it |
| --- | --- | --- |
| An `apply --exec-strings` mode for the 19 stub lines | converting the data tier mechanically | The same one-token regexp applies and `verify` already counts them as verified; a 12-line throwaway (pasted in the tracker comment) is cheaper than a tool mode deleted in S7. S3 decision-challenge 3 said "if S4 has many more, add the mode first": S4 has 19, one file, so the mode is still cut |
| Fixing the codemod's `repeated-q`/letter refusal for `-qc` | a more robust tool | One line (`test-tmp-purge.sh:300`), hand-converted and listed; the tool is deleted in S7 |
| A residual file-exact `=` row for the 4 W2 fixture lines | a counted pin instead of a marker | `_ts_re` classes a file-exact test path as a production row (`GATED_PROD_ROWS` counts it), so it needs a reviewed `_ts_re` widening; the marker is the guard's own documented spelling for "an intentional demo of the shape" |
| Obfuscating the W2 fixture (building `gre` + `p -q` at run time) | no marker needed | Changes what the detector is shown (the control must be the canonical spelling); the marker keeps the bytes the detector reads |
| A new suite row for the `-m` display | observing the here-string rewrite | Observed already: the refusal text is asserted by the suite and a never-match mutant on line 934 is killed (table below) |
| A new probe check for the canaries | a named check per subtree | A new check edits `SWEEP_PROBE_CHECKS` (S1 plan: S2 to S6 may not); widening the existing real-table check keeps the pinned count at 62 |
| A permanent drain-probe row in the guard selftest | the idiom stays proven on the CI grep | Same as S3: Phase 0 runs the probe as a gate; S7's plan decides whether to pin it |

### Census (guard- and codemod-derived, 2026-10-09, branch base `71c0bac35f`)

Commands: `bash .claude/hooks/grep-q-pipe-guard.test.sh` (rc 0, 8.0 s at load 5.8), then `python3 scripts/grep-q-drain-codemod.py apply --row 'tests/*'` (dry run, rc 0), then the same with `--reviewed-suspect` for the six files.

| Quantity | Value |
| --- | --- |
| Row before | `tests/* \| <= \| 181 \| #9217`, 181 lines, slack 0; 11 `DEFERRED:` lines; test-shaped total 437 |
| Codemod hits for the row | H-m 1, T0 76, data 24, suspect 81 (182 hits on 181 lines; no `unsure` tier is printed on this tree) |
| Default dry run | WOULD-CHANGE 76 lines in 16 files; QUEUE 106 entries (81 suspect, 24 data, 1 H-m) |
| Suspect tier | 80 lines in 6 files: `test-registry-restore-from-ghcr` 35, `test-tmp-purge` 22 (21 plain, 1 X), `test-registry-pull-path-health` 12, `test-sentry-alert-live-fidelity` 7, `test-audit-ruleset-bypass` 3, `test-supabase-logs-query` 1 |
| With the six files passed | WOULD-CHANGE 155 lines in 22 files (76 + 79); QUEUE 26 lines in 4 files: 24 data (19 in `test-git-data-rung2-evidence-capture`, 4 in `test-git-data-birth-readiness-gate`, 1 in `test-audit-ruleset-bypass`), 1 H-m (`rung2-evidence-capture:934`), 1 X (`test-tmp-purge:300`) |
| Files setting `pipefail` | 23 of 23 (`grep -nE '^[[:space:]]*set[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*o[[:space:]]+pipefail'` per file) |
| Negated pipelines among the 181 | 11 lines (`! producer \| grep -q X`: `test-sync-producer-reachability:368`, `rung2-evidence-capture:162`, `rung2-plan-shape:74`, `pull-path-health:440`, `restore-from-ghcr:1124/1224/1391/1403`, `stock-preflight-gate:47`, `supabase-advisor-scan:121`, `tmp-purge:649`) plus the 4 negated fixture lines (`if ! printf ... | grep ...`) that keep their shape |
| Owning suites | 23, each one registered suite id (`bash scripts/test-all.sh --enumerate-commands all`), summed manifest weight about 314 s (`scripts/suite-durations.tsv`); largest `git-data-birth-readiness-gate` 134 s, `sentry-alert-live-fidelity` 90 s |
| Population after | 277 lines in 62 files remain in the guard's whole population (458 minus 181), none under `tests/` |

### Trigger derivation (every `push` workflow against the 24 edited paths)

A throwaway script (not committed) loads every `.github/workflows/*.yml`, keeps those with a `push` trigger that can fire on `main` (25 of 86), and applies GitHub filter semantics (`*` stays inside a segment, `**` crosses `/`, `!` negates, patterns in order; `paths-ignore` the inverse) to each edited path. Sanity probe: `plugins/soleur/test/proc.test.sh`, `apps/web-platform/infra/server.tf` and `scripts/test-all.sh` together light `apply-deploy-pipeline-fix`, `apply-web-platform-infra`, `infra-validation`, `version-bump-and-release` and `web-platform-release` once each (1 of 3), so the matcher is not vacuous. Over the 24 edited paths: all 18 path-filtered workflows match 0 of 24; the seven unfiltered ones run. Adding the plan and spec paths under `knowledge-base/` changes nothing (0 of 26). `workflow_run` arms (`yaml` scan): Web Platform Release and Post-Merge Monitor on `CI` completed on `main` (clean skip and `[bot-fix]` filter), Deploy Docs on `Version Bump and Release` (not started: nothing releases), `fix-constraints-stage-b` on its stage A (not started).

### Rehearsal (scratch clones, no repository file touched)

`git clone --local --no-hardlinks` of this worktree into a fresh `/var/tmp` directory, branch `rehearsal` at `71c0bac35f`, then: `apply --row 'tests/*' --write` (76 lines, 16 files); the same with six `--reviewed-suspect` flags (79 lines, 6 files); the 19 stub-line rewrite (`data_convert.py`, below); 7 hand edits; row deleted and canaries added. Results: `git diff --numstat`: 181 insertions and 181 deletions in 23 test files plus 7 and 7 in the guard; `bash -n` clean on all 23; `verify --base 71c0bac35f --hand-edits <7 entries>`: `verified: 174`, `hand-edited: 7`, `unexplained: 0` (same on `origin/main` `01d2b5a0d8`); the idempotency dry run (run with the base guard, before the row goes) `WOULD-CHANGE: 0 lines in 0 files` (population 277); the guard rc 0, 10 `DEFERRED:` lines, `PASS: grep-q-zero-sweep-pass (1762 files swept; deferrals above)` and `PASS: grep-q-sweep-probe-pass`; `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`: 1495 scripts scanned, 0 new, 224 baselined; `bash scripts/lint-orphan-test-suites.sh`: none; `bash scripts/guard-vacuity-floor.test.sh`: `Total: 23 passed, 0 failed`; `bash scripts/pre-push-ratchet-lane.sh` on the rehearsal over `origin/main` `01d2b5a0d8` (at the six-canary state): `verdict=PASS members=23 red=0` (523 s, `merge=ok`). That lane first went RED on `lint-trap-tempfile-ownership` (`79 -> 70` against a merge base of `fa1e2c8733`): the scratch clone's `origin/main` was the source repository's stale local `main`, so the lane compared against an ancient base; with `origin/main` set to the real base (and `origin` pointed at a repository that serves it, because the lane fetches) it is green. Phase 3 therefore runs the lane in the worktree, not in a scratch clone. The state with only the two codemod passes applied leaves exactly 26 lines counted (`DEFERRED: tests/* (26 hits, ceiling 181, ...)`), which is the ceiling Phase 1 lowers to.

The throwaway for the 19 stub lines (nothing to do with the codemod's shell classifier; one regexp over named base-side lines, each asserted to change):

```python
import re, sys
path, lines = sys.argv[1], set(int(x) for x in sys.argv[2:])
src = open(path, encoding='utf-8').read().split('\n')
pat = re.compile(r'(grep(?:\s+-[A-Za-z0-9]+)*?\s+-[A-Za-z]*)q([A-Za-z0-9]*)(?=\s)')
for n in sorted(lines):
    old = src[n-1]; new, k = pat.subn(lambda m: m.group(1) + 'c' + m.group(2) + ' >/dev/null', old, count=1)
    assert k == 1 and new != old, (path, n, old)
    src[n-1] = new
open(path, 'w', encoding='utf-8').write('\n'.join(src))
```

### Pair run on the rehearsal (real detached clone at the base SHA, `node_modules` linked on both sides, one suite at a time under `ulimit -v 6000000`, base side then branch side, per-suite `timeout` = max(300 s, 4 x manifest weight))

All 23 owning suites read **rc 0 and the same final line on both sides** (`diff` of the id, rc and last-line columns is empty). Wall times are not comparable (host load moved between 3 and 11).

| suite id (`tests/…`) | rc | final line (identical on both sides) |
| --- | --- | --- |
| `commands/sync-domain-model` | 0 | `=== 13 passed, 0 failed ===` |
| `commands/sync-producer-reachability` | 0 | `=== 13 passed, 0 failed (13/13 cases) ===` |
| `commands/sync-rule-prune` | 0 | `=== 25 passed, 0 failed ===` |
| `scripts/audit-ruleset-bypass` | 0 | `=== 66 passed, 0 failed ===` |
| `scripts/dev-suite-mutex` | 0 | `test-dev-suite-mutex: 54 passed, 0 failed` |
| `scripts/dispatch-web-redeploy` | 0 | `=== test-dispatch-web-redeploy: 19 passed, 0 failed ===` |
| `scripts/git-data-birth-readiness-gate` | 0 | `=== 259 passed, 0 failed ===` |
| `scripts/git-data-rung2-evidence-capture` | 0 | `=== 174 passed, 0 failed ===` |
| `scripts/git-data-rung2-plan-shape` | 0 | `=== git-data-rung2-plan-shape: 36 passed, 0 failed (36 cases, 7 mutants) ===` |
| `scripts/inngest-host-dark-gate` | 0 | `inngest-host-dark-gate: 323 passed, 0 failed` |
| `scripts/kb-drift-walker` | 0 | `kb-drift-walker test summary: 4 pass / 0 fail` |
| `scripts/registry-delivery-change` | 0 | `=== Results: 137/137 passed, 0 failed ===` |
| `scripts/registry-pull-path-health` | 0 | `=== 60 passed, 0 failed ===` |
| `scripts/registry-restore-from-ghcr` | 0 | `=== 85 passed, 0 failed ===` |
| `scripts/scratch-session` | 0 | `test-scratch-session: 75 passed, 0 failed (75 cases)` |
| `scripts/sentry-alert-adoption-guards` | 0 | `=== 70 passed, 0 failed ===` |
| `scripts/sentry-alert-live-fidelity` | 0 | `=== 76 passed, 0 failed ===` |
| `scripts/stock-preflight-gate` | 0 | `stock-preflight-gate: 389 passed, 0 failed` |
| `scripts/supabase-advisor-scan` | 0 | `all checks passed` |
| `scripts/supabase-logs-query` | 0 | `all checks passed` |
| `scripts/tenant-integration-gate-verdict` | 0 | `tenant-integration-gate-verdict: 22 passed, 0 failed` |
| `scripts/tmp-purge` | 0 | `test-tmp-purge: 112 passed, 0 failed (112 cases)` |
| `scripts/zot-disk-sample` | 0 | `test-zot-disk-sample: 18 passed, 0 failed (18 assertions)` |

Adjacent suites that read an edited file or its text (found by `git grep -lF <basename>`), same method, same result on both sides: `scripts/lint-shell-capture-exit.test.sh` (`ALL TESTS PASSED`), `tests/scripts/test-registry-delivery-change-mutation-battery.sh` (copies the converted suite into a sandbox: `Results: 23/23 passed`), `tests/scripts/test-registry-d10-workflow-wiring.sh` (`23 passed`), `plugins/soleur/test/fixture-relative-assert.test.sh` (`62 passed`; its baseline counts operands per file and is unmoved by `>/dev/null`) and `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` (`73 passed`; it extracts only `_mq_strip_hcl` from `test-audit-ruleset-bypass.sh`). Not run locally: `tests/scripts/registry-gate-mutation-battery` (copies the pull-path-health and restore suites into a sandbox and mutates the SUT; the manifest carries a 2,500 s override, about 41 minutes, and the converted lines are exit-status identical and run in the pair run of the same two suites); CI is its gate.

### Classification of the 24 data lines before conversion

Three independent checks on the base tree (Phase 0 re-runs the second): (1) each line was read in context (table in Proposed Solution); (2) a repo-wide fixed-string search for each of the 181 lines' `grep -q ...` fragment (flags plus the first 40 characters of the operand, `git ls-files` minus `knowledge-base/`, other hit lines included) finds no other tracked line that pins the text of an edited line, except one genuine coupling: `test-audit-ruleset-bypass.sh:1274` contains the text of line 848 (below); the generic fragments that matched elsewhere (`grep -q '::notice::'` in two `apps/web-platform/scripts/*.test.sh` suites) are those suites' own lines; (3) two mutants per stub site in the rehearsal (observer table below). A site no suite reaches is still converted: the conversion is the transform `verify` proves, and the PR body lists the unreached sites.

### Suspect files read (R2 over-inclusion)

The codemod holds a whole file when its text names `sigpipe`, `EPIPE`, `false-FAIL` or `broken pipe`. Each of the six was grepped for the words and the hit lines read in context.

| File | Where it names the word | Verdict | Converted lines |
| --- | --- | --- | --- |
| `tests/scripts/test-audit-ruleset-bypass.sh` | line 1359, a comment: a comment naming the token "must not false-fail" | comment only | 3 (247, 848, 904); line 1274 is separate (data) |
| `tests/scripts/test-registry-pull-path-health.sh` | line 614, a comment: the no-A5 explanation "cannot false-fail its own guard" | comment only | 12 |
| `tests/scripts/test-registry-restore-from-ghcr.sh` | line 22, the authoring rule "Never `producer \| grep -q PATTERN`" inside the header comment | comment only (an authoring rule, not a demonstration) | 35 |
| `tests/scripts/test-sentry-alert-live-fidelity.sh` | line 1348, a comment recording why a here-string is used | comment only | 7 |
| `tests/scripts/test-supabase-logs-query.sh` | line 48, the same authoring rule in the suite constraints | comment only | 1 (772) |
| `tests/scripts/test-tmp-purge.sh` | line 465, a comment recording a past SIGPIPE in the SUT's report table | comment only | 21 plus the X line (300) by hand |

None demonstrates the shape on purpose (no early-quitting-reader stub, no existing `# sigpipe-demo: intentional`; `grep -c sigpipe-demo` over the 23 files is 0), so no marker is added to them and no counted pin is kept. The only existing markers under `tests/` are the two in the pinned `test-sentry-full-root-apply.sh`, outside this row.

### Institutional learnings applied

(Found by a learnings-researcher pass plus the S1 to S3 set; each file was read.)

- `knowledge-base/project/learnings/test-failures/2026-10-09-deleting-the-last-deferral-row-for-a-subtree-removed-the-only-witness-that-the-sweep-reaches-it.md`: canaries per owned subtree, both directions; compare tree-independent facts; landing check against a pristine copy, not a diff count.
- `knowledge-base/project/learnings/test-failures/2026-10-08-a-pair-run-needs-a-real-base-checkout-and-the-mandated-ulimit-aborts-vitest-on-both-sides.md`: real clone as base; vitest suites run without the cap; its session error 1 is the `/dev/null` delimiter trap that S4's `test-audit-ruleset-bypass.sh:1274` meets again.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-mechanical-rewrite-of-800-test-lines-needs-a-shell-aware-classifier-and-a-dry-run-that-names-what-it-refused.md`: read the dry run's queue line by line before `--write`; about one hit in five is data or an executed string.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-diff-verifier-cannot-use-the-hunk-as-its-unit-because-adjacent-changed-lines-merge.md`: `verify` keys hand edits by exact base-side range and refuses an entry wider than the edit.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-ceiling-at-slack-zero-is-satisfied-by-moving-a-hit-between-two-files-and-a-file-exact-test-row-reads-as-production.md`: no file-exact rows; S4 avoids the hole by reaching zero.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-behavior-preserving-grep-conversion-needs-rows-that-see-discrimination.md`: mutants are killed only on their named FAIL text.
- `knowledge-base/project/learnings/test-failures/2026-10-04-a-forced-test-condition-needs-a-negative-control-and-proc-status-is-read-once.md`: a detector's positive control must keep the shape it forces; the W2 fixture is that.
- `knowledge-base/project/learnings/test-failures/2026-10-06-a-source-text-pin-over-a-file-is-a-pipe-into-grep-q-so-the-suite-that-pins-its-own-subject-is-in-the-class.md`: self-reading suites are in the class (`test-audit-ruleset-bypass.sh` reads its own function text).
- `knowledge-base/project/learnings/test-failures/2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`: a mutant counts as killed only on its named FAIL text with rc 1.
- `knowledge-base/project/learnings/workflow-issues/2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md`: SIGPIPE shows only at real input scale; a pair run on small fixtures proves "no verdict change", never "the race is gone".

## Open Code-Review Overlap

88 open `code-review` issues were searched for the 24 edited paths and for each basename (two-stage `gh issue list --json` then standalone `jq --arg`). Matches: **None**. Nothing is folded in, acknowledged or deferred.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh`: delete the row `'tests/* | <= | 181 | #9217'` (line 439) as the last edit (lowered to `<= | 26` for the red step); widen the real-table probe (lines 863 to 876): add `"$rr/tests/scripts/lib" "$rr/tests/scripts/fixtures" "$rr/tests/commands" "$rr/tests/hooks" "$rr/tests/fixtures"` to the `mkdir -p`, add seven planted names to the `for _f in` list (`tests/zz.sh tests/scripts/test-zz.sh tests/scripts/lib/zz.sh tests/scripts/fixtures/zz.sh tests/commands/test-zz.sh tests/hooks/test_zz.sh tests/fixtures/zz.yml`), extend `real_want` by the same seven paths in `LC_ALL=C sort` order (15 paths), and change the literal `8` to `15` in `real_none == 8` and in the two messages that say eight/`want 8`. Nothing else: not `SWEEP_PROBE_CHECKS` (62), not `SWEEP_PATHSPEC`, not `SWEEP_CANARIES`, not `GATED_PROD_ROWS`, not a comment, not another row. Rehearsal diff: 7 insertions and 7 deletions.
- 22 test files edited by the codemod (155 lines), all under `tests/`: default pass (16 files) `tests/commands/test-sync-domain-model.sh`, `tests/commands/test-sync-producer-reachability.sh`, `tests/commands/test-sync-rule-prune.sh`, `tests/scripts/test-dev-suite-mutex.sh`, `test-dispatch-web-redeploy.sh`, `test-git-data-rung2-evidence-capture.sh` (2 lines), `test-git-data-rung2-plan-shape.sh`, `test-inngest-host-dark-gate.sh`, `test-kb-drift-walker.sh`, `test-registry-delivery-change.sh`, `test-scratch-session.sh`, `test-sentry-alert-adoption-guards.sh`, `test-stock-preflight-gate.sh`, `test-supabase-advisor-scan.sh`, `test-tenant-integration-gate-verdict.sh`, `test-zot-disk-sample.sh` (each `tests/scripts/`); six `--reviewed-suspect` files `tests/scripts/test-audit-ruleset-bypass.sh`, `test-registry-pull-path-health.sh`, `test-registry-restore-from-ghcr.sh`, `test-sentry-alert-live-fidelity.sh`, `test-supabase-logs-query.sh`, `test-tmp-purge.sh`.
- 26 lines in 4 files carry the non-codemod edits: `tests/scripts/test-git-data-rung2-evidence-capture.sh` (19 stub lines + the `-m` display), `tests/scripts/test-git-data-birth-readiness-gate.sh` (4 markers; the 23rd file, in neither codemod list), `tests/scripts/test-audit-ruleset-bypass.sh` (1274) and `tests/scripts/test-tmp-purge.sh` (300); the other three are also among the 22 codemod files.

The union is 23 files under `tests/` plus the guard (24; the list is in the session scratch directory and AC-2 re-derives it with `git diff --name-only`, not a pathspec). Not touched, on purpose: `scripts/grep-q-drain-codemod.py` and the guard's selftest (S1; deleted in S7), `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `plugins/soleur/skills/work/SKILL.md` (and every other `SKILL.md`), `tests/scripts/test-sentry-full-root-apply.sh` (pinned by the guard's named pass, carries two markers already), the main checkout's `.mcp.json`, and the pre-staged `scripts/followthroughs/watchdog-debounce-soak-9686.sh` if present in this checkout (stage by explicit path, never `git add -A` or `git add .`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s4-tests-dir/tasks.md`, `decision-challenges.md`, `session-state.md`, `hand-edits.txt` (7 entries, base-side line numbers, `verify` input) and `data-conversions.txt` (19 entries, the classification evidence). All five are written by this planning pass.
- One learning file under `knowledge-base/project/learnings/test-failures/` (candidate in AC-10), written at work time only if still non-obvious. No new `*.test.sh`: a new suite would fall into the covered floor scope and need a `run_suite` registration in `scripts/test-all.sh`, which is itself a runner edit.

## Problem Statement

The guard defers 181 test-harness sites under `tests/` behind one `<=` ceiling that only a human lowers, so a new early-exit pipe under `tests/` (117 `.sh` files, 23 of them already in the class) can hide in slack the moment someone converts a site and forgets the number, and an open draft (#9784) is already adding three. Most of the bulk is the mechanical transform S1 built a tool for; the rest is 26 lines the tool declines for reasons that are individually checkable. And once the row is gone, nothing but a planted canary proves the sweep still reaches `tests/`.

## Proposed Solution

### The conversion form

Unchanged from S1 to S3: `<producer> | grep -q<flags> ARGS` becomes `<producer> | grep -c<flags> >/dev/null ARGS` (`q` replaced by `c`, the redirect inserted immediately after the flag cluster). For stdin-only operands the exit status equals `grep -q`'s (0 iff a line was selected, `-v` and empty input included; S1 checked 1,080 rows under bash and dash), it reads the whole stream so the producer never takes EPIPE, and it is valid in `/bin/sh`. `>/dev/null` contains no quote or expansion character, so it is safe inside a single-quoted, double-quoted or heredoc layer. It does contain a `/`, which is why the one `sed` expression string below is not a plain rewrite.

### Disposition of every line that is not plain T0 (26 lines, re-read at file:line, base side)

| Site | Kind | Disposition | Observer (two mutants in a sandbox copy of the owning suite: `-vc` inversion, `-m 0 -c` never-match) |
| --- | --- | --- | --- |
| `tests/scripts/test-git-data-rung2-evidence-capture.sh:162, 174, 176, 182, 183, 184, 194, 197, 198, 199, 206` | stub-heredoc-unquoted | the body of `make_stub` (`cat > "$1" <<STUB`, lines 134 to 213) is a bash script the suite writes and runs as the Better Stack reader; `\$` escapes mark it as stub code. It starts `#!/usr/bin/env bash` and sets no option; neither the suite nor the SUT exports `SHELLOPTS`, so the pipes are inert today. Converted by the same token | 162, 174, 176, 194 both killed; 182, 183, 184, 197, 198, 199, 206 never-match killed, inversion survives (observed by never-match only; not analysed further) |
| `…rung2-evidence-capture.sh:301, 310` | stub-heredoc-quoted | `cat > "$SENTRY_STUB" <<'STUBEOF'` (`$*` unescaped): the Sentry argv dispatcher; converted | both killed |
| `…rung2-evidence-capture.sh:1087` | stub-heredoc-unquoted | `RECSTUB`, a recording stub whose two branches `cat` the same-effect fixture; converted | **neither mutant is killed**: unobserved by its suite |
| `…rung2-evidence-capture.sh:1718, 1721, 1723, 1725, 1727` | stub-heredoc-unquoted | `EXCSTUB` in `make_exc_stub` (the HTTP-200-carrying-an-error stub); converted | 1718 never-match killed, 1721 never-match killed, 1727 never-match killed; inversion survives on all; **1723 and 1725 neither killed**: unobserved |
| `tests/scripts/test-git-data-birth-readiness-gate.sh:2971, 2972, 2973, 2974` | detector fixture | seeded copy `$_w2c/seeded.sh` written by `<<'SH'`: four probe functions in the four shapes `W2_PATTERN` exists to catch (canonical, split flag cluster, `\|&`, `-m1`); `W2-control` requires at least 4 flagged lines in it. **Not converted**: each takes the trailing marker `# sigpipe-demo: intentional` after two spaces (hand edit). The guard drops marker lines (`ALLOW_MARKER`); `_w2_sweep` strips only full-line comments, so it still sees them | converting line 2971 alone makes `W2-control` fail (measured below); removing a marker makes the guard report 1 site outside the table (matrix row 2c) |
| `tests/scripts/test-audit-ruleset-bypass.sh:1274` | sed string coupled to code | the argument of `_mq_with_absent_mutated` is a `sed -E` expression, run against the text of `_mq_queue_absent` read from this same file, and it **must land** (`[FATAL] ... did not land`, exit 1). The line it targets is 848, converted by the codemod. Converting 1274 by the plain token would put `>/dev/null` inside an `s/…/…/` whose delimiter is `/`; instead the slashes are escaped (old and new text in the block under this table; hand edit; the alternative `#` delimiter is S2's fix and rewrites more bytes) | reverting only 1274 (848 converted) makes the suite stop with rc 1 after `T-mq-ctl5`, before `T-mq-ctl6`, with no summary line (landing check); both 848 mutants stop it the same way |
| `…rung2-evidence-capture.sh:934` | H-m | `printf 'rc=%s %s' "$_r" "$(printf '%s' "$_o" \| grep -m1 'refusing: --host-name' \|\| true)"` becomes `"$(grep -m1 'refusing: --host-name' <<<"$_o" \|\| true)"`. The producer was a `printf` of a variable (cannot fail); a here-string turns empty input into one blank line and the pattern cannot match a blank line. Old and new printed the same text on a populated three-line input whose first match is line 2, on an empty value and on a no-match value (scratch run) | never-match mutant killed (`FAIL the PRODUCTION host name soleur-git-data is refused (rc 64)`, `172 passed, 2 failed`, rc 1): the line is asserted by the suite |
| `tests/scripts/test-tmp-purge.sh:300` | X letter-c | `printf '%s' "$out2" \| grep -qc 'QUARANTINE' \` : `-q` and `-c` in one cluster; the codemod refuses it. Hand-converted to `grep -c >/dev/null 'QUARANTINE'` (exit status identical: 0 iff a line matched; probed `qc: 0/1`, `c: 0/1`) | inversion killed (`[FAIL] second apply moved entries`, 111 passed, 1 failed); never-match survives (the `\|\| pass` arm absorbs it) |

Line 1274, base side and new side (the only line that is written inside a bash double-quoted string; `\\|` is a literal pipe for `sed -E`, `\/` a literal slash):

```text
base: _mq_with_absent_mutated "s/^  if _mq_strip_hcl \"\\\$tf\" \\| grep -q 'merge_queue'; then return 1; fi\$/  :/" t_mq_queue_off
new:  _mq_with_absent_mutated "s/^  if _mq_strip_hcl \"\\\$tf\" \\| grep -c >\/dev\/null 'merge_queue'; then return 1; fi\$/  :/" t_mq_queue_off
```

So S4 removes 181 lines of 181 from the count; nothing is left counted. 4 of them (the fixture) stay physically unconverted and are exempt by the marker, which is the guard's documented spelling for an intentional demo.

### Ledger lowering

| Row | Before | After |
| --- | --- | --- |
| `tests/*` | `<=` 181 | deleted (0 hits) |
| the other ten rows | unchanged | unchanged (`.claude/*.test.sh` 5, `plugins/soleur/test/*` 5 `=`, `plugins/soleur/*.test.sh` 66, `apps/web-platform/*.test.sh` ceiling 180 with 178 hits, six production rows 23) |
| `DEFERRED:` lines printed | 11 | 10 |
| Test-shaped total (`5 + 181 + 5 + 66 + 180` before) | 437 | 256 |
| Real-table probe planted paths | 8 | 15 |

Row order is semantic ("first match wins") but no remaining row can own a path under `tests/` (the other test-shaped globs are `.claude/*.test.sh`, `plugins/soleur/test/*`, `plugins/soleur/*.test.sh`, `apps/web-platform/*.test.sh`, none of which starts with `tests/`), which matrix rows 1, 4 and 6 measure.

### Phases

**Phase 0, re-measure and gate (read-only).** `git fetch origin main`; if `origin/main` is ahead of the branch (it is, by five commits that touch none of the 24 files), merge it once at the start (never mid-flight afterwards) and re-run everything below; record `git merge-base HEAD origin/main` as the SHA that `verify --base`, the pair-run base and the trigger derivation all use. (1) Drain probe on the dev host and in `docker run --rm ubuntu:24.04` (command in AC-3): `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0`, `neg-c: 1`; if `c` prints 141 stop. (2) Run the guard, keep the `DEFERRED:` lines (expect 11); run the dry run, default and with the six `--reviewed-suspect` files, and diff the census and the 26-line queue against the tables above (any new queue entry stops the plan until read). (3) Re-run the trigger derivation over the union of the dry run's file list, `hand-edits.txt`, `data-conversions.txt` and the guard (expect 0 of 24 for every path-filtered workflow), the open-PR intersection and the added-line screen. (4) `uptime`; if the load average exceeds the core count (16) the pair run's wall times are not comparable and the table says so. (5) `grep -lE 'vitest|bun test'` over the 23 files (expect none; a suite that starts a worker runs without `ulimit -v`). (6) Re-run the fixed-fragment search for the pin class (check 2 of the classification).

**Phase 1, red first.** Edit only the guard: `'tests/* | <= | 26 | #9217'`. The guard must go RED (`has 181 hits, ceiling 26`): that is the failing test the conversion has to satisfy (`cq-write-failing-tests-before`; the instrument is the existing guard, so there is no new test to write). The row stays `<=` because `apply --write` refuses a `=` row and needs the row to exist. Paste the `deferral ceiling exceeded` line in the PR body; the red state is not committed on its own.

**Phase 2, convert.** Commit 1: guard row lowered, `apply --row 'tests/*' --write` (76 lines, 16 files), then the same with the six `--reviewed-suspect` flags (79 lines, 6 files). The sed expression at `test-audit-ruleset-bypass.sh:1274` goes into this commit too (hand edit, one line): line 848 is converted by the codemod pass, and the suite exits 1 at `T-mq-ctl6` until 1274 follows it, so the first commit would otherwise leave a red suite. The guard is then green at 25 hits against ceiling 26 (`<=`). Commit 2: the other 25 lines (the 19 stub lines by the throwaway, the `-m` display, the `-qc` line and the four markers by hand), `hand-edits.txt`, `data-conversions.txt`, then the idempotency dry run `apply --row 'tests/*'` (`WOULD-CHANGE: 0 lines in 0 files`, population 277), then, as the LAST edit, delete the row and widen the real-table probe. Stage by explicit path.

**Phase 3, verify.** `python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s4-tests-dir/hand-edits.txt` prints `verified: 174`, `hand-edited: 7`, `unexplained: 0`. The set of base-side lines changed outside the two codemod passes equals `hand-edits.txt` union `data-conversions.txt` (26, by command). `bash -n` on the 23 files; `git diff --numstat origin/main...HEAD -- tests/` equal insertions and deletions (181 each). Pair run (below). Then `bash scripts/pre-push-ratchet-lane.sh` (detached, rc file; in the worktree, where `origin/main` is the real base), `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`. `bash scripts/test-all.sh --print-selection` on the branch diff: record the `AFFECTED_SUMMARY` line (expect `fallback=none`). **Runner parity is not run**: neither `scripts/test-all.sh` nor `scripts/lib/test-affected-paths.sh` is edited, so selection and enumeration cannot differ from the base (`git diff --name-only origin/main...HEAD` shows neither). If a merge of `origin/main` or a review round puts either in the diff, S3's suite-id comparison (591 ids in S3; 587 selected-or-not registrations now) becomes mandatory.

**Pair run.** Base = a real clone of this repository checked out detached at the base SHA (`git clone --local --no-hardlinks --no-checkout`, `git checkout --detach <sha>`), never `git archive`; `node_modules` of the worktree symlinked into both sides. Branch = the worktree. Both sides sequential, one suite at a time, under `ulimit -v 6000000`, per-suite `timeout` = the larger of 300 s and four times the suite's `suite-durations.tsv` weight, `TMPDIR=/var/tmp`, cwd = the side's root, rc and final line compared. A timeout on both sides is `inconclusive`, never `identical`. The 23 owning suites **and** the five adjacent ones must read identical (28); a suite that starts a vitest worker would run without the cap, and none does. The `registry-gate-mutation-battery` is `not run locally` with the reason above.

**Phase 4, hand-applied mutation battery** (Guard Contract matrix plus the observer table) on scratch copies, one mutant at a time under `ulimit -v 6000000`, a green control first, the first red line recorded from printed output, the landing check by `cmp` against a pristine copy, restore by `git checkout -- .` in the scratch clone.

**Phase 5, evidence and ship.** One learning file if still non-obvious; tracker comment on #9217 (before and after `DEFERRED:` table, the command behind each number, the NOT-fixed list, the 12-line throwaway); the ship tail. The PR body names which later work lowers the next rows (S5 `plugins/soleur/*.test.sh` and part of `apps/web-platform/*.test.sh`, S6 the infra suites, Item F for the `.md` carriers). Sequencing: the row line S4 deletes (439) is separated from S5's rows (443, 444) by three lines, so the table hunks merge cleanly; but S4 and S5 both change the real-table probe's `real_want` line and the `real_none == 15` literal (each adds its canaries), so the second to merge rebases once and re-counts. The merge queue ejects rather than rebases, and no BEHIND branch is re-synced mid-flight.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Keep a residual `=` row for the 4 fixture lines (S2's posture for its five pins) | A file-exact test path is classed production by `_ts_re` (needs a reviewed widening and a `GATED_PROD_ROWS` bump) and the row stays open to add-one-delete-one inside the file; the marker is the established spelling. Challengeable (decision-challenges item 2) |
| Convert the 4 fixture lines and relax `W2-control` | Changes what the detector is shown and weakens a second guard (the W2 pin over `tests/scripts/lib/`) to make a ledger line disappear |
| Skip the canaries (S3's PR as first merged) | The measured hole: with the row gone and no canary, excluding `tests` from `SWEEP_PATHSPEC` stays green (rc 0) and a resurrected `tests/* <= 1` row plus one covering hit stays green (rc 0) |
| One canary per directory plus one per extension | Extension coverage is not per-subtree in this guard (the pathspec is shared); one `.yml` canary under a hit-free subtree stands for it; the rest is Item F |
| Run `scripts/test-all.sh --affected` (168 of 587, no fallback) | The user decided CI is the full-battery gate; stated above |
| A `#`-delimited sed expression at line 1274 | Rewrites more bytes of a string whose other bytes are pinned by the landing check; escaped slashes change only the inserted token |

## User-Brand Impact

- **If this lands broken, the user experiences:** a shell test suite under `tests/` that stopped asserting what it names (the gate that decides whether a production host holding every connected user's source code may be born, the tenant-isolation verdict, the registry restore and pull-path gates, the ruleset-bypass audit, the tmp-purge quarantine), so a regression in a verdict script ships green; the visible symptom is a defect the suite exists to catch reaching a merged change, or a CI job turned red by a mis-edited line.
- **If this leaks, the user's workflow is exposed via:** no secret or user data is read or written by the change; the exposure vector is a fail-open conversion that makes a security-adjacent assertion pass vacuously (a dropped `-x` or `-F`, an inverted `!`, a stub that stops refusing an unexpected call, a detector control that no longer flags), in suites such as `git-data-birth-readiness-gate`, `rung2-evidence-capture`, `tenant-integration-gate-verdict` and `audit-ruleset-bypass`.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no conversion touches user data or production configuration, 174 of 181 edits are one-token rewrites proved by `verify`, the 7 others are each read in context and observed (table above), and all 28 suites that read an edited file give the same rc and final line on a real base clone; not `none` because a systematic classifier or transform error would repeat across 23 suites, several of which guard verdicts for the production-host birth gate and tenant isolation, so the section carries no `threshold: none` scope-out. The brand-survival lens on the guard edit: a canary that fails to bite would let a future early-exit pipe land silently in a subtree that guards those verdicts; Guard 1 below is that lens.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and merge_group run and prints PASS lines plus one DEFERRED line per row
  cadence: per PR and per merge_group run; run directly before each push
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no Sentry surface)
  fail_loud: a FAIL line naming the row and the exceeded, loose or stale ceiling, or the file and line outside the table, or the real-table probe diagnosis, exit 1; an unreadable input, an empty derived population or a missing python3 prints UNRESOLVED and exits 3
failure_modes:
  - mode: a new early-exit pipe lands anywhere under tests/
    detection: no row owns the subtree, so the hit reports "outside the deferral table"
    alert_route: required test check red on the PR
  - mode: a deleted row is put back, with or without a covering hit
    detection: with no hits "stale deferral ... delete its row"; with a covering hit the real-table probe's real-table-owner check, because the planted tests/ canaries become owned
    alert_route: required test check red on the PR
  - mode: the sweep stops reaching a tests/ subtree (a pathspec exclusion, a renamed directory)
    detection: the planted canary under that subtree drops out of the undeferred set, real-table-owner and real-table-control report it
    alert_route: required test check red on the PR
  - mode: a converted suite changes behavior
    detection: the suite's own result line compared base versus branch (recorded in the PR body) and the suite itself in CI
    alert_route: required test check red on the PR
  - mode: the W2 fixture is converted instead of marked
    detection: W2-control in test-git-data-birth-readiness-gate.sh fails (needs at least 4 flagged lines in the seeded copy)
    alert_route: required test check red on the PR
logs:
  where: CI job logs of the test check; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: grep-q-sweep-probe-pass
```

Detection note for preflight Check 10: one deterministic file, no build or network. The suite-shaped-command proxy (a `.test.sh` basename) fires on this command and is argued down by measurement. On the converted rehearsal tree (on `origin/main` `01d2b5a0d8`) the guard took 10.3, 10.9 and 11.0 s wall plain under `ulimit -v 6000000` at a host load average of 11 (rc 0, `grep-q-sweep-probe-pass` printed once), and 8.7, 9.4 and 10.0 s inside the Check 10 sandbox shape (read-only `bwrap` from `plugins/soleur/skills/preflight/SKILL.md` lines 1150 to 1196 and 1256: `--ro-bind /usr /usr`, tmpfs `/home /root /run /tmp /var/tmp`, the repo bound read-only, `--unshare-all --share-net`, `env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp timeout 15s`, `RC:0`); the base tree took 8.0 s at load 5.8. All are under the 15 s cap, but the margin is thin on a contended host (S3 measured 12.9 s at load 16), and AC-10 re-measures after the edit. S4 removes one row and adds seven small files to a scratch tree, which adds a few milliseconds. An independent review run of the same guard on the converted tree measured 12.2 s at a load average of 13.8 (two thirds of the margin to the cap), so a contended host is the case to watch. The block is the same command S1 to S3 declared.

## Guard Contract

### Guard 1 — the subtree `tests/` after S4 has no deferral row and the sweep still reaches all of it

**Property.** After S4, no early-exit pipe into `grep` exists in any `*.sh`, `*.bash`, `*.bats`, `*.yml`, `*.yaml`, `*.tf`, `*.template` or `*.js` file under `tests/` (outside lines carrying the `# sigpipe-demo: intentional` marker), and the guard goes red when one is added (witnessed for `.sh` and `.yml`; the other swept extensions ride the shared pathspec and are not witnessed per extension, row 15), when a deleted row is put back with or without a covering hit, when a marker is removed, and when the sweep stops reaching any canaried subtree the row owned.

**Assembly.** One population and one verdict: `scan_sweep <root>` (git grep over `SWEEP_PATHSPEC` with `PATTERN_V2`, comment and marker lines dropped) and `sweep_verdict` over `SWEEP_DEFERRALS`, plus the stale-deferral rule and the `DEFERRED:` print. The chokepoint is `scan_sweep`; the table is one array whose order is semantic (first match wins) and whose globs cross `/`. The property quantifies over every path under `tests/` at any depth (`tests/scripts/`, `tests/scripts/lib/`, `tests/commands/`, `tests/hooks/`, `tests/fixtures/`, the top level, a directory added next month) and over every spelling `PATTERN_V2` matches (including the heredoc and string lines this slice converted, which the guard counts like any other line). Reachability of the sweep into each subtree is witnessed by the real-table probe (`_real_undeferred`, `real_want`, `real_none`), which runs `scan_sweep` on a scratch root holding one violating file per shape the deleted row owned: top level (`tests/zz.sh`), `tests/scripts/` with the `test-*` basename that holds all 171 current hits (`test-zz.sh`), the nested `tests/scripts/lib/` (`zz.sh`) and `tests/scripts/fixtures/` (`zz.sh`), `tests/commands/` (`test-zz.sh`), `tests/hooks/` with the underscore basename (`test_zz.sh`) and a non-`.sh` extension under a hit-free subtree (`tests/fixtures/zz.yml`). Any row that owns a `tests/` hit must be test-shaped (`_ts_re`) or the probe's `real-table-test-shaped` and `real-table-production-rows` checks fail, which closes the resurrection of a non-test-shaped narrow glob (a row that owns real hits but none of the canaries). It does not close a test-shaped narrow glob such as `tests/commands/*.test.sh` (matrix row 14) or a partial exclusion that spares the canary names such as `tests/scripts/test-[a-m]*` (row 6i); both are listed as known surviving mutants. Unswept shapes, stated rather than assumed: a symlink (file or directory) is read as a blob of its target path, so the target is swept at its own path only (measured by the test-design seat: green), and extensions outside the eight listed. The second reader of the same population is the codemod (`apply`, `verify`), used as a parity check before any edit, never as a second ledger; the third is the suite-local W2 pin over `tests/scripts/lib/`.

**Mutation matrix** (hand-applied on a scratch clone of the converted tree, one mutant at a time under `ulimit -v 6000000`, green control first (rc 0, `grep-q-sweep-probe-pass`), landing check by `cmp` against a pristine copy; every "measured" cell was printed during planning on the rehearsal clone):

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `x="$(printf %s a)"; echo "$x" \| grep -q p` to (a) `tests/scripts/test-zot-disk-sample.sh`, (b) `tests/commands/test-sync-domain-model.sh` (a path no remaining row can own) | RED rc 1 each: `pipe-into-early-exit-grep outside the deferral table (1 site(s))` (measured); this is also the paired control for the must-PASS rows |
| 1c | Append the same line to a new file whose name has spaces, `tests/scripts/zz a b.sh` | RED rc 1: `outside the deferral table (1 site(s))` (measured; file names with spaces are swept) |
| 2 | Revert one converted or marked site: (a) `test-tmp-purge.sh:300` back to `grep -qc`; (b) the stub line `test-git-data-rung2-evidence-capture.sh:206` back to `grep -q`; (c) delete the marker from `test-git-data-birth-readiness-gate.sh:2971`; (d) `test-audit-ruleset-bypass.sh:848` back to `grep -q` | RED rc 1 for each: `outside the deferral table (1 site(s))` (measured; proves the conversion is tight against overshoot in hand-converted, stub, marked and codemod lines) |
| 3 | Append a hit to files in three subtrees after a compliant first (`tests/scripts/test-zot-disk-sample.sh`, a new `tests/scripts/lib/zz-planted.sh`, `tests/commands/test-sync-domain-model.sh`) | RED rc 1: `outside the deferral table (3 site(s))` (measured; a check that stops at the first member would read 1) |
| 4 | Put back the row `'tests/* \| <= \| 181 \| #9217'` (a lowering forgotten, a row resurrected with slack) | RED rc 1: `stale deferral: tests/* has no hits left — delete its row`, and the probe's `real-table-owner` diagnosis (measured) |
| 5 | Put back `'tests/* \| <= \| 1 \| #9217'` **and** append one covering hit to `test-zot-disk-sample.sh` (the S3 known surviving mutant) | RED rc 1: `the derived sweep's own probe is broken` with `real-table-owner: the shipped table left [... the 8 non-tests paths ...] outside every row` (measured; the seven tests/ canaries are owned). Control on the S3-form guard (no S4 canaries) with the same row and hit: GREEN rc 0 (measured) |
| 6 | Exclude one owned subtree from `SWEEP_PATHSPEC` (insert `':(exclude)<x>'` after the `knowledge-base` exclusion): (a) `tests/commands`, (b) `tests/hooks`, (c) `tests/scripts/lib`, (d) `tests/fixtures`, (e) `tests/scripts`, (f) `tests`, (g) `':(exclude,glob)tests/*.sh'` for the top level, (h) `tests/scripts/fixtures`; (i) a partial exclusion that spares the canary names, `':(exclude,glob)tests/scripts/test-[a-m]*'` | RED rc 1 for (a) to (h): `the derived sweep's own probe is broken ... real-table-owner` (measured, 8 of 8). (i) GREEN rc 0 (measured; known surviving mutant, see row 14). Control on the S3-form guard (row deleted, no S4 canaries): (a) and (f) GREEN rc 0 (measured) |
| 7 | Empty the table (`SWEEP_DEFERRALS=()`), the guard's own dispatch, on the converted tree and on the base-content tree | RED rc 1 on both: `outside the deferral table (277 site(s))` on the converted tree and `(458 site(s))` on the base-content tree (measured; the invariant is that the two differ by 181, S4's population, which is tree-independent; the absolute counts move with the rest of the repository; the listed sites are capped at 50, so the count and not the list is the discriminator) |
| 8 | The base content of the 23 files with the row deleted (the complement of the conversion: every original shape visible with no row masking it) | RED rc 1: `outside the deferral table (181 site(s))` (measured) |
| 9 | Harness row, edit to the SUITE: drop one canary (`tests/fixtures/zz.yml`) from the `for _f in` list but not from `real_want` | RED rc 1: `real-table-owner` and `real-table-control: with no rows 14 planted paths were undeferred (want 15)` (measured) |
| 10 | Must-PASS inputs that differ from the canonical in a way the contract permits, each with a `cmp` landing check and row 1 as its paired control: (a) append `x \| grep -cE >/dev/null -- "$p"` to `test-zot-disk-sample.sh`; (b) append `x \| grep -q p  # sigpipe-demo: intentional` to the same file; must-RED marker look-alikes with the same landing check: (c) `... # sigpipe-demo: intentionally`, (d) the marker text inside a quoted string before the pipe | (a) and (b) GREEN rc 0, (c) and (d) RED rc 1 `outside the deferral table (1 site(s))` (all measured). (e) a marker followed by trailing text (`# sigpipe-demo: intentional because X`) is GREEN (measured): the marker regex ends at `intentional` plus a space or end of line, so the hole is wider than "one bare marker"; known surviving mutant, Item F |
| 11 | Resurrect a narrow test-looking glob that owns real hits but none of the canaries: `'tests/scripts/test-t* \| <= \| 1 \| #9217'` and revert `test-tmp-purge.sh:300` | RED rc 1: `real-table-test-shaped: loose (<=) rows whose glob is not test-shaped: tests/scripts/test-t*` and `real-table-production-rows: 7 non-test-shaped rows (want exactly 6)` (measured) |
| 12 | Known surviving mutant (anchor): weaken the probe consistently, i.e. drop `tests/fixtures/zz.yml` from the loop, from `real_want` and `14` for `15` in `real_none` | GREEN rc 0 (measured). One diff that edits the canary list and its pinned literals together proves consistency, not integrity: the only barrier is review of the probe hunk. Listed in Risks and the NOT-fixed list |
| 13 | `verify` side (P3): (a) delete the `:1274:` entry from `hand-edits.txt`; (b) drop `>/dev/null` from one converted line in `test-dev-suite-mutex.sh` | `unexplained: 1` each, with `UNEXPLAINED ...:1274: added line is not the transform of its base line` and `...test-dev-suite-mutex.sh:261:` (measured) |
| 14 | Known surviving mutant (test-shaped narrow row): put back `'tests/commands/*.test.sh \| <= \| 1 \| #9217'` and plant one hit in a new `tests/commands/zz.test.sh` (a name the row owns and no canary uses) | GREEN rc 0 (measured by the correctness reviewer and re-measured here). The `_ts_re` gate accepts a `*.test.sh` glob and the stale rule fires only at zero hits; closing it needs a guard line that forbids any deferral glob starting with `tests/` (a guard-logic insertion, left to S7 or Item F, decision-challenges item 16). Listed in Risks and the NOT-fixed list |
| 15 | Known surviving mutant (extension witness): drop one of `':(glob)**/*.bash'`, `*.bats`, `*.yaml`, `*.template` from `SWEEP_PATHSPEC` while a violating `tests/scripts/zzx.<ext>` file exists | GREEN rc 0 for each of the four (measured by the test-design seat and re-measured here). No canary uses those extensions anywhere in the repository, so this is a guard-wide gap, not a `tests/` one; `.tf` is held only incidentally by the `workspaces-luks.tf` row and `.js`/`.yml` by the existing canaries. Listed in the NOT-fixed list; Item F |

Harness rows. Suite edits that must go RED are rows 4 and 5 (a deleted row put back), row 6 (the sweep narrowed), row 7 (the table emptied: the guard's own dispatch) and row 9 (the probe edited). Must-PASS inputs that differ from the canonical: row 10 (a drained spelling no converted line used, and a real trailing marker). Each must-PASS row is only evidence if the mutation landed and the guard would have seen it: `cmp` against the pristine file differs, and the paired control (row 1, the same line with `-q` and no marker) goes RED at the same position.

Anchor. The table and the probe live in the file they protect, so one commit can move both together; this proves consistency, not integrity (row 12). What must also move for a weakening to pass: a row put back is a visible one-line diff; the canary names, `real_want` and the literal 15 are three places in the probe that must move together; `verify`, the before and after `DEFERRED:` lines in the PR body and the tracker comment would disagree; and with no row at all there is nothing for a count to be moved between. The known hole that remains is the marker (`# sigpipe-demo: intentional` hides any line from the count; nothing caps its use per file; this PR adds four), documented in the guard header and owned by Item F.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an engineering-internal CI-hygiene change with no product, marketing, legal, finance, sales or support surface. No regulated-data surface is touched (no schema, migration, auth flow or API route), so the GDPR gate does not fire; no store or connection is added (no encryption-posture section); no infrastructure is introduced; no architectural decision is made or changed (the guard's design is unchanged), so no ADR or C4 view moves. The engineering lens is carried by the plan-review panel.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "S4 (own plan): the guard row `tests/*` (181 hits, ceiling 181, mode <=) in .claude/hooks/grep-q-pipe-guard.test.sh." [brief] | Overview, Census, Files to Edit, Phases | mapped |
| 2 | "S1 (#9720), S2 (#9765) and S3 (#9788, merge e7c64c42dc) are DONE and merged; do not redo them." [brief] | Premise Validation, Overview, Files to Edit (not touched list) | mapped |
| 3 | "Start with `python3 scripts/grep-q-drain-codemod.py apply --row 'tests/*'` as a dry run and the guard's DEFERRED: lines; decide from the code what is actually hit (data vs code, suspect files that need --reviewed-suspect, the grep -m display shapes, executed strings)." [brief] | Census, Suspect files read, Disposition of every line | mapped |
| 4 | "(1) when a slice deletes the last deferral row for a subtree, plant a violating-file canary under each shape the deleted row owned in the guard's real-table probe (real_want/real_none) in the same PR and mutation-prove it in both directions" [brief] | Overview, Files to Edit, Guard Contract rows 4 to 6, 9, 11 | mapped |
| 5 | "(2) pair-run base must be a real detached clone of the base SHA with node_modules linked on both sides, under ulimit -v 6000000, suites that start vitest run without the cap; (3) compare suite ids ... for runner parity; (4) ... cmp ...; (5) rely on CI as the full-battery gate" [brief] | Pair run, Phase 3 (runner parity not applicable, reason stated), Phase 4, Overview (local gate) | mapped |
| 6 | "Per PR: evidence comment on the tracker #9217, Ref not Closes, a plain NOT-fixed list, no [skip-deploy-fix-apply], nothing added to plugins/soleur/skills/work/SKILL.md." [brief] | Phase 5, AC-8, AC-9, AC-12 | mapped |
| 7 | "Run mutation batteries under ulimit -v 6000000, one mutant at a time. Leave the main checkout's uncommitted .mcp.json alone." [brief] | Phase 4, AC-6, AC-9 | mapped |
| 8 | "Later work (not this PR): S5 to S7, Items D, E, F, G, I, H, Wave A3 carriers, #9639/#9638 triage." [brief] | NOT-fixed list | mapped |
| 9 | "disposition of EVERY non-T0 line read at file:line ... list which subdirectories it owns" [brief, plan contents] | Research Reconciliation row 3, Disposition table | mapped |
| 10 | "which workflows fire on merge ... open-PR intersection ... semantic screen ... User-Brand Impact ... Observability (measure its wall time under the 15 s Check 10 cap plain and inside bwrap)" [brief, plan contents] | Overview, Trigger derivation, Research Reconciliation, Observability | mapped |
| 11 | "Write hand-edits.txt ... and data-conversions.txt into the spec dir ... alongside tasks.md, decision-challenges.md and session-state.md" [brief] | Files to Create | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Converting 155 lines with the S1 codemod | "Start with `python3 scripts/grep-q-drain-codemod.py apply --row 'tests/*'`" | asked |
| Deleting the row | "the guard row `tests/*` (181 hits ...)" and "(1) when a slice deletes the last deferral row for a subtree" | asked |
| Seven canary paths in the real-table probe | "plant a violating-file canary under each shape the deleted row owned" | asked |
| Marker (not conversion) on the four W2 fixture lines | "decide from the code what is actually hit (data vs code ...)" | inferred — justification: the lines are a detector's positive control; a conversion fails `W2-control` (measured), and a counted pin needs a `_ts_re` widening |
| Hand-editing the sed expression at line 1274 | "decide from the code ... executed strings" | inferred — justification: the string is matched against converted line 848 and must land (the suite exits 1 when it does not, measured), and `/dev/null` collides with the `s///` delimiter |
| Pair-running all 23 owning suites and 5 adjacent ones | "pair-run base must be a real detached clone ..." and "list the owning suites that must read identical" | inferred — justification: the whole hit set costs 460 s per side; a subset would leave unobserved the suites with no hand edit |
| Not running runner parity | "(only if scripts/test-all.sh or the affected index is edited, otherwise state why not)" | asked (the reason is stated) |
| One learning file | "a plain NOT-fixed list" and the series convention | inferred — justification: one learning per non-obvious finding; AC-10 names the candidate and forbids filler |
| `tasks.md`, `session-state.md`, `decision-challenges.md` | "alongside tasks.md, decision-challenges.md and session-state.md" | asked |

### Split Assessment

- Subsystems touched: 3 — `tests`, `.claude`, `knowledge-base`
- Planned files: about 31 (23 test files, the guard, five spec files, the plan, one learning) | Estimated changed lines: about 200 (181 one-line edits, 14 guard lines, about 60 lines of documents)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the file count crosses the threshold only because the 23 test files are one-line edits proved by one `verify` run; the series boundary (one deferral area per PR) is already the split.

## Acceptance Criteria

> **Superseded at work and review (2026-10-09):** the final measured numbers are in `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s4-tests-dir/evidence.md` (section 'Review addendum'): guard diff 6 added / 7 removed against the merge base at the work commit and larger after review, `hand-edited: 10`, 17 planted real-table paths and 5 canary roots. Where an AC below quotes 7/7, 15 paths, `hand-edited: 7` or 181/181, the addendum wins.

Pre-merge boxes are checkable on the final tree; post-merge boxes are executed by `soleur:postmerge` and the tracker comment, with no human step.

### Pre-merge (PR)

- [ ] AC-1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0, prints 10 `DEFERRED:` lines and none for `tests/`; the ten are byte-identical to the merge-base's other ten (`diff` of the two `DEFERRED:` sets is exactly the one deleted line); the test-shaped total is 256 (sum of the four remaining test-shaped ceilings), down from 437, both sums pasted in the PR body, together with the Phase 1 `deferral ceiling exceeded` line (`has 181 hits, ceiling 26`), which is otherwise never committed. If Phase 0 finds different counts, the AC carries the re-measured numbers.
- [ ] AC-2 `python3 scripts/grep-q-drain-codemod.py verify --base "$(git merge-base HEAD origin/main)" --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s4-tests-dir/hand-edits.txt` prints `verified: 174`, `hand-edited: 7`, `unexplained: 0` after `git fetch origin main` (the base SHA is named in the PR body); the idempotency dry run before the row goes prints `WOULD-CHANGE: 0 lines in 0 files`; `bash -n` passes on all 23 edited files; `git diff --numstat origin/main...HEAD -- tests/` shows 181 insertions and 181 deletions; `git diff --name-only origin/main...HEAD` lists the 23 test files, the guard and the spec and plan paths only; the base-side lines changed outside the two codemod passes equal the entries of `hand-edits.txt` plus `data-conversions.txt` (26, compared by command, not by eye); the open-PR intersection list is pasted (expect #9784 by file, no hunk within three lines). `verify` proves the transform only, not that a converted line was code rather than data (that is the table read in this plan and AC-4).
- [ ] AC-3 The Phase 0 drain probe printed `q: 141`, `c: 0`, `nomatch: 1`, `neg-q: 0` and `neg-c: 1` on the dev host's grep and inside `ubuntu:24.04`, with both outputs in the PR body. Command: `bash -c 'set -o pipefail; (echo 1; sleep 0.4; echo 2) | grep -q 1; echo "q: $?"; (echo 1; sleep 0.4; echo 2) | grep -c 1 >/dev/null; echo "c: $?"; (echo 2; sleep 0.4; echo 3) | grep -c 1 >/dev/null; echo "nomatch: $?"; ! (echo 1; sleep 0.4; echo 2) | grep -q 1; echo "neg-q: $?"; ! (echo 1; sleep 0.4; echo 2) | grep -c 1 >/dev/null; echo "neg-c: $?"'`.
- [ ] AC-4 The PR body carries the pair-run result: a one-sentence summary for the suites that read identical and one row for each suite that differed or needs a caveat. The 23 owning suites and the 5 adjacent ones (28) must read `identical` (same rc, same final line, base clone versus branch); `not run locally` is allowed only for `registry-gate-mutation-battery`, with the reason; `inconclusive` (timeout both sides) is not allowed for the 28. A difference blocks the PR until explained. The body states that a pair run on small fixtures shows "no verdict change", not "the race is gone".
- [ ] AC-5 `bash scripts/pre-push-ratchet-lane.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` and `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new) pass; `bash scripts/test-all.sh --print-selection` on the branch diff prints its `AFFECTED_SUMMARY` line with `fallback=none`, pasted in the PR body with the sentence "`scripts/test-all.sh --affected` was not run: CI's required test check runs the full battery on the PR head". `git diff --stat origin/main...HEAD -- scripts/test-all.sh scripts/lib/test-affected-paths.sh` is empty, which is why no runner-parity digest is recorded.
- [ ] AC-6 The Guard 1 matrix was hand-applied on scratch copies after a green control, one mutant at a time under `ulimit -v 6000000`, each RED row killed by its named FAIL text with rc 1 (an rc 2, 126 or 127, or a crash, is an instrument failure and not a kill), the landing check a `cmp` against a pristine copy (never a `git diff` count; a `sed` replacement whose text contains the delimiter is built by a script instead), the restore check clean (`git status` empty in the scratch clone), rows 1 to 9, 11 and 13 RED (including 1c), row 10a/b and the 6i partial exclusion GREEN (the first with its paired controls), 10c/d RED, and rows 10e, 12, 14 and 15 recorded as the surviving mutants.
- [ ] AC-7 The observer table is in the PR body: for each of the 19 stub lines the result of the `-vc` inversion and the `-m 0 -c` never-match (killed with the first red line, or survived with the reason; expect 16 of 19 killed by at least one, unobserved 1087, 1723 and 1725), for `test-tmp-purge.sh:300` both mutants, for the `-m` display one scratch run of old and new expression on a populated, an empty and a no-match input with identical stdout plus the never-match mutant, for line 1274 the revert run (the suite stops with rc 1 after `T-mq-ctl5`), and for the four fixture lines the convert-instead-of-mark run (`W2-control` fails). A surviving mutant is listed as unobserved by its suite and is not claimed as covered.
- [ ] AC-8 The PR body (authored by `soleur:ship` from the diff plus `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s4-tests-dir/`) has as its first line that merging fires no path-filtered workflow (the trigger derivation output over the 24 files, 0 of 24 for each of the 18 filtered ones) and no plugin or web-platform release, apply or deploy; `Ref #9217` and never `Closes`; no `[skip-deploy-fix-apply]`; a `## Changelog` section; the NOT-fixed list under a heading that avoids the ship-gate deny tokens; labels `semver:patch`, `type/chore`, `domain/engineering` (the series convention; no `app:web-platform`).
- [ ] AC-9 Untouched, each checked against the merge-base: `git diff --stat origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md scripts/grep-q-drain-codemod.py scripts/test-all.sh scripts/lib/test-affected-paths.sh` is empty; `git diff --numstat origin/main...HEAD -- .claude/hooks/grep-q-pipe-guard.test.sh` shows the row deletion and the canary lines only (rehearsal: 7 added, 7 removed; `SWEEP_PROBE_CHECKS` still 62, `SWEEP_PATHSPEC`, `SWEEP_CANARIES`, `GATED_PROD_ROWS` and every other row unchanged); `tests/scripts/test-sentry-full-root-apply.sh` is not in the diff; no commit lists a file outside the 24 plus the knowledge-base artifacts; the main checkout's `.mcp.json` was not touched; no file outside this worktree and the session scratch directories was written.
- [ ] AC-10 One learning file (candidate: a data line can be the text another converted line is matched against, so a mechanical sweep needs a coupling check between its data tier and its code tier, and the converted token `>/dev/null` collides with a `/` delimiter; and a detector's seeded positive control must keep the shape and take the marker), written only if still non-obvious at work time; `markdownlint-cli2` is clean on the plan, `tasks.md`, `decision-challenges.md` and the learning; the discoverability command is re-measured under the 15 s cap after the guard edit, plain and in a Check 10-shaped `bwrap`, with `uptime` beside each figure.

### Post-merge (automated)

- [ ] AC-11 `soleur:postmerge`: `gh run list --json workflowName,headSha,conclusion` for the merge SHA shows the seven unfiltered push workflows and none of the 18 path-filtered ones (no `version-bump-and-release`, `web-platform-release` push run, `apply-web-platform-infra`, `apply-deploy-pipeline-fix` or `infra-validation` run exists for that SHA), recorded as such; CI on main is green; the files are verified at the merge SHA (`git show <sha>:.claude/hooks/grep-q-pipe-guard.test.sh | awk '/^  .tests\//{n++} END{print n+0}'` prints 0; a count and not a `grep -q`).
- [ ] AC-12 Tracker comment on #9217 with the before and after `DEFERRED:` table, the per-tier counts, the command behind each number, the NOT-fixed list and the 12-line throwaway; the `Filed:` line, Merge Danger (`Undo:` and `Blast Radius:`), Pipeline Tally, Changelog and Model Dissents sit in the PR body.

NOT fixed by S4 (stated in the PR body and the tracker comment): the other 256 test-shaped ceiling units (S5 and S6: `plugins/soleur/*.test.sh` 66 and `apps/web-platform/*.test.sh` 180, which is 178 hits with slack 2 and includes the infra suites; five data pins in `plugins/soleur/test/*`; five data lines in `.claude/*.test.sh`); the 23 wave A3 production sites; the producer-side join (S7); the guard's own blind spots (Item F: variable binary, flag order, wrappers such as `time`, `sh -c`, a subshell group or `rg`, split-line pipes, `| head`, the `.md` fences in SKILL.md files, `.py`/`.ts`/`.mjs`; the marker `# sigpipe-demo: intentional` accepted with trailing text and not capped per file, 4 more lines now use it; no per-extension probe for `.bash`, `.bats`, `.yaml`, `.tf`, `.template`, `.js`); the consistent-weakening hole of the probe (row 12), the test-shaped narrow-row hole (row 14) and the partial-exclusion hole (row 6i), the per-extension witness gap (row 15) and the trailing-text marker hole (row 10e); the codemod edge cases S1 listed, its `repeated-q` refusal and its producer screen; `verify`'s trust gaps (it cannot tell code from data); the three unobserved stub lines (`rung2-evidence-capture.sh:1087, 1723, 1725`) and the sites whose inversion mutant survives; the latent fact that the stub bodies set no `pipefail` (19 converted lines are inert today); the dead `test-*` clause in the guard legend and `_ts_re` (S7 cleanup); the S7 exit ledger (the glob rows left after S4 are `.claude/*.test.sh` `<=` 5, `plugins/soleur/test/*` `=` 5, `plugins/soleur/*.test.sh` and `apps/web-platform/*.test.sh`, so the S1 plan's S7 exit wording is still not met by them; S7's plan reconciles it); #8659 and #8800 (not touched), #9638 and #9639; #9784's three new early-exit pipes under `tests/` (`test-inngest-backstop-retire-gate.sh:590` and `:601`, `test-inngest-host-dark-gate.sh:879` on its head; another PR's files, named in the PR body; after S4 merges they fail "outside the deferral table" on that PR's CI instead of widening a ceiling).

## Test Scenarios

- Given the row lowered to `<= | 26` before any edit, when the guard runs, then rc 1 with `has 181 hits, ceiling 26` (Phase 1 red).
- Given the 155 codemod edits applied and nothing else, when the guard runs, then it prints `DEFERRED: tests/* (26 hits, ceiling 181 ...)` or, at the lowered ceiling, is green at 26 of 26.
- Given all 181 lines handled and the row deleted, when the guard runs, then rc 0 and 10 `DEFERRED:` lines, none for `tests/`.
- Given the row `tests/* | <= | 181` put back, when the guard runs, then `stale deferral` and rc 1; given `tests/* | <= | 1` plus one covering hit, then `real-table-owner` and rc 1.
- Given any one of the seven canaried `tests/` subtrees excluded from `SWEEP_PATHSPEC`, when the guard runs, then `real-table-owner` and rc 1.
- Given a writer that emits a second line after the first match and a negated pipeline, when it feeds `grep -c 1 >/dev/null` under `pipefail`, then the pipeline status is 0 and the negated form is 1; with `grep -q 1` they are 141 and 0.
- Given a three-line message whose first match is on line 2, when the old and the new `-m` display expressions run, then both print the same single line, and likewise for an empty and a no-match input.
- Given `test-audit-ruleset-bypass.sh` with line 848 converted and line 1274 not, when the suite runs, then it exits 1 after `T-mq-ctl5` (the mutation did not land); with both converted it prints `66 passed, 0 failed`.
- Given one of the four W2 fixture lines converted instead of marked, when `test-git-data-birth-readiness-gate.sh` runs, then `W2-control` fails.

## Risks and Sharp Edges

- **A classifier error converts data, and `verify` cannot see it** (a mis-converted data line still equals `transform(removed)`). S4 found three such cases the tool cannot see or refuses: a sed string matched against a converted line (1274), a detector's seeded control (2971-2974) and a `-qc` cluster (300). Mitigations: the 26 queue lines were read in context and listed; the six suspect files were read at file:line; the fragment search for pins; the pair run; the observer table.
- **The 19 stub lines are the least-observed edits.** They set no `pipefail`, so they are inert today; where the `-vc` swap survives (the dispatch branches are exclusive) the line is converted on the strength of the transform proof alone, and 3 of 19 survive both mutants (1087, 1723, 1725). The PR body lists those sites and does not claim a row sees them.
- **A previously masked negative assertion can surface as red at scale.** Under the old form a SIGPIPE'd producer turned a `! producer | grep -q X` pass into a vacuous one; the drained form evaluates the assertion for real. The pair run uses small fixtures, where the race does not bite, so it shows "no verdict change" and cannot show a masked failure; if one exists it appears in CI or the merge queue as a red suite on the converted line. The 11 negated sites are listed in the Census so a red can be read against them.
- **Known surviving mutants** (matrix rows 12 and 14, partial exclusion 6i, and the marker): consistent weakening of the probe in one diff; a test-shaped narrow row such as `tests/commands/*.test.sh <= 1` with a hit in a file it owns and no canary uses; a pathspec exclusion that spares the canary names (`tests/scripts/test-[a-m]*`); and `# sigpipe-demo: intentional` appended to any line. The only barrier is review of the diff; closing the second needs a guard line forbidding any deferral glob that starts with `tests/` (S7 or Item F), and Item F owns the marker cap.
- **The marker is now used on 4 more lines**, inside a heredoc: a later edit that rewrites the heredoc could drop the trailing text and the guard would then count 4 sites (loud, row 2c), while a later edit that converts the lines instead of marking them fails `W2-control` (loud, measured).
- **Probe literal conflicts with S5 and S6.** Each adds canaries to the same `real_want` line and `real_none` literal; the second to merge rebases once and re-counts (the canary list is additive; a miscount fails `real-table-control`).
- **#9784** (draft) already adds three early-exit pipes under `tests/`; it exceeds today's ceiling (slack 0) and, after S4, fails "outside the deferral table". S4 does not touch its files; the PR body names the three lines. The screen is point-in-time: Phase 0 and the PR-ready step re-run it.
- **Merge-queue ejection.** #9784 edits `test-inngest-host-dark-gate.sh` at distant hunks (862-997, 1961) from S4's line 823, so a textual conflict is not predicted; if the queue ejects the entry, rebase once, re-run Phases 0 and 3, re-enter. Never re-sync a BEHIND branch mid-flight.
- **Producers now run to EOF.** Wall time can rise where a producer is a full SUT run; the pair run records per-suite wall time (460 s base against 440 s branch, load-dependent) and the body lists any suite that grows noticeably.
- **A failure message that quotes a command in backticks inside double quotes runs that command when the check fails** (S1 finding). Every battery runs under `ulimit -v 6000000`, and any new check text avoids backticks inside double quotes.
- **Verify the verifiers.** Every count in this plan was read from a command's output on `71c0bac35f`, `origin/main` `01d2b5a0d8` or the rehearsal clones; read rc files, not completion notifications; never `git add -A`; never `rm -rf` a directory that contains `.git` (fresh scratch directories per run).
- A plan whose `## User-Brand Impact` is empty, holds only `TBD`/`TODO`/placeholder text or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.

## Dependencies and References

- Tracker #9217 (this series); #7376, #6601 (related); #7797 (xtrace lint: comment only if a touched file enters its scope; none of the 23 is one of the four files its plan named); #9482 (only if a slice changes an ejection-class fact, expected in S7); #9638 and #9639 (not fixed).
- Merged: #9213, #9525, #9554, #9587, #9632, #9708, #9720 (S1, `f44463a7e9`), #9765 (S2, `f1497664ae`), #9788 (S3, `e7c64c42dc`).
- Guard: `.claude/hooks/grep-q-pipe-guard.test.sh` (header, `SWEEP_DEFERRALS`, `SWEEP_PATHSPEC`, the real-table probe, `SWEEP_PROBE_CHECKS`, `_ts_re`). Tool: `scripts/grep-q-drain-codemod.py`.
- Series plan: `knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md` (Slice Register, Producer-side join design); S2 plan `knowledge-base/project/plans/2026-10-08-chore-grep-q-wave-b-s2-plugin-test-harness-plan.md`; S3 plan `knowledge-base/project/plans/2026-10-08-chore-grep-q-wave-b-s3-scripts-test-harness-plan.md`.
- Workflows read for the trigger: every `.github/workflows/*.yml` with a `push` trigger plus the four `workflow_run` arms; `.github/workflows/ci.yml` for the full-battery legs.
