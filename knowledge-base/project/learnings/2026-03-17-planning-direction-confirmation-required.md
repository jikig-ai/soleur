---
title: Planning direction confirmation required for merge operations
date: 2026-03-17
category: workflow-issues
tags: [planning, merge-direction, user-confirmation, knowledge-base]
module: skills/plan
---

# Planning direction confirmation required for merge operations

## Problem

When a task involves merging directory A into B (or vice versa), the planner inferred the merge direction from code evidence (PR #606 had updated skill references to point to root-level paths) instead of asking the user. This produced a complete plan with the wrong direction — merging project/ into root instead of root into project/.

The error cascaded: research agents reinforced the wrong assumption, a full plan was created and deepened, and implementation began before the user caught the mistake. The entire plan had to be scrapped and re-done.

## Root Cause

The planner treated the most recent PR (#606) as authoritative evidence of canonical directory structure. But PR #606 itself may have been incorrect — it moved references away from project/ instead of toward it. Code evidence doesn't always reflect user intent.

## Solution

When a plan involves directional ambiguity (merge A→B vs B→A, move files from X to Y), the plan skill must explicitly confirm the direction with the user before proceeding. This applies even in pipeline mode — directional ambiguity is a critical decision, not a detail to infer.

## Session Errors

1. Plan v1 created with wrong merge direction (project/ → root instead of root → project/)
2. Worktree corruption from draft-pr script required worktree recreation
3. Research agent reinforced wrong assumption by labeling root-level dirs as "canonical"
4. Path-update subagent misreported results (said "no changes needed" but made 19 file changes)
5. git push rejected due to draft-pr having already pushed to remote
6. git mv failed for overlapping directory (feat-ralph-loop-idle-detection already in project/specs/)

## Key Insight

Code evidence can be wrong. When a task involves a directional choice (A→B vs B→A), the planner must ask the user, not infer from the codebase. The cost of one clarifying question is trivial compared to the cost of executing an entire wrong plan.

## Prevention

- Add a directional confirmation gate to the plan skill for restructuring/merge tasks
- When multiple conflicting signals exist (PR says X, user says Y), always defer to the user
- Research agents should flag ambiguity rather than resolve it unilaterally

## Related

- [2026-03-13-readme-self-references-missed-in-rename.md](./2026-03-13-readme-self-references-missed-in-rename.md) — KB directory restructuring planning gap (missed self-references after rename)
- [2026-03-13-stale-cross-references-after-kb-restructuring.md](./2026-03-13-stale-cross-references-after-kb-restructuring.md) — Stale cross-references after KB restructuring
- [2026-03-10-document-plan-conditional-omissions.md](./2026-03-10-document-plan-conditional-omissions.md) — Plan-implementation mismatch from silent omissions
- [2026-02-06-parallel-plan-review-catches-overengineering.md](./2026-02-06-parallel-plan-review-catches-overengineering.md) — Plan review catching errors before implementation
