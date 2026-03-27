---
adr: ADR-009
title: Git Worktree Isolation
status: active
date: 2026-03-27
---

# ADR-009: Git Worktree Isolation

## Context

Need isolated branches for parallel feature development without conflicts on main. Repo uses core.bare=true where git pull and git checkout are unavailable from root.

## Decision

Never commit directly to main (hook-enforced). Create worktrees via `git worktree add .worktrees/feat-<name> -b feat/<name>`. At session start, run cleanup-merged. Never git stash in worktrees (commit WIP first). Never rm -rf on worktree paths (hook-enforced). MCP tools resolve paths from repo root — always pass absolute paths.

## Consequences

Clean parallel development with full isolation. Hook enforcement prevents accidental main commits. worktree-manager.sh handles lifecycle (create, cleanup-merged, draft-pr). All PreToolUse hooks block destructive operations on worktrees.
