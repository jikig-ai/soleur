---
title: Canonicalize merge strategy and add conflict marker guard
date: 2026-03-03
category: workflow-patterns
tags: [integration-issues, git-workflow, claude-hooks]
---

# Learning: Canonicalize merge strategy and add conflict marker guard

## Problem
AGENTS.md and constitution.md mandated `git rebase origin/main` but both `/ship` Phase 6.5 and `/merge-pr` Phase 2 used `git merge origin/main`. The `pre-merge-rebase.sh` hook used rebase. Three codepaths with inconsistent strategies. Additionally, conflict markers had been accidentally committed with no automated prevention.

## Solution
1. Updated AGENTS.md and constitution.md to canonicalize on merge (not rebase)
2. Edited pre-merge-rebase.sh in place to use `git merge origin/main` instead of `git rebase origin/main`, switched from force-push to regular push
3. Added Guard 4 to guardrails.sh blocking commits with conflict markers in staged content
4. Cross-referenced constitution.md advisory grep with the new enforced guard

## Key Insight
When documentation says one thing and code does another, canonicalize on what the code already does -- unless there is a strong reason to change the code. Since PRs are squash-merged, feature branch strategy (rebase vs merge) is irrelevant to the final history. Merge is simpler (single composite conflict vs per-commit conflicts) and does not rewrite history. Also: plan reviewers cutting scope from 4 fixes to 2 saved significant effort -- the two deferred items (Phase 5.5, worktree refresh) were redundant with existing mechanisms.

## Tags
category: integration-issues
module: git-workflow, claude-hooks
