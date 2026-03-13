# Tasks: fix bare repo worktree-manager stale files

## Phase 1: Harden worktree-manager.sh

- [ ] 1.1 Add `IS_BARE` global flag after GIT_ROOT detection (line ~31)
  - [ ] 1.1.1 Compute once: `IS_BARE=false; [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] && IS_BARE=true`
  - [ ] 1.1.2 Use `$IS_BARE` in all subsequent guards (avoid re-calling `git rev-parse`)
- [ ] 1.2 Guard "update main checkout" block in `cleanup_merged_worktrees` (lines 509-526)
  - [ ] 1.2.1 Wrap in `if [[ "$IS_BARE" == "true" ]]` check -- skip `git diff`, `git checkout`, `git pull`
  - [ ] 1.2.2 Add informational message when skipping (verbose mode only)
- [ ] 1.3 Guard `create_worktree()` -- exit early with message when `IS_BARE=true`
  - [ ] 1.3.1 Add guard after `local branch_name="$1"` (before `git checkout "$from_branch"`)
- [ ] 1.4 Guard `create_for_feature()` -- exit early with message when `IS_BARE=true`
  - [ ] 1.4.1 Add guard after `local name="$1"` (before `git checkout "$from_branch"`)
- [ ] 1.5 Add explanatory comment block at top of script (after line 5)
  - [ ] 1.5.1 Document bare-repo stale-file problem and IS_BARE flag purpose
- [ ] 1.6 Add `BASH_SOURCE` guard at script end for testability
  - [ ] 1.6.1 Replace direct `main` call with `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main ...; fi`

## Phase 2: Sync Stale On-Disk Files

- [ ] 2.1 Sync critical files from git HEAD to bare repo root on-disk copies
  - [ ] 2.1.1 `git show HEAD:AGENTS.md > AGENTS.md`
  - [ ] 2.1.2 `git show HEAD:CLAUDE.md > CLAUDE.md`
  - [ ] 2.1.3 `git show HEAD:plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh > ...` + `chmod +x`
  - [ ] 2.1.4 `git show HEAD:plugins/soleur/AGENTS.md > ...`
  - [ ] 2.1.5 `git show HEAD:plugins/soleur/CLAUDE.md > ...`
  - [ ] 2.1.6 `git show HEAD:.claude/settings.json > ...`
  - [ ] 2.1.7 Sync `.claude/hooks/*.sh` files and restore execute permissions

## Phase 3: Testing

- [ ] 3.1 Test `cleanup-merged` from bare repo root with no [gone] branches (expect exit 0)
- [ ] 3.2 Test `cleanup-merged` from bare repo root with [gone] branches (expect cleanup + skip update-main)
- [ ] 3.3 Test `cleanup-merged` from worktree (expect existing behavior: cleanup + update main)
- [ ] 3.4 Verify on-disk files at bare repo root match git HEAD after sync
- [ ] 3.5 Test `list` from bare repo root (expect success, shows worktrees)
- [ ] 3.6 Test `create` from bare repo root (expect early exit with clear error message)

## Phase 4: Follow-up (Out of Scope -- File GitHub Issue)

- [ ] 4.1 File GitHub issue to track bare-repo hardening for 11 other scripts using `git rev-parse --show-toplevel` with fallbacks
  - `plugins/soleur/hooks/welcome-hook.sh`
  - `plugins/soleur/hooks/stop-hook.sh`
  - `plugins/soleur/scripts/setup-ralph-loop.sh`
  - `plugins/soleur/skills/community/scripts/discord-setup.sh`
  - `plugins/soleur/skills/community/scripts/x-setup.sh`
  - `plugins/soleur/skills/community/scripts/bsky-setup.sh`
  - `scripts/generate-article-30-register.sh`
