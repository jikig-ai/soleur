# Spec: Pull Latest Before Worktree Creation

**Branch:** feat-pull-before-worktree
**Created:** 2026-02-06

## Problem Statement

The `create_for_feature()` function in `worktree-manager.sh` creates worktrees without first pulling the latest changes from the remote. This can result in feature branches based on stale local refs, causing merge conflicts or missing recent changes.

## Goals

- Ensure worktrees created via `create_for_feature()` are based on the latest remote state
- Maintain consistency with `create_worktree()` which already pulls before branching

## Non-Goals

- Changing the pull behavior in `create_worktree()` (already correct)
- Adding fetch-only options (decided against in brainstorm)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | `create_for_feature()` must pull from origin before creating the worktree |
| FR2 | Pull failures must not block worktree creation (graceful degradation) |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Use same pattern as `create_worktree()`: checkout + pull with `|| true` |
| TR2 | Add status message showing which branch is being updated |

## Acceptance Criteria

- [ ] Running `worktree-manager.sh feature <name>` pulls latest from base branch first
- [ ] If pull fails (offline/auth), worktree creation still proceeds
- [ ] Output shows "Updating $from_branch..." message before pull
