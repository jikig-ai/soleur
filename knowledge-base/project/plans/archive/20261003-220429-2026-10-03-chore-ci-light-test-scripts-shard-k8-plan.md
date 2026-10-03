---
title: "chore(ci): bump the light test-scripts matrix from K=7 to K=8 shard legs"
date: 2026-10-03
slug: ci-light-test-scripts-shard-k8
branch: feat-one-shot-light-shard-legs-k8
issue: 9307
lane: single-domain
type: chore
ref: "#9307 (umbrella; stays open - never Closes)"
---

# chore(ci): bump the light `test-scripts` matrix K=7 -> K=8

## Enhancement Summary

**Deepened on:** 2026-10-03. **Gates run:** 4.6 User-Brand Impact (present, threshold `none` with scope-out; ci.yml does not match the sensitive-path regex), 4.7 Observability (Files-to-Edit match no code/infra trigger path of plan Phase 2.9: ci.yml, repo-root scripts/, plugins/soleur/test; the observable effect is the existing `suite-timings-scripts-<k>` artifact upload plus job wall time, discoverable without SSH via `gh api`), 4.8 PAT grep (no hits), 4.9/4.10 not triggered (no UI, no store), 4.11 Guard Contract (no new guard; one existing mutation row's literals are updated and the row is run, see Acceptance Criteria).
**Verified live:** #9307 OPEN, #9447 OPEN, #8864/#9232/#8006 CLOSED; rule id `cq-write-failing-tests-before` active in AGENTS.md; zero other `/7`-denominator literals in `plugins/soleur/test` or `scripts` beyond those listed in the K-sensitive table.
**Corrections made by this pass:** the post-merge balance check no longer claims the closed #9232 follow-through will fire; the CI-sharded mutation battery risk was added.

## Overview

Operator-approved ("Bump K to 8 yes"). The light `test-scripts` matrix in `.github/workflows/ci.yml` moves from seven legs to eight, and the duration-aware shard manifest pair (`scripts/suite-shard-legs.tsv` + `scripts/suite-durations.tsv`) is regenerated wholesale at K=8 from the five newest green `main` runs. Goal: every light leg predicted under the 10-minute target. Part of umbrella #9307, which stays open (PR body says `Ref #9307`, never `Closes`).

Measured today with the committed regenerator in dry-run, against the staged five-run artifact set (command in Research Insights):

| K | predicted per-leg suite time | verdict |
|---|---|---|
| 7 (today) | 666.4-692.6 s | every leg above 600 s |
| 8 (this plan) | 567.2-596.8 s (legs 592.3-596.8 s except leg 8 at 567.2 s; spread 29.6 s) | all under 600 s, but the worst leg has only ~3 s of headroom |

## Premise Validation

Checked: #9307 is OPEN (umbrella, as stated). Sibling PR #9447 ("price audit-suite-reads and check-web-host-escrow-config from real CI timings") is OPEN and not merged; `git log HEAD..origin/main` is empty, so the branch is on current main. The matrix literal, the `# n=7` header, and the runbook lines all exist on the branch. The five staged run dirs each contain `suite-timings-scripts-0..6` (re-download not needed). No ADR proposes or rejects a K bump as a mechanism (ADR-240 governs the generator, not K). Nothing stale.

## Research Insights

**Property List** (what the ask buys, one observable outcome each)
1. P1: no light `test-scripts` leg is predicted above 600 s of suite time on the current timing medians.
2. P2: `n` in the manifest header, the ci.yml matrix length, and every `/N` denominator agree, so no registration runs nowhere.
3. P3: the manifest pair is a faithful regeneration (not a hand-merge) so the next `--incremental` regen has a clean base.
4. P4: a reader of the runbook finds the new topology, prediction, and the added per-run cost.

**Cut List** (mechanisms considered and cut)
- New "leg-count" constant or shared variable for K -> P2 is already enforced by `plugins/soleur/test/scripts-shard-manifest.test.sh` (n == ci.yml leg count) and `scripts-shard-totality.test.sh` (matrix read as VALUES). A new constant would add a second source of truth. Cut.
- Splitting the longest single suite instead of bumping K -> operator already chose the K bump; the longest suite is already split (#8864). Cut.
- Editing the leg-balance probe `scripts/followthroughs/ci-leg-balance-9232.sh` -> it reads expected N from the manifest `# n=` header (verified in its header comment), so P2 holds with zero edits. Cut.
- Editing required-check lists -> `scripts/required-checks.txt` gates only the synthetic `test` aggregate (grep for `test-scripts (` there returns nothing); matrix leg names are not required contexts. Cut.

**K-sensitive surfaces (the blast radius, from the K=6->7 precedent commit `ebca96756b` and a fresh grep of the tree)**

| Surface | Why it changes |
|---|---|
| `.github/workflows/ci.yml` L1056 matrix `shard:` literal | the one real K |
| `.github/workflows/ci.yml` comments L1033-1037, L1077, L1227, L1250 | prose says K=7 / "seven legs" / `1/7` |
| `scripts/suite-shard-legs.tsv` `# n=7` header + rows; `scripts/suite-durations.tsv` | regenerated wholesale, never hand-edited |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` ROW5 (~L465-471) | both the `old` and `new` literal embed the 7-value matrix; the `old` literal must match ci.yml byte-for-byte or the row errors; the mutated `new` drops the LAST leg (`... "7/8"` list one short) |
| `plugins/soleur/test/scripts-shard-totality-mutations.sh` ~L739 comment ("starve seven legs") and `scripts-shard-totality.test.sh` L10, L170 comments | prose only |
| `scripts/test-all.sh` L5544 comment ("fans out over seven legs") | prose only; no runtime constant (runner takes N from `matrix.shard`) |
| `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` L19, L31 (topology table), Measured history, Runner-availability section | topology, prediction, cost note |
| `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` L67 | fixture job name `test-scripts (1/7)`; synthetic data, intentionally left alone (it does not read the real matrix) |

Do NOT touch the sandbox keep-list in `scripts/test-all-affected.test.sh` (operator constraint).

**Cost note source (Phase 0.6c, measured not asserted).** `gh api /repos/jikig-ai/soleur/actions/runs/37130724002/jobs` shows the seven light legs' wall time at 444-746 s (sum 4217 s); the dry-run's suite total is 4736167 ms across 545 tabled suites. K=8 adds exactly one runner (one more checkout + toolchain setup + artifact upload) per CI run on every push/PR run that executes the light group; the repo's own runbook (Runner-availability section) records that extra legs are not free because group occupancy and start spread bind on ~a quarter of runs. The exact added runner-minutes cannot be stated from the dry-run (it predicts suite time only); the runbook note records the mechanism and the command that measures it after the first K=8 run: setup overhead = leg wall minus summed `suite-timings-scripts-<k>` time.

**Learnings applied.** `knowledge-base/project/learnings/` precedent for the K=6->7 rebalance (commit `ebca96756b`): K-sensitive surfaces updated atomically in one PR; `--write` with K != workflow N is refused by the regenerator, so ci.yml is edited first.

## Implementation Phases

Order matters: the regenerator refuses `--write` unless K equals the workflow's N, and the manifest test reds when `n` != the matrix length, which is the failing test that drives the change (cq-write-failing-tests-before).

### Phase 1 - Matrix to 8 and the RED test

1. Edit `.github/workflows/ci.yml` `test-scripts` matrix to `["1/8", "2/8", "3/8", "4/8", "5/8", "6/8", "7/8", "8/8"]`.
2. Run `bash plugins/soleur/test/scripts-shard-manifest.test.sh`. Expect RED (manifest `n=7` vs 8 legs). This is the failing test.
3. Update the ci.yml comment prose (L1033-1037 K=7 paragraph, L1077 `light leg ~... at K=7`, L1227 `matrix.shard is 1/7`, L1250 `seven legs`). Fix the `L1077` sentence to state the K=8 prediction (filled after Phase 3 with the real written figures, as a predicted-suite-time range, not a CI measurement).

### Phase 2 - Update the guard's mutation row first, then regenerate

1. In `scripts-shard-totality-mutations.sh` ROW5: `old` = the 8-value literal; `new` = the same list with `"8/8"` removed (7 values still saying `/8`); comment text "Six legs whose values still say /7" becomes "Seven legs whose values still say /8: leg 8's suites run nowhere"; the `RED` description string becomes "ci.yml declares 7 legs while the partition computes mod 8".
2. Update the prose-only comments listed in the table (totality test L10/L170, mutations ~L739, `test-all.sh` L5544).

### Phase 3 - Regenerate the TSV pair wholesale

1. Sibling check: `gh pr view 9447 --json state,mergedAt`. If merged, `git fetch origin main && git rebase origin/main` (a rebase, never `git merge main` - the rename-guard trips on merge commits). If the rebase conflicts in the TSV pair, discard BOTH sides (`git checkout origin/main -- scripts/suite-shard-legs.tsv scripts/suite-durations.tsv`) and let the next step rewrite them; never hand-merge.
2. Run, with the artifact dirs under `/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/455cbd60-5231-4a3b-8c49-cf1ee3d3b19e/scratchpad/t/` (re-download any missing dir by name: `gh run download <run> -n suite-timings-scripts-<k> -D <dir>`; the `-p` glob does not work):
   ```bash
   python3 scripts/regenerate-shard-manifest.py \
     --timings-dir <t>/37130724002 --timings-dir <t>/37116885720 --timings-dir <t>/37112007418 \
     --timings-dir <t>/37111686980 --timings-dir <t>/37109744841 \
     --group light            # dry-run first: confirm max leg < 600000 ms
   # then the same command + --write
   ```
3. Confirm the diff is confined to `# n=8`, the generated-from-runs provenance header, row `leg` columns, and the durations table, and that `git diff --stat` touches no other TSV (the heavy pair is untouched).
4. If 9447 had already repriced two labels, those labels' medians flow in through the five-run median; accept the regenerated output as is.

### Phase 4 - Runbook

Edit `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`:
- TL;DR sentence (L19): "light group runs K=8".
- Topology table row (L31): `K=8`; prediction from the written manifest (expected 567.2-596.8 s, i.e. ~9.5-9.9 min predicted suite time; every leg under 600 s; label it the table's prediction, not a CI measurement; state the thin headroom).
- Add a Measured-history bullet `2026-10-03 K=7 -> K=8 (#9307)`: K=7 predicted 666.4-692.6 s, K=8 567.2-596.8 s from five runs (ids above), provenance of the regen command.
- Add the cost note in the Runner-availability section: one more CI leg (runner) per run; the mechanism; the measurement command above.

### Phase 5 - Verify (targeted; CI is the gate)

`TEST_GROUP=affected` on a runner-touching diff exceeds 5000 s locally, so run only:
- `bash plugins/soleur/test/scripts-shard-manifest.test.sh` (GREEN: n=8 == 8 legs)
- `bash plugins/soleur/test/scripts-shard-totality.test.sh`
- `bash plugins/soleur/test/scripts-shard-totality-mutations.sh` with `--rows A-B` narrowed to the range containing ROW5 (the battery has 42 declared rows; locate ROW5's ordinal by reading the `row`/`in_range` calls above it, do not guess), else leave the full battery to CI's three `shard-totality-mutations` legs
- `bash scripts/lint-orphan-test-suites.sh`
- `bash scripts/followthroughs/ci-leg-balance-9232.test.sh`
- `bash plugins/soleur/skills/ship/scripts/battery-owed.sh` decides the remainder (rc 42 = skippable).

Then ship per the normal pipeline; the PR body says `Ref #9307`.

## Files to Edit

- `.github/workflows/ci.yml`
- `scripts/suite-shard-legs.tsv` (regenerated)
- `scripts/suite-durations.tsv` (regenerated)
- `plugins/soleur/test/scripts-shard-totality-mutations.sh`
- `plugins/soleur/test/scripts-shard-totality.test.sh` (comments)
- `scripts/test-all.sh` (one comment)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-light-shard-legs-k8/tasks.md`

## Acceptance Criteria

- [ ] `.github/workflows/ci.yml` `test-scripts` matrix has exactly eight values `1/8`..`8/8`; `git grep -nE '"[1-7]/7"' .github/workflows/ci.yml` returns nothing. Verify the matrix glob matched a real file with `git ls-files .github/workflows/ci.yml`.
- [ ] `scripts/suite-shard-legs.tsv` header reads `# n=8` and the file was produced by `regenerate-shard-manifest.py --write` (not hand-edited); the heavy pair and infra files are byte-identical to the base.
- [ ] The regenerated manifest's dry-run/write output reports every leg strictly below 600000 ms (expected max about 596813 ms on the current main; re-derive after any rebase onto a main that carries #9447, and record the actual figures).
- [ ] `bash plugins/soleur/test/scripts-shard-manifest.test.sh`, `scripts-shard-totality.test.sh`, `scripts/lint-orphan-test-suites.sh`, and `scripts/followthroughs/ci-leg-balance-9232.test.sh` exit 0.
- [ ] ROW5 in `scripts-shard-totality-mutations.sh` applies (its `old` literal matches ci.yml) and the mutated ci.yml drives the totality test RED; confirmed by running that row, not by reading it.
- [ ] Runbook shows K=8 in the TL;DR and topology table, the new prediction, a `2026-10-03` Measured-history entry, and the added-runner cost note; no remaining `K=7` outside historical Measured-history entries (`git grep -n 'K=7' knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` lists only history lines).
- [ ] No merge commit on the branch (`git log --merges origin/main..HEAD` is empty); `scripts/test-all-affected.test.sh` is not in the diff.
- [ ] PR body uses `Ref #9307` (not `Closes`); #9307 remains open.

## Test Scenarios

- Given ci.yml with 8 legs and the n=7 manifest, when the manifest test runs, then it reds (RED proof of Phase 1).
- Given the regenerated manifest, when the manifest and totality tests run, then both are green and every registration lands on exactly one of 8 legs.
- Given ci.yml with the last leg dropped (ROW5 mutation), when the totality test runs, then it reds on the value list, not the count.

## Risks and Sharp Edges

- **Thin headroom.** The worst predicted leg (596.8 s) clears the 600 s target by ~3 s, and the prediction is suite time only; wall time adds ~2-3 min of setup per leg (measured wall 444-746 s on K=7 legs vs ~677 s mean suite). The "under the 10-minute target" claim is about predicted suite time per the runbook convention; the plan records it that way and does not promise wall-clock under 10 minutes. Actual balance is not auto-measured: tracker #9232 is CLOSED, so `ci-leg-balance-9232.sh` is not a live follow-through. The post-merge check is the first K=8 main run's `suite-timings-scripts-0..7` artifacts re-run through the regenerator dry-run (`--timings-dir`, no `--write`) plus the legs' wall time from `gh api .../runs/<id>/jobs`; no new soak enrolment is added because the plan carries no time-gated close criterion.
- **Sibling race.** #9447 regenerates the same TSV pair. Whichever merges second regenerates on top of main (rebase, take-main-then-regen); never merge main into the branch.
- **ROW5 literal drift.** The mutation row `old` string must equal the ci.yml line exactly (indent included); an edit to either alone errors the row. Edit both in one commit and run the row.
- **Pre-merge artifact sets.** `ci-leg-balance-9232.sh` reads N from the manifest header and only counts runs with all N=8 artifacts; it keeps working unedited, but its tracker is closed, so do not expect it to fire.
- **Mutation battery runs sharded in CI.** `shard-totality-mutations` (ci.yml L1349) invokes the battery with `--rows`; ROW5's ordinal must fall in exactly one leg's range, which is unchanged because no row is added or removed.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan; it is filled below.

## User-Brand Impact

**If this lands broken, the user experiences:** a red or hung required `test` check on PRs (a leg that runs nowhere is the worst case, and the totality test exists to catch it), delaying merges for contributors; no end-user-facing artifact changes.
**If this leaks, the user's data is exposed via:** no vector; the change edits a CI matrix literal, committed timing tables, tests, and a runbook, and touches no credential, data, or runtime path.
**Brand-survival threshold:** none
threshold: none, reason: CI parallelism and committed shard tables only; no regulated-data, auth, or product runtime surface is touched.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change confined to CI matrix sizing and its documentation. Cost impact (one more runner per run) is recorded in the runbook; no budget gate applies at this scale.
