---
title: A byte-identical row is not a clean hunk, and main push runs carry no suite timings
date: 2026-11-15
category: workflow-issues
module: scripts/suite-durations.tsv, scripts/regenerate-shard-manifest.py
tags: [shard-manifest, suite-durations, merge-conflict, closing-keyword, merge-group]
issues: [12441, 12778, 12780, 12698, 12791]
---

# Learning: a byte-identical row is not a clean hunk, and main push runs carry no suite timings

## Problem

PR #12778 re-priced one row of `scripts/suite-durations.tsv`: `cloudflare-readonly.test.sh` went from `1261 floor` to `155229 measured`. The work raised three problems.

1. **The timing source.** The archived P.2 task said to take timings "from the first green main run". `green_main_runs()` in `scripts/regenerate-shard-manifest.py` selects `gh run list --workflow ci.yml --branch main --status success`. That query returns only `push` runs, because merge-queue runs have headBranch `gh-readonly-queue/main/...`. `push-dedupe` elides the test shards on push runs, so those runs have no `suite-timings-*` artifacts (run 43513147865 has 0; merge_group run 43506075307 has 11). The runbook's `--runs 5 --write` regen would therefore write an all-floor manifest, and the only signal is a stderr WARN.
2. **A false conflict claim.** The plan and the commit message said this row is byte-identical to #12698's line, so the two PRs cannot conflict on it. Running `git merge-file` disproved it: #12698's table conflicts with this branch as one hunk (lines 7-461). Byte-identity guarantees that both sides carry the same value. It says nothing about whether git can merge the surrounding hunk, because #12698 rewrites neighbouring rows.
3. **A closing keyword in prose.** A Research Reconciliation cell paired the word "fix" (after "Docs") with the #12780 reference, and GitHub parses that pairing as a closing reference. My own session-state note then re-created the same pairing while describing the fix, and the first draft of this learning did it a third time.

## Solution

1. Use merge_group runs as the timing source. 155229 ms is the median of #12698's five green merge_group runs, read from each run's `suite-timings-scripts-4` artifact. The selector fix (merge_group for the ci.yml groups, push for `infra`, die on an all-empty `--write`) is added scope on #12780, under a CTO ruling.
2. Replace the conflict claim with the measured result. Measure it with `git merge-file -p ours base theirs` or `git merge-tree --write-tree`, and never infer it from a matching value.
3. Reword the cell to "Docs follow-up: #12780". Re-grep the whole diff with a positive control: a planted hit must make the grep exit 0 before you trust an rc=1 result.

## Key Insight

A matching value is a claim about content. "No conflict" is a claim about hunks, and only a merge run can show it. The same shape applies to timings: "the latest green main run" names a population, so check which event type that population contains before reading artifacts from it.

## Session Errors

1. **#12780 filing was blocked twice by a hook** (the body path was in a shell variable; the machinery label was missing). This recurred at compound, filing #12791 (same two refusals). Recovery: write the body first, pass a literal absolute `--body-file`, and add `--label meta/machinery`. **Prevention:** compound's file-issue exception prescribes flags the hook refuses; the corrected wording is proposed in #12791.
2. **`technical-ruling-gate` exited 1 on 5 rows** because the rulings had the wrong shape. Recovery: rows were reshaped as `Ruled by CTO agent, <date>: <decision> - <rationale>` or reclassified as taste. **Prevention:** already enforced by the gate. Run `technical-ruling-gate.sh --branch` right after writing decision-challenges.md, not at ship.
3. **The "byte-identical row, so no rebase conflict" claim was false.** Recovery: measured the conflict with `git merge-file` and corrected the plan's Sharp Edges and decision row 10. **Prevention:** a plan-sharp-edges bullet, proposed in #12791 (this PR is row-only). A conflict claim against a sibling PR needs a merge run, never a value comparison.
4. **The 155229 provenance did not name its source runs.** Recovery: review re-read each run's artifact, and row 10 now lists all five run IDs and values. **Prevention:** already covered by work's "verify a measurement once" rule. Cite run IDs at the first write.
5. **A closing keyword appeared in a plan cell, again in my note describing the fix, and again in the first draft of this learning.** Recovery: reworded both and re-grepped with a positive control. **Prevention:** already covered by ship's `closingIssuesReferences == []` gate and `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`. Grep after every prose edit that mentions an issue number, including notes about the fix.
6. **I overstated what seed mode and `--write` rewrite.** Recovery: corrected the counts from the scratch dry run. **Prevention:** quote the dry-run output, not a recollection of it.
7. **`green_main_runs()` samples push runs, which have no timings (pre-existing).** Recovery: routed to #12780 as added scope. **Prevention:** tracked in #12780 (selector fix plus a die-on-empty test).
8. **quality-guards went red because of #12781, and #12700 was ejected from the queue.** Neither came from this diff. Recovery: confirmed both came from main; fix PR #12782 is open. **Prevention:** tracked in #12781/#12782.
9. **I read an exit code through `| tail`.** Recovery: re-ran with the output redirected and `echo RC=$?`. **Prevention:** already covered by work's "the wrapper that reports a gate is itself a guard" rule.
10. **I re-armed monitors more than once.** Recovery: one watch per condition. **Prevention:** none needed (one-off).
11. **A turn ended on an announcement instead of "Paused:" or "Blocked:".** Recovery: continued in the same turn. **Prevention:** already enforced by the stop hook.

## Tags

category: workflow-issues
module: shard-manifest
