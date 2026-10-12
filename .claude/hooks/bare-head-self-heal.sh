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
# The repair happens only when ALL of these hold, checked cheapest-first:
#   1. `dir` is a repository ROOT in this layout: `<dir>/.git` is a real directory (not a file or
#      symlink, so a `gitdir:` redirect and a linked worktree both fail here), git resolves to
#      exactly that directory, and `core.bare` reads `true` from its config FILE. Bareness is read
#      from the file, never from `--is-bare-repository`: ADR-173 records that under a masked config
#      the command reports `true` for any normal clone. A true-bare repo (`git init --bare`, a
#      mirror or server repo) is deliberately out of scope: it is not this layout.
#   2. HEAD is symbolic and names a BRANCH (`refs/heads/*`)
#   3. that ref does not EXIST (`show-ref --verify` rc 1). rc 128 means the ref exists but its
#      object is missing or corrupt: that is a real corruption signal and is left untouched
#   4. refs/heads/main exists
# The write runs with hooks and fsmonitor disabled, so a repository-controlled
# `reference-transaction` hook cannot run code as a side effect of a session start. A failed write
# (HEAD.lock held, read-only fs) exits 0 with NO marker: a marker claims a repair that happened.
# Two sessions racing both write the same value; idempotent by construction.
#
# No `set -e`, by design: every step is an explicit `|| exit 0`.
set -uo pipefail

# An inherited git-location variable overrides `cd` and `git -C` alike, and would aim every call
# below at a different repository than the one named.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

dir="${1:-$PWD}"
cd -- "$dir" 2>/dev/null || exit 0
root=$(pwd -P) || exit 0

[[ -d "$root/.git" && ! -L "$root/.git" ]] || exit 0
[[ "$(git config --file "$root/.git/config" --get core.bare 2>/dev/null)" == "true" ]] || exit 0
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
[[ "$git_dir" == "$root/.git" ]] || exit 0

old=$(git symbolic-ref -q HEAD 2>/dev/null) || exit 0
[[ "$old" == refs/heads/* ]] || exit 0

rc=0
git show-ref --verify -q "$old" 2>/dev/null || rc=$?
[[ "$rc" -eq 1 ]] || exit 0
git show-ref --verify -q refs/heads/main 2>/dev/null || exit 0

git -c core.hooksPath=/dev/null -c core.fsmonitor=false symbolic-ref HEAD refs/heads/main 2>/dev/null || exit 0

# The old ref name is read from `.git/HEAD` and enters agent context via the loader: keep only
# ref-name-safe ASCII (this also drops Unicode line/paragraph separators) and cap the length.
safe_old=$(printf '%s' "$old" | tr -cd 'A-Za-z0-9._/-' | cut -c1-200)
printf 'SOLEUR_BARE_HEAD_HEALED from=%s to=refs/heads/main\n' "$safe_old"
exit 0
