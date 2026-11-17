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
# A name holding a newline cannot be one line of a one-name-per-line list (it would split into extra "paths", and a
# gate that ALLOWS on a match can be satisfied by a fragment), so such a diff exits 2: callers treat 2 as unknown and
# fail closed. Output-format flags (-s, --output, -q, --exit-code, ...) are refused for the same reason: they leave
# stdout empty at rc 0, which a caller would read as "nothing changed".
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

# ALLOWLIST of options: revs and paths (anything not starting with `-`), `--cached`/`--staged`/`--merge-base`/`--diff-filter=*`,
# and everything after `--`. Every other option is refused (exit 2): output-format flags leave stdout empty or corrupt the
# list at rc 0 (-s, --output, -q, --exit-code, bundled `-ps`), and flags appended after the baked-in ones win in git, so
# `-M`/`-C`/`--find-renames`/`--ignore-submodules=all` would silently re-enable the rename and submodule hiding this helper
# exists to remove.
for a in "$@"; do
  case "$a" in
    --) break ;;
    --cached|--staged|--merge-base|--diff-filter=*) ;;
    -*) usage ;;
  esac
done

if ! top="$(git rev-parse --show-toplevel 2>/dev/null)" || [ -z "$top" ]; then
  printf 'changed-paths: not inside a git work tree\n' >&2
  exit 2
fi

# The raw NUL stream goes to a temp file FIRST, so a git failure is a failure (never an empty list) and the bytes can be
# inspected before any LF-splitting. An unwritable TMPDIR is also rc 2: unknown, never "none match".
if ! tmp="$(mktemp 2>/dev/null)" || [ -z "$tmp" ]; then
  printf 'changed-paths: cannot create a temp file\n' >&2
  exit 2
fi
trap 'rm -f "$tmp"' EXIT
if ! git -C "$top" diff -z --no-renames --ignore-submodules=none --name-only "$@" >"$tmp"; then
  printf 'changed-paths: git diff failed\n' >&2
  exit 2
fi

# Byte locale throughout: the list is raw bytes now, and under a UTF-8 locale GNU grep reports a name holding an
# invalid UTF-8 byte as "binary file matches" instead of printing it.
if [ "$(LC_ALL=C tr -dc '\n' <"$tmp" | wc -c)" -gt 0 ]; then
  printf 'changed-paths: a changed path contains a newline; it cannot be listed one per line\n' >&2
  exit 2
fi
out="$(LC_ALL=C tr '\0' '\n' <"$tmp")"

if [ "$have_match" -eq 0 ]; then
  # A failed write (full disk, closed pipe) is a failure: a truncated list at rc 0 reads as a shorter diff.
  [ -z "$out" ] || printf '%s\n' "$out" || exit 2
  exit 0
fi

[ -n "$out" ] || exit 1
# printf into grep (no -q, so grep reads everything and never SIGPIPEs the writer); a here-string would spill to a
# temp file for a large list and an unwritable TMPDIR would skip grep entirely and read as rc 1.
printf '%s\n' "$out" | LC_ALL=C grep -E -e "$match"
exit $?
