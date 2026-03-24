---
title: "fix: test isolation failures when running global bun test from worktrees"
type: fix
date: 2026-03-24
---

# fix: test isolation failures when running global bun test from worktrees

## Overview

Two test files break when run via `bun test` (global) from a git worktree, despite passing in isolation. The `bun-test` lefthook pre-commit hook triggers global `bun test` when any `.ts`/`.js` file is staged, which hits these failures and blocks commits from worktrees.

**Issue:** [#1089](https://github.com/jikig-ai/soleur/issues/1089)

## Problem Statement

### Problem 1: `pre-merge-rebase.test.ts` temp directory race

The test's `beforeAll` creates temp directories (`mkdtempSync`) then immediately clones between them. When Bun's test runner discovers and runs multiple test files in a single process (global `bun test`), file ordering and parallel test setup can cause the remote temp directory to be cleaned up or not yet initialized when the clone attempt occurs:

```
Setup failed: git clone /tmp/hook-test-remote-OeVKis /tmp/hook-test-local-8uR6yD exited 128:
fatal: repository '/tmp/hook-test-remote-OeVKis' does not exist
```

This correlates with the documented Bun FPE/spawn-count sensitivity (see `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`). The test passes when run in isolation because no other test suites are competing for process resources.

### Problem 2: `workspace.test.ts` git context leak

The `provisionWorkspace()` function calls `execFileSync("git", ["commit", "-m", "Initial workspace"], { cwd: workspacePath })`. When run from a worktree, git config inheritance from the parent repo can interfere with the test. The issue reports that this "destroyed the working tree in the `feat-blog-url-redirects` worktree" by accidentally committing to the worktree's feature branch.

The test file already has a comment acknowledging this: "Git init test skipped: Bun's test runner inherits the parent git context, causing `git init` in /tmp to reference the worktree repo."

### Problem 3: lefthook `bun-test` hook runs global `bun test`

The `lefthook.yml` `bun-test` pre-commit hook runs `bun test` (global) rather than `scripts/test-all.sh` (sequential per-directory). The sequential runner was specifically created to avoid the spawn-count FPE crash (see `scripts/test-all.sh` header comment). The `package.json` `test` script already points to `scripts/test-all.sh`, but the lefthook hook bypasses it.

## Proposed Solution

Three targeted fixes, each addressing one root cause:

### Fix 1: Isolate `pre-merge-rebase.test.ts` temp directories

Add `GIT_DIR` and `GIT_WORK_TREE` environment overrides to prevent git operations in temp directories from inheriting the parent worktree's git context. Ensure the `beforeAll` setup is resilient to concurrent test execution by:

- Using unique temp directory prefixes with `process.pid` to avoid collision
- Setting `GIT_DIR` explicitly in `spawnChecked` calls that operate on temp repos
- Adding defensive checks that the temp directories exist before cloning

**Files:** `test/pre-merge-rebase.test.ts`

### Fix 2: Isolate `workspace.test.ts` git operations

The `provisionWorkspace` function's `execFileSync("git", ...)` calls inherit the parent process's git environment. The test should set `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, and crucially `GIT_CEILING_DIRECTORIES` to prevent git from discovering the parent repo. Options:

- **Option A (test-side):** Set `GIT_CEILING_DIRECTORIES=/tmp` in the test's process.env before importing workspace.ts, so all git operations in `/tmp` subdirectories cannot traverse above `/tmp` to find the worktree's `.git`
- **Option B (production code):** Add environment isolation to `provisionWorkspace()` itself using `env` option in `execFileSync`

Option A is preferred -- it fixes the test without modifying production code. The production code runs inside Docker containers where there is no parent git repo.

**Files:** `apps/web-platform/test/workspace.test.ts`

### Fix 3: Change lefthook `bun-test` hook to use `scripts/test-all.sh`

Replace `run: bun test` with `run: bash scripts/test-all.sh` in the `bun-test` pre-commit hook. This aligns the hook with:

- The `package.json` `test` script (already uses `scripts/test-all.sh`)
- The CI pipeline (uses sequential per-directory test execution)
- The documented workaround for Bun's FPE spawn-count sensitivity

**Files:** `lefthook.yml`

## Acceptance Criteria

- [ ] `bun test` from a worktree root passes all tests (or at minimum, `pre-merge-rebase.test.ts` and `workspace.test.ts` do not fail due to isolation issues)
- [ ] `bun test test/pre-merge-rebase.test.ts` continues to pass in isolation
- [ ] `bun test apps/web-platform/test/workspace.test.ts` continues to pass in isolation
- [ ] `scripts/test-all.sh` continues to pass
- [ ] The lefthook `bun-test` pre-commit hook runs `scripts/test-all.sh` instead of `bun test`
- [ ] Committing `.ts`/`.js` files from a worktree no longer fails due to test isolation issues
- [ ] `workspace.test.ts` git operations do not leak into the worktree's git context (verified by checking no unexpected commits appear on the feature branch after test run)

## Test Scenarios

- Given a git worktree with staged `.ts` files, when `git commit` triggers the `bun-test` lefthook, then all tests pass without isolation failures
- Given `pre-merge-rebase.test.ts` running alongside other test files via `bun test`, when `beforeAll` creates temp git repos, then the temp directories are properly isolated and do not collide
- Given `workspace.test.ts` running from a worktree, when `provisionWorkspace()` calls `git init` and `git commit` in `/tmp`, then git operations do not affect the worktree's feature branch
- Given no staged `.ts`/`.js` files, when committing from a worktree, then the `bun-test` hook does not trigger (existing behavior preserved)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

### Existing Mitigations

The `scripts/test-all.sh` sequential runner already exists as the solution for Bun's FPE crash. The `bunfig.toml` excludes `.worktrees/**` from test discovery. The `pre-merge-rebase.test.ts` already uses `GIT_CONFIG_NOSYSTEM` and `GIT_CONFIG_GLOBAL=/dev/null` -- but not `GIT_CEILING_DIRECTORIES` or `GIT_DIR` isolation.

### Related Learnings

- `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` -- FPE crash from subprocess spawn count; motivates sequential test runner
- `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md` -- segfault from missing node_modules in worktrees
- `knowledge-base/project/learnings/2026-03-20-bun-segfault-leaked-setinterval-timers.md` -- segfault from timer leaks; demonstrates test cleanup patterns
- `knowledge-base/project/learnings/2026-03-20-test-dependency-guard-pattern.md` -- conditional test skipping pattern

### MVP

#### test/pre-merge-rebase.test.ts

Add process isolation to prevent temp directory collisions:

```typescript
// In GIT_ENV, add ceiling to prevent parent repo discovery
const GIT_ENV = {
  ...process.env,
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CEILING_DIRECTORIES: tmpdir(),
};
```

#### apps/web-platform/test/workspace.test.ts

Add git isolation before imports:

```typescript
import { tmpdir } from "os";
process.env.GIT_CEILING_DIRECTORIES = tmpdir();
```

#### lefthook.yml

```yaml
bun-test:
  priority: 5
  glob: "*.{ts,tsx,js,jsx}"
  run: bash scripts/test-all.sh
```

## References

- Issue: [#1089](https://github.com/jikig-ai/soleur/issues/1089)
- Sequential test runner: `scripts/test-all.sh`
- Lefthook config: `lefthook.yml`
- Bun FPE learning: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
