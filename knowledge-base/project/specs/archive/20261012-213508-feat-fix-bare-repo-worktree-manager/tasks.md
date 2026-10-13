# Tasks: fix bare repo worktree-manager stale files

## Phase 1: Harden worktree-manager.sh

- [x] 1.1 Add `IS_BARE` global flag after GIT_ROOT detection (line ~31)
  - [x] 1.1.1 Compute once: `IS_BARE=false; [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && IS_BARE=true`
  - [x] 1.1.2 Use `$IS_BARE` in all subsequent guards (avoid re-calling `git rev-parse`)
- [x] 1.2 Guard "update main checkout" block in `cleanup_merged_worktrees` (lines 509-526)
  - [x] 1.2.1 Wrap in `if [[ "$IS_BARE" == "true" ]]` check -- skip `git diff`, `git checkout`, `git pull`
  - [x] 1.2.2 Add informational message when skipping (verbose mode only)
- [x] 1.3 Guard `create_worktree()` -- exit early with message when `IS_BARE=true`
  - [x] 1.3.1 Add guard after `local branch_name="$1"` (before `git checkout "$from_branch"`)
- [x] 1.4 Guard `create_for_feature()` -- exit early with message when `IS_BARE=true`
  - [x] 1.4.1 Add guard after `local name="$1"` (before `git checkout "$from_branch"`)
- [x] 1.5 Add explanatory comment block at top of script (after line 5)
  - [x] 1.5.1 Document bare-repo stale-file problem and IS_BARE flag purpose
- [x] 1.6 Add `BASH_SOURCE` guard at script end for testability
  - [x] 1.6.1 Replace direct `main` call with `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main ...; fi`

## Phase 2: Sync Stale On-Disk Files

- [x] 2.1 Add `sync-bare-files` subcommand to worktree-manager.sh
  - [x] 2.1.1 Syncs AGENTS.md, CLAUDE.md, plugin AGENTS/CLAUDE, worktree-manager.sh itself
  - [x] 2.1.2 Syncs .claude/settings.json
  - [x] 2.1.3 Syncs .claude/hooks/*.sh files and restores execute permissions
  - [x] 2.1.4 Auto-called at end of cleanup-merged when bare repo and branches were cleaned

## Phase 3: Testing

- [x] 3.1 Test `cleanup-merged` from bare repo root with no [gone] branches (expect exit 0)
- [x] 3.2 Test `cleanup-merged` from worktree (expect existing behavior: cleanup + update main)
- [x] 3.3 Verify on-disk files at bare repo root match git HEAD after sync (9 files synced)
- [x] 3.4 Test `list` from bare repo root (expect success, shows worktrees)
- [x] 3.5 Test `create` from bare repo root (expect early exit with clear error message)
- [x] 3.6 Test `feature` from bare repo root (expect early exit with clear error message)
- [x] 3.7 Test `sync-bare-files` from bare root (expect success, syncs files)

## Phase 4: Follow-up (Out of Scope -- Filed GitHub Issue)

- [x] 4.1 Filed GitHub issue #610 to track bare-repo hardening for 11 other scripts
