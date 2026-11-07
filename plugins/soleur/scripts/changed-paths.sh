#!/usr/bin/env bash
# changed-paths.sh -- print the changed-path list of a `git diff` as EXACT, repo-root-relative names.
#
# USAGE
#   changed-paths.sh [--match ERE] <git diff args...>
#
#   changed-paths.sh origin/main...HEAD          every changed path, one per line
#   changed-paths.sh --cached                    the staged set
#   changed-paths.sh --match '^docs/' origin/main...HEAD   only the paths matching the ERE
#
# CONTRACT
#   Plain mode   exit 0 = the list (possibly empty) is on stdout; exit 2 = git failed or usage was wrong. On a
#                non-zero exit stdout is NOT a list and must not be read as "nothing changed".
#   --match ERE  grep exit semantics: 0 = at least one path matches (the matches are printed), 1 = none match,
#                2 = git or usage failure. A git failure is NEVER folded into "none match".
#   No arguments, or a flag this helper owns but does not support, exits 2 with a usage line on stderr; the helper never
#   defaults to a diff target of its own.
#
# WHY THIS CONSTRUCTION (#12332, reference fix #12326). A plain `git diff --name-only` is wrong for a `^`-anchored
# regex in four ways: (1) git C-quotes a name holding a non-ASCII byte, tab, `"` or `\`, so the quoted form never starts
# with the anchored prefix (`core.quotePath=false` fixes only bytes >= 0x80); (2) default rename detection lists only a
# rename's NEW path, so a rename AWAY from a gated surface is invisible; (3) a gitlink hidden by `diff.ignoreSubmodules`
# or a committed `ignore=all` is not listed; (4) a bare `$(git diff | tr)` pipe turns a git failure into an empty list.
# So: NUL-delimited (`-z`), `--no-renames`, `--ignore-submodules=none`, `git -C <top>` (so `diff.relative=true` cannot
# make the names cwd-relative), and `set -o pipefail` so a git failure is a failure. In `--match` mode git runs FIRST and
# its status is checked, then grep reads a here-string: never `grep -q` on a pipe (SIGPIPE 141 would read as failure).
#
# A name holding a newline splits into extra lines; that can only add a false positive, never hide the prefix line.
#
# WHEN TO USE THIS VERSUS THE INLINE FORM. Skill prose (preflight, ship, review) calls this helper: the inline form costs
# about twice the body bytes against ceilings that only ratchet down. Workflow steps and hooks stay INLINE
# (`git diff -z --no-renames --ignore-submodules=none --name-only ... | tr '\0' '\n'` inside a scoped pipefail capture)
# so a path-filtered gate never depends on a plugin script being present in the checkout it is judging.
#
# Pathspecs after `--` are relative to the repository root (the helper runs `git -C <top>`).
set -uo pipefail

usage() {
  printf 'usage: changed-paths.sh [--match ERE] <git diff args...>   (e.g. origin/main...HEAD, --cached)\n' >&2
  exit 2
}

match=""
have_match=0
if [ "$#" -eq 0 ]; then usage; fi
if [ "${1:-}" = "--match" ]; then
  [ "$#" -ge 3 ] || usage
  match="$2"
  have_match=1
  shift 2
fi

# Flags this helper owns and does not support, plus output-format flags that would corrupt the name list.
for a in "$@"; do
  case "$a" in
    --) break ;;
    --match|--match=*|-h|--help|-z|--name-only|--name-status|--raw|--stat|--stat=*|--numstat|--shortstat|--summary|-p|-u|--patch|--no-relative|--relative|--relative=*) usage ;;
  esac
done

if ! top="$(git rev-parse --show-toplevel 2>/dev/null)" || [ -z "$top" ]; then
  printf 'changed-paths: not inside a git work tree\n' >&2
  exit 2
fi

if ! out="$(set -o pipefail; git -C "$top" diff -z --no-renames --ignore-submodules=none --name-only "$@" | tr '\0' '\n')"; then
  printf 'changed-paths: git diff failed\n' >&2
  exit 2
fi

if [ "$have_match" -eq 0 ]; then
  [ -z "$out" ] || printf '%s\n' "$out"
  exit 0
fi

[ -n "$out" ] || exit 1
grep -E -e "$match" <<<"$out"
exit $?
