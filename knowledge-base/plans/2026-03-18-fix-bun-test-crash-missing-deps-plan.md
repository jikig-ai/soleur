---
title: "fix: Bun test runner crash on missing dependencies"
type: fix
date: 2026-03-18
---

# fix: Bun test runner crash on missing dependencies

## Overview

`bun test` (v1.3.5) crashes with a segfault (`pas panic: deallocation did fail ... Large heap did not find object`) when test files import modules that are not installed. This occurs reliably in fresh git worktrees where `bun install` has not been run, and intermittently in other contexts where dependencies are partially missing.

The original hypothesis was that Bun recursively discovers duplicate test files inside `.worktrees/` directories. Investigation disproved this: `.worktrees/` is at the bare repo level, not inside individual worktree checkouts. The actual root cause is a Bun 1.3.5 bug where the test runner segfaults instead of reporting missing module errors during test file loading.

## Problem Statement

**Crash reproduction (deterministic):**

```bash
# In a fresh worktree (no node_modules)
bun test
# => [PID] pas panic: deallocation did fail at 0x100...: Large heap did not find object
# RSS spikes to 1.09GB before crash
```

**After `bun install`, tests pass reliably** -- 1136 tests across 13 files in ~3 seconds.

**Impact:**
- Every new worktree starts without `node_modules`, so the first `bun test` always crashes
- CI is unaffected (runs `bun install` before `bun test` in `ci.yml`)
- Developers lose time debugging a segfault that is actually "missing dependencies"
- The crash report URL points to a Bun internal bug, not user error

## Root Cause Analysis

1. **Bun 1.3.5 allocator bug:** When test files import unresolvable modules, Bun's heap allocator panics instead of producing a clean error message. This is a known class of Bun bugs fixed in later versions.

2. **Missing dependency guard:** There is no pre-flight check before `bun test` to ensure dependencies are installed. The root `package.json` has devDependencies (`@11ty/eleventy`, `markdown-it`, `yaml`) that test files transitively depend on.

3. **Worktree isolation:** Git worktrees share the git object store but not the working tree. Each worktree needs its own `bun install`. The existing learning `2026-02-26-worktree-missing-node-modules-silent-hang.md` documents a similar issue but for a different symptom (silent hang, not crash).

## Proposed Solution

### 1. Create root `bunfig.toml` with test discovery guard

Add a root-level `bunfig.toml` that restricts test discovery to prevent accidental traversal into unexpected directories. While `.worktrees/` is not the direct cause, the `bunfig.toml` provides defense-in-depth and a standard location for future test configuration.

**File: `bunfig.toml` (repo root)**

```toml
[test]
# Prevent test discovery from traversing into worktree directories
# (defense-in-depth -- worktrees are at the bare repo level, not inside checkouts,
# but this guards against layout changes)
root = "."
```

Note: Bun does NOT support `pathIgnorePatterns` for test discovery (only `coveragePathIgnorePatterns` for coverage). The `root` option is the only discovery-scoping mechanism. Since `.worktrees/` starts with a dot, Bun's default behavior already excludes it -- but the config makes the intent explicit.

### 2. Upgrade Bun from 1.3.5 to 1.3.11

Update the CI workflow to pin the latest stable version instead of `latest` (which is already 1.3.11). Pinning prevents surprise breakage from future Bun releases.

**File: `.github/workflows/ci.yml`**

```yaml
- name: Setup Bun
  uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
  with:
    bun-version: "1.3.11"
```

### 3. Add dependency check to worktree creation

The worktree-manager script should run `bun install` automatically after creating a new worktree, or at minimum warn when `node_modules/` is missing. This prevents the crash at the source.

**File: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`**

Add a post-creation step that checks for `package.json` and runs `bun install` if `node_modules/` is absent.

### 4. Document the fix as a learning

**File: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`**

Document that Bun 1.3.5 segfaults on missing dependencies instead of reporting a clean error, and that worktrees need `bun install` before testing.

## Acceptance Criteria

- [ ] Root `bunfig.toml` exists with `[test]` section documenting intent
- [ ] CI pins Bun to `1.3.11` instead of `latest`
- [ ] `bun test` passes reliably from repo root (13 files, 1136 tests)
- [ ] Worktree creation flow ensures `node_modules/` is populated
- [ ] Learning document captures the root cause and fix

## Test Scenarios

- Given a fresh worktree without `node_modules/`, when `bun install && bun test` runs, then all 1136 tests pass
- Given `bunfig.toml` at repo root, when `bun test` runs from root, then only 13 test files are discovered (not files from other worktrees)
- Given CI with `bun-version: "1.3.11"`, when the CI workflow runs, then tests pass without segfault

## Context

**Existing patterns:**
- `apps/telegram-bridge/bunfig.toml` -- per-app test config with coverage thresholds (keep as-is, Bun merges configs)
- `.github/workflows/ci.yml` -- currently uses `bun-version: latest`
- Learning: `2026-02-26-worktree-missing-node-modules-silent-hang.md` -- related prior incident

**Relevant files:**
- `package.json` (root) -- devDependencies needed by tests
- `.gitignore` -- already ignores `.worktrees`
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- worktree lifecycle

## References

- Bun crash report: `bun.report/1.3.5/lt11e86ceb...`
- Bun test discovery docs: `github.com/oven-sh/bun/blob/main/docs/test/discovery.mdx`
- Learning: `knowledge-base/project/learnings/technical-debt/2026-03-03-no-unified-test-runner-from-repo-root.md`
- Learning: `knowledge-base/project/learnings/implementation-patterns/2026-02-12-bun-coverage-threshold-config.md`
