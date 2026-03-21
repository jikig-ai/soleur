---
title: "Fix: Handle Bare Repository Detection in worktree-manager.sh"
category: build-errors
tags:
  - git-worktree
  - bare-repository
  - initialization
  - git-rev-parse
module: git-worktree
severity: critical
date: 2026-03-13
---

# Learning: Bare repo breaks git rev-parse --show-toplevel

## Problem

`worktree-manager.sh cleanup-merged` fails at session startup with `fatal: this operation must be run in a work tree` (exit code 128). The script calls `git rev-parse --show-toplevel` at global scope (line 20), which doesn't work when `core.bare = true`.

Soleur intentionally uses `core.bare = true` to prevent accidental commits to main — all work happens in worktrees. This means the session-start instruction in AGENTS.md (`bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`) always runs from the bare repo root.

## Solution

Replace the unconditional `--show-toplevel` with bare repo detection:

```bash
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  _git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null)
  if [[ "$_git_dir" == */.git ]]; then
    GIT_ROOT="${_git_dir%/.git}"
  else
    GIT_ROOT="$_git_dir"
  fi
else
  GIT_ROOT=$(git rev-parse --show-toplevel)
fi
```

The `--absolute-git-dir` returns the `.git` directory path. For repos with a `.git` subdirectory (like this one), strip the suffix to get the repo root. For true bare repos (where the git dir IS the root), use it directly.

## Key Insight

`git rev-parse --show-toplevel` assumes a working tree exists. In bare repos, use `--is-bare-repository` to detect the repo type and `--absolute-git-dir` to derive the root. Other scripts in the codebase use `|| pwd` or `|| "."` fallbacks which survive but may resolve to wrong paths in edge cases.

## Session Errors

1. `worktree-manager.sh cleanup-merged` exit code 128 — the bug itself
2. Cascading cancellation of parallel `gh issue view` call

## Related

- `knowledge-base/project/learnings/2026-02-22-cleanup-merged-path-mismatch.md` — prior worktree path issues
- `knowledge-base/project/learnings/2026-02-17-worktree-not-enforced-for-new-work.md` — worktree enforcement history

## Tags

category: build-errors
module: git-worktree
