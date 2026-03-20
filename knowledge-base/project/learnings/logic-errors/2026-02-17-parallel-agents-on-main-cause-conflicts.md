---
title: "Parallel agents working on main cause merge conflicts"
category: logic-errors
tags:
  - parallel-agents
  - git-branching
  - worktree
  - workflow
  - merge-conflicts
module: workflow-commands
created: 2026-02-17
severity: high
synced_to:
  - plugins/soleur/commands/soleur/work.md
  - plugins/soleur/commands/soleur/one-shot.md
---

# Learning: Agents must branch before editing, even for trivial fixes

## Problem

When an agent skips brainstorm (which normally creates a worktree in Phase 3) and goes directly to `/soleur:work` or is invoked ad-hoc for a quick fix, the `work` command offers "Option C: Continue on the default branch." This allows agents to edit files directly on main.

When two agents run in parallel on the same repo -- both on main or both touching the same files -- the second agent's rebase silently drops its changes because the first agent already modified the same lines. In one session, a complete set of edits (agents page reorder, getting-started fix, version bump) was lost after rebase because a parallel agent had already made equivalent changes to the same files.

The root cause is that `work.md` Phase 1 treats branch creation as optional (3 options including "stay on main"), and `one-shot.md` doesn't enforce branch creation at all before delegating to plan/work.

## Solution

1. **Remove Option C from `work.md`** -- never allow working directly on the default branch. The only options should be: create a new branch (Option A) or use a worktree (Option B). CLAUDE.md already mandates "never commit directly to main."

2. **Add branch/worktree creation to `one-shot.md`** before the plan step -- since one-shot skips brainstorm (which normally handles worktree creation), it must ensure isolation before any work begins.

3. **Default to worktree (Option B)** when parallel development is detected (e.g., other worktrees exist or other agents are active).

## Key Insight

Branch creation must happen BEFORE the first file edit, not as an optional step during setup. When brainstorm is skipped, the worktree creation that brainstorm normally handles never runs, leaving agents to work on main. Every entry point to implementation (work, one-shot, ad-hoc fixes) must enforce isolation as a precondition, not a recommendation.

## Prevention

- Remove all "continue on default branch" options from workflow commands
- Add a hard gate in work.md Phase 1: if on default branch, MUST branch before proceeding
- one-shot should create branch/worktree as step 0 before plan

## Cross-references

- CLAUDE.md Working Agreement: "Never commit directly to main"
- [2026-02-17-truncated-changelog-during-rebase-conflict-resolution.md](../integration-issues/2026-02-17-truncated-changelog-during-rebase-conflict-resolution.md) -- related rebase conflict from same session
- PR #121 session: parallel agent conflict that triggered this learning

## Tags

category: logic-errors
module: workflow-commands
symptoms: changes lost after rebase, parallel agent conflicts, zero diff after rebase, silent change loss
