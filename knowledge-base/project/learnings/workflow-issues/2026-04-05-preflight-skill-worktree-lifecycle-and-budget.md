---
module: System
date: 2026-04-05
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Worktree created by brainstorm disappeared when one-shot started"
  - "Skill description budget exceeded at 1806/1800 requiring two trim iterations"
  - "draft-pr script reported bare repo despite CWD showing worktree"
  - "Eleventy docs build fails on main with dateToShort filter error"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [worktree, skill-budget, preflight, docs-build, one-shot]
---

# Learning: Preflight Skill -- Worktree Lifecycle and Budget Constraints

## Problem

During one-shot execution of the preflight skill feature (#1242), several workflow issues surfaced:

1. **Worktree lifecycle gap:** The brainstorm skill created a worktree in its subshell, but when the one-shot skill started in a fresh shell context, the worktree directory didn't exist. The `pwd` command showed the old path but the filesystem had no directory there.

2. **Skill description budget sensitivity:** Adding a 24-word description pushed the cumulative count from ~1780 to 1806 (over the 1800 limit). Required two iterations to trim from 24 to 15 words.

3. **Script CWD detection:** The `worktree-manager.sh draft-pr` command failed with "Cannot run from bare repo root" even though the shell's CWD was inside the worktree. The script's detection logic didn't match the shell state after the worktree was re-created.

4. **Pre-existing docs build failure:** The Eleventy docs build fails with a `dateToShort` filter error in `sitemap.njk`. This is on main and unrelated to any PR. Filed as #1531.

## Solution

1. **Worktree:** Re-created the worktree using `worktree-manager.sh --yes feature preflight-gates` and explicitly `cd` into the full absolute path.

2. **Budget:** Progressively trimmed the description: "This skill should be used when validating technical readiness before shipping. It checks database migration status, security headers, and execution context." -> "This skill should be used when running pre-ship checks on migrations and security headers." (15 words, 1798/1800).

3. **Script CWD:** Used explicit `cd /full/path && command` pattern to ensure the script ran from the correct directory.

4. **Docs build:** Filed #1531 tracking issue. The data files (skills.js, agents.js) load correctly — only the sitemap template has the filter issue.

## Key Insight

When skills run in pipeline mode (brainstorm -> one-shot -> work), worktree state created in one skill's subshell doesn't automatically persist to the next skill's execution context. Each pipeline stage should verify worktree existence before assuming it exists. The skill description budget is at 99% capacity (1798/1800) — every new skill must aggressively trim its description or an existing description must be shortened first.

## Session Errors

1. **Skill description budget exceeded twice** — Recovery: Trimmed description from 24 to 15 words across two iterations. Prevention: Check current budget (`bun test plugins/soleur/test/components.test.ts`) before writing a new skill description. Target 12-15 words for new skills.

2. **Worktree disappeared between pipeline stages** — Recovery: Re-created worktree and explicitly cd'd. Prevention: One-shot's Step 0b already checks branch isolation — this worked as designed. The brainstorm-created worktree was a bonus that didn't survive context transition.

3. **draft-pr script bare-repo detection mismatch** — Recovery: Explicit cd to absolute worktree path before running script. Prevention: Always use absolute paths with `cd /full/path && command` pattern when running worktree scripts.

4. **Shell CWD lost after cd in Bash tool** — Recovery: Used absolute path in next command. Prevention: Avoid `cd` to subdirectories; use absolute paths for all git and script commands.

5. **Pre-existing docs build failure** — Recovery: Filed #1531 tracking issue. Prevention: Already tracked.

## Cross-References

- Related: `2026-03-30-skill-description-word-budget-awareness.md`
- Related: `2026-03-27-skill-description-budget-headroom.md`
- Issue: #1242 (preflight feature)
- Issue: #1531 (docs build failure)
- Issue: #1532 (preflight v2 deferred items)

## Tags

category: workflow-issues
module: System
