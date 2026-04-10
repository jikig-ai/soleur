# Tasks: Worktree Verification, SKILL.md Sharp Edges, Vitest Binding Fix

## Phase 1: Setup

- 1.1 Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` to confirm current verification logic (lines 264-347 for `create_worktree`, 350-427 for `create_for_feature`)
- 1.2 Read `plugins/soleur/skills/git-worktree/SKILL.md` to identify insertion point for Sharp Edges (before `## Technical Details` around line 293)
- 1.3 Read `scripts/test-all.sh` to confirm npx vitest invocation line (last section, `run_suite "apps/web-platform"`)
- 1.4 Read `apps/web-platform/package.json` to confirm current scripts section

## Phase 2: Core Implementation

### 2.1 Add belt-and-suspenders directory check (#1854)

- 2.1.1 In `create_worktree()`, add `[[ ! -d "$worktree_path" ]]` check after `git worktree add` (line 317) and before `git rev-parse` verification (line 322). Error message: `"Error: Worktree directory not created at $worktree_path"`
- 2.1.2 In `create_for_feature()`, add the same `[[ ! -d "$worktree_path" ]]` check after `git worktree add` (line 388) and before `git rev-parse` verification (line 393)

### 2.2 Add Sharp Edges section to SKILL.md (#1855)

- 2.2.1 Add `## Sharp Edges` section before `## Technical Details` in `plugins/soleur/skills/git-worktree/SKILL.md`
- 2.2.2 Document the silent creation failure fallback pattern with reference to #1854 and #1806
- 2.2.3 Document the `draft-pr` path resolution caveat (`SCRIPT_DIR`)
- 2.2.4 Document the absolute path requirement for manual `git worktree add` (per learning `2026-03-17`)
- 2.2.5 Document the lefthook hang workaround (>60s, kill and commit with `LEFTHOOK=0`)

### 2.3 Fix vitest invocation (#1856)

- 2.3.1 Add `"test:ci": "vitest run"` script to `apps/web-platform/package.json`
- 2.3.2 Change `npx vitest run` to `npm run test:ci` in `scripts/test-all.sh`
- 2.3.3 Regenerate `package-lock.json` if `package.json` changed: `cd apps/web-platform && npm install --package-lock-only`

## Phase 3: Testing

- 3.1 Run `bash scripts/test-all.sh` from the worktree to verify all tests pass with the new vitest invocation
- 3.2 Run `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list` to verify no syntax errors in the modified script
- 3.3 Run `npx markdownlint-cli2 --fix` on changed `.md` files
- 3.4 Verify both lockfiles are in sync: `cd apps/web-platform && npm install --package-lock-only && git diff --exit-code package-lock.json`
