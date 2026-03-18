#!/usr/bin/env bash

# resolve-git-root.sh -- Sourceable helper to detect bare repos and resolve GIT_ROOT
#
# Usage: source this file. It sets GIT_ROOT, GIT_COMMON_ROOT, and IS_BARE.
# Do NOT execute directly.
#
# Variables set:
#   GIT_ROOT        -- absolute path to the repository root (bare or non-bare)
#   GIT_COMMON_ROOT -- absolute path to the shared repo root across all worktrees
#                      (equals GIT_ROOT when not in a worktree)
#   IS_BARE         -- "true" or "false"
#
# On error (not inside a git repo), returns 1 without calling exit.
# Does not call set or modify the caller's shell options.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: resolve-git-root.sh must be sourced, not executed." >&2
  echo "Usage: source path/to/resolve-git-root.sh" >&2
  exit 1
fi

IS_BARE=false
if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
  IS_BARE=true
  _resolve_git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null)
  if [[ "$_resolve_git_dir" == */.git ]]; then
    GIT_ROOT="${_resolve_git_dir%/.git}"
  else
    GIT_ROOT="$_resolve_git_dir"
  fi
  unset _resolve_git_dir
else
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: Not inside a git repository." >&2
    return 1
  }
fi

# Validate that GIT_ROOT resolves to an actual directory
if [[ ! -d "$GIT_ROOT" ]]; then
  echo "Error: GIT_ROOT resolved to non-existent path: $GIT_ROOT" >&2
  return 1
fi

# Resolve common root (shared across worktrees)
# git rev-parse --git-common-dir returns the shared .git dir; may be relative,
# so cd+pwd resolves to absolute. Strip trailing /.git for the repo root.
_resolve_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [[ "$_resolve_common_dir" == */.git ]]; then
  GIT_COMMON_ROOT="${_resolve_common_dir%/.git}"
else
  GIT_COMMON_ROOT="$_resolve_common_dir"
fi
unset _resolve_common_dir
