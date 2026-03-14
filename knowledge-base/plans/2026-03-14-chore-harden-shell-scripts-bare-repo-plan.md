---
title: "chore: harden remaining shell scripts for bare repo context"
type: chore
date: 2026-03-14
semver: patch
---

# chore: harden remaining shell scripts for bare repo context

## Enhancement Summary

**Deepened on:** 2026-03-14
**Sections enhanced:** 7
**Review perspectives applied:** code-simplicity, security, pattern-recognition, spec-flow-analysis, learnings (shell-script-defensive-patterns, bash-arithmetic-and-test-sourcing-patterns, bare-repo-stale-files, bare-repo-git-rev-parse-failure)

### Key Improvements

1. Revised shared helper approach to avoid `source` path resolution problems -- the helper must resolve its own location via `BASH_SOURCE[0]` internally, not rely on consumers knowing where it lives
2. Identified critical test regression risk: the test file runs hooks via `bash "$HOOK"` inside temp git repos, so `source resolve-git-root.sh` must be resolvable from the hook's own directory (not CWD)
3. Added `trap`-based cleanup for `mktemp` in the atomic writes implementation (from shell-script-defensive-patterns learning)
4. Added `sync_bare_files` to worktree-manager.sh's own sync list (self-update bootstrapping problem)
5. Identified that `worktree-manager.sh` should also source the shared helper instead of keeping an inline copy (DRY applies to the original too)

### New Considerations Discovered

