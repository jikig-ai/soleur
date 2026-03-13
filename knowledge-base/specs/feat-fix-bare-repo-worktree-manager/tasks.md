# Tasks: fix bare repo worktree-manager stale files

## Phase 1: Harden worktree-manager.sh

- [ ] 1.1 Guard "update main checkout" block in `cleanup_merged_worktrees` to skip when `core.bare=true`
  - [ ] 1.1.1 Wrap lines 509-526 (the `if cleaned > 0` update-main block) in a bare repo check
  - [ ] 1.1.2 Add informational message when skipping (verbose mode only)
- [ ] 1.2 Audit remaining functions for working-tree assumptions
  - [ ] 1.2.1 `ensure_gitignore` -- verify behavior when GIT_ROOT is a bare repo (no `.gitignore` to append to at repo root in bare context, but this function is only called from `create_worktree`/`create_for_feature` which are interactive and unlikely to run from bare root)
  - [ ] 1.2.2 `list_worktrees` line 241 `git rev-parse --abbrev-ref HEAD` -- verify in bare repo context
- [ ] 1.3 Add comment block at top of script explaining bare-repo stale-file hazard

## Phase 2: Sync Stale On-Disk Files

- [ ] 2.1 Create a `sync-bare-files.sh` helper script or document the manual sync commands
  - [ ] 2.1.1 Extract key files from git HEAD: AGENTS.md, CLAUDE.md, worktree-manager.sh
  - [ ] 2.1.2 Overwrite on-disk copies and restore execute permissions
- [ ] 2.2 Consider adding sync to `cleanup-merged` itself (auto-sync stale files when bare repo detected)

## Phase 3: Testing

- [ ] 3.1 Test `cleanup-merged` from bare repo root with no [gone] branches (expect clean exit)
- [ ] 3.2 Test `cleanup-merged` from bare repo root with [gone] branches (expect cleanup without fatal)
- [ ] 3.3 Test `cleanup-merged` from worktree (expect existing behavior preserved)
- [ ] 3.4 Verify on-disk files at bare repo root match git HEAD after sync
