---
title: Plan skill generated tasks.md before plan review, causing stale-derivative risk
date: 2026-04-15
category: workflow-issues
tags: [workflow, plan-skill, tasks, plan-review, ordering]
status: fixed
---

# Learning: Plan skill ordered `tasks.md` generation before plan review

## Problem

`plugins/soleur/skills/plan/SKILL.md` had these sections in order:

1. "## Save Tasks to Knowledge Base (if exists)" — generates `tasks.md` and commits + pushes
2. "## Plan Review (Always Runs)" — spawns DHH, Kieran, code-simplicity reviewers; applies changes to plan

This ordering meant that when plan review prompted material changes to the plan (phase cuts, deliverable rewrites, scope adjustments), the already-generated `tasks.md` immediately went stale. The options at that point were bad:

- **Regenerate `tasks.md`** → extra work, plus the original commit now contains a half-finished artifact
- **Leave `tasks.md` stale** → `/soleur:work` executes against a task list that doesn't match the final plan, causing silent drift
- **Skip plan review** → bypasses the quality gate

## Solution

Swapped the section order in `plugins/soleur/skills/plan/SKILL.md`:

1. Plan Review runs first (spawns 3 parallel reviewers, applies requested changes)
2. `tasks.md` is generated from the **finalized, post-review** plan
3. Commit covers both the plan file and `tasks.md` atomically (single `git revert` scope)

Added a "Why Plan Review runs BEFORE Save Tasks" paragraph to the skill explaining the ordering — `tasks.md` is a derivative breakdown, so it must reflect the final source-of-truth plan.

## Key Insight

When an artifact B is derived from artifact A, any review/mutation pass on A must complete before B is materialized. Generating B first and regenerating after A changes is a workflow smell — double work plus an inconsistency window. The skill-enforced ordering is: **source → review → derivative → commit-together**.

This is the same principle as "don't commit generated files before the source is final" — applied to plan/tasks.md instead of source/build-output.

## Session Errors

**Initial Read on bare repo paths** — Two `Read` calls at session start used file_path under the bare repo root (`/home/jean/git-repositories/jikig-ai/soleur/knowledge-base/...`) while the active branch was checked out in a worktree (`.worktrees/collapsible-navs-ux-review/`). Both returned "File does not exist."

- **Recovery:** switched to worktree-absolute paths (`/home/jean/git-repositories/jikig-ai/soleur/.worktrees/collapsible-navs-ux-review/knowledge-base/...`) and re-read successfully.
- **Prevention:** existing rule `hr-when-in-a-worktree-never-read-from-bare` covers this. The deeper fix would be a PreToolUse hook that auto-rewrites or blocks bare-repo paths when a worktree is active — non-trivial (requires branch → worktree mapping). Tracked as a follow-up candidate, not shipped this session. Rule remains the primary enforcement.

**Plan skill tasks-before-review ordering** — see Solution above. Fixed this session via skill edit.

- **Recovery:** swapped ordering mid-session; ran plan review first, applied changes, then generated `tasks.md` from the finalized plan.
- **Prevention:** `plugins/soleur/skills/plan/SKILL.md` edited this session — Plan Review now precedes Save Tasks with an explanatory "Why" paragraph. Future `/soleur:plan` invocations get the corrected ordering.

## Files Affected

- `plugins/soleur/skills/plan/SKILL.md` (sections swapped; "Why" paragraph added)
- `knowledge-base/project/plans/2026-04-15-feat-ux-audit-skill-plan.md` (first artifact to exercise the corrected ordering)
- `knowledge-base/project/specs/feat-collapsible-navs-ux-review/tasks.md` (derived from the post-review plan)