- The helper cannot use `set -euo pipefail` on its own (it would override the sourcing script's settings) -- it must be designed to be sourced, not executed
- Stale file cleanup in `sync_bare_files` must handle the case where `.claude/hooks/` directory does not exist on disk (first sync after adding hooks)
- The `sync` alias rename should be added to the `show_help()` output and the BARE REPO NOTE comment at the top of worktree-manager.sh

## Overview

Follow-up from worktree-manager.sh bare repo fix (PR #609). 11 shell scripts use `git rev-parse --show-toplevel` with `|| pwd` or `|| "."` fallbacks. They survive in bare repo context but may resolve to incorrect paths silently -- leading to .env files being written to the wrong directory, state files being created in unexpected locations, and `cd` commands failing.

This plan covers two work streams: (1) hardening the 11 scripts with proper IS_BARE detection, and (2) fixing medium/low-priority issues in worktree-manager.sh itself identified during PR #609 review.

## Problem Statement

`git rev-parse --show-toplevel` fails with exit 128 in bare repos (`core.bare=true`). Every script using this command either crashes or silently falls back to `pwd`/`"."`, which resolves to the bare repo root -- not a valid working tree. This causes:

- `.env` files written to the bare root instead of the project root (security: secrets in an unexpected location)
- Ralph loop state files created in the wrong `.claude/` directory
- `generate-article-30-register.sh` crashes with `cd` to non-existent working tree
- Welcome hook sentinel check fails silently, re-welcoming every session

### Research Insights

**Security (from security-sentinel review):**
- The `.env` files written to bare root are a credential exposure risk. If the bare root is served or shared differently from the working tree, secrets could be exposed. This elevates the community setup scripts (discord, x, bsky) from "cosmetic fix" to "security hardening."
- The `generate-article-30-register.sh` script generates GDPR-regulated content. A crash in bare context is acceptable (fail-closed), but the error message should be informative.

**Pattern consistency (from pattern-recognition review):**
- All 7 Category 1 scripts use one of two patterns: `PROJECT_ROOT=$(... 2>/dev/null) || PROJECT_ROOT="."` or `repo_root="$(... 2>/dev/null || pwd)"`. After this change, all should use the identical `source` + variable assignment pattern.
- The community scripts (discord, x, bsky) have nearly identical `cmd_write_env` and `cmd_verify` functions. The bare repo fix is a good opportunity to ensure consistency but not to refactor their shared structure (that would be scope creep).

## Proposed Solution

### Approach A: Shared `resolve-git-root.sh` helper (chosen)

Extract the IS_BARE detection pattern from worktree-manager.sh into a reusable helper script at `plugins/soleur/scripts/resolve-git-root.sh`. Each script sources the helper and gets `GIT_ROOT` and `IS_BARE` variables. Benefits:

- Single source of truth for bare repo detection logic
- DRY -- fixes propagate to all consumers automatically
- Consistent behavior across all scripts
- Minimal diff per script (replace 1 line with 1 `source` line + optional guard)

### Research Insights: Helper Design

**From bash-arithmetic-and-test-sourcing-patterns learning:**
The `BASH_SOURCE[0]` guard pattern (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) is the standard way to make bash scripts both sourceable and executable. The helper should NOT use this guard -- it is designed to be sourced only. But it should include a guard that prints a usage message if accidentally executed directly.

**Critical design constraints for the helper:**

1. **No `set -euo pipefail`** -- the helper is sourced into other scripts. Setting `set -e` would override the caller's error handling. The helper should only set variables.

2. **No `exit` statements** -- `exit` in a sourced script terminates the caller. Use `return` if validation fails.

3. **Self-resolving path** -- consumers should not need to know the relative path from their location to the helper. Instead, the helper should be located via `GIT_ROOT` itself. But this creates a chicken-and-egg problem: you need GIT_ROOT to find the helper, and the helper computes GIT_ROOT.

**Resolution of the chicken-and-egg problem:**

Option 1 (chosen): Each consumer computes `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and constructs the path to the helper relative to the known directory structure. This is reliable because each script knows its own location in the repo tree.

Option 2 (rejected): Inline the pattern. This was already rejected as Approach B.

**Concrete source pattern per script category:**

Hooks (`plugins/soleur/hooks/*.sh`):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/resolve-git-root.sh"
```

Scripts (`plugins/soleur/scripts/*.sh`):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/resolve-git-root.sh"
```

Community scripts (`plugins/soleur/skills/community/scripts/*.sh`):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/resolve-git-root.sh"
```

Top-level scripts (`scripts/*.sh`):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../plugins/soleur/scripts/resolve-git-root.sh"
```

### Approach B: Inline IS_BARE pattern in each script (rejected)

Copy the 7-line bare repo detection block into each script. Downside: 11 copies of the same logic that must be updated in sync.

## Technical Approach

### The shared helper (`plugins/soleur/scripts/resolve-git-root.sh`)

Exports two variables when sourced:

- `GIT_ROOT` -- absolute path to the repository root (bare or non-bare)
- `IS_BARE` -- `"true"` or `"false"`

Implementation matches the proven pattern from worktree-manager.sh lines 27-38.

### Research Insights: Helper Implementation

**Reference implementation (from worktree-manager.sh):**

```bash
# resolve-git-root.sh -- Sourceable helper to detect bare repos and resolve GIT_ROOT
# Usage: source this file. It sets GIT_ROOT and IS_BARE.
# Do NOT execute directly.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: resolve-git-root.sh must be sourced, not executed." >&2
  echo "Usage: source path/to/resolve-git-root.sh" >&2
  exit 1
fi

IS_BARE=false
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  IS_BARE=true
  _git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null)
  if [[ "$_git_dir" == */.git ]]; then
    GIT_ROOT="${_git_dir%/.git}"
  else
    GIT_ROOT="$_git_dir"
  fi
  unset _git_dir
else
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: Not inside a git repository." >&2
    return 1
  }
