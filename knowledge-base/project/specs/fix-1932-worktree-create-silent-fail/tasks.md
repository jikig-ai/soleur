# Tasks: fix-1932-worktree-create-silent-fail

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` to confirm current line numbers and structure

## Phase 2: Core Implementation

- [ ] 2.1 Add `verify_worktree_created()` function after `ensure_bare_config()` (~line 125) with:
  - [ ] 2.1.1 Check 1: `git -C "$worktree_path" rev-parse --show-toplevel` (existing logic)
  - [ ] 2.1.2 Check 2: `git worktree list --porcelain | grep -qF "worktree $worktree_path"` (new)
  - [ ] 2.1.3 Retry with `git worktree repair "$worktree_path"` on Check 2 failure (targeted repair)
  - [ ] 2.1.4 Cleanup and exit 1 on all verification failures
- [ ] 2.2 In `create_worktree()`: replace inline verification block (lines 322-334) with call to `verify_worktree_created`
- [ ] 2.3 In `create_worktree()`: move post-add `ensure_bare_config` (line 320) to AFTER `verify_worktree_created` call
- [ ] 2.4 In `create_for_feature()`: replace inline verification block (lines 394-405) with call to `verify_worktree_created`
- [ ] 2.5 In `create_for_feature()`: move post-add `ensure_bare_config` (line 391) to AFTER `verify_worktree_created` call
- [ ] 2.6 Confirm pre-add `ensure_bare_config` calls (line 265, line 353) remain unchanged

## Phase 3: Testing

- [ ] 3.1 Run `worktree-manager.sh --yes create test-verify-1932` from an existing worktree to confirm success path works
- [ ] 3.2 Verify created worktree appears in `git worktree list`
- [ ] 3.3 Clean up test worktree with `git worktree remove`
- [ ] 3.4 Run shellcheck on modified script (if available)
