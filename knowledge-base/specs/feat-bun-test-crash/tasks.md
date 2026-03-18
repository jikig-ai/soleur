---
title: "Tasks: fix Bun test runner crash on missing dependencies"
branch: feat/bun-test-crash
plan: knowledge-base/plans/2026-03-18-fix-bun-test-crash-missing-deps-plan.md
date: 2026-03-18
---

# Tasks: fix Bun test runner crash on missing dependencies

## Phase 1: Setup

- [ ] 1.1 Create root `bunfig.toml` with `[test]` section and `root = "."` to make test discovery scope explicit

## Phase 2: Core Implementation

- [ ] 2.1 Update `.github/workflows/ci.yml` to pin `bun-version: "1.3.11"` instead of `latest`
- [ ] 2.2 Add post-creation dependency install to `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - [ ] 2.2.1 Detect `package.json` in newly created worktree
  - [ ] 2.2.2 Run `bun install` if `node_modules/` is absent
  - [ ] 2.2.3 Print warning if `bun` is not available on PATH

## Phase 3: Testing

- [ ] 3.1 Verify `bun test` passes from repo root (13 files, 1136 tests, no segfault)
- [ ] 3.2 Verify `bunfig.toml` is picked up by Bun (check with `bun test --list`)
- [ ] 3.3 Verify `apps/telegram-bridge/bunfig.toml` coverage config still works (Bun merges configs)

## Phase 4: Documentation

- [ ] 4.1 Create learning: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`
  - Root cause: Bun 1.3.5 allocator panic on unresolvable imports
  - Fix: upgrade Bun + ensure `bun install` in worktree lifecycle
  - Prevention: pin Bun version in CI, auto-install deps on worktree creation
