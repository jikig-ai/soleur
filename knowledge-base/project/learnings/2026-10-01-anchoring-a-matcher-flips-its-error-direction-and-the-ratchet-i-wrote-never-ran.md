---
title: Anchoring a matcher flips its error direction, and the ratchet I wrote never ran
date: 2026-10-01
category: logic-errors
module: scripts/test-all.sh (affected gate)
issue: 9307
pr: 9306
---

# Learning: anchoring a matcher flips its error direction, and the ratchet I wrote never ran

## Problem

PR 1 of #9307 made the affected-suite gate select fewer suites: directory/file edges became line-anchored (`^dir/`, `^file`)
instead of substring matches, 24 always-on suites were audited for demotion to declared edges, and a ratchet suite
(`scripts/test-affected-kb-consumers.test.sh`) was added to stop a demotion silently dropping a knowledge-base reader.
Everything was green locally and a 30-diff corpus replay showed 0 widened selections. A ten-seat review then found:

1. **The ratchet was registered nowhere.** The plan said "auto-registered by the `scripts/*.test.sh` glob"; no such glob exists
   (the runner's own comments say so), and `lint-orphan-test-suites.sh` reported the suite as never run. My earlier
   "0 orphaned" came from a run made while the file was still untracked.
2. **Anchoring flipped the error direction.** A substring over-matches toward RUNNING (safe); an anchored edge errs toward
   NOT running whenever the diff text does not present a path as its own line. The diff blob also carries `--name-status -M`
   rows (`R100<TAB>old<TAB>new`) and git C-quoted names, so a file moved out of a guarded directory declined the suite that
   guards it. Seven of ten seats found it independently. The corpus replay used `--name-only` and structurally could not see it.
3. **A demotion is not free.** An always-on label skips derivation; an edge label runs the full source-closure derive.
   `scripts/domain-model-drift` cost 82 s of pre-pass to save 0.9 s of suite time, and the ratchet itself costs a full
   `--print-selection` walk (about 11 minutes).
4. **`--paths` did not reach the enumerate child**, so relevance-gated suites were decided on the real diff while the report
   claimed to describe the named paths.

## Solution

Split rename rows on TABs and unwrap C-quoted names in `_diff_edge_hit` (memoised); forward `--paths` to the child; register the
ratchet with a declared edge set; put `domain-model-drift` back in `ALWAYS_ON_SUITES`; make the oracle's join total, treat
`$ROOT`/`show-toplevel` as real-tree reads, exclude the ratchet from its own population, and require the baseline to equal its
regeneration. Rows `t8`-`t11`, `m7`-`m9`, `f1`, `q5`, `q6`, `b1`, `j1`, `hop1`, `r1` pin each. The ratchet found a real
uncovered read in one of the four demoted suites it flagged (`tenant-dpa-register-guard-live`), now covered.

## Key Insight

When a change turns a permissive matcher into a strict one, the review question is not "does the strict matcher still select
what it should in the cases I replayed" but "what text does the matcher now fail to see, and which channels feed that text".
The replay corpus was built from the same assumption as the matcher (one path per line), so it could not disagree with it.
And a guard added in the same PR is a registration like any other: run the census that proves it executes before believing
the plan's sentence that it does.

## Session Errors

Earlier-session errors (the class-receipt misreading of `--print-affected-set`, wrong research claims, a suite edited under a
running baseline, weak mutants) are in
`2026-09-30-print-affected-set-prints-classes-not-selection-and-the-ask-was-half-shipped.md`. This stretch:

1. **Registered nothing, trusted the plan's "glob" sentence.** Recovery: orphan census, then a `run_suite` line at the end of the
   scripts block. **Prevention:** run `bash scripts/lint-orphan-test-suites.sh` the moment a new `*.test.sh` is tracked (now a
   plan sharp edge).
2. **Edited the worktree while a sandbox battery ran**, so the runner's boundary check fired and one row (m3) failed for a reason
   unrelated to the SUT. Recovery: re-ran m3 alone with no edits. **Prevention:** none beyond the existing rule; a focused copy
   still reads the live tree, so hold edits until it returns.
3. **First oracle self-exclusion at the wrong layer** (`scan()`, but the false positives arrived through the one-hop scan of the
   runner the suite names), costing a second 11-minute run. **Prevention:** reproduce the false positive's SOURCE before fixing it
   (print the file the ref came from).
4. **A blocked process-matching command, an absent `/usr/bin/time`, a `kill_mine` pattern with a slash and a `list_runs` call with
   no argument.** Recovery: `proc.sh` with a basename pattern, the shell `time` builtin. **Prevention:** hook-enforced already.
5. **A SKILL.md edit exceeded the `work` body ceiling by 132 bytes**; the budget lint caught it. Recovery: shortened the sentence.
   **Prevention:** run `python3 scripts/lint-skill-body-budget.py --base origin/main` after any lifecycle SKILL.md edit.
6. **First focus run covered 24 sandbox rows at ~4 minutes each under load 30-60**; killed and reduced to the rows I changed.
   **Prevention:** select rows by what changed, and time one arm before launching a batch.

## Tags

category: logic-errors
module: scripts/test-all.sh
