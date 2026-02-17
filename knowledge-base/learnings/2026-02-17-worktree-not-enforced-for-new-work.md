# Learning: Worktree creation not enforced for new feature work

## Problem

When starting a new feature task directly (not via `/soleur:work` or `/soleur:one-shot`), Claude created a bare `git checkout -b` branch on the main repo checkout instead of creating a worktree under `.worktrees/`. This leaves the main repo checkout dirty and prevents parallel work on other features.

## Root Cause

The AGENTS.md instructions have a gap between two rules:

1. **Branching rule** says: "Create a feature branch for every change. Do not create additional branches or worktrees unless explicitly requested." -- This actively discourages worktree creation.
2. **Worktree Awareness** says: "When a worktree is active for the current task..." -- This only enforces discipline when a worktree already exists.

There is no rule that says "always use a worktree for feature work." The branching rule's "do not create worktrees unless explicitly requested" clause directly contradicts the intent.

## Solution

Update the AGENTS.md branching rule to require worktree creation for feature work:

- Change: "Create a feature branch for every change"
- To: "Create a worktree under `.worktrees/feat-<name>/` for every feature change. Use `git worktree add .worktrees/feat-<name> -b feat/<name>` from the main repo root."
- Remove the "do not create worktrees unless explicitly requested" clause

The Worktree Awareness section already handles the discipline once a worktree exists -- the gap is only in creation.

## Key Insight

Instructions that say "do X when Y is active" but never say "activate Y" create a dead rule. The worktree discipline was well-defined but never triggered because nothing required worktree creation in the first place.

## Tags
category: workflow-patterns
module: AGENTS.md
symptoms: work done on main checkout instead of worktree
