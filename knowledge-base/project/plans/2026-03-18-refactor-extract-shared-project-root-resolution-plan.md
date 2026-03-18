---
title: "refactor: extract shared PROJECT_ROOT resolution into resolve-git-root.sh"
type: refactor
date: 2026-03-18
deepened: 2026-03-18
---

# refactor: extract shared PROJECT_ROOT resolution into resolve-git-root.sh

Closes #659

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 3 (Proposed Solution, Test Scenarios, Non-goals)

### Key Improvements

1. Verified `git rev-parse --git-common-dir` behavior across all repo configurations (bare, non-bare, worktree, bare-with-`.git`-dir) with live tests
2. Identified edge case where `--git-common-dir` returns `.` in standalone bare repos -- confirmed the `cd + pwd` pattern handles it correctly
3. Added implementation notes on `set -euo pipefail` interaction with the `source ... || { ... }` pattern
4. Documented future simplification opportunity for `worktree-manager.sh` (out of scope)

## Overview

`plugins/soleur/hooks/stop-hook.sh` and `plugins/soleur/scripts/setup-ralph-loop.sh` both duplicate a 5-line `--git-common-dir` pattern to resolve the shared repo root (PROJECT_ROOT). A shared helper already exists at `plugins/soleur/scripts/resolve-git-root.sh` but it resolves a *different* path -- the worktree-local root (`--show-toplevel`), not the shared/common root (`--git-common-dir`). The helper must be extended before the two scripts can source it.

## Problem Statement

The duplicated pattern in both scripts:

```bash
_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd) || {
  # error handling differs: hook exits 0, setup exits 1
}
PROJECT_ROOT="${_common_dir%/.git}"
unset _common_dir
```

This resolves the **shared** repo root across all worktrees -- the parent bare repo, not the current worktree. The ralph loop state file must live at the shared root so the stop hook can find it regardless of which worktree the session runs in.

The existing `resolve-git-root.sh` helper sets `GIT_ROOT` via `--show-toplevel` (non-bare) or `--absolute-git-dir` (bare). In a worktree, `--show-toplevel` returns the worktree path (e.g., `.worktrees/feat-x/`), NOT the shared parent. So simply sourcing `resolve-git-root.sh` and aliasing `PROJECT_ROOT="$GIT_ROOT"` would break both scripts when run from a worktree.

### Key semantic difference

| Git command | Returns | In worktree `.worktrees/feat-x/` |
|---|---|---|
| `git rev-parse --show-toplevel` | Worktree root | `/repo/.worktrees/feat-x` |
| `git rev-parse --git-common-dir` | Shared .git dir | `/repo/.git` (or `/repo` if bare) |

Both ralph scripts need the **common** root, not the worktree root.

## Proposed Solution

Extend `resolve-git-root.sh` to also export `GIT_COMMON_ROOT` -- the shared repo root across all worktrees. Then refactor both scripts to source the helper and use `GIT_COMMON_ROOT` instead of inline resolution.

### Changes to `plugins/soleur/scripts/resolve-git-root.sh`

Add a new variable `GIT_COMMON_ROOT` after the existing `GIT_ROOT` resolution:

```bash
# Resolve common root (shared across worktrees)
_resolve_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [[ "$_resolve_common_dir" == */.git ]]; then
  GIT_COMMON_ROOT="${_resolve_common_dir%/.git}"
else
  GIT_COMMON_ROOT="$_resolve_common_dir"
fi
unset _resolve_common_dir
```

For non-worktree repos, `GIT_COMMON_ROOT == GIT_ROOT`. For worktrees, `GIT_COMMON_ROOT` points to the parent repo.

### Research Insights: `--git-common-dir` behavior by context

Verified via live testing:

| Context | `--git-common-dir` returns | After `cd + pwd` | After `%/.git` strip |
|---|---|---|---|
| Normal repo | `.git` (relative) | `/repo/.git` | `/repo` |
| Bare repo (`.git` dir) | `.git` (relative) | `/repo/.git` | `/repo` |
| Bare repo (`repo.git`) | `.` (relative) | `/path/repo.git` | `/path/repo.git` (no-op) |
| Worktree of bare repo | `/repo/.git` (absolute) | `/repo/.git` | `/repo` |
| Non-git directory | exits 128 | N/A (unreachable -- `GIT_ROOT` check returns 1 first) | N/A |

**Implementation notes:**

- The `cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd` pattern is necessary because `--git-common-dir` may return relative paths (`.git` or `.`). The `cd + pwd` resolves to absolute.
- The `GIT_COMMON_ROOT` resolution block only executes after `GIT_ROOT` succeeds, so the "not in a git repo" case is already handled.
- Under `set -euo pipefail` (used by both consumer scripts), `source resolve-git-root.sh || { exit N; }` works correctly: the `||` absorbs the `return 1` from the helper, preventing the `-e` trap from firing before the `||` branch executes.

### Changes to `plugins/soleur/hooks/stop-hook.sh`

