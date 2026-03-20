---
title: Auto-Cleanup Worktrees - Implementation Tasks
spec: ./spec.md
plan: ../../plans/2026-02-06-feat-auto-cleanup-worktrees-plan.md
created: 2026-02-06
updated: 2026-02-06
---

# Implementation Tasks

## Phase 1: Core Implementation

### 1.1 Add cleanup_merged_worktrees function
- [x] Add function to `worktree-manager.sh` after line 331
- [x] Implement TTY detection for output mode (`[ -t 1 ]`)
- [x] Run `git fetch --prune` with error capture
- [x] Find `[gone]` branches via `git for-each-ref` (robust detection)

### 1.2 Implement cleanup logic
- [x] Skip active worktree (PWD check)
- [x] Skip worktrees with uncommitted changes (`git status --porcelain`)
- [x] Archive spec directory with timestamp: `knowledge-base/specs/archive/YYYY-MM-DD-HHMMSS-<name>/`
- [x] Sanitize branch names containing `/` for archive paths
- [x] Remove worktree with `git worktree remove` (no --force)
- [x] Delete branch with `git branch -d` (safe delete)
- [x] Report failures as warnings, continue with next branch

### 1.3 Implement output formatting
- [x] Verbose mode (TTY): detailed output with warnings
- [x] Quiet mode (non-TTY): summary only when cleanup occurred
- [x] Track cleaned branches in array for summary

### 1.4 Update command handler
- [x] Add `cleanup-merged` case to main() switch statement
- [x] Update show_help() with new command documentation

## Phase 2: Hook Configuration

### 2.1 Configure SessionStart hook
- [x] Verify correct hook config location (`.claude/settings.local.json` vs plugin.json)
- [x] Add SessionStart hook with script path
- [ ] Test hook fires on session start

## Phase 3: Testing

### 3.1 Manual testing scenarios
- [ ] No [gone] branches (should exit cleanly)
- [ ] Single [gone] branch + worktree + spec
- [ ] [gone] branch with worktree but no spec
- [ ] [gone] branch with spec but no worktree
- [ ] Active worktree (should skip)
- [ ] Worktree with uncommitted changes (should skip)
- [ ] Branch name with `/` (e.g., `feature/auth`)
- [ ] Network failure (disconnect before fetch)
- [ ] Branch with local-only commits (safe delete should fail gracefully)

### 3.2 Verify hook trigger
- [ ] Start new Claude Code session, verify SessionStart fires
- [ ] Verify quiet output when run from hook (non-TTY)

## Phase 4: Documentation

### 4.1 Update plugin documentation
- [ ] Update README with new cleanup-merged command
- [x] Bump version in plugin.json
- [x] Update CHANGELOG.md

---

## Task Dependencies

```
1.1 -> 1.2 -> 1.3 -> 1.4 (sequential - core function)
2.1 (after 1.4 - needs command to exist)
3.1 -> 3.2 (sequential - manual before hooks)
4.1 (after all implementation complete)
```

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Core | ~45 min |
| Phase 2: Hooks | ~15 min |
| Phase 3: Testing | ~30 min |
| Phase 4: Docs | ~15 min |
| **Total** | ~1.75 hours |

## Review Feedback Applied

- [x] Use `git for-each-ref` for robust branch detection (Kieran)
- [x] Add uncommitted changes check before removal (Kieran)
- [x] Use TTY detection instead of `--auto` flag (DHH, Simplicity)
- [x] Use timestamp in archive name, no collision loop (DHH, Simplicity)
- [x] Report warnings instead of silent failures (Kieran)
- [x] Sanitize branch names with `/` (Kieran)
- [x] Start with SessionStart only, defer PostToolUse (Simplicity)
- [x] Removed `specific_branch` parameter (YAGNI)