fi
```

**Key details:**
- `unset _git_dir` -- clean up the temporary variable to avoid polluting the caller's namespace
- `return 1` (not `exit 1`) -- sourced scripts must never call `exit`
- The `2>/dev/null` on `--is-bare-repository` handles the edge case where `git` is not installed or CWD is not a repo at all
- No `set` commands -- the caller controls strict mode

**From shell-script-defensive-patterns learning:**
- Validate that `GIT_ROOT` resolves to an actual directory after detection: `[[ -d "$GIT_ROOT" ]]`
- This catches the edge case where `--absolute-git-dir` returns a path that has been deleted or moved

### Script categories and required changes

**Category 1: Scripts that need GIT_ROOT for file paths (replace fallback)**

These scripts use `PROJECT_ROOT` or `repo_root` to locate `.env`, `.claude/`, or template files. Replace the fallback pattern with the sourced helper.

| Script | Variable | Current Pattern | Bare Behavior |
|--------|----------|----------------|---------------|
| `welcome-hook.sh` | `PROJECT_ROOT` | `\|\| PROJECT_ROOT="."` | Sentinel check uses `.` -- relative, fragile |
| `stop-hook.sh` | `PROJECT_ROOT` | `\|\| PROJECT_ROOT="."` | State file path uses `.` -- works if CWD is repo root, breaks otherwise |
| `setup-ralph-loop.sh` | `PROJECT_ROOT` | `\|\| PROJECT_ROOT="."` | State file created at `./.claude/` -- CWD dependent |
| `discord-setup.sh` (write-env) | `repo_root` | `\|\| pwd` | `.env` written to CWD, not repo root |
| `discord-setup.sh` (verify) | `repo_root` | `\|\| pwd` | `.env` sourced from CWD |
| `x-setup.sh` (write-env) | `repo_root` | `\|\| pwd` | `.env` written to CWD |
| `x-setup.sh` (verify) | `repo_root` | `\|\| pwd` | `.env` sourced from CWD |
| `bsky-setup.sh` (write-env) | `repo_root` | `\|\| pwd` | `.env` written to CWD |
| `bsky-setup.sh` (verify) | `repo_root` | `\|\| pwd` | `.env` sourced from CWD |

### Research Insights: Per-Script Details

**welcome-hook.sh (5 lines, trivial):**
The script checks for a sentinel file and creates it. In bare repo context, the sentinel should be at `$GIT_ROOT/.claude/soleur-welcomed.local`. The fix is mechanical: source helper, set `PROJECT_ROOT="$GIT_ROOT"`.

**stop-hook.sh (222 lines, most complex):**
This is the most sensitive script. It runs on every session stop. The `PROJECT_ROOT` is used only for locating the ralph-loop state file. No IS_BARE guard is needed because the ralph loop is valid in both contexts (a ralph loop started from a worktree still has its state file at the project root). The fix is mechanical: source helper, set `PROJECT_ROOT="$GIT_ROOT"`.

**setup-ralph-loop.sh (202 lines, moderate):**
Creates the ralph-loop state file. Uses `PROJECT_ROOT` for `mkdir -p "${PROJECT_ROOT}/.claude"` and the state file path. Fix is mechanical.

**Community scripts (discord-setup.sh, x-setup.sh, bsky-setup.sh):**
Each has two functions using `repo_root`. The `repo_root` variable is local to each function. After sourcing the helper at script top, replace each function's local `repo_root` assignment with `local repo_root="$GIT_ROOT"`.

**generate-article-30-register.sh (30 lines, simplest but needs guard):**
Uses `cd "$(git rev-parse --show-toplevel)"` to navigate to repo root. In bare context, the template file does not exist on disk (no working tree). The script should exit with a clear error. After sourcing, add:
```bash
if [[ "$IS_BARE" == "true" ]]; then
  echo "Error: Cannot generate Article 30 register from bare repo root." >&2
  echo "Run from a worktree: cd .worktrees/<name> && bash ../../scripts/generate-article-30-register.sh" >&2
  exit 1
fi
cd "$GIT_ROOT"
```

**Category 2: Scripts that `cd` to repo root (must guard or skip)**

| Script | Current Pattern | Required Change |
|--------|----------------|-----------------|
| `generate-article-30-register.sh` | `cd "$(git rev-parse --show-toplevel)"` | Use helper; guard with IS_BARE exit since the script needs a working tree to find the template |

### worktree-manager.sh improvements (from PR #609 review)

**Medium priority:**

1. **`create_draft_pr()` IS_BARE guard** -- Add `require_working_tree` call at the top of the function. `git commit --allow-empty` requires a working tree.

2. **`list_worktrees()` bare-context output** -- When IS_BARE is true, replace "Main repository" label with "Bare root (no working tree)" and suppress the `git rev-parse --abbrev-ref HEAD` call (returns misleading output).

3. **Add `.claude-plugin` to `sync_bare_files` file list** -- The plugin manifest is read by Claude Code from disk. Missing from the sync list means stale plugin config after merges.

### Research Insights: worktree-manager.sh

**`create_draft_pr()` (spec-flow analysis):**
The function currently has a guard against running on main/master but no IS_BARE guard. The `git commit --allow-empty` on line 586 would crash with "fatal: this operation must be run in a work tree" in bare context. `require_working_tree` (already defined) is the correct guard. Place it immediately after the main/master check.

**`list_worktrees()` (code-simplicity review):**
The "Main repository" section (lines 262-266) is the only part that needs an IS_BARE guard. Replace the entire block with:
```bash
echo ""
if [[ "$IS_BARE" == "true" ]]; then
  echo -e "${YELLOW}Bare root (no working tree):${NC}"
  echo "  Path: $GIT_ROOT"
