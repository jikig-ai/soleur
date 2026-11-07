---
title: A review-complete marker is not a turn boundary, and a guard fix tightens the instance unless the class is enumerated
date: 2026-10-29
category: workflow-issues
tags: [one-shot, review, continuation-gate, guard-class-vs-instance, mutation-battery]
pr: 11483
---

# Learning: review-complete marker is not a turn boundary; guard fixes hit the instance

## Problem

Two process failures on PR 11483 (a bundle of #11388, #11211, #11212, #11265):

1. After the review fix round the turn ended on the `## Review Phase Complete` marker with "Next, QA, compound, ship" as the last text. The pipeline's deliverable is a merged PR; the operator had to ask why it stopped. `one-shot`'s CONTINUATION GATE named `## Code Review Complete` and generic summary headings, but not the compact `## Review Phase Complete` marker that review actually emits in pipeline mode, and the marker template itself said nothing about continuing. The state was also reached right after a context compaction, so the only in-band cue was the trailer script's own "review is not a turn boundary" line, printed before the summary was written.
2. Eleven fix-round seats found that almost every first-round fix tightened the one named instance rather than the class: step-level CI keys were allow-listed while job and workflow level stayed deny-lists; the unquoted-label enumerator matched one spelling; the `-target` check matched any line instead of the command; the 11265 trust check rejected the text form of a mid-stream failure but accepted the object form; the census marker followed one local, not chains. Test-design added that no mutant scorer had a wrong-reason negative control, so a battery could stay green with its crediting disarmed.

## Solution

- `plugins/soleur/skills/one-shot/SKILL.md` CONTINUATION GATE now names `## Review Phase Complete` explicitly.
- `plugins/soleur/skills/review/SKILL.md` marker template carries a `NEXT (same response)` bullet. Both skill bodies sit at their `lint-skill-body-budget` ceilings, so the explanation lives here, not in the skill.
- Fix round 1 (`c896a125ba`) allow-lists job and workflow keys, widens the guard-env pattern to bare `GUARD_*` names, rejects non-local root module sources, makes the header check cross-check every `logtail_exploration` line, binds `-target` to real arguments, makes the census transitive across root `.tf` files, and adds scorer negative controls. Probe fixes: object lines without `dt` and `raw` read as unreadable, and the canary reads an archive-only window (CTO ruling) so a dead archive arm cannot read as NOT YET.

## Key Insight

A status marker must carry its own continuation instruction at the point where the model writes it; a rule that lives only in the caller's skill, under a different heading name, is invisible at the moment of the stop. Separately, when a review names a guard escape, the fix is to enumerate the layers and spellings the predicate covers (step, job, workflow; every file, every spelling) and give each a mutation row, not to patch the one repro.

## Session Errors

1. **Ended the turn on the review marker mid-pipeline.** Recovery: operator asked; resumed at QA. Prevention: gate now names the marker and the marker template carries a NEXT line (this PR).
2. **A fix agent used a Python heredoc for a batch of edits, against the Write-tool-only rule.** Recovery: later edits used Edit. Prevention: one-off, already covered by the brief's rule; no change.
3. **`gh issue create` was blocked by the net-issue-flow hook (no user-visible consequence named).** Recovery: refiled with `meta/machinery`, which is the honest home for verification-machinery findings. Prevention: one-off; the hook message states the three exits.
4. **Fix-round seats had no copy of their own first-panel reports, so they could not re-run their prior repros.** Recovery: seats re-derived classes from the brief. Prevention: when briefing a fix round, persist each seat's first-panel report to `/var/tmp/review-<pr>-<seat>.md` and name the path in the brief (only four of eleven existed).
5. **A fix agent's own 300 s timeout killed `run-registered-suites.test.sh` (rc 124, read as a failure until investigated).** Recovery: re-ran with 900 s. Prevention: one-off.
6. **The local affected-test gate returned rc=6 (budget-deferred behind other sessions); no tests ran.** Recovery: ran the suites individually and left CI as the authoritative gate. Prevention: known behaviour, never label it as passed.