Replace lines 13-20 (the inline `_common_dir` resolution) with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/resolve-git-root.sh" || {
  # Not in a git repo -- allow exit
  exit 0
}
PROJECT_ROOT="$GIT_COMMON_ROOT"
```

The error behavior is preserved: `resolve-git-root.sh` returns 1 on failure (does not exit), and the `|| { exit 0; }` catches that -- matching the hook's existing behavior of silently allowing exit when not in a git repo.

### Changes to `plugins/soleur/scripts/setup-ralph-loop.sh`

Replace lines 13-19 (the inline `_common_dir` resolution) with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/resolve-git-root.sh" || {
  echo "Error: Not inside a git repository." >&2
  exit 1
}
PROJECT_ROOT="$GIT_COMMON_ROOT"
```

The error behavior is preserved: exits 1 with an error message, matching the existing behavior.

### Path arithmetic verification

Per learnings from `2026-03-14-bare-repo-helper-extraction-patterns.md`, verify each `../` step:

- **stop-hook.sh** is at `plugins/soleur/hooks/stop-hook.sh`
  - `$SCRIPT_DIR` = `plugins/soleur/hooks/`
  - `../scripts/` = `plugins/soleur/scripts/` -- correct target

- **setup-ralph-loop.sh** is at `plugins/soleur/scripts/setup-ralph-loop.sh`
  - `$SCRIPT_DIR` = `plugins/soleur/scripts/`
  - `./resolve-git-root.sh` = `plugins/soleur/scripts/resolve-git-root.sh` -- correct target (same directory)

## Acceptance Criteria

- [ ] `resolve-git-root.sh` exports `GIT_COMMON_ROOT` in addition to `GIT_ROOT` and `IS_BARE`
- [ ] `GIT_COMMON_ROOT` equals `GIT_ROOT` when not in a worktree
- [ ] `GIT_COMMON_ROOT` points to the shared parent repo root when in a worktree
- [ ] `stop-hook.sh` sources `resolve-git-root.sh` instead of inline resolution
- [ ] `setup-ralph-loop.sh` sources `resolve-git-root.sh` instead of inline resolution
- [ ] Error behaviors are preserved: hook exits 0 on failure, setup exits 1
- [ ] Existing tests in `resolve-git-root.test.sh` still pass
- [ ] New tests cover `GIT_COMMON_ROOT` in worktree and non-worktree scenarios
- [ ] No temp variables leak into the caller's namespace

## Test Scenarios

- Given a normal (non-bare) repo, when `resolve-git-root.sh` is sourced, then `GIT_COMMON_ROOT` equals `GIT_ROOT`
- Given a bare repo with a `.git` directory, when `resolve-git-root.sh` is sourced, then `GIT_COMMON_ROOT` equals `GIT_ROOT`
- Given a worktree of a bare repo, when `resolve-git-root.sh` is sourced, then `GIT_COMMON_ROOT` points to the bare repo root and `GIT_ROOT` points to the worktree root
- Given a worktree of a non-bare repo, when `resolve-git-root.sh` is sourced, then `GIT_COMMON_ROOT` points to the parent repo root
- Given a subdirectory within a repo, when `resolve-git-root.sh` is sourced, then `GIT_COMMON_ROOT` resolves to the repo root (not the subdirectory)
- Given the stop hook is run outside a git repo, when it tries to source resolve-git-root.sh, then it exits 0 silently
- Given the setup script is run outside a git repo, when it tries to source resolve-git-root.sh, then it exits 1 with an error message
- Given the stop hook runs inside a worktree with an active ralph loop, when `PROJECT_ROOT` is resolved, then the state file path matches the one written by setup-ralph-loop.sh
- Given `GIT_COMMON_ROOT` is set, when checked, then it is a valid existing directory
- Given the helper is sourced, when `GIT_COMMON_ROOT` is set, then `_resolve_common_dir` is not leaked into the caller namespace

## Non-goals

- Refactoring `worktree-manager.sh` -- it has its own inline detection pattern with additional worktree-of-bare-repo logic (detecting bare-repo-parent from within a worktree and overriding `IS_BARE`/`GIT_ROOT`). The new `GIT_COMMON_ROOT` variable would partially serve this need, but worktree-manager also needs `IS_BARE=true` when running from a worktree of a bare repo, which `resolve-git-root.sh` does not detect (it sees `--is-bare-repository == false` inside worktrees). This is a valid future simplification but out of scope for this PR.
- Changing the behavior of `GIT_ROOT` for existing consumers (welcome-hook.sh, community scripts, generate-article-30-register.sh)
- Adding a CLI interface to `resolve-git-root.sh`

## Context

- Issue: #659
- Related PR: #654 (where the duplication was identified)
- Learnings: `knowledge-base/project/learnings/2026-03-14-bare-repo-helper-extraction-patterns.md`
- Existing consumers of `resolve-git-root.sh`: welcome-hook.sh, community scripts (discord/bsky/x-setup.sh), generate-article-30-register.sh
- Semver: `semver:patch` (no new capabilities, pure refactoring)

## References

- `plugins/soleur/scripts/resolve-git-root.sh` -- the shared helper to extend
- `plugins/soleur/hooks/stop-hook.sh:13-20` -- inline resolution to replace
- `plugins/soleur/scripts/setup-ralph-loop.sh:13-19` -- inline resolution to replace
- `plugins/soleur/test/resolve-git-root.test.sh` -- existing tests to extend
- `plugins/soleur/hooks/welcome-hook.sh:5-7` -- existing consumer (no changes needed)
