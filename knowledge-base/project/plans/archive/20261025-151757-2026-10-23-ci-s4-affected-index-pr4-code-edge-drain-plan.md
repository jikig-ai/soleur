---
title: "ci: S4 PR4, drain the code-edge gap pairs of the affected index (baseline shrinks in the same commit)"
date: 2026-10-23
slug: s4-affected-index-pr4-code-edge-drain
branch: feat-one-shot-s4-affected-index-pr4-code-edge-drain
issue: 10860
type: chore
lane: cross-domain
refs: [10860, 10448, 9729]
brand_survival_threshold: aggregate pattern
---

# ci: S4 PR4, drain the code-edge gap pairs of the affected index

Ref #10860. Ref #10448 (series tracker, stays open). Ref #9729 (epic). PR text uses `Ref` only, never a closing keyword.
Spec lacks a valid `lane:` (there is no spec.md for this branch), so it defaults to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-23
**Research agents used:** verify-the-negative pass (8 claims against the code), architecture-strategist, spec-flow-analyzer, git-history-analyzer (attribution), plus the earlier plan-review panel (DHH, Kieran, code-simplicity), the learnings researcher, the CTO agent (7 rulings) and the functional-overlap check (no overlap found).

### Key Improvements
1. Corrected a fact the plan had wrong: a declared array must contain `scripts/lib/test-affected-paths.sh` (not the suite file), and array order/placement is checked only by the registration-only pre-pass this PR does not use.
2. Found a suite that reads the baseline's CONTENT (`scripts/lib/inngest-probe-row.test.sh`): draining both pairs that name its lib turns an allow-list entry `STALE`, so PR4 must keep one baselined (it edits no test file); the same hold-back rule now covers any edge that breaks another suite.
3. Made the reveal accounting executable: per-chain rounds, first-report counts, bisect-when-over-cap, shared-array multiplicity measured before the table is built, and a label-injectivity check for the ~126 new array names.
4. Closed process gaps: rebase mid-work procedure without `git stash`, the full gate re-run only when the rebase touched the index/runner/suites, gate-failure triage on a detached `origin/main`, runbook written before verification, a `CI_PR_AFFECTED` environment receipt, and a compliant `## Observability` block.