else
  echo -e "${BLUE}Main repository:${NC}"
  local main_branch
  main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  echo "  Branch: $main_branch"
  echo "  Path: $GIT_ROOT"
fi
```

**`.claude-plugin` sync (pattern-recognition):**
Add `".claude-plugin"` to the `files=()` array alongside `plugin.json`. Also consider adding `marketplace.json` since it is also read from disk by the marketplace. But check whether `marketplace.json` exists in git HEAD first -- it may be CI-generated only.

**Should worktree-manager.sh also source the helper?**
Yes, but with a caveat: worktree-manager.sh is itself in the `sync_bare_files` list. If the helper is added to `sync_bare_files`, both files would be synced. The existing inline pattern in worktree-manager.sh should be replaced with `source` to the helper, and the helper should also be in the sync list. This is safe because `sync_bare_files` is called after the IS_BARE detection has already run.

Actually, reconsider: worktree-manager.sh runs at session start from the bare root. If it sources the helper, the helper must exist on disk. But on-disk files can be stale. The worktree-manager.sh IS_BARE detection MUST remain inline because it runs before any sync. The helper is for other scripts that run after worktree-manager.sh has already synced. This is a critical ordering dependency.

**Decision: keep IS_BARE detection inline in worktree-manager.sh, extract the helper for all other scripts, and add the helper to the sync list so the bare root always has a current copy.**

**Low priority:**

4. **Atomic file overwrites in `sync_bare_files`** -- Write to temp file with `mktemp`, then `mv` into place. Prevents truncated files if interrupted mid-write.

### Research Insights: Atomic Writes

**From shell-script-defensive-patterns learning:**
Use `trap` for temp file cleanup. The pattern is:

```bash
local tmpfile
tmpfile=$(mktemp "${GIT_ROOT}/${file}.XXXXXX")
trap 'rm -f "$tmpfile"' EXIT

if git show "HEAD:$file" > "$tmpfile" 2>/dev/null; then
  mv "$tmpfile" "$GIT_ROOT/$file"
  synced=$((synced + 1))
else
  rm -f "$tmpfile"
  echo -e "${YELLOW}Warning: Could not sync $file${NC}"
