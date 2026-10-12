#!/usr/bin/env bash
# bare-head-self-heal.sh [dir] — repair a bare repo root's dangling HEAD.
#
# Called from session-rules-loader.sh (SessionStart) as a child process, before the loader reads
# the branch for its `[session-context]` line. In this repo's layout the root has `core.bare=true`
# and every feature branch lives in a linked worktree; when a PR merges and its branch is deleted,
# the root's `.git/HEAD` can be left as `ref: refs/heads/<deleted-branch>`. git does not treat that
# as an error, but `git rev-parse HEAD` fails there, the branch line reads `HEAD`, and
# `worktree-manager.sh sync-bare-files` (`git read-tree HEAD`) cannot refresh the root's copies.
#
# Contract: always exits 0. Prints exactly one line,
#   SOLEUR_BARE_HEAD_HEALED from=<old-ref> to=refs/heads/main
# when — and only when — it performed the repair; prints nothing otherwise. Zero model tokens.
#
# The repair happens only when ALL of these hold, checked cheapest-first so a normal non-bare
# checkout costs one `git` fork:
#   1. the repo is bare (`--is-bare-repository`; `core.bare` alone is NOT enough, it reads `true`
#      inside linked worktrees too because the config is shared)
#   2. git-dir == git-common-dir (a worktree's HEAD is not the root's HEAD)
#   3. HEAD is symbolic (a detached HEAD is left alone)
#   4. the ref HEAD names does NOT resolve (a resolving HEAD — main or not — is never touched)
#   5. refs/heads/main exists (otherwise there is nothing safe to point at)
# A failed write (HEAD.lock held, read-only fs) exits 0 with NO marker: a marker claims a repair
# that happened. Two sessions racing both write the same value; idempotent by construction.
#
# No `set -e`, by design: every step is an explicit `|| exit 0`.
set -uo pipefail

dir="${1:-$PWD}"

[[ "$(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] || exit 0

git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[[ -n "$git_dir" && "$git_dir" == "$common_dir" ]] || exit 0

old=$(git -C "$dir" symbolic-ref -q HEAD 2>/dev/null) || exit 0
[[ "$old" == refs/* ]] || exit 0

if git -C "$dir" show-ref --verify -q "$old" 2>/dev/null; then
  exit 0
fi
git -C "$dir" show-ref --verify -q refs/heads/main 2>/dev/null || exit 0

git -C "$dir" symbolic-ref HEAD refs/heads/main 2>/dev/null || exit 0

# The old ref name is read from `.git/HEAD` and enters agent context via the loader: strip control
# characters and cap its length first.
safe_old=$(printf '%s' "$old" | tr -d '\000-\037\177' | cut -c1-200)
printf 'SOLEUR_BARE_HEAD_HEALED from=%s to=refs/heads/main\n' "$safe_old"
exit 0