### New Considerations Discovered
- A shared-array spread multiplies any mention inside the helper by the number of spreaders (44 for `scratch-root.sh`), which can trip the round-1 cap by itself.
- Merging inside the observation window is the same schedule effect as a delay; the plan states it in the first PR-body line and leaves the schedule call to the owner (row 7).
- The `_CLOSURE_LEAF_RT_*` precedent comes from the A5 work (#9422); ADR-242 decision 18 documents it.

## Overview

PR4 of the S4 affected-index series removes the code-extension pairs from the shrink-only baseline
`scripts/ci-pr-affected-audit.baseline.tsv`. For each live `(suite, undeclared tracked path)` pair whose path has a code
extension (`CODE_EXT` in `scripts/ci-pr-affected-replay.py`), the work reads the line context and declares the path in
`AFFECTED_<LABEL>_PATHS` in `scripts/lib/test-affected-paths.sh` ONLY when the suite really reads or executes the file
(the rubric of decision row 1). Pairs the suite merely mentions stay in the baseline and move to PR5 (#10861). The baseline
shrinks in the same commit through `ratchet --print-baseline` (prune-only, never by hand), the audit is re-run to a fixpoint
inside the PR (drain-reveal rule), and the PR runs the full battery once because it edits a runner trigger.

Standing holds, all still in force and none executed or scheduled here: do NOT set `CI_PR_AFFECTED`, do NOT remove the
activation lock, do NOT run PR D (#10414); also held are the required-context PR3b (#10859), the evidence re-run, the
criterion-c measurement, the flip PR, and delaying PR4 (the owner has not asked to delay). No live credentialed probe is planned.
The `s4-drain` claim is held by this PR (#10945, draft, label `s4-drain`, mirror comment on #10448).

## Research Insights

### Premise validation (Phase 0.6)

Checked: #10860, #10448, #9729, #10861, #10862, #10859, #10865, #10414 are all OPEN; draft PR #10945 is open with label
`s4-drain` and is the only PR carrying it (`gh pr list --label s4-drain --state open`). `origin/main` is `6b8f7fcaf5` and the
branch is one init commit ahead. `scripts/ci-pr-affected-audit.accept.tsv` does not exist yet. The archived PR3 plan, its 41
CTO rulings, the runbook and the 2026-10-23 canary learning were read. What held: PR3a is merged (the job, the `ratchet`
subcommand, the baseline of 1,888 lines, the probe and the runbook section 7 exist on `origin/main`). What was stale or
different: the issue text says "about 945 of 1,884"; the measured set on `6b8f7fcaf5` is 947 code pairs of 1,888 (ADR-276 item 3
already says the baseline file, not a prose count, is the authority); the 2026-10-22 plan allowed `ALWAYS_ON_SUITES` under 60 s,
which the CTO narrowed to OUT for PR4 (decision row 4); the runbook says a drain PR inside the window "restarts the window
count" but the probe has no such rule (decision row 6, tracked as #10949). No ADR in `knowledge-base/engineering/architecture/decisions/`
rejects the mechanism (declaring edges in the index file is the ADR-276 amendment's own drain tool, item 2).

### Measurements (this planning session, read-only, local)

- `python3 -I scripts/ci-pr-affected-replay.py audit --root <detached worktree of origin/main> --all-refs`, 287 s wall, rc 1:
  `SOLEUR_PR_AFFECTED_AUDIT suites=663 always_on=118 audited=545 unaudited=0 gap_suites=297 gap_refs=1888 accepted=0 stale=0 refs=3445 files_read=971`
  (matches the 1,888-line baseline). The output holds 297 `gap` rows and 3,508 `ref` rows (`ref suite path file:line anchor/ordinal text`).
- Classified by the audit's own `CODE_EXT`: 947 code pairs (781 `.sh`, 129 `.ts`, 18 `.py`, 11 `.tsx`, 4 `.mjs`, 3 `.js`, 1 `.cjs`) over 206 suites and 428
  distinct paths; 941 non-code pairs. Concentration: 17 suites with more than 10 code pairs hold 585 (62 percent); the 12 heaviest hold 497 (52 percent; the
  top 8 hold 379); 170 suites with at most 3 code pairs hold 251; 19 suites with 4 to 10 hold 111.
- Provenance: 668 pairs appear only through a library or closure file, 257 only in the suite's own file, 22 in both. Biggest sources: `scripts/lib/test-relevance-paths.sh`
  271 pairs (nine runner-SUT suites, about 30 data-array entries each), `scripts/lint-betterstack-emitter-read.sh` 52, `plugins/soleur/test/test-helpers.sh:58` 43
  (`scripts/lib/scratch-root.sh` sourced by a computed path in a swallowed-failure subshell, 44 suites), `apps/web-platform/infra/run-registered-suites.sh` 33,
  `.claude/hooks/lib/incidents.sh` 30, `plugins/soleur/scripts/lib/tmp-classify.sh` 19.
- Yield estimate: a random 14-pair sample read in context gave about 4 real reads and about 10 mentions. Expect about 25 to 35 percent real (about 250 to 330
  declared pairs); roughly 600 to 700 code-extension mentions stay in the baseline for PR5, which then holds about 1,500 pairs (decision row 9).
- Index file: 185 `AFFECTED_*_PATHS` arrays exist; 80 of the 206 suites already have one and 126 would need a new block. Arrays are NOT sorted (75 adjacent inversions), so
  "alphabetical by label" in the archived plan is a loose convention, not a gate; placement is whatever the orphan census accepts (Phase 0 trial). The orphan census
  (`scripts/lint-orphan-test-suites.sh`) fails a declared literal entry that is not a tracked file (dead edge) and a directory prefix that does not exist. Every declared set
  by convention also lists `scripts/lib/test-affected-paths.sh`.
- Any edit to `scripts/lib/test-affected-paths.sh` other than a registration-only diff degrades the affected gate to the full battery (`runner-changed`); the file's header also
  records that an added comment line is an `INDEX-ANCHOR` finding only inside the registration-only exception, which this PR is not.
- Recorder probe (`scripts/audit-suite-reads.sh record --only scripts/ci-pr-selection`): `--cover-from-selection` failed (`test-all.sh --print-selection` in the private cold
  checkout exceeded the 300 s selection cap, rc 124); without it, the run was refused on host load (`reason=load_refused`, load 12 to 20 against `--max-load 4.0`). netns works
  (`unshare -cn true`). The work phase raises `--max-load` and `--load-wait` and uses `cover=argv` (decision row 11).
- Summed `scripts/suite-durations.tsv` time for the 206 suites is about 43 minutes, a lower bound (many rows are the 1.2 s floor).

### Institutional learnings applied

- `2026-10-10-a-declared-edge-must-say-what-the-walker-reads-and-a-malformed-one-must-fail-wide.md`: a declared edge must match a real repo-relative diff line; avoid `*/` tails.
- `2026-10-06-one-self-inclusion-claim-hid-three-edge-provenances-across-four-suites.md`: classify each edge by provenance (deliberate arming, real read, stale header-comment mention) before deciding.
- `2026-10-19-a-per-area-drawdown-cannot-satisfy-a-live-census-gate-and-reindenting-breaks-text-anchored-mutants.md`: the baseline must equal the live census, so commit the drawdown whole per commit; do not re-indent code mutants anchor on.
- `2026-10-18-ratchet-guards-must-pin-the-scan-population-and-their-own-registrations.md`: a new always-on label needs a `suite-durations.tsv` floor row (moot: ALWAYS_ON is OUT here).
- `2026-10-19-the-audit-a-ratchet-trusts-reached-less-than-its-name-and-both-p1s-were-in-the-fixes.md`: the audit reach is frozen; do not widen it in this PR.
- `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md` and `2026-10-15-i-claimed-every-covering-suite-had-run-and-the-bounded-gate-found-three-regressions-of-mine.md`: preview with `--print-selection`; coverage is computed, not asserted.
- `2026-10-20-a-queued-gate-is-not-a-verdict-and-a-name-matcher-cannot-find-a-wrapper-run-process.md`: `AFFECTED_GATE_BUDGET_DEFERRED` rc=6 is a deferral, not a pass; kill own stale runs first.
- `2026-10-06-a-source-text-pin-over-a-file-is-a-pipe-into-grep-q-...md`: never `producer | grep -q` under pipefail; use `grep -q P < <(producer)`.
- `2026-10-23-an-advisory-job-claimed-to-keep-the-run-green-...md`: state only what was measured at the level it was measured; reproduce a trigger locally before pushing; floors in the shared replay suite conflict with every sibling that adds rows, so confirm by a measured run; regenerate the baseline after every rebase (1887, 1886, 1888 across three rebases there).

### Property List and Cut List (Phase 0.6b)

Properties the ask buys: (P1) every code-extension pair the suite really reads or executes is declared, so the selector would select the suite when that file changes; (P2) no
mention is declared (the index is not diluted and PR5's accept rows stay honest); (P3) the baseline shrinks by exactly the drained pairs and never grows, in the same commit as the
edge edit; (P4) the audit is at a fixpoint when the PR lands (no revealed pair left); (P5) the PR is mergeable through the queue with the full battery run once.
Mechanisms in the ask and what already covers them: the shrink-only baseline and `ratchet --print-baseline` already buy P3 and the growth rule; the audit's `--all-refs` output already buys the line
context for P1/P2; the existing precedent of shared underscore arrays buys the helper-read case. Cut List (mechanisms NOT built): a new triage or classifier tool committed to the repo (the evidence is a
reviewed TSV, the heuristics stay in the scratchpad); a probe change for window restart (decision row 6; #10949); any `ratchet` logic or replay-suite rows (row 12); a derive widening in
`scripts/test-all.sh` for helper reads (row 3); `ALWAYS_ON_SUITES` entries (row 4); a PR4-side accept file (Ruling 7); an ADR-276 amendment for PR4 (the rubric lives once, in the runbook; PR5 appends the closing Stage-status line); a negative-control re-run per batch and a random exact-edge selection canary (the RED proof of Phase 2.1 already proves each edge drains its pair).

### Value-proposition measurement (Phase 0.6c)

The PR claims no cost or performance saving. The one cost it can add is extra suite runs from over-declared edges once the lever flips; that is bounded by the ambiguous-declare rule of row 1 (about 1 suite run per 20 PRs
per ambiguous declaration) and measured, not asserted, by the selection canary of Phase 3.3 (before/after selection size for every prefix or glob edge; exact edges are covered by the RED proof of 2.1).

## Research Reconciliation: Spec vs. Codebase

| Claim (issue #10860 / archived plan / runbook) | Reality on `origin/main` `6b8f7fcaf5` | Plan response |
|---|---|---|
| "about 945 of 1,884" code pairs | 947 of 1,888 (measured, 287 s audit) | Phase 0 re-measures on the final base; counts come from the baseline file, never prose. |
| Archived PR4 text: declare "~945" edges | A 14-pair sample suggests only 25 to 35 percent are real reads; 271 pairs are data rows in one library | Expect about 250 to 330 declared pairs; the rest are mentions for PR5 (row 9); PR4's acceptance is "strictly smaller", not "code pairs gone". |
| Archived plan: `ALWAYS_ON_SUITES` allowed under 60 s | CTO round 2026-10-23 rules it OUT for PR4 | Row 4: such a suite is not drained here, one PR-body row, follow-up. |
| Archived plan: arrays "alphabetical by label" | 75 adjacent inversions already in the file; the census, not an order rule, is the gate | Phase 0 places one trial block and runs the census; follow whatever it accepts. |
| Runbook: a drain PR inside the window "restarts the window count" | The probe restarts only on a defect | Row 6: human-recorded restart on #10865; wording corrected in the runbook; residual tracked in #10949. |
| Runbook "wc -l of the baseline" and prose counts of 1,884 / 1,888 | The ratchet requires live == baseline, so any prose count goes stale | Update prose to point at `wc -l`, quote counts only as dated measurements. |

## Technical Rulings (CTO agent, 2026-10-23; full rows in `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4-code-edge-drain/decision-challenges.md`)

1. Rubric: declare on execute/source (computed and best-effort included), content open (including copy-then-assert), existence or mode assertion where the verdict depends on it, or a data row whose consumer loop is quoted; a library that opens the path counts for every suite that sources it at runtime; mentions are messages, docstrings, comments, test vectors, fixture rows, scratch-written files, allow-list/classification/relevance rows and negative strings. Ambiguous: declare one exact file only if the read cannot settle it in 20 minutes and it adds at most about 1 suite run per 20 PRs; else leave for PR5; list every ambiguous declare in the PR body.
2. Recorder: REQUIRED one-directional cross-check on 27 suites (top 12 by code pairs plus 15 random), `--mode check`; an opened-but-called-mention pair flips to declared; `disqualified`/`unreliable` is `recorder-blind`; never demotes a declared pair; not-run is stated, not a blocker.
3. Helper reads: underscore-prefixed shared arrays (`_CLOSURE_LEAF_SCRATCH_ROOT`, `_CLOSURE_LEAF_INCIDENTS_LIBS`, more by source), spread only into labels that really source the helper, each commented with the sourcing `file:line`; no derive widening.
4. Breadth: exact file default; directory prefix only for a real walker (line quoted), at least 3 segments, at most 25 tracked files; `glob:` only for extension-aware walks; ALWAYS_ON out; prefix edges need a before/after `--print-selection` canary.
5. Stop line: round 1 reveal under 60, later rounds under 30, at most 4 rounds, cumulative at most 150, each round smaller than the last; else hold the revealing edge back and file PR4b under the same claim chain; one PR, one commit per batch, each commit `ratchet` exit 0.
6. Window restart: human-recorded on #10865 with the merge SHA; probe untouched; residual `unverified by probe` (#10949).
7. (decision-log row 6b) Revealed mentions: HOLD BACK the revealing edge; PR4 creates no accept file (it is a PR5 artefact and an oracle input). A revealed pair is classed by the rubric applied to the revealing file F's line: a real read is declared next round; a mention means the edge to F is not declared (never committed), so the audit never reads F for that suite and the original pair (suite, F) stays baselined for PR5/PR4b. If F is read for real AND also names G only as a mention, the two cannot be separated: split that F edge out to PR4b/PR5. Every pair a round reveals counts against the caps (60 / 30 / 4 rounds / 150); the commit message records how many were real and how many held-back mentions. If F names more than 5 paths as mentions for that suite, hold it back without trying it. No recorder or extra read bar for a held-back mention. The "ambiguous means declare" default applies only when the declaration reveals nothing. Each held-back edge goes in the decision TSV (`suite, F, reason, file:line`) and its count in the PR body, as PR5's first batch.

## Implementation Phases

Run every long command detached: write a small script file under the scratchpad and `setsid nohup bash <file>`, write the exit status to an `.rc` file, and wait with a Monitor
until-loop on that file (a `bash -c` string holding a variable is blocked by the hook; polling in a background run is forbidden by `hr-monitor-not-run-in-background-for-polling`).
Use `grep -q P < <(producer)`, never `producer | grep -q P`. No `git stash`. Use `git -C <abs path>` forms. Read every `.rc` (an rc of 127 means "did not run").

### Phase 0 - claim, base, and calibrate the tools before any edit

0.1 Claim check: `gh pr list --label s4-drain --state open` returns only #10945; the mirror comment on #10448 exists. If the claim is lost, duplicated or #10945 is closed, STOP and report (do not proceed under another claim). Rebase on `origin/main` (`git fetch origin main`; `git rebase origin/main`); never sync by hand later.
0.2 Re-measure on the rebased tree: audit run (detached, `--root` a detached worktree of `origin/main`, `--all-refs`, about 5 minutes); record the `SOLEUR_PR_AFFECTED_AUDIT` line and the code/non-code split with the `CODE_EXT` classifier, and assert `gap_refs` equals the baseline's line count; on a mismatch re-fetch, re-rebase and re-measure once, and STOP and report if it persists (a sibling moved the live set, or the tool is wrong). Sibling PRs that change the live set (see Sibling PR Overlap) make the numbers drift; use the base you will merge on. The byte-for-byte `--print-baseline` idempotence check is run once here only if 0.2 disagrees, and after every rebase (3.7).
0.3 Calibration trial (throwaway, reverted): add about 10 edges for the heaviest suites plus ONE new `AFFECTED_<LABEL>_PATHS` block and one `"${_CLOSURE_LEAF_..._[@]}"` spread; run `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/test-all-affected.test.sh` and one `ratchet --report <file>` run. Learn (i) the census rules: every declared array must contain `scripts/lib/test-affected-paths.sh` itself (the suite's own file is covered by a derived self-edge, not an array element), an empty array and any literal entry that is not a tracked file are red, and array order / placement is checked only by the registration-only pre-pass in `scripts/test-all.sh`, which this PR does not use; record the new-block template (including the lib entry) in the decision TSV header; (ii) the reveal rate per declared edge; and (iii) for every candidate shared helper, statically list the paths its library file names (`grep` on the helper) and the number of labels that would spread it, because a spread multiplies reveals by the number of spreaders (44 suites for `scratch-root.sh`), so a single mention in a helper can trip the round-1 cap on its own; set the batch order, any early split and each helper's spread BEFORE the 947-row table is built. Count reveals as distinct (F, G) pairs with their multiplicity noted. Also run the injectivity check once: map every live registration label through `_aff_label_map` (defined in `scripts/test-all.sh`, documented there as NOT injective: `a/b-c` and `a/b_c` map to one array name) and confirm no two labels share an array name and that every NEW array name maps to exactly one label. Revert the trial.
0.4 Prepare the scratch tooling (not committed): the first-pass heuristic triage (line kind by regex: `source`/`.`, `bash|sh|python3|node|bun <path>`, read verbs, write/echo/printf, import) writes `candidates.tsv` from `audit --all-refs`; the human read, not the heuristic, decides. The heuristic must never be the sole evidence for a declare or a mention.
0.5 Recorder trial (timeboxed, one attempt): `bash scripts/audit-suite-reads.sh record --rev origin/main --only <one non-runner label> --mode check --max-load <n> --load-wait <s> --out <new dir>` detached. Check mode is documented for the 18 rows whose closure reaches the runner and prints at most 8 opened files per row, so confirm it accepts a non-runner label and read the full per-window events in `--out`. If it is refused again (load, selection cap), write `recorder: not run, <reason>` (Ruling 2) and do not retry.

### Phase 1 - the decision table (RED for the whole PR: nothing is declared yet)

1.0 Environment receipt: `env` shows no `CI_PR_AFFECTED` in the shell used for the ratchet, the recorder and the local gate (`grep -c '^CI_PR_AFFECTED=' < <(env)` prints 0); the lever stays unset everywhere in this work.
1.1 Build `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4-code-edge-drain/pairs-decisions.tsv`: one row per code pair at the Phase 0.2 base, columns `suite, path, class (a, b, c, d, mention or deferred-real), file:line, decision (declare, mention, ambiguous-declared or deferred-real), touches_90d, suites_selected` (the last two filled for ambiguous rows and for every pair that a shared-array spread covers: `git log --since=90.days --oneline -- <path>` count and the number of suites that declare or spread the path; the "about 1 suite run per 20 PRs" bound of Ruling 1 is applied to them numerically, and the ten hottest path-by-suite products are listed in the PR body); `deferred-real` is a pair the suite really reads whose edge is held back because the same file also reveals a mention (Ruling 7) or breaks another suite, excluded from the drained-set equality and counted in the PR body as a known false negative; batch membership is read from the commit that declared the row. Revealed pairs and held-back edges go in a second section of the same file (`suite, F or G, reason, file:line`). No class means no declaration and no accept row.
1.2 Work by cluster where pairs share one consumer: decide on the consumer once, quote the consumer line, and record `cluster:<id>` in the evidence column. Rubric (d) requires the consumer loop line to be quoted before any data row is declared. The 271 pairs that come from `scripts/lib/test-relevance-paths.sh` (nine runner-SUT suites) are read ONCE PER CONSUMER SUITE, not per pair: classify the cluster `mention` unless that suite's quoted loop reads, execs or stats each row (Ruling 1, Amendment 1: a text-scanned data library is not a read), so the 20-minute reads go to the roughly 670 pairs that can be real.
1.3 Batches, in order (commit boundaries only; the stop-line count in Phase 2 is PR-wide): A the 17 suites with more than 10 code pairs (585 pairs); B the cross-suite library clusters (scratch-root.sh, incidents.sh libs, run-registered-suites.sh rows, tmp-classify.sh, lint-betterstack-emitter-read.sh and the like), decided once per helper and spread per Ruling 3; C the long tail (170 suites with at most 3 pairs, then 4 to 10). A shared `_CLOSURE_LEAF_*` array is made only when 3 or more labels spread the same helper; a helper with 1 or 2 consumers gets literal exact entries.
1.4 Recorder cross-check (Ruling 2, best-effort, not a gate): over the top 12 suites plus 15 random, compare the FULL per-window opened set in the `--out` directory (not the capped table row) against the table, restricted to opened paths that match a pair in the table: any opened pair labelled `mention` flips to declared. An `uncovered` list under `cover=argv` is expected to be long (the cover is only the suite's own argv files); it adds an edge only for a path that is also a table pair, anything else is out of scope. Record `recorder-blind` rows and report how many of the 27 suites completed (n/27); a partial run still counts, a flip found in it is still binding.
1.5 Run-away guards: a pair is never declared to make a number move; an edge for a file the suite does not read is a defect even if it drains a pair (Goodhart guard, Ruling 4).

### Phase 2 - declare, prune, reveal: one commit per batch

Definitions (one place): a ROUND is one cycle of declare, `ratchet`, prune, re-run. Each batch opens a new reveal chain whose first cycle is round 1 of that chain; a pair revealed by round N is declared or held back in round N+1 of the same chain, and every chain is resolved BEFORE its batch commit, so each commit is a post-resolution state with `ratchet` at exit 0. The per-chain caps of Ruling 5 apply to each chain (round 1 under 60 revealed pairs, later rounds under 30, at most 4 rounds, each round smaller than the last within the chain) and the cumulative cap of 150 revealed pairs is PR-wide (decision-log row 15 records this reading of the ruling). The count is the number of `new-pair` entries in a cycle's FIRST report, before any hold-back (holding back does not reduce it). If a batch's first report is already over the round-1 cap, bisect the batch's edge set in halves, re-run RED, keep the half under the cap and file the other as the PR4b continuation; count only the retained half. Every `ratchet` run uses `--report <file>` and every count below is taken from that uncapped report, never from stdout (stdout prints at most 25 entries per class and a `more` line).
For each batch (A, B, C):
2.1 RED proof: edit the index (exact files by default; shared arrays per Ruling 3; a prefix or glob only per Ruling 4), do NOT touch the baseline, run `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main --report <file>` (about 4 to 5 minutes): the report must list `stale-line` for EXACTLY the declared pairs (set equality against the batch's declare rows) and `new-pair` for anything revealed. If a declared pair is not reported stale, the edge does not cover it: fix the edge, not the baseline. This is also the control that the edge is what drains the pair, so no separate removal control is run. A prefix or glob that drains a pair classed `mention` is narrowed to exact files or sent to PR5; the mention is never relabelled to make the sets match (that is the Goodhart move of 1.5).
2.1b Per batch, before the commit, also run the cheap checks: `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/test-all-affected.test.sh`, `shellcheck scripts/lib/test-affected-paths.sh`, and the suites that read the baseline's CONTENT (`git grep -l 'ci-pr-affected-audit.baseline.tsv' -- '*.test.sh'`; the planner found `scripts/lib/inngest-probe-row.test.sh`, whose `ALLOW` list names the baseline as a data file because two baseline lines name `scripts/lib/inngest-probe-row.sh`, and which reports that entry `STALE` if both pairs are drained). PR4 edits no test file, so an edge, a spread or a drained pair that breaks another suite is treated like a revealing edge: hold it back (for the inngest-probe-row case, keep at least one of the two pairs baselined) and log it as held-back with the reason.
2.2 GREEN: `ratchet --base origin/main --print-baseline > scripts/ci-pr-affected-audit.baseline.tsv.new && mv ...` (never a direct redirect onto the file; prune-only, refuses on a degraded census). Re-run `ratchet`: exit 0, `live == baseline`. Revealed pairs make the first run exit 1 `new-pair`; they are classed by the rubric and resolved by the next declare or by holding the revealing edge back (Ruling 7) BEFORE the batch commit, so each commit is the post-resolution state with `ratchet` at exit 0.
2.3 Reveal count: count the `new-pair` entries of each cycle's first report (real plus mention) against the per-chain and PR-wide caps above. A revealed REAL read is declared in the next cycle; a revealed MENTION means the revealing edge is held back (Ruling 7): remove or never commit that edge, re-run, and confirm live == baseline; log it as a held-back edge (`suite, F, reason, file:line`). If a stop line trips, hold the revealing edge back (its original pair stays baselined) and note the continuation PR4b.
2.4 Commit the batch with the baseline in the same commit (`ci(s4): PR4 batch <A|B|C> ... Ref #10860`; the message records real versus held-back mention counts and the running totals), push, and record the batch's local `ratchet` wall time (the hosted job is capped at 5 minutes with provisional 210 s p95 / 270 s maximum ceilings; a batch that pushes the local run clearly past 210 s is split and its tail goes to PR4b). The HEAD-pin reproduction check (`git worktree add --detach <pin> HEAD`; the baseline path tracked; `--print-baseline` must reproduce the committed file) runs once on the final HEAD and after any rebase (3.7), not per batch.

### Phase 3 - fixpoint and verification (the full battery runs once)

3.0 Write the runbook edit of 4.1 first, so the HEAD that is verified is the HEAD that merges (the window-dependent observation-log line is NOT written into the file: a PR cannot contain its own merge SHA; it goes only into the #10865 comment).

3.1 Fixpoint: after the last commit, run the audit once (`audit --root <detached worktree of the branch HEAD> --all-refs`); its `refs`, `files_read`, `gap_refs` and `stale` must equal the last cycle's (nothing was declared after it), `gap_refs` must equal `wc -l` of the baseline, and the last `ratchet` marker must read `exit=0 reason=pass`. Paste the audit line and the marker line in the PR. The final cycle reveals 0 new pairs.
3.2 Breadth check (inline, not committed): every added entry is a tracked file or an existing directory; every prefix has at least 3 segments and at most 25 tracked files (count printed); no `scripts/`, `apps/web-platform/`, `plugins/soleur/` prefix; the baseline has no added line against the merge base: `grep -c '^+[^+]' < <(git diff origin/main...HEAD -- scripts/ci-pr-affected-audit.baseline.tsv)` prints 0 (three dots).
3.3 Selection canary, for prefix and glob edges ONLY (Ruling 4; the RED proof of 2.1 already covers exact edges): `bash scripts/test-all.sh --print-selection --paths=<path>` for each prefix or glob edge, before and after; the declared suite is selected with reason `edge:declared`; record selection sizes; a prefix or glob edge whose selected set exceeds 10 suites is converted to exact entries or held back (a lead threshold, decision-log row 15). If the PR declares no prefix or glob edge, say so in the PR body and skip.
3.4 Replay suite, detached, run first because it fails fast on a logic regression: `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` (1,069 assertions, 420 mutants, about 17 minutes) -> rc file. Floors `FLOOR_ASSERTIONS` / `FLOOR_MUTANTS` unchanged by this PR; if a rebase brought a sibling's rows, resolve additively and confirm by a measured run.
3.5 Full affected gate, detached, launched only after the final rebase that changed the index, `scripts/test-all.sh` or a suite file (a rebase that brought only unrelated sibling changes re-runs the ratchet, the census and the replay suite, not the hours-long gate, because the queue's `merge_group` run is the full battery of record): `SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=14400 TC_RUNTIME_CEILING_S=39600 bash scripts/test-all.sh --affected` -> rc file. The default local gate degrades to rc=6 `AFFECTED_GATE_BUDGET_DEFERRED` after 900 s, which is a deferral, not a pass; repo-global ratchets show up only in the full run. Before launching, list and kill own stale runs (`source plugins/soleur/scripts/lib/proc.sh` first: `list_runs` is a function defined in that file, not a binary); do not claim the battery per commit. If the gate fails, run the failing suite on a detached worktree of `origin/main`; a failure that reproduces there is pre-existing (record the rc, file or reference the issue per the pre-existing-failure rule, and say so in the PR body), any other failure is this PR's to fix; if the run is killed at the ceiling or OOM, report the rc and rely on the queue run. The local gate is not a substitute for waiting on the queue.
3.6 Census and lint, early and cheap: `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/test-all-affected.test.sh`, `shellcheck scripts/lib/test-affected-paths.sh`, the repo markdown lint script on the changed docs (`scripts/markdown-lint.sh`, not a bare linter; `knowledge-base/project/` is ignored by `.markdownlintignore`). The census, `test-all-affected.test.sh` and shellcheck also run per batch (2.1b); this is the final confirmation.
3.7 After any rebase (the baseline is regenerated ONLY on a tree rebased onto the current `origin/main`): if the replay of batch commits conflicts on the baseline, take main's copy and regenerate per the baseline-conflict recipe in every conflicting commit so each stays green (no `git stash`); re-key `pairs-decisions.tsv` against the new merge base, moving rows a sibling already drained or deleted to a `retired-by-sibling` section; re-run 3.1 and 3.2 and recompute every acceptance number against the final merge base as a set difference (any removed baseline line that is not a table row is a defect). Regenerate the baseline with a HEAD pin (worktree of HEAD, baseline path tracked, `ratchet --print-baseline` to a `.new` file), diff it against the committed one, commit, re-run `ratchet`. Right before the push, run the sibling overlap loop and `git merge-tree` (Sibling PR Overlap).
3.8 Job-budget check: the CI job is capped at `timeout-minutes: 5` with provisional ceilings of 210 s p95 and 270 s maximum, and more declared edges raise `files_read`. Time the final local `ratchet` run (wall) and compare it with the 162 s hosted datapoint of the runbook observation log; a clear regression is reported in the PR body and on #10448, not silently shipped.
3.9 Rollback simulation: in a scratch detached worktree squash the branch onto `origin/main`, `git revert` the squash commit, run `ratchet --base origin/main`, and record the verdict (expected `grown`, exit 1) and the tree in the Rollback section.

### Phase 4 - documentation and handoff

4.1 (written in 3.0) Runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` section 7: add "The drain rubric" (about 15 lines: the classes (a) to (d), the mention class, the breadth limits, the stop line and the hold-back rule, so PR5 and later authors apply the same bar; this is the ONE durable home of the rubric, and the PR body and comments carry counts and a pointer), correct "Until PR4 drains" wording to the post-PR4 state, point counts at `wc -l`, replace "restarts the window count" by "is recorded on #10865 and restarts the count by hand" (row 6), add a dated observation-log line only if PR4 merges inside the window, and state that a revert of a drain PR re-adds baseline lines and therefore reads `grown` (advisory red) until the next drain regenerates.
4.2 Comments: #10448 (result, counts, the rubric pointer), #10861 (the PR5 sizing note: expected 600 to 700 code mentions plus 941 non-code, the table path, the `ambiguous-declared` and held-back rows PR5 may take first, and the reminder that PR5 removes the adoption arm), and, only if PR4 merges inside the window, #10865 (merge SHA and the sentence of row 6; the comment only records the SHA, it does not start, close or re-run the evidence window).
4.3 PR body (`Ref #10860`, `Ref #10448`, `Ref #9729`, no closing keyword): the audit lines before and after, class counts by (a)-(d) and mention, the ambiguous-declare list, the held-back count, the prefix/glob list with file counts, the always-on-candidate rows (suite, reason, duration) if any, recorder status, the stop-line outcome, the holds, the window consequence, and that the PR edits a runner trigger so the full battery ran once.

### Phase 5 - ship (no operator step)

If the observation window (#10865, earliest 2026-10-31) is still open when the PR is marked ready, the first line of the PR body states that merging restarts the window count by hand (row 6); the plan does not delay PR4 (row 7). Mark ready after the full gate and replay suite are green; merge through the merge queue (`max_entries_to_merge = 1`); BEHIND is expected and never synced by hand; a flaky e2e dequeue gets ONE re-enqueue, a second is reported with the run URL. Because `merge_group` fails closed on a stale baseline, a sibling merge in front forces a rebase and a regenerated baseline (3.7). This PR edits no `.github/workflows` file, so the agent `--admin` fallback question does not arise. If a stop line tripped, file the PR4b continuation issue (labels `priority/p3-low`, `type/chore`, `domain/engineering`, `meta/machinery`, `Ref #10448`) before marking ready and hand the `s4-drain` label to the PR4b draft at merge so the claim chain is never open to PR5 in the gap. Otherwise, after merge `gh pr list --label s4-drain --state open` is empty (claim released); #10860 stays open until the owner closes it (Ref only).

## Files to Edit

- `scripts/lib/test-affected-paths.sh` (runner trigger: new/extended `AFFECTED_*_PATHS` entries, the shared `_CLOSURE_LEAF_*` arrays; exact files by default).
- `scripts/ci-pr-affected-audit.baseline.tsv` (shrinks only, via `ratchet --print-baseline`, in the same commit as each batch).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (section 7 as in 4.1).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4-code-edge-drain/pairs-decisions.tsv` (the decision table; archived at ship).
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4-code-edge-drain/tasks.md` (derived task list).
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4-code-edge-drain/receipts/` (audit before/after, ratchet marker lines, recorder table, canary output, breadth check output).
- NOT created: `scripts/ci-pr-affected-audit.accept.tsv` (Ruling 7: PR4 creates no accept file).
Files verified: every path above exists on `origin/main` (`git ls-files`) except the ones listed under Create.

## Consumer of the declared lists

A declared entry is inert unless something reads it for the diff shape in question. The consumers, verified by grep on `scripts/test-all.sh`: the per-label array is resolved by name through the indirection `_m="AFFECTED_$(_aff_label_map "$_l")_PATHS"`, each entry is minted into an anchored edge by `_affected_add_edge() {` and unioned with the derived edges, and the selector's `AFFECTED_SELECTED` rows (`--print-selection --paths=<path>`) are what the ratchet and the audit read. The audit itself judges coverage with the selector's own grammar, so a declared pair that leaves the live set is proven to be covered by the same list the gate consumes. The shared `_CLOSURE_LEAF_*` arrays are consumed only through the per-label arrays that spread them.

## Sibling PR Overlap

Open PRs touching the same files (measured with `gh pr list --state open --json files`): #10937 (retires four followthrough probes: edits the baseline, the index and `scripts/test-all.sh`, so it moves the live set and conflicts on all three), #10926, #10900 and #10891 (edit the index), #7390 (WIP: `ci.yml`, the index, `scripts/test-all.sh`), #10928, #9640, #6778 (`scripts/test-all.sh` only; no conflict on PR4's files). Mitigation: one drain PR at a time (the `s4-drain` claim); resolve index conflicts additively; take main's baseline and regenerate with the prune-only tool (the baseline-conflict recipe), never by hand; floors in the replay suite resolved additively and confirmed by a measured run; re-run the overlap loop and `git merge-tree` right before the push.

## Open Code-Review Overlap

#8800 (test fixture: census sandbox shares inodes/symlinks with live repo) names `scripts/lib/test-affected-paths.sh`: Acknowledge, different concern (a census-sandbox write-through hazard, no change to it here). #8659 and #7942 name `scripts/test-all.sh`, which this PR does not edit: none. No match for the baseline, the runbook, ADR-276, the replay script or the replay suite.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "drain the code-extension gap pairs of the affected index" | Phases 1-3 | mapped |
| 2 | "declare an edge in scripts/lib/test-affected-paths.sh ONLY when the suite really reads or executes the file; mentions move to PR5 (#10861)" | Phase 1 rubric (row 1), Phase 2 | mapped |
| 3 | "re-run the audit to a fixpoint inside the PR" | Phase 2.3, 3.1 | mapped |
| 4 | "The baseline shrinks in the same commit via `ratchet --print-baseline` (never by hand)" | Phase 2.2, 2.4 | mapped |
| 5 | "The PR edits a runner trigger, so it runs the full battery once" | Phase 3.5 | mapped |
| 6 | "PR text uses `Ref #10448` / `Ref #9729` / `Ref #10860` only, never a closing keyword" | Phase 4.4 | mapped |
| 7 | "Technical forks go to soleur:engineering:cto, not the user" | Technical Rulings, decision-challenges.md | mapped |
| 8 | "do NOT set CI_PR_AFFECTED, do NOT remove the activation lock, do NOT run PR D (#10414)" and the other holds | Overview, row 8 | mapped (held) |
| 9 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" | decision-challenges.md | mapped |
| 10 | "Regenerate the baseline after every rebase" | Phase 3.7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| decision table TSV | "for each of the ~945 code-extension pairs read the line context" | asked |
| recorder cross-check on 27 suites | — | inferred — justification: CTO ruling 2 (the rubric's class (c) is invisible to line-reading alone; the recorder is the only empirical read evidence the repo has); it is one-directional, bounded, never a merge blocker |
| shared `_CLOSURE_LEAF_*` arrays | — | inferred — justification: CTO ruling 3; 44 suites read one helper through a computed path the derive cannot resolve |
| breadth guard (3 segments, 25 files) and the selection canary | — | inferred — justification: CTO ruling 4; without it a coarse prefix drains pairs and destroys selection value that criterion (c) is measured on |
| stop line (60/30/4/150) and the PR4b continuation | "if a reveal is too large, re-split" is the standing series rule | inferred — justification: CTO ruling 5 supplies the numbers the series rule lacks |
| runbook rubric section | "update the runbook" is the standing PR3a/PR3b pattern | inferred — justification: PR5 and later authors apply the same bar; one durable home (plan review cut the ADR amendment) |
| #10861 sizing comment | "mentions move to PR5 (#10861)" | asked |
| issue #10949 (probe-enforced window restart) | — | inferred — justification: deferral tracking rule; CTO ruling 6 left a residual "unverified by probe" |

### Split Assessment

- Subsystems touched: 2 (CI machinery under `scripts/`, knowledge-base docs).
- Planned files: 3 edited + 3 to 4 created; estimated changed lines: roughly 600 to 900 in the index file (about 250 to 330 pairs, many via 44 one-line spreads) and 330 baseline lines removed.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR; the series already split code pairs (PR4) from mentions and non-code pairs (PR5), and Ruling 5 supplies the continuation PR4b if a reveal trips the stop line.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today, because the lever (`CI_PR_AFFECTED`) is unset and locked and the ratchet job is advisory; after a later, separately authorized flip, a pull request that changes a file a test suite reads could merge without that suite having run (an omitted real read), or every PR could pay for suites it does not need (an over-declared edge). Review (2026-10-24) named the end-user surfaces whose suites carry `mention` rows that were line-read only, never recorded: the GDPR-gate path regex over the account-delete route and `lib/auth/dev-mode.ts`, the sandbox credential gate over `agent-auth-env-vars.ts`, and the Stripe and billing deny-paths. Those rows are string-only on the lines read, but a flip must wait until the held-back edges and the whole-tree reads are declared or accepted, and the recorder cross-check is a PR5 entry condition for the accept rows.
**If this leaks, the user's [data / workflow / money] is exposed via:** no data path: the work reads tracked repository text and runs local suites under a scrubbed environment with no network namespace; the exposure is CI minutes (money) if edges are over-declared once the lever flips.
**Brand-survival threshold:** aggregate pattern

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** seven technical forks ruled on 2026-10-23 (rubric, recorder, shared arrays, breadth guard and ALWAYS_ON, stop line, window restart, revealed mentions); see Technical Rulings. No product, marketing, legal, finance, operations, sales or support implication: internal CI index maintenance, no user-facing surface, no data processing change, no new vendor or spend. Product/UX gate: none (no `components/`, `app/**/page.tsx` or layout file; no UI path in Files to Edit/Create).

## Architecture Decision (ADR/C4)

No new architectural decision: the drain is ADR-276's own tool (amendment item 2); the rubric and the stop line refine an existing operating rule and live in the runbook. ADR-276 is not edited by PR4 (plan review cut the amendment: it would only restate the PR record; PR5 appends the closing Stage-status line). C4: no impact. Checked against `model.c4`, `views.c4` and `spec.c4`: no external human actor, external system, data store or actor-to-surface access relationship changes (the index file, the baseline and the audit script are repository-internal CI machinery already inside the CI container); derived cardinalities in edge prose do not move because no workflow, job, monitor or heartbeat is added or removed (`plugins/soleur/test/c4-count-parity.test.sh` is part of the full battery in 3.5 and must stay green).

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
  - mode: a stale or new pair after a sibling merge or a rebase (baseline no longer equals the live set)
    detection: the marker reads exit=1 reason new-pair or stale-line on the next pull_request or merge_group run; merge_group fails closed with max_entries_to_merge 1
    alert_route: red check on the PR and the queue entry; fix-forward owner is the author who introduced the pair, due within one working day (ADR-276 item 8)
  - mode: an edge omitted for a file the suite really reads (false negative once the lever flips)
    detection: not visible to the ratchet (declared limit); bounded before merge by the recorder sample and the PR-body ambiguous and held-back lists, and reviewed again when PR5 writes accept rows
    alert_route: PR review of the decision table; PR5 demotion with evidence
  - mode: job wall time grows because more declared edges raise files_read
    detection: marker exit=2 reason timeout or a wall above the 210 s p95 and 270 s maximum ceilings of the observation window probe
    alert_route: Phase 3.8 timing check in the PR body and the ceiling re-rule owed to the CTO agent at the close of the window

logs:
  where: GitHub Actions run logs of the affected-index-ratchet job, plus the --report file uploaded to the step summary
  retention: the repository's Actions log retention (default 90 days); the decision table and receipts persist in the spec directory

discoverability_test:
  command: grep -o -e 'SOLEUR_PR_AFFECTED_RATCHET exit' scripts/ci-pr-affected-replay.py
  expected_output: SOLEUR_PR_AFFECTED_RATCHET exit
```

## Test Scenarios

1. RED then GREEN per batch (2.1, 2.2): declared edges without a baseline prune make the uncapped `--report` list `stale-line` for exactly the declared pairs (set equality); after the prune `ratchet` exits 0. This is also the control that each edge is what drains its pair.
2. Reveal accounting (2.3): the `new-pair` entries of each cycle are counted from the report, real and held-back mention separately, against the PR-wide caps.
3. Fixpoint (3.1): the post-final audit equals the last cycle on `refs`, `files_read`, `gap_refs`, `stale`; `gap_refs` equals `wc -l` of the baseline; the final cycle reveals 0.
4. Growth rule (3.2): `grep -c '^+[^+]' < <(git diff origin/main...HEAD -- scripts/ci-pr-affected-audit.baseline.tsv)` prints 0.
5. Selection canary (3.3), prefix and glob edges only: each selects its suite with reason `edge:declared`.
6. Recorder (1.4, best-effort): no opened-but-mention pair that matches a table pair remains un-flipped in a clean recording.
7. Regression: replay suite (1,069 assertions, 420 mutants), orphan census, `test-all-affected.test.sh`, shellcheck, and the full affected gate rc 0.
8. Rollback simulation (3.9).

## Acceptance Criteria

### Pre-merge

- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` exits 0 with `live == baseline`, and the baseline's line count is smaller than on the merge base by exactly the number of `declare` plus `ambiguous-declared` rows of `pairs-decisions.tsv` (quote the three numbers: `git show origin/main:scripts/ci-pr-affected-audit.baseline.tsv | wc -l`, the branch count, the table count).
- [ ] The baseline has no added line against the merge base (`grep -c '^+[^+]' < <(git diff origin/main...HEAD -- scripts/ci-pr-affected-audit.baseline.tsv)` prints 0) and is C-locale sorted with a final newline.
- [ ] Fixpoint (3.1): audit line and last ratchet marker pasted; the final cycle revealed 0; the stop-line outcome (rounds, per-round and cumulative reveal, real versus held-back mention) is stated.
- [ ] `pairs-decisions.tsv` has one row per code pair at the base, every row classed, plus the revealed-pair and held-back section; set equality holds between (base baseline minus head baseline) and the `declare` and `ambiguous-declared` rows; `mention` rows that are no longer in the baseline are zero; ambiguous declares are listed in the PR body with their consumer.
- [ ] No accept file is created (`scripts/ci-pr-affected-audit.accept.tsv` absent); every held-back edge is a table row and the count is in the PR body.
- [ ] Every prefix has at least 3 segments and at most 25 tracked files (counts in the PR body); no `ALWAYS_ON_SUITES` line added; any always-on candidate appears as one PR-body row.
- [ ] Recorder: the sample ran and has no unresolved flip, or the PR body says `recorder: not run, <reason>` (best-effort, not a merge gate).
- [ ] Replay suite rc 0 at the measured floors; `SOLEUR_ALLOW_FULL_GATE=1 ... bash scripts/test-all.sh --affected` rc 0 (not rc 6); orphan census, `test-all-affected.test.sh`, shellcheck and the markdown-lint script rc 0.
- [ ] Runbook section 7 and the comments on #10448 and #10861 are written; the PR body uses `Ref #10860`, `Ref #10448`, `Ref #9729` only and restates the holds and the window consequence; the final ratchet wall time is reported against the 162 s hosted datapoint (3.8).
- [ ] The PR touches no variable, lock, ruleset, `required-checks.txt`, workflow, probe or ADR file: `git diff --name-only origin/main...HEAD` (three dots, the merge-base form, so a sibling merge cannot redden it) lists only the index file, the baseline, the runbook, this plan, and files under `knowledge-base/project/specs/feat-one-shot-s4-affected-index-pr4-code-edge-drain/`.

### Post-merge

- [ ] `gh pr list --label s4-drain --state open` is empty; #10860, #10448 and #9729 stay open.
- [ ] If merged inside the window: the comment on #10865 with the merge SHA and the row-6 sentence is posted.
- [ ] Observation only (depends on a later queue entry, so never a merge gate): the first `merge_group` run of `affected-index-ratchet` after the merge reads `exit=0 reason=pass`.

## Rollback

The change is data (index entries, a pruned baseline, docs). A plain revert is NOT a clean rollback: it re-adds the drained baseline lines, which the growth rule reads as `grown` (exit 1; advisory red until PR3b, blocking after it), and the rule has no sanctioned exception (a baseline re-base is forbidden). The supported correction is forward: keep the edge (an extra edge only costs suite runs once the lever flips), or remove it together with its pair's accept row in a drain-class PR. Phase 3.9 simulates the revert once in a scratch detached worktree (squash the branch onto `origin/main`, `git revert` it, run `ratchet --base origin/main`) and records the verdict here as "simulated in the squash shape" with the date and tree. The lever is off, so no production behavior depends on the edges.

## Non-Goals

CI_PR_AFFECTED, the activation lock, PR D (#10414), PR3b (#10859), the evidence re-run, criterion (c), the flip PR, #10862 (no-run investigation), PR5's accept rows and baseline deletion (#10861), any `ratchet` or audit-reach change, any probe change (#10949), any `scripts/test-all.sh` edit, any `ALWAYS_ON_SUITES` entry. Deferred items are tracked: #10861 (mentions, non-code pairs, baseline deletion), #10949 (probe-enforced window restart), #10862, #10859, #10414.

## Risks and Sharp Edges

- The `## User-Brand Impact` section is filled with a concrete artifact, vector and threshold; an empty or unfilled one fails `deepen-plan` Phase 4.6.
- Omitted real read: a pair left as a mention that the suite really reads becomes a false negative once the lever flips. Mitigations: ambiguous declares, the 27-suite recorder sample, the PR-body list, PR5's accept rows quote the line kind.
- Over-declare: an edge for a file the suite does not read costs suite runs and dilutes the index. Mitigations: rubric, breadth limits, selection canary.
- Reveal: a declared code file makes the audit read it; revealed pairs cannot be baselined. Stop line in Ruling 5; hold the revealing edge back rather than loosen anything.
- Baseline conflicts: take main's copy and regenerate with the prune-only tool; never hand-resolve; `merge_group` fails closed on a stale baseline with `max_entries_to_merge = 1`.
- The baseline names itself: generate on a tree where the baseline path is tracked (HEAD pin), or suites that mention its path gain a pair.
- Full gate duration (hours, ceiling 39,600 s) and rc 6 deferral; kill own stale runs first; a green replay suite alone is not the battery.
- A canary or fixture trigger must be reproduced locally before it is pushed (2026-10-23 learning); a recorder run on a loaded host is refused, not wrong.
- The probe does not enforce the window restart (row 6, #10949); do not claim it does.
- A reach-widening change is out; if a read-set question arises, it is a different PR.
- Guard-contract and encryption-posture gates are not triggered: no check, lint, hook or workflow is added to the repository (the breadth check and the fixpoint audit are inline verification commands run in the work phase, not committed artifacts), and no store or connection is introduced.
