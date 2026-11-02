---
date: 2026-11-02
category: workflow-patterns
pr: 11844
branch: feat-one-shot-11776-machinery-batch
---

# Free-model subagent deaths favor lead-verification over respawn

## What happened

A Tier B fan-out of 4 `run_subagent` workers on Devin CLI lost 3 of 4 to
`Reached free model rate limit` — spawned agents ride the free tier and die
rather than retry. Each left partial on-disk work (test rows, SUT edits) that
was recoverable by inspection, not by its report.

## The recovery shape that worked

Per the work skill's own Tier B fallback ("if any subagent failed, complete
those tasks sequentially"), the lead:

1. Read the dead agent's on-disk diff — partial work is inspectable state, not
   a black box. Group C's fix was fully written and verified green by running
   its suite directly (12/12).
2. Verified rather than respawned — a respawn pays the same rate-limit coin
   again; `bash <suite>` on the agent's on-disk output is deterministic and
   free-tier-free.
3. Completed the untouched scope inline (Group D had written nothing).

## Rules of thumb

- **Check `git status`/diff before believing a dead agent did nothing.** All
  three dead agents here had real, mostly-correct edits on disk.
- **Spawn prompts for flaky-tier agents should front-load the commit-shaped
  work** — the parts that die last are the ones written first.
- **A 0-agent review panel is a trailer state, not a skip.** `inline-fallback`
  mode on `emit-review-trailer.sh` is the honest coverage record; never emit
  `full` when the panel didn't run.
