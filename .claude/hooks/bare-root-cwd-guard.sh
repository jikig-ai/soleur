#!/usr/bin/env bash
# bare-root-cwd-guard.sh [dir] — detect a session anchored at a bare repo ROOT (#10383).
#
# Called from session-rules-loader.sh (SessionStart) as a child process, after the corpus is
# read. In this repo's layout the root is a bare repository carrying a deliberately maintained
# sync_bare_files overlay of HEAD, which makes it look like a worktree: the readiness probe
# reports it READY by design (cleanup-merged legitimately runs there), the loader injects the
# corpus from it, and sessions anchored there accumulate scratch — a stray `.env` among them —
# and do file-touching work outside any branch. go.md's Step 1 guard only reaches sessions
# that route through /soleur:go; this arm is the session-start layer for every session that
# does not.
#
# Contract: always exits 0. On detection prints exactly one marker line
#   SOLEUR_BARE_ROOT_CWD source=session-start
# followed by a bounded [bare-root-cwd] redirect block; prints nothing otherwise.
#
# Detection is the SAME three-term config-FILE predicate as bare-head-self-heal.sh (and the
# copy inlined in plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh —
# plugins/soleur/test/git-repo-readiness-diag.test.sh pins the parity):
#   1. `dir` is a repository ROOT in this layout: `<dir>/.git` is a real directory (not a file
#      or symlink, so a `gitdir:` redirect and a linked worktree both fail here), git resolves
#      to exactly that directory, and `core.bare` reads `true` from its config FILE. Bareness
#      is read from the file, never from `--is-bare-repository`: ADR-173 records that under a
#      masked config the command reports `true` for any normal clone. A true-bare repo
#      (`git init --bare`, a mirror or server repo) is deliberately out of scope: it is not
#      this layout. `git config --file` reads only the named file, so a per-worktree
#      `core.bare` set solely in `config.worktree` is missed — consistent with the sibling and
#      with ADR-173's removal of `extensions.worktreeConfig`.
# Scope note: the predicate fires only when `dir` IS the root; a session anchored at a
# bare-root SUBDIRECTORY (e.g. plugins/soleur/) does not match the gitdir-identity term.
# That narrowing is deliberate (go.md:536's `--is-bare-repository` check covers in-bare
# subdirs at routing time); #10392 tracks the wider arm.
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
[[ "$(git config --file "$root/.git/config" --type=bool --get core.bare 2>/dev/null)" == "true" ]] || exit 0
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
[[ "$git_dir" == "$root/.git" ]] || exit 0

# Sanitize the path for display: it enters agent context via the loader, so strip control
# characters (incl. embedded newlines, which would inject lines into the block) and cap it.
safe_root=$(printf '%s' "$root" | tr -d '\000-\037' | cut -c1-200)

printf 'SOLEUR_BARE_ROOT_CWD source=session-start\n'
cat <<EOF
[bare-root-cwd] ${safe_root} is a bare repository root with a synced overlay of HEAD, not a worktree.
[bare-root-cwd] Route file-touching work through a linked worktree:
[bare-root-cwd]   bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create <name>
[bare-root-cwd] then cd into the new .worktrees/<name>/ path before editing.
[bare-root-cwd] Repo maintenance here is legitimate: git worktree list,
[bare-root-cwd] worktree-manager.sh cleanup-merged, the .mcp.json restore.
[bare-root-cwd] A .env at this root is NOT project configuration — do not read it as one.
EOF
exit 0
