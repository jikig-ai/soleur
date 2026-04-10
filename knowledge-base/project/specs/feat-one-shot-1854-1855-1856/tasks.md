# Tasks: Worktree Verification, SKILL.md Sharp Edges, Vitest Binding Fix

## Phase 1: Setup

- 1.1 Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` to confirm current verification logic
- 1.2 Read `plugins/soleur/skills/git-worktree/SKILL.md` to identify insertion point for Sharp Edges
- 1.3 Read `scripts/test-all.sh` to confirm npx vitest invocation line

## Phase 2: Core Implementation

### 2.1 Add belt-and-suspenders directory check (#1854)

- 2.1.1 In `create_worktree()`, add `[[ ! -d "$worktree_path" ]]` check after `git worktree add` and before `git rev-parse` verification (around line 320)
- 2.1.2 In `create_for_feature()`, add the same `[[ ! -d "$worktree_path" ]]` check after `git worktree add` and before `git rev-parse` verification (around line 391)

### 2.2 Add Sharp Edges section to SKILL.md (#1855)

- 2.2.1 Add `## Sharp Edges` section before `## Technical Details` in `plugins/soleur/skills/git-worktree/SKILL.md`
- 2.2.2 Document the silent creation failure fallback pattern with reference to #1854 and #1806
- 2.2.3 Document the `draft-pr` path resolution caveat

### 2.3 Fix vitest invocation (#1856)

- 2.3.1 Change `npx vitest run` to `./node_modules/.bin/vitest run` in `scripts/test-all.sh`

## Phase 3: Testing

- 3.1 Run `bash scripts/test-all.sh` from the worktree to verify all tests pass with the new vitest invocation
- 3.2 Run `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --help` or `list` to verify no syntax errors
- 3.3 Run `npx markdownlint-cli2 --fix` on changed `.md` files
