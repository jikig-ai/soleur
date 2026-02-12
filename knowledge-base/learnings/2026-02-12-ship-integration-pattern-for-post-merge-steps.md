---
name: Ship Integration Pattern for Post-Merge Steps
description: How to extend /ship with conditional post-merge skill invocations
date: 2026-02-12
category: workflow-patterns
module: plugins/soleur
tags: [ship, skill-integration, post-merge, release-announce]
---

# Ship Integration Pattern for Post-Merge Steps

## Problem

Need to add a new post-merge step to `/ship` (release announcements) without bloating the ship skill or tightly coupling the announcement logic.

## Solution

Create a standalone skill and add a conditional invocation in `/ship` Phase 8:

1. **Standalone skill** handles the domain logic (e.g., `release-announce` handles Discord + GitHub Releases)
2. **Ship Phase 8** adds a conditional check (~5 lines) that invokes the skill only when relevant

Pattern:
```markdown
**If merged:**
1. Check if <condition>:
   git diff --name-only $(git merge-base HEAD origin/main)..HEAD -- <path>
2. If <path> was modified: Run /<skill-name>
3. Run worktree cleanup (existing step)
```

## Key Insight

The ship skill should remain a thin orchestration layer. Domain logic belongs in standalone skills that ship conditionally invokes. This keeps ship focused on lifecycle enforcement while making each capability independently testable, discoverable by agents, and invocable standalone.

The condition check uses `git diff` against the merge base to determine if the skill is relevant to this particular PR, avoiding unnecessary invocations.

## Tags

category: workflow-patterns
module: plugins/soleur
