---
title: Devin subagents cannot spawn nested subagents — pipeline fan-outs must originate at the orchestrator
date: 2026-11-01
category: workflow-patterns
tags: [devin-cli, run_subagent, one-shot, pipeline, harness-parity]
---

# Learning: Devin subagents cannot spawn nested subagents

## Problem

A `run_subagent`-spawned planning subagent (profile `subagent_general`) reported
"no Task/subagent tool exists in this harness" when a plan phase prescribed
spawning `soleur:engineering:cto` or a `plan-review` panel. The parent's own
`run_subagent` works fine — the tool simply isn't in a *subagent's* tool set,
so any skill phase that delegates spawning one level deeper silently degrades
to in-process equivalents.

## Solution

Structure the pipeline so every fan-out (CTO consults, review seats, fix-round
seats) is spawned by the orchestrator itself. When a subagent returns with a
"panel could not run" residual, treat it as a real capability note — the parent
re-runs that fan-out directly (we did: 9-seat panel + 3-seat fix round). Record
the gap in `decision-challenges.md` so the trailer `Reviewed-Coverage:` stays
honest.

## Evidence

- PR #11824 planning subagent (agent_id=3695d551): returned `plan-review`
  panel + CTO spawn as residuals; technical-ruling gate rows had to be resolved
  in-process.
- Parent then ran `Own the epic` CTO + 12 total seat spawns via `run_subagent`
  with no nesting issues.

## Additional instance: inline dispositions fail the machine-gated ruling shape (2026-11-08, PR #12446)

The constraint bites one level earlier than panel seats: a planning
subagent that cannot spawn at all writes its `decision-challenges.md`
technical rows as **inline dispositions** — which
`technical-ruling-gate.sh --branch` rejects identically to "Applied by the
planner" (only `Ruled by CTO agent, <date>:` passes). The fix ran at the
orchestrator: ONE batched `soleur:engineering:cto` spawn carried all 11
technical rows (`cto_spawns=1`) and the cells were rewritten to the gated
shape — the `plan-sharp-edges.md` batched-spawn remedy, issued one level up
because the planner has no spawn tool. Rows the CTO had already ruled on the
source issues (#12428/#10448) were carried as BINDING inputs, not re-ruled.
Disclosure: `Reviewed-Coverage: sequential-fallback` in the file header,
session-state.md and the PR body.

## Also learned this session

- `gh pr merge --auto` on a merge-queue repo answers "already queued to merge"
  while `autoMergeRequest` reads `null` — the queue holds it; check
  `mergeStateStatus`/`amq`, don't re-arm blindly (confirmed on #11822).
- A cancelled `gh pr checks` entry can be a superseded-run artifact: a fresh
  same-SHA run succeeded 22s later. Read `gh api .../jobs/<id>` conclusion
  before treating it as CI red.
