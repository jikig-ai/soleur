---
title: "Tasks: fix Bun test runner crash on missing dependencies"
branch: feat/bun-test-crash
plan: knowledge-base/project/plans/2026-03-18-fix-bun-test-crash-missing-deps-plan.md
date: 2026-03-18
deepened: 2026-03-18
---

# Tasks: fix Bun test runner crash on missing dependencies

## Phase 1: Setup

- [ ] 1.1 Create root `bunfig.toml` with `[test]` section documenting Bun's discovery behavior (comment-only config -- `root = "."` is the default and should be omitted)

## Phase 2: Core Implementation

- [ ] 2.1 Update `.github/workflows/ci.yml` to pin `bun-version: "1.3.11"` instead of `latest`
- [ ] 2.2 Add `install_deps()` function to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - [ ] 2.2.1 Implement function: detect `package.json`, check for existing `node_modules/`, prefer `bun` over `npm`, degrade gracefully on failure
  - [ ] 2.2.2 Call `install_deps "$worktree_path"` after `copy_env_files` in `create_worktree()` (~line 177)
  - [ ] 2.2.3 Call `install_deps "$worktree_path"` after `copy_env_files` in `create_for_feature()` (~line 237)
  - [ ] 2.2.4 Ensure function follows shell conventions: `local` variables, color output matching existing style, non-blocking on failure

## Phase 3: Testing

- [ ] 3.1 Run `bun install && bun test` from worktree root -- verify 13 files, 1136 tests pass
- [ ] 3.2 Verify `bunfig.toml` does not break `apps/telegram-bridge` coverage config (run `bun test --coverage` from `apps/telegram-bridge/`)
- [ ] 3.3 Verify `bun test --list` discovers exactly 13 test files (not files from worktrees or node_modules)

## Phase 4: Documentation

- [ ] 4.1 Create learning: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`
  - Root cause: Bun 1.3.5 allocator panic on unresolvable imports (segfault instead of error message)
  - Fix: upgrade Bun + auto-install deps on worktree creation
  - Cross-reference: `2026-02-26-worktree-missing-node-modules-silent-hang.md` (implements its recommendation)
  - Category: `runtime-errors`, tags: `bun`, `testing`, `git-worktree`, `segfault`
