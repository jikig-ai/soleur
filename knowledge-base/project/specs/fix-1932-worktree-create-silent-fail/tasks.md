# Tasks: fix-1932-worktree-create-silent-fail

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` to confirm current line numbers and structure

## Phase 2: Core Implementation

- [ ] 2.1 In `create_worktree()`: move `ensure_bare_config` call from after `git worktree add` to after verification block
- [ ] 2.2 In `create_worktree()`: add `git worktree list --porcelain` verification with retry+repair after existing `rev-parse` check
- [ ] 2.3 In `create_for_feature()`: move `ensure_bare_config` call from after `git worktree add` to after verification block
- [ ] 2.4 In `create_for_feature()`: add `git worktree list --porcelain` verification with retry+repair after existing `rev-parse` check
- [ ] 2.5 Verify both functions have identical verification flow (no divergence)

## Phase 3: Testing

- [ ] 3.1 Run `worktree-manager.sh --yes create test-verify-1932` from an existing worktree to confirm success path works
- [ ] 3.2 Verify created worktree appears in `git worktree list`
- [ ] 3.3 Clean up test worktree
- [ ] 3.4 Run shellcheck on modified script (if available)
