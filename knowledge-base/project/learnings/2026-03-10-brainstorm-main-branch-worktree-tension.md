# Learning: Brainstorm skill's main-branch abort conflicts with worktree creation

## Problem

The brainstorm skill (Phase 0) aborts if `git branch --show-current` returns `main`. But the brainstorm itself creates the worktree in Phase 3 (before any file writes). This creates a chicken-and-egg problem: you can't brainstorm without a feature branch, but the brainstorm is what creates the feature branch.

## Solution

Worked around by manually creating the worktree before starting the brainstorm dialogue:

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature x402-mcp-payments
cd .worktrees/feat-x402-mcp-payments
```

Then Phase 3's worktree creation was skipped since the worktree already existed.

## Key Insight

The branch safety check protects against committing to main, but Phases 0.5-2 (domain leader assessment, dialogue) don't write any files. The check is too aggressive — it should gate file writes (Phase 3+), not the entire skill. Alternatively, the skill should create the worktree in Phase 0 instead of Phase 3.

## Tags

category: logic-errors
module: brainstorm-skill
