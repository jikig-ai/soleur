# Learning: ops-provisioner modifies files on main instead of worktree

## Problem

The ops-provisioner agent was invoked from the main branch to set up Plausible Analytics. It modified `plugins/soleur/docs/_includes/base.njk` and `knowledge-base/ops/expenses.md` directly on main, violating the repository's worktree convention (AGENTS.md: "Never commit directly to main").

The agent's instructions contain no worktree awareness -- it edits files wherever it's invoked from without checking branch context.

## Solution

Two fixes needed:

1. **Caller responsibility:** The invoking workflow (brainstorm, manual invocation) should create a worktree before spawning ops-provisioner. The agent itself shouldn't create worktrees -- it's a subagent, and worktree creation is the caller's job.

2. **Agent guardrail:** Add a safety check to ops-provisioner's Setup section that warns when running on main/master and suggests the user create a worktree first. This catches the case where a user invokes the agent directly.

Applied fix: Added a branch check to ops-provisioner's Setup section that warns when on main and asks the user to confirm or create a worktree.

## Key Insight

Subagents that modify files inherit the caller's branch context. If the caller is on main, the subagent writes to main. Worktree enforcement belongs at the orchestration layer (commands, skills) not the agent layer, but agents that edit project files should have a defensive check as a safety net.

## Session Errors

1. ops-provisioner modified files on main branch (convention violation)
2. Searched for agent at `agents/operations/ops-provisioner.md` instead of `plugins/soleur/agents/operations/ops-provisioner.md` (wrong path)
3. Tried `plugins/soleur/plugin.json` instead of `plugins/soleur/.claude-plugin/plugin.json` (wrong path)

## Tags

category: workflow-patterns
module: agents/operations/ops-provisioner
symptoms: files modified on main branch, worktree convention violated
