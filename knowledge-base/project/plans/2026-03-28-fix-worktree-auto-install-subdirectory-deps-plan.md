---
title: "fix: worktree creation should install subdirectory dependencies"
type: fix
date: 2026-03-28
deepened: 2026-03-28
---

## Enhancement Summary

**Deepened on:** 2026-03-28
**Sections enhanced:** 3 (Proposed Fix, Edge cases, Test Scenarios)
**Research sources:** constitution.md shell conventions, existing `copy_env_files` pattern, `npm ci` semantics, `set -euo pipefail` audit vectors

### Key Improvements

1. Added reference implementation with concrete code for the enhanced `install_deps()` function
2. Identified null-glob safety requirement under `set -euo pipefail` (constitution line 27, vector 2) and the existing `[[ -f ]]` guard pattern from `copy_env_files()`
3. Added `yarn.lock` detection for completeness and future-proofing
4. Clarified `npm ci` semantics: it deletes `node_modules/` before install, so the existing `node_modules/` skip check prevents unnecessary reinstalls

### New Considerations Discovered

- The existing `install_deps()` is bun-only -- the root package uses `package-lock.json` (npm), so the root install currently uses bun even though the lockfile is npm. This is a pre-existing inconsistency but out of scope for this fix.
- `npm ci` requires `package-lock.json` to be in sync with `package.json`; out-of-sync lockfiles will fail, which is the correct behavior for deterministic installs in worktrees.

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

### Reference Implementation

Add the following block at the end of the existing `install_deps()` function, after the root-level install logic (after line 161):

```bash
  # --- Subdirectory dependency install ---
  # Scan apps/*/ for package.json files and install per-directory.
  # Follows the same null-glob-safe pattern as copy_env_files().
  local app_dir
  for app_dir in "$worktree_path"/apps/*/; do
    [[ -d "$app_dir" ]] || continue
    [[ -f "$app_dir/package.json" ]] || continue
    [[ -d "$app_dir/node_modules" ]] && continue

    local app_name
    app_name=$(basename "$app_dir")

    local install_cmd=""
    if [[ -f "$app_dir/bun.lockb" ]]; then
      if command -v bun &>/dev/null; then
        install_cmd="bun install --frozen-lockfile --cwd $app_dir"
      else
        echo -e "  ${YELLOW}Warning: $app_name has bun.lockb but bun not found -- skip${NC}"
        continue
      fi
    elif [[ -f "$app_dir/package-lock.json" ]]; then
      if command -v npm &>/dev/null; then
        install_cmd="npm ci --prefix $app_dir"
      else
        echo -e "  ${YELLOW}Warning: $app_name has package-lock.json but npm not found -- skip${NC}"
        continue
      fi
    elif [[ -f "$app_dir/yarn.lock" ]]; then
      if command -v yarn &>/dev/null; then
        install_cmd="yarn install --frozen-lockfile --cwd $app_dir"
      else
        echo -e "  ${YELLOW}Warning: $app_name has yarn.lock but yarn not found -- skip${NC}"
        continue
      fi
    else
      echo -e "  ${YELLOW}Warning: $app_name has package.json but no lockfile -- skip${NC}"
      continue
    fi

    echo -e "${BLUE}Installing dependencies for $app_name...${NC}"
    local app_install_output
    if app_install_output=$($install_cmd 2>&1); then
      echo -e "  ${GREEN}$app_name dependencies installed${NC}"
    else
      echo -e "  ${YELLOW}Warning: $app_name install failed -- run manually${NC}" >&2
      echo "  $app_install_output" >&2
    fi
  done
```

**Implementation notes:**

- The `for app_dir in "$worktree_path"/apps/*/` pattern with trailing `/` ensures only directories match. The `[[ -d "$app_dir" ]]` guard handles the null-glob case where no matches exist (bash expands the literal glob string, which is not a directory).
- All variables are declared with `local` per constitution.
- Warning messages go to stderr via `>&2` per constitution.
- `npm ci --prefix` sets the working directory for npm, equivalent to bun's `--cwd`.
- `yarn.lock` detection is included for completeness even though no current app uses yarn.
- The `command -v` check is done per-directory, not once globally, because different subdirectories may use different package managers and only one needs to be available.

### Lockfile inventory (current state)

| Directory | `package.json` | Lockfile | Package Manager |
|-----------|:-:|-----------|:-:|
| Root (`/`) | Yes | `package-lock.json` | npm |
| `apps/web-platform/` | Yes | `package-lock.json` | npm |
| `apps/telegram-bridge/` | Yes | None | Skip |

### Edge cases

- **No `bun` and no `npm`:** Warn and return. Never block worktree creation.
- **Network failure during install:** Warn and continue. The existing pattern already handles this.
- **`apps/` directory does not exist:** Skip subdirectory scan silently. The `for app_dir in "$worktree_path"/apps/*/` glob expands to the literal string when no matches exist; the `[[ -d "$app_dir" ]]` guard catches this (same pattern as `copy_env_files`).
- **New apps added in the future:** The generic `apps/*/package.json` scan picks them up automatically.
- **Root install already failed:** If the root install failed (e.g., bun not found), still attempt subdirectory installs with npm if available, since subdirectories may use a different package manager.
- **`npm ci` vs `npm install`:** `npm ci` deletes existing `node_modules/` and installs from `package-lock.json` exactly. The `[[ -d "$app_dir/node_modules" ]] && continue` check prevents unnecessary reinstalls on re-runs. `npm ci` will fail if `package-lock.json` is out of sync with `package.json`, which is correct behavior (nondeterministic installs are worse than a warning).
- **`set -euo pipefail` safety (constitution line 27):** The `for ... in glob` pattern does not trigger `pipefail` or `-e` when no matches exist because there is no pipeline or command exit code -- the shell just expands the glob literally. The `[[ -d ]]` guard handles the literal expansion. No `|| true` needed here, unlike `grep` in pipelines.

## Acceptance Criteria

- [x] `install_deps()` installs dependencies in `apps/*/` subdirectories that have both `package.json` and a lockfile
- [x] Package manager is detected per directory: `bun.lockb` -> bun, `package-lock.json` -> npm
- [x] Directories without a lockfile are skipped with a warning
- [x] Directories with existing `node_modules/` are skipped
- [x] Failures warn but never block worktree creation
- [x] Both `create_worktree()` and `create_for_feature()` benefit (they already call `install_deps`)

## Test Scenarios

- Given a fresh worktree with `apps/web-platform/package.json` and `apps/web-platform/package-lock.json`, when `create_worktree` runs, then `npm ci` is executed in `apps/web-platform/` and `node_modules/` is created.
- Given a fresh worktree where `apps/web-platform/node_modules/` already exists, when `create_worktree` runs, then the subdirectory install is skipped.
- Given `apps/telegram-bridge/` with `package.json` but no lockfile, when `create_worktree` runs, then a warning is printed and install is skipped for that directory.
- Given neither `bun` nor `npm` is available, when `create_worktree` runs, then a warning is printed but worktree creation completes successfully.
- Given `npm ci` fails (e.g., network error), when `create_worktree` runs, then a warning is printed but worktree creation completes successfully.
- Given the `apps/` directory does not exist in the worktree, when `create_worktree` runs, then the subdirectory scan is skipped silently.
- Given a future app with `yarn.lock`, when `create_worktree` runs and `yarn` is available, then `yarn install --frozen-lockfile` is used.
- Given `install_deps` is called a second time on the same worktree (re-run), when `apps/web-platform/node_modules/` already exists, then the install is skipped (no unnecessary `npm ci` that would delete and recreate `node_modules/`).

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
