---
title: "ci: S4 PR4b, the held-back real-read edges of the code-edge drain and their revealed mentions"
date: 2026-10-25
slug: ci-s4-affected-index-pr4b-held-back-edges
branch: feat-one-shot-s4-affected-index-pr4b-held-back-edges
issue: 10959
type: chore
lane: cross-domain
refs: [10959, 10448, 9729]
brand_survival_threshold: aggregate pattern
---

# ci: S4 PR4b, the held-back real-read edges of the code-edge drain and their revealed mentions

Ref #10959. Ref #10448 (series tracker, stays open). Ref #9729 (epic). PR text uses `Ref` only, never a closing keyword.
Draft PR #11109 (label `s4-drain`, branch `feat-one-shot-s4-affected-index-pr4b-held-back-edges`) already exists and the claim comment on #10448 is posted.
Spec lacks a valid `lane:` (there is no spec.md for this branch), so it defaults to `cross-domain` (fail-closed).

## Overview

PR4 (#10945, merged as `45fe23b7671e`, baseline 1,878 to 1,640 lines) declared 239 code-extension edges and HELD BACK 117 more because declaring them reveals mention pairs
(the audit reads a declared file, and every path that file names becomes a new pair for that suite). This plan drains the held-back edges under the same rubric
(runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` section 7) and CTO ruling 5's stop line, with one change the CTO ruled on 2026-10-25: the
revealed MENTIONS are now accepted with anchor-keyed accept rows in the same commit as the edge that reveals them (decision-challenges.md row 1; the accept file exists with 18 sibling rows).

What it does, in order: (1) re-measures the base; (2) takes the worklist (`receipts/worklist-edges.tsv`, 117 rows, 115 candidates after rulings 5) in ascending order of measured reveal and cuts a slice
whose round-1 reveal sums to at most 130 pairs (about 36 edges, 31 suites, indicative: the trial table); (3) groups the slice into chains of under 60 round-1 pairs and, per chain,
declares the edges, saves the first report, pre-classifies every revealed pair (real read: declared next round; mention: accept row; doubt: hold the whole edge), and repeats to a fixpoint;
(4) regenerates the baseline only with the prune-only `ratchet --print-baseline`; (5) leaves everything above the slice baselined for the continuation PR4c (tracker #10959, which stays open) and PR5.

Expected yield is modest and is stated as a range so nobody reads it as the series' last drain: the baseline loses one line per declared edge, at most about 36 of 1,640 (the CTO's hot-file and 10-row holds will cut some),
the accept file gains on the order of 190 rows (an estimate: the slice's 143 first-pass pairs scaled by the trial's 748 boundary lines per 501 pairs; Phase 1.2 measures it), and no baseline line is added. The value is retiring the cheapest real reads, proving the accept-row flow
under the stop line before PR4c and PR5 repeat it at larger scale, and recording the policy rulings those PRs need.

## Research Insights

### Premise validation (Phase 0.6)

Checked by `gh`/`git`: #10959, #10448, #9729, #10860, #10861, #10865, #10414, #10859, #10949 and #10964 are all OPEN; #10945 is MERGED as `45fe23b7671ed13c53b46ae7517156d6e793734a`; draft PR #11109 is open with label `s4-drain` and is the only `s4-drain` PR;
`origin/main` equals this branch's tree (`git diff origin/main HEAD` empty). The baseline has 1,640 lines and `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` prints
`SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=1640 baseline=1640` (local wall 162 s at load about 10). Of the 117 worklist rows 116 are still baselined; `scripts/inngest-probe-heartbeat-feeder` -> `scripts/lib/inngest-probe-row.sh`
is not (a sibling drained it). The brief's "mirror comment already posted" holds (last comment on #10448 names #11109).
STALE premise found: archived row 6b says "PR4 creates no accept file" and the runbook says "Never in a drain PR: create an accept file", but `scripts/ci-pr-affected-audit.accept.tsv` now exists on main with 18 rows
(sibling PRs #10931 and later) and the issue #10959 body says the accept rows land with the edge; resolved by CTO row 1 (see Technical Rulings). ADR corpus: ADR-276 (demand-first hosted-runner budget) amendment item 2 is the drain tool; no ADR rejects accept rows
(grep of `knowledge-base/engineering/architecture/decisions/` for "accept row" finds only ADR-276's own mechanism). The 43 whole-tree-read pairs the issue asks to take to the CTO were ruled as policy only (row 6).

### Measurements (this planning session, read-only, local)

- Base: `ratchet` exit 0, `live=1640 baseline=1640`, wall 162 s (receipt `receipts/ratchet-baseline-45fe23b767.out`). Hosted figures are the parent's to record (see Phase 4.5).
- Trial (throwaway detached worktree of `45fe23b767`, all 117 worklist edges declared at once, 11 new arrays appended, NO accept rows): `exit=1 reason=new-pair live=2025 baseline=1640` => 501 new pairs (328 code-extension, 173 non-code), 748 boundary lines (one accept row each), 116 `stale-line` (the drained pairs), wall 261 s.
  Per-suite round-1 reveal, ascending, with cumulative sums: `receipts/trial-all-edges-reveal-by-suite.tsv`; the 501 pairs with the first referencing file: `receipts/trial-all-edges-new-pairs.tsv`.
- Shape: 25 suites reveal 1 to 6 pairs; cumulative 130 is reached at `scripts/compound-promote` (38 rows, of which 2 are the inngest-probe-row rows, so at most 36 declarable); the heavy tail is `scripts/battery-tag-authorship` 29, `scripts/betterstack-emitter-read` 29 (18 edges),
  `.claude/hooks/grep-q-pipe-guard.test.sh` 68 (31 edges) and `tests/scripts/git-data-birth-readiness-gate` 152 (one edge naming 227 hook paths).
- Edge classes of the 117: b (open content) 50, d (data row with quoted loop) 45, a (execute/source) 18, c (existence) 4. A 10-suite sample of the cheapest reveals shows both kinds: real reads (`github-community.test.sh` -> `plugins/soleur/test/test-helpers.sh:60` best-effort-sources `scripts/lib/scratch-root.sh`;
  `rtk-grammar-parity` via `.claude/hooks/lib/incidents.sh:71` sourcing `scripts/lib/rule-metrics-constants.sh`) and mentions (a runbook path in a PR-body string at `cron-content-vendor-drift.ts:2170`; JSDoc in `cla-doc-path.ts:5`; a menu line at `scripts/betterstack-query.sh:109`).
- Hot-file counts for the slice (`git log --since=90.days --oneline -- F | wc -l`): `scripts/cutover-inngest.sh` 31, `tests/scripts/lib/git-data-birth-readiness-gate.sh` 17, `.claude/hooks/pre-merge-rebase.sh` 14, `.claude/hooks/guardrails.sh` 13, `apps/web-platform/test/plugin-root-anchoring.test.ts` 11,
  `scripts/rule-metrics-aggregate.sh` 10, `scripts/followthroughs/git-data-rung2-evidence-capture.sh` 15; any of these that needs an accept row is held (CTO row 1c). The count is re-run in Phase 0.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-10-25-draining-an-index-by-declaring-edges-reveals-pairs-and-per-batch-commits-do-not-survive-a-moving-main.md`: keep edge lists as data, not commits; regenerate the baseline from `git checkout origin/main -- <baseline>` after each rebase; run the audit WITH main's accept file (without it the audit reports more pairs than the ratchet);
  after every merge of main list duplicate `AFFECTED_*_PATHS` names (`grep -oE '^AFFECTED_[A-Z0-9_]+_PATHS=\(' scripts/lib/test-affected-paths.sh | sort | uniq -d`; bash keeps the last assignment and silently re-opens drained pairs);
  run `scripts/test-affected-kb-consumers.test.sh` and `scripts/lib/inngest-probe-row.test.sh` after every edge batch.
- `knowledge-base/project/learnings/2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md`: a declaration for a suite that only `SUITE_GLOBS` registers is INDEX-UNBOUND and degrades `--affected` to the full battery; check each of the 11 new-array labels is a registered label before adding its block.
- `knowledge-base/project/learnings/2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md`: `producer | grep -q` under pipefail returns 141; write the stream to a file, or use `grep -q P < <(producer)`.
- `knowledge-base/project/learnings/2026-10-19-a-per-area-drawdown-cannot-satisfy-a-live-census-gate-and-reindenting-breaks-text-anchored-mutants.md`: the baseline must equal the live census of the working tree, so the commit unit is the whole tree; do not hand-split the baseline per area.
- `knowledge-base/project/learnings/2026-10-22-a-hop-regex-was-quadratic-on-one-long-token-and-my-own-stale-runs-held-the-test-queue.md`: kill your own stale `test-all.sh` runs (`list_runs`, `kill_mine` in `plugins/soleur/scripts/lib/proc.sh`) before the final gate; run `test-all.sh --capacity` first.
- `knowledge-base/project/learnings/2026-10-21-sibling-session-owned-commits-on-my-branch.md`: stage by explicit pathspec, check `git log origin/<branch>..HEAD` before each commit.
- No learning exists on accept-row anchors going stale (the learnings researcher found none): `soleur:compound` at ship should capture one.

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes):
1. A held-back edge is declared only where the suite really reads or executes the file, and a revealed pair is declared only for a real read (no false negative introduced).
2. The baseline only loses lines, and only through the prune-only `ratchet --print-baseline` run to a fixpoint (no hand edit, no added line).
3. Every revealed pair is classified from a cited line BEFORE the commit, and the round caps of CTO ruling 5 (as ruled again on 2026-10-25) hold.
4. Every commit leaves `ratchet` at exit 0 (bisects green) and the final audit shows zero new pairs and zero stale or unused accept rows.
5. The continuation is visible: what PR4b did not take, and why, is tracked on #10959 and handed to PR5 by name.
6. The window consequence is recorded on #10865 with the merge SHA.

Mechanisms the ask names and what already buys each property (grep of `scripts/ci-pr-affected-replay.py --help`, the runbook and the accept file on `origin/main`): the declaration mechanism (`AFFECTED_*_PATHS`) exists; the prune-only `--print-baseline` exists (properties 2, 4);
anchor-keyed accept rows exist with 18 rows and a validator (`load_accept`, `judge_rules` in `scripts/ci-pr-affected-replay.py`) that makes an unreachable row stale (property 4); the stop line is a CTO ruling, not code (property 3). 
Cut list: no new script or lint (the classification table is a committed TSV, not a guard); no change to `ratchet`, the audit reach or the replay suite; no new `_CLOSURE_LEAF_*` array unless 3 or more labels spread the same helper (row 14d); no ADR edit; no accept-file schema change; no new issue (the continuation lives on #10959).
Cut because already covered: a separate "accept row linter" (the audit's own `stale`/`not-a-gap`/`anchor-not-live` verdicts already do it); a recorder-in-CI (never wired into CI, archived row 2).

### Value-proposition measurement (Phase 0.6c)

The justification is not a CI-cost saving (the lever `CI_PR_AFFECTED` is unset and locked), so no saving is claimed. The measurable output is baseline lines drained: `wc -l scripts/ci-pr-affected-audit.baseline.tsv` before and after, upper bound 36 of 1,640 (2.2 percent),
and accept rows added (`wc -l scripts/ci-pr-affected-audit.accept.tsv`, an estimate of about 190). Whether the slice is worth a PR at that yield is the scope call the brief already made; the plan reports the yield and does not argue it.

## Research Reconciliation: Spec vs. Codebase

| Claim (issue #10959, the brief, the archived rulings, the runbook) | Reality on `origin/main` | Plan response |
|---|---|---|
| "the 117 in the worklist"; issue title "115 held-back real-read edges" | 117 `held-back` rows; the 2 `inngest-probe-row.sh` rows are the extras; 116 rows are still baselined; the feeder row is not | Worklist file `receipts/worklist-edges.tsv` (117); candidates 115; `kept-for-census` and `already-undrained` retired (row 5) |
| Issue next step 2: "write PR5 accept rows for the mentions it would reveal; the edge and its accept rows land together" vs archived row 6b "PR4 creates no accept file" and runbook "Never in a drain PR: create an accept file" | The accept file exists (18 rows, sibling PRs); the runbook line is now false for the file's existence | CTO row 1: allowed for PR4b/PR4c with four limits; runbook edit in Phase 4.1 |
| Brief: "60 revealed-pair cap per round" | Ruling 5 reads: 60 round-1 per chain, 30 later, 4 rounds, 150 cumulative; row 15f makes it per chain | CTO row 2 adds a 130 round-1 ceiling across chains for chain headroom; the trial total (501) is far above it, so the slice is a subset |
| Archived row 6b: "If F names more than 5 paths as mentions for that suite, hold it back without trying it" | Ruling 1c replaces it for PR4b with: more than 10 accept rows, or a hot file (more than 8 commits in 90 days) with any row, is held | Use the new bar; Phase 0 computes both numbers per edge |
| Issue next step 3: "Take the 43 whole-tree-read pairs to the CTO agent as a selection-policy call" | The pairs are in section 2 kind `deferred-sweep` | CTO row 6 rules the policy now; PR4b implements none (row 4 of the archived log stands: no `glob:`, no `ALWAYS_ON_SUITES` in a drain PR) |
| Archived table: `tests/scripts/inngest-host-dark-gate` -> `scripts/lib/inngest-probe-row.sh` held because the census reported UNCLASSIFIED | `scripts/lib/inngest-probe-row.test.sh:143-144` now allow-lists the index; the live blocker is the ALLOW entry for the baseline (STALE when no baseline pair names the lib) and baseline line 1529 is the only such pair | HOLD as `kept-for-census` (row 5); the test is not edited |
| Brief: "baseline is 1,640 lines" | Verified, `wc -l` 1640, ratchet exit 0 | Quoted in the PR body as `wc -l` output |

## Technical Rulings (CTO agent, 2026-10-25; full rows in `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4b-held-back-edges/decision-challenges.md`)

Every row below is `Ruled by CTO agent, 2026-10-25`. The earlier rulings (archived log rows 1-6b, 14, 15, 16) still bind where they are not amended here.

1. **Accept rows are allowed in PR4b and PR4c** (amends archived row 6b, scoped to these two PRs): mentions only; doubt means hold the whole edge; hold an edge that needs more than 10 accept rows, or any accept row on a file F with more than 8 commits in the last 90 days; the final audit shows zero stale or unused accept rows. PR5 inherits the file.
2. **Cap accounting**: counted on the first report of a round with the round's edges declared and no accept rows for them; accepted mentions count against the 150 cumulative; 60 per chain in round 1, later rounds under 30 and strictly shrinking, at most 4 rounds; round 1 summed over all chains at most 130; shared-array reveals multiplied by the number of spreaders.
3. **Slice**: ascending round-1 reveal, line at a cumulative 130 (through `scripts/compound-promote`); chains of at most 59, re-measured; a single edge that alone reveals 60 or more pairs is never declared in a drain PR (the 152-pair `git-data-birth-readiness-gate` edge goes to PR5); `grep-q-pipe-guard` (31 edges) stays out of PR4b; PR4c keeps the rest, tracked on #10959.
4. **Pre-classification bar**: real read vs mention by the line kind and the edge class (b/c/d default mention unless the suite extracts and re-reads the path; class a: read every ref line); accept reasons name the line kind from a closed list; unsure means hold; recorder on the 5 suites with the most accepted pairs, evidence only.
5. **`inngest-host-dark-gate` -> `scripts/lib/inngest-probe-row.sh`**: hold as `kept-for-census`, no test edit; the feeder row is `already-undrained`.
6. **The 43 whole-tree pairs**: policy only (`glob:` edge at 60 s or less and at most 25% selection over 200 merged PRs; `ALWAYS_ON_SUITES` at 30 s or less when selected more often; else stay baselined; never an accept row for a real whole-tree reader). A later PR brings the two measurements.
7. **Commit shape**: data in the spec directory; one commit per round on the final base; collapse to one commit on a conflicting rebase and record it; full battery and replay suite once at the end and again after a rebase that moved the index, `test-all.sh` or the suites.
8. **Plan shape** confirmed; the CTO's extra acceptance criteria are in Acceptance Criteria below.

## Implementation Phases

Process rules for the work phase: run every long command detached (script file, `setsid nohup bash <file>` or the Bash tool's `run_in_background`, an rc file, one `until` loop or Monitor); `grep -q P < <(producer)` never `producer | grep -q`; no `git stash`; stage by explicit pathspec; push before any long wait (a worktree directory has vanished mid-session before);
`CI_PR_AFFECTED` unset in every shell used (receipt: `env | grep -c '^CI_PR_AFFECTED='` prints 0).

### Phase 0 - claim, base, calibrate (no edit)

- 0.1 `gh pr list --label s4-drain --state open` returns only #11109 and the mirror comment on #10448 is present (a lost or duplicated claim: STOP and report). `git fetch origin main`; rebase on `origin/main`; run the sibling-overlap loop (Sibling PR Overlap below).
- 0.2 Re-measure only if `origin/main` moved past `45fe23b767` (`git rev-parse origin/main`); otherwise cite `receipts/ratchet-baseline-45fe23b767.out`. A re-measure runs on a detached worktree of `origin/main`: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --report <file>` and `audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` (the audit WITH main's accept file); record both summary lines and `wc -l` of the baseline and the accept file.
- 0.3 Rebuild the candidate table `receipts/edges-decisions.tsv` (columns `suite, F, outcome (declare|held-brittle|held-hot|held-unsure|kept-for-census|already-undrained), accept_rows, commits_90d`) from `receipts/worklist-edges.tsv`: mark `kept-for-census` (`tests/scripts/inngest-host-dark-gate` -> `scripts/lib/inngest-probe-row.sh`; pin it by content with `grep -Fxn` on the baseline, not by line number) and `already-undrained` (`scripts/inngest-probe-heartbeat-feeder` -> the same lib); confirm every other row is still a baseline line (`test "$(grep -Fxcf receipts/worklist-edges.tsv scripts/ci-pr-affected-audit.baseline.tsv)" = 116` at `45fe23b767`); compute per edge `commits_90d` for F (`git log --since=90.days --oneline -- F | wc -l`) and the label's array name with `_aff_label_map`; list the labels with no `AFFECTED_*_PATHS` array (11 in the trial), check each is a registered label (not glob-only) and that no other live label maps to the same array name (the map is not injective).
- 0.4 Cut the slice by ascending suite reveal from `receipts/trial-all-edges-reveal-by-suite.tsv`, never past a cumulative 130, and write it to `receipts/slice.tsv` so the cut is reproducible. Mark `per-edge >= 60` (never declared) and `grep-q-pipe-guard` (out). The trial cut is: chain 1 = the first 25 table rows through `tests/scripts/git-data-rung2-evidence-capture` (cum 59, 24 declarable edges after the feeder row), chain 2 = the next rows through `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (cum 118; it sits exactly at the 59 cap, so cut at 58 if the re-measure adds one), chain 3 = `scripts/compound-promote` (cum 130).
- 0.5 Record, for the PR body, the two results the parent re-checks: the push CI run for `45fe23b7671e` (run 40223185) conclusion and the first hosted `affected-index-ratchet` wall time (jobs API `completed_at` minus `started_at`, with the run URL). If they are not yet available write `not yet observed, <date>` and name the command; this is not a merge gate.

### Phase 1 - chain by chain: declare, first report, pre-classify (RED for the chain)

For chain k (at most 59 round-1 pairs; re-measure, do not trust the trial for the cut):
- 1.1 In a scratch copy of the tree add the chain's edges as exact entries to the right `AFFECTED_<LABEL>_PATHS` (existing array: keep its order and keep `scripts/lib/test-affected-paths.sh` in it; new array: a new block in the file's sorted position by array name, entries sorted, self entry `# THIS FILE`). Do NOT add accept rows. Run `ratchet --base origin/main --report <file>`; save its summary line and the counted `new-pair` total as `receipts/chain-<k>-round-<n>-first-report.txt` (the report itself is 100+ KB and stays in the scratchpad). If the total is 60 or more, bisect the chain and the other half moves to the next chain; if the running round-1 sum would pass 130, drop the highest-reveal suite from the slice.
- 1.2 Get the boundary lines from `python3 -I scripts/ci-pr-affected-replay.py audit --root <scratch git worktree> --all-refs --accept <main's accept file>`, NOT from the ratchet report: the report prints at most 3 `ref` lines per pair (`refs[:3]` in `ratchet_new_entry`) and a gap is accepted only when EVERY boundary line that names it has a row. The `ref` line format is `ref<TAB>suite<TAB>path<TAB>file:line<TAB>anchor/ordinal<TAB>text`; split `anchor/ordinal` on `/` into the two accept columns.
- 1.3 Pre-classify EVERY revealed pair in `receipts/reveals-decisions.tsv` (columns: `suite, edge_F, path, ref file:line, class (real-read|mention), line_kind`; chain and round are in the receipt filename, anchor and ordinal are regenerated from the audit in 2.1). Real read = declare the exact file next round; mention = accept row; unsure = the whole edge is held and leaves the chain. Apply the bar of CTO row 4 line by line (read the suite for class a; for class b/c/d ask whether the suite extracts and re-reads the named path).
- 1.4 Hold rules per edge, evaluated after classification and written to `receipts/edges-decisions.tsv`: more than 10 accept rows for the edge (counted from the all-refs boundary lines, not the report), or F has more than 8 commits in 90 days and the edge has any accept row, or any pair is unsure: remove the edge from the chain (its original pair stays baselined), re-run 1.1 for the reduced chain, and log `held-brittle`, `held-hot` or `held-unsure`. Never accept a real read; never declare a prefix or glob. Dry-run the two numeric holds on the table once before building rows.
- 1.5 Round n+1 (only if round n had real reads): add the real-read files as exact entries, re-run, save the receipt; the new-pair total must be under 30 and smaller than the previous round; at most 4 rounds; PR-wide cumulative (round 1 of every chain plus every later round, accepted mentions included) at most 150; round 1 summed over chains at most 130. A violation stops the chain and the leftover edges go to PR4c.
- 1.6 Shared helpers: if 3 or more labels spread the same helper read (for example `test-helpers.sh` -> `scripts/lib/scratch-root.sh`), use the existing `_CLOSURE_LEAF_SCRATCH_ROOT` or `_CLOSURE_LEAF_INCIDENTS_LIBS`; otherwise literal entries. Multiply a shared-array reveal by the number of spreaders for the cap.

### Phase 2 - one commit per round on the final base

- 2.1 Generate the accept rows from the all-refs output of the LAST round's audit (ordinals can shift when a declared file is read, `anchor-not-live`): suite, path, anchor, ordinal, `false-positive: <line kind>: <one clause naming the file:line>` from the table. Assert rows per pair equals that pair's `ref` line count. Insert them into `scripts/ci-pr-affected-audit.accept.tsv` in the file's existing order so a sibling's edit merges cleanly. The reason cell never contains a TAB.
- 2.2 GREEN: `git add` by pathspec every new or changed tracked file first (the audit scans every tracked file, and the plan, tasks, receipts and runbook name hundreds of paths), then `git checkout origin/main -- scripts/ci-pr-affected-audit.baseline.tsv` and `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv.new && mv scripts/ci-pr-affected-audit.baseline.tsv.new scripts/ci-pr-affected-audit.baseline.tsv`, then `ratchet --base origin/main` exits 0 with `live == baseline`; print the wall time of this run (it is the 3.8 datapoint). The `.new` file is untracked and is not read.
- 2.3 Per round: `ratchet` plus the two suites the learning names as edge-batch breakers, `scripts/test-affected-kb-consumers.test.sh` and `scripts/lib/inngest-probe-row.test.sh` (the kept-for-census baseline line must still exist and the suite must not report STALE). `test-all-affected.test.sh`, `lint-orphan-test-suites.sh` and shellcheck run once in 3.6/3.7. An edge that breaks another suite is held like a revealing edge.
- 2.4 Merge round n of all chains into one commit (at most 4 commits, CTO row 7); commit by explicit pathspec; the message records real vs accepted vs held counts and the running PR-wide totals. If a rebase conflicts, rebuild from the saved edge and accept lists on current main and commit once, and record the deviation in decision-challenges.md (archived row 16a).

### Phase 3 - fixpoint and verification (the full battery runs once)

Commit the last round first: the three-dot diffs read HEAD only. Use files, not `grep -c < <(...)` forms, so a failing `git diff` cannot hide behind a printed `0`.
- 3.1 Fixpoint: the post-final `audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` equals the last cycle (`refs`, `files_read`, `gap_refs`, `accepted`, `stale`), `gap_refs` equals `wc -l` of the baseline, `stale=0` (no stale or unused accept row), the last ratchet marker reads `exit=0 reason=pass`, the final reveal is 0.
- 3.2 Prune-only: `git diff origin/main...HEAD -- scripts/ci-pr-affected-audit.baseline.tsv > <scratch>/bdiff && grep -q '^-[^-]' <scratch>/bdiff && ! grep -q '^+[^+]' <scratch>/bdiff`; the removed lines equal the `declare` rows of `receipts/edges-decisions.tsv` (`LC_ALL=C comm -23 <(git show origin/main:scripts/ci-pr-affected-audit.baseline.tsv | sort) <(sort scripts/ci-pr-affected-audit.baseline.tsv)` against the declare set; an extra drained line from a shared-array spread or the non-injective label map needs an explanation); `scripts/lib/inngest-probe-row.test.sh` untouched and the kept-for-census pair present.
- 3.3 Scope checks (same file-based form): `git diff --name-only origin/main...HEAD` lists no test file, no workflow, no `scripts/test-all.sh`, no ADR; the added lines of `scripts/lib/test-affected-paths.sh` contain no `glob:`, no `ALWAYS_ON` and no entry ending in `/"`; the accept file's diff shows additions only.
- 3.4 Recorder (CTO row 4), on the committed HEAD (the script requires a trusted ancestor of HEAD or `origin/main`): `bash scripts/audit-suite-reads.sh record --mode check --only <label,label,...> --max-load <N> --load-wait <S>` for the 5 suites with the most accepted pairs, one timeboxed attempt, no retry loop. A pair it saw opened that the table calls a mention is a flip: declare it as a real read in an extra round (repeat that chain's 1.5 caps and 3.1 once); otherwise the recorder changes nothing. If it cannot run write `recorder: not run, <reason>` (not a merge gate, never wired into CI).
- 3.5 Replay suite detached: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (about 17 minutes); it hard-codes no count of the real baseline, so no suite edit is expected.
- 3.6 Full gate detached: kill own stale runs first (`kill_mine` in `plugins/soleur/scripts/lib/proc.sh`), `test-all.sh --capacity`, then `SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600 bash scripts/test-all.sh --affected`; rc 0, not rc 6 (a deferral); re-run after any rebase that changed the index, `test-all.sh` or a suite (CTO row 7); a failure is first reproduced on a detached `origin/main` worktree.
- 3.7 `scripts/test-all-affected.test.sh`, `scripts/lint-orphan-test-suites.sh`, shellcheck on the index and `scripts/markdown-lint.sh` on the changed docs, on the final tree.
- 3.8 Quote the final local `ratchet` wall time (2.2) against the 162 s measured this session and the 162 s hosted datapoint (job cap 5 minutes, provisional ceilings 210 s and 270 s); the all-edges trial measured 261 s, so a slice of about 36 should land between. No separate run.

### Phase 4 - documentation and handoff

- 4.1 Runbook section 7 (`knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`), three edits and nothing else: (a) the "Never in a drain PR" bullet (an accept row for a revealed mention is allowed in PR4b and PR4c under the four limits; the accept file already exists); (b) the "Reveal and hold-back" bullet gains only what is new (first report counted before accept rows; round 1 at most 130 across chains; a single edge of 60 or more pairs never in a drain PR); (c) the "Ambiguous pairs and big files" sentence "a declared file that names more than 5 other paths as mentions for that suite is held back" is replaced by the two numeric holds (more than 10 accept rows; a file with more than 8 commits in 90 days and any row). The "PR4b worklist" bullet is not extended with counts (#10959 owns them). Counts via `wc -l`, never a dated prose number. Write it BEFORE the verification so the verified HEAD is the merged HEAD.
- 4.2 Update the body of #10959 (remaining-edge list by suite with the reveal counts from the table, the row-3 cases, "PR4c" as the continuation vehicle) and comment on #10861 (PR5 inherits `git-data-birth-readiness-gate`, the 43 sweeps with the row-6 policy, `grep-q-pipe-guard`, and the accept-row brittleness measurement).
- 4.3 PR body (`Ref #10959`, `Ref #10448`, `Ref #9729`; no closing keyword): the counts via `wc -l`, per-chain first-report totals and the stop-line outcome, accept rows by line kind, held edges by reason, the recorder suites and results (or `recorder: not run`), the window consequence, the two parent-recorded results (CI run 40223185 conclusion and the first hosted ratchet wall time, 0.5) and the holds.

### Phase 5 - ship (no operator step)

- 5.1 Mark ready after the full gate and the replay suite are green; merge through the queue; a BEHIND PR is never synced by hand; one re-enqueue on a flaky e2e dequeue, a second reported with the run URL.
- 5.2 After merge: post the merge SHA on #10865 with the sentence "units before this SHA ran against the pre-drain oracle; the window count restarts here" (archived row 6; the probe does not enforce it, tracked in #10949); `gh pr list --label s4-drain --state open` is empty (claim released); #10959, #10448, #9729 stay open. The compound step (accept-row brittleness; the all-edges trial as a sizing method) runs at ship via `soleur:compound`.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` (runner trigger: exact entries in existing `AFFECTED_*_PATHS` arrays and up to 11 new blocks; shared `_CLOSURE_LEAF_*` spreads only per row 14d).
- `scripts/ci-pr-affected-audit.baseline.tsv` (shrinks only, via `ratchet --print-baseline`, in the same commit as each round).
- `scripts/ci-pr-affected-audit.accept.tsv` (additions only: anchor-keyed rows for revealed mentions, reason names the line kind; an oracle input, so the job prints the non-blocking `oracle-inputs-changed` notice).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (section 7 as in 4.1).
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4b-held-back-edges/decision-challenges.md` (exists; extended only if the work phase needs a new ruling).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4b-held-back-edges/tasks.md` (derived task list).
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4b-held-back-edges/receipts/reveals-decisions.tsv` (the pre-classification table), `receipts/edges-decisions.tsv` (one row per worklist edge with its outcome), `receipts/slice.tsv` (the cut) and `receipts/chain-<k>-round-<n>-first-report.txt` (each first report's summary line and counted total); archived at ship.
- Already created by this planning run: `receipts/worklist-edges.tsv`, `receipts/trial-all-edges-reveal-by-suite.tsv`, `receipts/trial-all-edges-new-pairs.tsv`, `receipts/ratchet-baseline-45fe23b767.out`.
- NOT edited: any test file (including `scripts/lib/inngest-probe-row.test.sh`), `scripts/test-all.sh`, `scripts/ci-pr-affected-replay.py`, any workflow, probe, ADR, `required-checks.txt`, ruleset or variable.
Files verified: every path above exists on `origin/main` (`git ls-files`) except the ones listed under Create.

## Consumer of the declared lists

A declared entry is inert unless something reads it for the diff shape in question. The per-label array is resolved by name in `scripts/test-all.sh` through `_m="AFFECTED_$(_aff_label_map "$_l")_PATHS"`, each entry is minted into an anchored edge by `_affected_add_edge` and unioned with the derived edges, and the selector's `AFFECTED_SELECTED` rows (`--print-selection --paths=<path>`) are what the audit and the ratchet read.
An accept row is read only by `load_accept` / `judge_rules` in `scripts/ci-pr-affected-replay.py` (`--accept FILE`; the ratchet passes the tracked accept file), which exempts a pair when EVERY boundary line that names it has a row and marks a row stale when the pair is no longer a gap, the anchor is not live, or the path is untracked. No suite reads the accept file (the research agent found only scratch fixtures and the observation probe's ORACLE list).

## Sibling PR Overlap

Open PRs touching the same files (`gh pr list --state open --json number,title,files`): #10968 (merge-effect classifier), #10926 (npm-publish SIGPIPE), #10893 (git-commit-secret-scan), #7390 (WIP provenance build-arg) each edit `scripts/lib/test-affected-paths.sh` and/or the baseline or accept file, so they move the live set. Mitigation: one drain PR at a time (the `s4-drain` claim); resolve index conflicts additively;
take main's baseline and regenerate with the prune-only tool, never by hand; insert accept rows in sort order; list duplicate `AFFECTED_*_PATHS` names after every merge of main; re-run the overlap loop and `git merge-tree` right before the push.

## Open Code-Review Overlap

#8800 (test fixture: census sandbox shares inodes/symlinks with live repo) names `scripts/lib/test-affected-paths.sh`: Acknowledge, a different concern (a census-sandbox write-through hazard, no change to it here). No open code-review issue names the baseline, the accept file, the runbook or `scripts/ci-pr-affected-replay.py`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Work unit: PR4b (#10959), the held-back edges of the code-edge drain (the 117 in the worklist)" | Phases 0-3; slice per CTO row 3 | mapped (partial by ruling: the slice is a subset, the rest is PR4c/PR5 on #10959) |
| 2 | "declare exact-file edges only where a suite really reads or executes the file" | Phase 1.2-1.3, CTO row 4 | mapped |
| 3 | "shrink the baseline only via `ratchet --print-baseline`, run to a fixpoint" | Phase 2.2, 3.1, 3.2 | mapped |
| 4 | "honour CTO ruling 5's stop line (60 revealed-pair cap per round, with the reveals pre-classified)" | Phase 1.1-1.4, CTO row 2 | mapped |
| 5 | "take every technical fork to the soleur:engineering:cto agent (record `Ruled by CTO agent`), never to the operator" | decision-challenges.md rows 1-8 | mapped |
| 6 | "Use `Ref #10959`, never `Closes`" | Phase 4.3 | mapped |
| 7 | "Holds stay in force: no CI_PR_AFFECTED, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR" | Overview, row 12, Non-Goals | mapped (held) |
| 8 | "On merge, comment the merge SHA on #10865 (the window restarts)" | Phase 5.2 | mapped |
| 9 | "include a plan task to record both results in the PR body" (CI run 40223185, first hosted ratchet wall time) | Phase 0.5, 4.3 | mapped |
| 10 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in .../decision-challenges.md" | decision-challenges.md | mapped |
| 11 | issue #10959 next step 3: "Take the 43 whole-tree-read pairs to the CTO agent as a selection-policy call" | CTO row 6 (policy only) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| the slice and chains | "honour CTO ruling 5's stop line (60 revealed-pair cap per round" | asked (the 130 ceiling is CTO row 2, a refinement of the same ruling) |
| accept rows with the edge | issue #10959: "write PR5 accept rows for the mentions it would reveal, then declare the edge. The edge and its accept rows land together" | asked |
| `receipts/reveals-decisions.tsv` | "with the reveals pre-classified" | asked |
| the hot-file and 10-row holds | — | inferred — justification: CTO row 1c; an anchor-keyed row on a hot file turns every editor's PR red |
| recorder on 5 suites | — | inferred — justification: CTO row 4; the only empirical read evidence the repo has, evidence only |
| runbook section 7 edits (three) | "rubric in runbook ci-pr-affected-activation.md section 7" (the rubric's home, and three statements in it are now false) | asked |
| policy ruling for the 43 sweeps | issue #10959 step 3 | asked |

### Split Assessment

- Subsystems touched: 2 (CI machinery under `scripts/`, knowledge-base docs).
- Planned files: 5 edited + 3 to 6 created; estimated changed lines: about 36 index lines plus up to 11 new blocks (about 40 lines), up to 36 baseline lines removed, an estimated 190 accept rows.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines. None met.
- Recommendation: single PR; the series already split code pairs (PR4) from mentions and non-code pairs (PR5), and the CTO's slice is the split of PR4b from PR4c.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today, because the lever (`CI_PR_AFFECTED`) is unset and locked and the ratchet job is advisory; after a later, separately authorized flip, a pull request that changes a file a test suite reads could merge without that suite having run when a revealed pair was wrongly accepted as a mention (a false negative: an accept row on a file the suite really reads), or every PR could pay for suites it does not need (an over-declared edge).
The accept rows are the new risk of this PR: the ratchet does not verify them and no required review exists, so the classification table with the cited line per row, the recorder on the five suites with the most rows, and the hold-on-doubt rule are the controls.
**If this leaks, the user's [data / workflow / money] is exposed via:** no data path: the work reads tracked repository text and runs local suites under a scrubbed environment with no network namespace; the exposure is CI minutes (money) if edges are over-declared once the lever flips.
**Brand-survival threshold:** aggregate pattern

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** eight technical forks ruled on 2026-10-25 (accept rows in PR4b, cap accounting, slicing and the per-edge ceiling, pre-classification bar, the inngest-probe-row hold, the 43-sweep policy, commit shape, plan shape); see Technical Rulings. No product, marketing, legal, finance, operations, sales or support implication: internal CI index maintenance, no user-facing surface, no data processing change, no new vendor or spend. Product/UX gate: none (no `components/`, `app/**/page.tsx` or layout file; no UI path in Files to Edit/Create).

## Architecture Decision (ADR/C4)

No new architectural decision: the drain is ADR-276's own tool (amendment item 2); the accept-row allowance is a scoped operating rule (CTO row 1) recorded in the decision log and the runbook, not an architecture change, and ADR-276 is not edited (PR5 appends the closing Stage-status line and the dated reconcile citing rows 5, 6b and this amendment).
C4: no impact. Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: no external human actor, external system, data store or actor-to-surface access relationship changes (the index, the baseline, the accept file and the audit script are repository-internal CI machinery already inside the CI container); derived cardinalities in edge prose do not move because no workflow, job, monitor or heartbeat is added or removed (`plugins/soleur/test/c4-count-parity.test.sh` is part of the full battery in 3.6 and must stay green).

## Observability

The change is CI index data under `scripts/`, outside the plan Phase 2.9 path set, but deepen-plan Phase 4.7 applies to any non-docs Files-to-Edit entry, so the surface that already observes this change is declared here. It adds no new emitter: the signal is the existing advisory job's marker line.

```yaml
liveness_signal:
  what: the marker line SOLEUR_PR_AFFECTED_RATCHET exit/reason/live/baseline printed last by the affected-index-ratchet job (exit 0 reason pass means live equals baseline)
  cadence: every pull_request and merge_group run, drafts and bots included
  alert_target: the job's own ::error annotation and a red check on the PR check list (advisory until PR3b; no pager)
  configured_in: .github/workflows/ci.yml job affected-index-ratchet (unchanged by this PR)

error_reporting:
  destination: GitHub Actions job log, step summary and the ::error title=affected-index-ratchet annotation
  fail_loud: exit 1 (a verdict about the tree) or exit 2 (infrastructure) renders the job red with the reason token; no silent path

failure_modes:
  - mode: an accept row goes stale or an accepted pair re-appears after an edit of the mention line in the revealed file, or after a sibling merge or a rebase (baseline or accept file no longer equals the live set)
    detection: the marker reads exit=1 reason stale-accept or new-pair on the next pull_request or merge_group run; merge_group fails closed with max_entries_to_merge 1
    alert_route: red check on the PR and the queue entry; fix-forward owner is the author who changed the line, due within one working day (ADR-276 item 8)
  - mode: a revealed pair accepted as a mention that the suite really reads (false negative once the lever flips)
    detection: not visible to the ratchet (declared limit, the remedy text says so); bounded before merge by the line-cited classification table, the hold-on-doubt rule, the 10-row and hot-file holds and the recorder on the five suites with the most accepted pairs
    alert_route: PR review of receipts/reveals-decisions.tsv; PR5 demotion of any accept row with evidence
  - mode: job wall time grows because more declared edges raise files_read
    detection: marker exit=2 reason timeout or a wall above the 210 s p95 and 270 s maximum ceilings of the observation window probe
    alert_route: Phase 3.8 timing check in the PR body and the ceiling re-rule owed to the CTO agent at the close of the window

logs:
  where: GitHub Actions run logs of the affected-index-ratchet job, plus the --report file in the step summary
  retention: the repository's Actions log retention (default 90 days); the classification table and the receipts persist in the spec directory

discoverability_test:
  command: grep -o -e 'SOLEUR_PR_AFFECTED_RATCHET exit' scripts/ci-pr-affected-replay.py
  expected_output: SOLEUR_PR_AFFECTED_RATCHET exit
```

## Test Scenarios

The Acceptance Criteria below are the single list of checks; the scenarios name only the three controls that are not restated there.

1. RED then GREEN per round (2.2): with a chain's edges declared and no accept rows and no prune, the uncapped `--report` lists `new-pair` for the revealed pairs and `stale-line` for exactly the declared edges' pairs; after the accept rows and the prune, `ratchet` exits 0. The RED report is the control that each edge is what drains its pair.
2. Hold rules (1.4): dry-run once on the table that an edge with 11 rows, and an edge on a file with 9 commits in 90 days with one row, are removed from the chain.
3. Regression: the replay suite, `test-affected-kb-consumers.test.sh`, `inngest-probe-row.test.sh` and the full affected gate (3.5-3.7). The audit's own `not-a-gap` / `anchor-not-live` / `stale` verdicts and the replay suite already prove that an unreachable accept row is refused, so no scratch experiment re-tests it.

## Acceptance Criteria

### Pre-merge

- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` exits 0 with `live == baseline`; the baseline's line count is smaller than on the merge base by exactly the number of `declare` rows in `receipts/edges-decisions.tsv` (quote the three numbers: `git show origin/main:scripts/ci-pr-affected-audit.baseline.tsv | wc -l`, the branch count, the table count).
- [ ] The baseline diff is prune-only by the file-based check of 3.2 (at least one removed line, no added line; the shell forms `grep -c ... < <(git diff ...)` are not used: they print `0` over a failing diff); the file is C-locale sorted with a final newline.
- [ ] The first report of each round, before accept rows, is saved as a receipt; each chain's round 1 is under 60, later rounds under 30 and strictly shrinking, at most 4 rounds, round 1 summed over chains at most 130, the PR-wide cumulative (accepted mentions included) at most 150; the stop-line outcome is stated in the PR body.
- [ ] The final audit (`audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv`) equals the last cycle: zero new pairs, zero stale baseline lines other than the drained pairs, zero stale or unused accept rows; audit line and last ratchet marker pasted.
- [ ] `receipts/reveals-decisions.tsv` lists each revealed pair as `real-read` or `mention` with the `file:line` cited; accept rows equal the `mention` rows, with one row per boundary line (rows per pair equal that pair's `ref` lines); no accepted pair is a real read; held edges are in `receipts/edges-decisions.tsv` with the deciding count; the recorder suites and results are listed (or `recorder: not run, <reason>`).
- [ ] Every new accept row has a reason naming the line kind (`message`, `JSDoc/comment`, `PR-body string`, `help/menu text`, `data row not fed to a read loop`); no edge has more than 10 accept rows; no edge touches a hot file (more than 8 commits in 90 days) with any row; the accept-file diff is additions only.
- [ ] The PR touches no test file, adds no `glob:`, no directory prefix, no `ALWAYS_ON_SUITES` entry and no whole-tree reader edge; `scripts/lib/inngest-probe-row.test.sh` is untouched and the `tests/scripts/inngest-host-dark-gate` -> `scripts/lib/inngest-probe-row.sh` baseline line is still present (asserted by content, `grep -Fx`).
- [ ] `git diff --name-only origin/main...HEAD` (three dots) lists only the index, the baseline, the accept file, the runbook, this plan and files under `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4b-held-back-edges/`; no variable, lock, ruleset, `required-checks.txt`, workflow, probe or ADR file.
- [ ] Replay suite rc 0; `SOLEUR_ALLOW_FULL_GATE=1 ... bash scripts/test-all.sh --affected` rc 0 (not rc 6) on the final base, re-run after a rebase that moved the index, `test-all.sh` or a suite; orphan census, `test-all-affected.test.sh`, shellcheck and `scripts/markdown-lint.sh` rc 0.
- [ ] Runbook section 7 edited as in 4.1 (three edits); #10959 body updated with the remaining-edge list and the row-3 cases; #10861 commented; the PR body uses `Ref #10959`, `Ref #10448`, `Ref #9729` only (not `Closes`), lists the edges deferred to PR4c and PR5 and why (the sweep, the per-edge ceiling, the cap, the hot-file hold), restates the holds and the window consequence, carries the CI run 40223185 conclusion and the first hosted ratchet wall time (or `not yet observed`), and reports the final local ratchet wall against 162 s.

### Post-merge

- [ ] The merge SHA is commented on #10865 with the row-6 sentence (the window restarts by hand; unverified by probe, #10949).
- [ ] `gh pr list --label s4-drain --state open` is empty; #10959, #10448 and #9729 stay open.

## Rollback

The change is data (index entries, a pruned baseline, accept rows, docs). A plain revert is NOT a clean rollback: it re-adds the drained baseline lines, which the growth rule reads as `grown` on the revert PR itself (advisory red until PR3b, blocking after it), and it removes the accept rows together with the edges, which is consistent. The supported correction is forward: keep the edge (an extra edge only costs suite runs once the lever flips), or remove an edge together with its accept rows and re-baseline nothing. A wrongly accepted pair is corrected by declaring the edge (the accept row then reads `not-a-gap` stale and is deleted in the same PR). The lever is off, so no production behavior depends on the edges or the rows; this section is the recipe the archived PR4 simulated, and PR4b does not repeat the simulation.

## Non-Goals

CI_PR_AFFECTED, the activation lock, PR D (#10414), PR3b (#10859), the evidence re-run, criterion (c), the flip PR, #10862, any `ratchet` or audit-reach change, any probe change (#10949), any `scripts/test-all.sh` edit, any test-file edit, any `glob:` or `ALWAYS_ON_SUITES` entry, the 43 whole-tree sweeps (policy recorded, executed later), the 152-pair `git-data-birth-readiness-gate` edge and the `grep-q-pipe-guard` edges (PR4c/PR5), the remaining non-code pairs and mentions of PR5 (#10861), baseline deletion.
Deferred items are tracked: #10959 (PR4c, the remaining held-back edges, stays open), #10861 (PR5: mentions, non-code pairs, the per-edge-ceiling case, the 43 sweeps, baseline deletion), #10949 (probe-enforced window restart), #10862, #10859, #10414.

## Risks and Sharp Edges

- The `## User-Brand Impact` section is filled with a concrete artifact, vector and threshold; an empty or unfilled one fails `deepen-plan` Phase 4.6.
- A wrong accept is a false negative once the lever flips and no automated control checks it: the controls are the cited-line table, hold-on-doubt, the recorder on the five largest suites, the 10-row and hot-file holds, and PR5's review of every accept row.
- Accept rows are brittle by design: an edit of a mention line turns the row stale AND the pair new on the editing PR (red until re-accepted). That is why hot files and edges with more than 10 rows are held, and why the baseline pairs of held edges stay as the robust form.
- The trial total (501) is an all-at-once estimate: reveals deduplicate across suites that share a file and chain through real reads, so each chain is re-measured; do not cite the trial as a declared number.
- Reveal: a declared code file makes the audit read it; revealed pairs cannot be baselined. A real-read chain reads more files; the 20-pair headroom of the 130 ceiling exists for it.
- Duplicate `AFFECTED_*_PATHS` names after a merge of main silently re-open drained pairs (bash keeps the last assignment): list duplicates after every merge; new arrays go in sorted position, and the label-map is not injective (check collisions).
- The audit scans every TRACKED file (`git ls-files`): stage the plan, tasks, receipts and runbook before the final `--print-baseline`, `ratchet` and audit runs, or a later `git add` changes the live set; the baseline is already tracked, so `git checkout origin/main -- <baseline>` keeps it so. Run the audit with main's accept file.
- Full gate duration (hours, ceiling 39,600 s) and rc 6 deferral; kill own stale runs first; a green replay suite alone is not the battery. A recorder run on a loaded host is refused (`load_refused`), not wrong.
- The probe does not enforce the window restart (#10949); do not claim it does.
- A reach-widening change is out; if a read-set question arises it is a different PR.
- Guard-contract and encryption-posture gates are not triggered: no check, lint, hook or workflow is added (the classification table is data, the breadth and fixpoint checks are inline verification commands), and no store or connection is introduced.