fi
```

**Important: `mktemp` location matters.** The temp file must be on the same filesystem as the target to ensure `mv` is atomic (same-filesystem rename is guaranteed atomic by POSIX). Using `mktemp` without a template creates the temp file in `$TMPDIR` (usually `/tmp`), which may be a different filesystem. Use `mktemp "$GIT_ROOT/$file.XXXXXX"` to ensure same-filesystem.

**Trap scope issue:** The `trap EXIT` in a function sets the trap for the entire shell process, not just the function. In a loop, only the last temp file would be cleaned up. Alternative: use a temp directory with a single trap:

```bash
local tmpdir
tmpdir=$(mktemp -d "${GIT_ROOT}/.sync-tmp.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

for file in "${files[@]}"; do
  local tmpfile="$tmpdir/$(basename "$file")"
  # ...
done
```

5. **Consolidate `.claude/settings.json` into `files=()` array** -- Remove the dedicated 7-line block and add the path to the main array. Add `mkdir -p` logic for paths with subdirectories.

### Research Insights: Settings Consolidation

The current dedicated block (lines 652-657) duplicates the same cat-file/mkdir/show pattern. Moving `.claude/settings.json` into the `files=()` array requires the sync loop to handle `mkdir -p "$(dirname ...)"` for paths containing subdirectories. This is already done on line 637 (`dir=$(dirname "$GIT_ROOT/$file"); mkdir -p "$dir"`), so it is already compatible.

6. **Rename `sync` alias to `sync-bare`** -- The `sync` alias in the case statement shadows the Unix `sync` command. Add `sync-bare` as the primary, keep `sync` as a secondary alias with a deprecation note.

7. **Stale file cleanup in `sync_bare_files`** -- Track which hook files exist in git HEAD and remove on-disk files that no longer exist. Prevents deleted hooks from continuing to execute.

### Research Insights: Stale File Cleanup

**Implementation approach:**

```bash
# After syncing hook files, remove stale ones
if [[ -d "$GIT_ROOT/.claude/hooks" ]]; then
  local git_hooks on_disk_hooks
  git_hooks=$(git ls-tree --name-only HEAD .claude/hooks/ 2>/dev/null | sed 's|.claude/hooks/||' || true)

  for on_disk_hook in "$GIT_ROOT/.claude/hooks"/*; do
    [[ -f "$on_disk_hook" ]] || continue
    local hook_name
    hook_name=$(basename "$on_disk_hook")
    if ! echo "$git_hooks" | grep -qx "$hook_name"; then
      rm "$on_disk_hook"
      echo -e "${YELLOW}Removed stale hook: $hook_name${NC}"
    fi
  done
fi
```

**Edge cases to handle:**
- `.claude/hooks/` directory does not exist on disk (first run) -- the glob produces no results, which is fine
- `.claude/hooks/` exists in git but has no files -- `git ls-tree` returns empty, which triggers removal of all on-disk hooks. This is correct behavior
- Non-hook files in the directory (e.g., `.DS_Store`) -- the cleanup should only remove `.sh` files or files that match the git list. Safer: only remove files that were previously synced (tracked via a manifest), but that adds complexity. Simpler: remove any file whose name is not in git HEAD. Accept that manually placed files will be removed (this is documented behavior for sync)

## Acceptance Criteria

- [ ] A shared `resolve-git-root.sh` helper exists at `plugins/soleur/scripts/resolve-git-root.sh`
- [ ] The helper uses `return` (not `exit`) for error paths and does not call `set`
- [ ] All 7 scripts listed in Category 1 source the helper instead of inline fallback patterns
- [ ] `generate-article-30-register.sh` uses the helper and exits cleanly in bare repo context with an informative error message
- [ ] `create_draft_pr()` has IS_BARE guard (calls `require_working_tree`)
- [ ] `list_worktrees()` shows "Bare root (no working tree)" instead of "Main repository" when bare
- [ ] `.claude-plugin` is in the `sync_bare_files` file list
- [ ] `resolve-git-root.sh` is in the `sync_bare_files` file list
- [ ] `sync_bare_files` uses atomic writes (mktemp on same filesystem + mv)
- [ ] Temp files from atomic writes are cleaned up via `trap EXIT`
- [ ] `.claude/settings.json` is consolidated into the `files=()` array
- [ ] `sync-bare` is the documented alias (with `sync` kept for backward compat)
- [ ] Stale hook files are cleaned up during sync
- [ ] worktree-manager.sh keeps inline IS_BARE detection (runs before sync, cannot depend on helper)
- [ ] All scripts pass `set -euo pipefail` (no regressions)
- [ ] Test file `ralph-loop-stuck-detection.test.sh` still works (it creates its own git repos via `git init`)

## Test Scenarios

- Given a bare repo root, when `welcome-hook.sh` runs, then the sentinel file is created at the correct bare root path (not `.`)
- Given a bare repo root, when `stop-hook.sh` runs with an active ralph loop, then the state file is found at the correct path
- Given a bare repo root, when `setup-ralph-loop.sh` runs, then `.claude/ralph-loop.local.md` is created under `GIT_ROOT`
- Given a bare repo root, when `discord-setup.sh write-env` runs, then `.env` is written to `GIT_ROOT`, not CWD
- Given a bare repo root, when `generate-article-30-register.sh` runs, then it exits with exit code 1 and a message mentioning "bare repo" and "worktree"
- Given a bare repo root, when `worktree-manager.sh draft-pr` runs, then it exits with `require_working_tree` error
- Given a bare repo root, when `worktree-manager.sh list` runs, then it shows "Bare root (no working tree)" instead of "Main repository"
- Given a bare repo root, when `worktree-manager.sh sync-bare-files` runs, then `.claude-plugin` is synced
- Given a bare repo root, when `sync_bare_files` is interrupted mid-write, then no target file is left truncated (atomic writes via same-filesystem mktemp + mv)
- Given a deleted hook script in git HEAD, when `sync_bare_files` runs, then the stale on-disk hook file is removed
- Given the existing test suite, when `ralph-loop-stuck-detection.test.sh` runs, then all tests pass (including tests 16-17 which run hooks from temp git repos)
- Given `resolve-git-root.sh` is executed directly (not sourced), then it prints a usage error and exits 1

### Research Insights: Test Regression Analysis

**Critical finding:** The test file `ralph-loop-stuck-detection.test.sh` (tests 16-17) creates temporary git repos with `git -C "$TEST_DIR" init -q` and runs hooks via `bash "$HOOK"`. The hooks currently use `git rev-parse --show-toplevel` which resolves to the temp dir. After the change, the hooks will `source` the helper. The helper path is resolved via `BASH_SOURCE[0]` which points to the hook's real location (not the temp dir), so the relative path to `resolve-git-root.sh` will still work. However, the helper's `git rev-parse --is-bare-repository` will execute in the temp dir's git context (which is a normal repo, not bare), so it will fall through to `--show-toplevel` and resolve to the temp dir. This is correct behavior -- the tests will pass without modification.

**Verification needed:** Run the test suite after implementation to confirm. The test creates a non-bare git repo, so the helper's bare detection path is never exercised in tests. This is acceptable because the tests are testing ralph-loop behavior, not bare repo detection.

## Non-Goals

- Refactoring scripts beyond what is needed for bare repo compatibility
- Adding bare repo support to the test file (`ralph-loop-stuck-detection.test.sh`) -- it creates its own git repos
- Changing how worktrees themselves work (worktrees have working trees by definition)
- Adding tests for the community setup scripts (they require API credentials)
- Refactoring worktree-manager.sh to source the shared helper (it must keep inline detection because it runs before sync)
- Refactoring the shared structure of community setup scripts (discord, x, bsky have similar patterns but that is a separate cleanup)

## Dependencies and Risks

**Dependencies:**
- PR #609 must be merged first (provides the baseline IS_BARE pattern) -- already merged as of this plan

**Risks:**

- **Source path resolution**: `source` in the helper needs a reliable path. Since hooks and scripts are invoked from various CWD locations, the helper must be located relative to `BASH_SOURCE[0]` of the consumer. Mitigation: each script category has a known relative path (documented above in "Concrete source pattern per script category").

- **Test regression**: The ralph loop test file creates temp git repos and runs hooks via `bash "$HOOK"`. The `source` path resolution works because `BASH_SOURCE[0]` resolves to the hook's real filesystem path, not the temp dir. Verified by tracing the path resolution for tests 16-17. Mitigation: run the test suite after implementation.

- **Ordering dependency**: worktree-manager.sh must keep inline IS_BARE detection because it runs at session start before any sync. The shared helper is for scripts that run after the bare root has been synced. Mitigation: documented in Non-Goals; worktree-manager.sh is excluded from the helper migration.

- **Trap scope in loops**: `trap EXIT` in `sync_bare_files` sets a process-level trap. If the function is called multiple times, the last trap wins. Mitigation: use a single temp directory for all files in a single `sync_bare_files` invocation, with one trap at function entry.

## References

- PR #609: worktree-manager.sh bare repo hardening
- GitHub Issue: #610
- Learning: `knowledge-base/learnings/2026-03-13-bare-repo-stale-files-and-working-tree-guards.md`
- Learning: `knowledge-base/learnings/2026-03-13-bare-repo-git-rev-parse-failure.md`
- Learning: `knowledge-base/learnings/2026-03-13-shell-script-defensive-patterns.md`
- Learning: `knowledge-base/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`
- Existing pattern: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` lines 27-38
- Test file: `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` (tests 16-17 exercise hook path resolution)
