# Learning: git --git-common-dir vs --show-toplevel resolve different roots in worktrees

## Problem
Two shell scripts needed the shared repo root (where `.claude/` state files live), not the worktree-local root. A shared helper (`resolve-git-root.sh`) already existed but used `--show-toplevel`, which returns the worktree path in worktree contexts. Simply aliasing `PROJECT_ROOT="$GIT_ROOT"` after sourcing the helper would silently break both scripts when run from a worktree.

## Solution
Extended the helper with a second variable `GIT_COMMON_ROOT` using `git rev-parse --git-common-dir`:

```bash
_resolve_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [[ "$_resolve_common_dir" == */.git ]]; then
  GIT_COMMON_ROOT="${_resolve_common_dir%/.git}"
else
  GIT_COMMON_ROOT="$_resolve_common_dir"
fi
unset _resolve_common_dir
```

Key behaviors verified via live testing:

| Context | `--git-common-dir` returns | After `cd + pwd` | After `%/.git` strip |
|---|---|---|---|
| Normal repo | `.git` (relative) | `/repo/.git` | `/repo` |
| Bare repo (`repo.git`) | `.` (relative) | `/path/repo.git` | no-op |
| Worktree of bare repo | `/repo/.git` (absolute) | `/repo/.git` | `/repo` |

The `cd + pwd` pattern is necessary because `--git-common-dir` may return relative paths.

## Key Insight
`--show-toplevel` and `--git-common-dir` are not interchangeable. In non-worktree repos they resolve to the same place, but in worktrees they diverge. Any script that needs a path shared across all worktrees (state files, config) must use `--git-common-dir`, not `--show-toplevel`. The helper now exposes both: `GIT_ROOT` for worktree-local paths, `GIT_COMMON_ROOT` for shared paths.

## Tags
category: shell-scripts
module: resolve-git-root
