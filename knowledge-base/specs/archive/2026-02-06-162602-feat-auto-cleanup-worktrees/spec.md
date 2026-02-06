---
title: Auto-Cleanup Worktrees After PR Merge
status: draft
issue: "#15"
related: "#10"
branch: feat-auto-cleanup-worktrees
created: 2026-02-06
---

# Auto-Cleanup Worktrees After PR Merge

## Problem Statement

Worktrees persist after PR merge, requiring manual cleanup. Users must remember to run `worktree-manager.sh cleanup` and manually archive spec directories. This creates clutter and cognitive overhead.

## Goals

1. Automatically detect when PRs are merged
2. Clean up associated worktrees without user intervention
3. Preserve completed specs in an archive for future reference
4. Notify user of cleanup actions taken

## Non-Goals

- Real-time webhook-based detection (too complex)
- Cross-machine synchronization
- Cleaning worktrees for PRs closed without merge

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | `cleanup-merged` command detects branches with `[gone]` status |
| FR2 | Command removes worktree directory from `.worktrees/` |
| FR3 | Command archives spec to `knowledge-base/specs/archive/YYYY-MM-DD-<name>/` |
| FR4 | Command deletes local branch after worktree removal |
| FR5 | `--auto` flag enables silent mode with summary output only |
| FR6 | SessionStart hook triggers cleanup on Claude Code session start |
| FR7 | PostToolUse hook triggers cleanup after `gh pr merge` command |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Extend existing `worktree-manager.sh` script |
| TR2 | Use `git fetch --prune` before detection |
| TR3 | Use `git branch -vv | grep '\[gone\]'` for detection |
| TR4 | Configure hooks in Claude Code settings |
| TR5 | Handle case where spec directory doesn't exist gracefully |
| TR6 | Handle case where worktree is currently active (skip with warning) |

## User Stories

**As a developer**, I want merged worktrees cleaned up automatically so I don't have clutter from completed work.

**As a developer**, I want to see what was cleaned so I have visibility into automatic actions.

## Open Questions

- Should there be a `.worktree-keep` marker to prevent cleanup of specific worktrees?
