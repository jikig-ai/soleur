---
title: "fix: worktree creation should install subdirectory dependencies"
type: fix
date: 2026-03-28
---

# fix: worktree creation should install subdirectory dependencies

After worktree creation, the `install_deps()` function in `worktree-manager.sh` only installs root-level dependencies (`$worktree_path/package.json`). Subdirectory packages like `apps/web-platform/` are skipped, causing `npx vitest run` and other app-level commands to fail with missing module errors or silent hangs.

This was reported during the sign-in fix session (#1213, #1219) where `npx vitest run` failed in a fresh worktree because `apps/web-platform/node_modules/` did not exist.

Two prior learnings document the same root cause:

- `2026-02-26-worktree-missing-node-modules-silent-hang.md` -- Eleventy hangs silently when `node_modules/` is missing; explicitly recommended adding install to worktree creation.
- `2026-03-18-bun-test-segfault-missing-deps.md` -- Added `install_deps()` for root-level deps but did not extend it to subdirectories.

## Current State

The existing `install_deps()` function (lines 137-162 of `worktree-manager.sh`):

1. Checks for `$worktree_path/package.json` -- exits early if absent.
2. Checks for `$worktree_path/node_modules` -- exits early if already present.
3. Requires `bun` to be available -- warns and returns if missing.
4. Runs `bun install --frozen-lockfile --cwd "$worktree_path"`.

The function is called in both `create_worktree()` (line 223) and `create_for_feature()` (line 280), but only for the root package.

## Proposed Fix

Extend `install_deps()` to also discover and install dependencies in subdirectories. The detection logic should be generic (scan for `package.json` files in known app directories) rather than hardcoded to `apps/web-platform/`.

### Implementation: `install_deps()` changes in `worktree-manager.sh`

After the existing root-level install logic, add a loop that:

1. Finds subdirectories under `apps/` containing a `package.json`.
2. Skips directories that already have `node_modules/`.
3. Detects the correct package manager per directory:
   - If `bun.lockb` exists: use `bun install --frozen-lockfile`.
   - If `package-lock.json` exists: use `npm ci` (deterministic, respects lockfile).
   - If neither lockfile exists: skip with a warning (no lockfile means nondeterministic install).
4. Runs the install command with `--cwd` or from the subdirectory.
5. Warns but never blocks worktree creation on failure (existing graceful degradation pattern).

### Lockfile inventory (current state)

| Directory | `package.json` | Lockfile | Package Manager |
|-----------|:-:|-----------|:-:|
| Root (`/`) | Yes | `package-lock.json` | npm |
| `apps/web-platform/` | Yes | `package-lock.json` | npm |
| `apps/telegram-bridge/` | Yes | None | Skip |

### Edge cases

- **No `bun` and no `npm`:** Warn and return. Never block worktree creation.
- **Network failure during install:** Warn and continue. The existing pattern already handles this.
- **`apps/` directory does not exist:** Skip subdirectory scan silently. Some worktrees (e.g., for plugin-only changes) may not have apps.
- **New apps added in the future:** The generic `apps/*/package.json` scan picks them up automatically.
- **Root install already failed:** If the root install failed (e.g., bun not found), still attempt subdirectory installs with npm if available, since subdirectories may use a different package manager.

## Acceptance Criteria

- [ ] `install_deps()` installs dependencies in `apps/*/` subdirectories that have both `package.json` and a lockfile
- [ ] Package manager is detected per directory: `bun.lockb` -> bun, `package-lock.json` -> npm
- [ ] Directories without a lockfile are skipped with a warning
- [ ] Directories with existing `node_modules/` are skipped
- [ ] Failures warn but never block worktree creation
- [ ] Both `create_worktree()` and `create_for_feature()` benefit (they already call `install_deps`)

## Test Scenarios

- Given a fresh worktree with `apps/web-platform/package.json` and `apps/web-platform/package-lock.json`, when `create_worktree` runs, then `npm ci` is executed in `apps/web-platform/` and `node_modules/` is created.
- Given a fresh worktree where `apps/web-platform/node_modules/` already exists, when `create_worktree` runs, then the subdirectory install is skipped.
- Given `apps/telegram-bridge/` with `package.json` but no lockfile, when `create_worktree` runs, then a warning is printed and install is skipped for that directory.
- Given neither `bun` nor `npm` is available, when `create_worktree` runs, then a warning is printed but worktree creation completes successfully.
- Given `npm ci` fails (e.g., network error), when `create_worktree` runs, then a warning is printed but worktree creation completes successfully.
- Given the `apps/` directory does not exist in the worktree, when `create_worktree` runs, then the subdirectory scan is skipped silently.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- Issue: [#1224](https://github.com/jikig-ai/soleur/issues/1224)
- File: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Session: sign-in fix (#1213, #1219)
- Learning: `2026-02-26-worktree-missing-node-modules-silent-hang.md`
- Learning: `2026-03-18-bun-test-segfault-missing-deps.md`

## References

- Related issue: #1224
- Related PRs: #1213, #1219
- Constitution: "Shell scripts must use `#!/usr/bin/env bash` shebang and declare `set -euo pipefail`"
- Constitution: "Shell functions must declare all variables with `local`; error messages go to stderr (`>&2`)"
- AGENTS.md: "Ensure all dependencies are installed at the correct package level (not just root) before running tests or CI"
