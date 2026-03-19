---
title: "Bun 1.3.5 segfaults on missing dependencies instead of reporting errors"
date: 2026-03-18
category: runtime-errors
tags: [bun, testing, git-worktree, segfault, node-modules]
module: plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
---

# Learning: Bun 1.3.5 segfaults on missing dependencies instead of reporting errors

## Problem

Running `bun test` in a fresh git worktree (no `node_modules/`) crashes with a segfault instead of reporting missing modules:

```
panic(main thread): Segmentation fault at address 0x0
oh no: Bun has crashed. This indicates a bug in Bun, not your code.
```

RSS spikes to ~1.1GB before the allocator panic. The crash is intermittent even with deps present, but deterministic when `node_modules/` is absent. Every new worktree starts without `node_modules/`, so the first `bun test` in any worktree always crashes.

CI is unaffected because `ci.yml` runs `bun install` before `bun test`.

## Solution

Three-layer fix:

1. **Root cause (worktree-manager.sh):** Added `install_deps()` function that auto-installs dependencies via `bun install --frozen-lockfile` after worktree creation. Degrades gracefully if bun is unavailable or network fails. Inserted after `copy_env_files` in both `create_worktree()` and `create_for_feature()`.

2. **Defense-in-depth (bunfig.toml):** Created root `bunfig.toml` with `pathIgnorePatterns = [".worktrees/**"]` to explicitly exclude worktree directories from test discovery. Bun already skips dot-directories by default, but the explicit config guards against renames.

3. **CI hardening (ci.yml):** Pinned Bun to `1.3.11` instead of `latest` to prevent surprise breakage from future releases.

## Key Insight

Bun's test runner has a known class of allocator bugs where unresolvable module imports cause a segfault instead of a clean error message. The prior learning `2026-02-26-worktree-missing-node-modules-silent-hang.md` documented a related symptom (silent hang from missing deps) and explicitly recommended adding `npm install` to worktree creation -- this fix finally implements that recommendation.

**Rule of thumb:** Any post-creation hook in worktree-manager.sh (env files, deps) should degrade gracefully -- warn but never block worktree creation.
