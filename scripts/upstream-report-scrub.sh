#!/usr/bin/env bash
# Assert that a body destined for a THIRD PARTY'S PUBLIC repository carries none of
# the four exposure categories this repo's plan named (#7490): absolute home paths in
# either spelling, the names and layout of unrelated local repositories, install
# timestamps, and machine identifiers.
#
# WHY THIS IS A SCRIPT AND NOT A GREP IN A DOCUMENT. The obvious form is to write the
# grep into the document it checks. That does not work: the pattern literals inside
# the command match THEMSELVES, so the document fails its own scrub for containing a
# description of the scrub. Measured — the first draft of upstream-reports.md failed
# on exactly two lines, both of which were the check, not a leak. Holding the pattern
# in one executable place also means the posted-body re-check and the local check run
# the SAME predicate, which is the property that actually matters: the local copy is
# not evidence about the posted body, so both have to be judged identically.
#
# Usage:
#   upstream-report-scrub.sh <file> [<file>...]
#   gh api repos/<o>/<r>/issues/comments/<id> --jq .body | upstream-report-scrub.sh -
#
# Exit: 0 = clean. 1 = at least one exposure (each is printed). 2 = could not run.

set -euo pipefail

# Each entry is <label>|<ERE>. Kept as data so a new category is one line, and so the
# labels can name the CATEGORY rather than the regex when reporting a hit — an
# operator reading "unrelated local repository path" acts faster than one reading a
# character class.
PATTERNS=(
  'absolute home path|/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+'
  'tilde-form claude state path|~/\.claude'
  'local repository layout|/git-repositories/'
  'install timestamp|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}'
)

[[ $# -ge 1 ]] || { echo "usage: $(basename "$0") <file> [<file>...]" >&2; exit 2; }
command -v grep >/dev/null 2>&1 || { echo "FATAL: grep unavailable" >&2; exit 2; }

exposures=0
files=0

scan_one() { # <display-name> <path>
  local name="$1" path="$2" entry label ere hits
  files=$((files + 1))
  for entry in "${PATTERNS[@]}"; do
    label="${entry%%|*}"
    ere="${entry#*|}"
    # Read the FILE directly rather than piping into grep: under `set -o pipefail` a
    # `producer | grep -q` closes the pipe on first match, the producer takes SIGPIPE,
    # and the pipeline reports failure even though the match succeeded. `-c` also
    # reads all input rather than short-circuiting.
    hits="$(grep -cE -- "$ere" "$path" 2>/dev/null || true)"
    [[ -n "$hits" ]] || hits=0
    if [[ "$hits" -gt 0 ]]; then
      exposures=$((exposures + hits))
      printf 'EXPOSURE [%s] %s: %s hit(s)\n' "$label" "$name" "$hits" >&2
      grep -nE -- "$ere" "$path" 2>/dev/null | head -5 | sed 's/^/    /' >&2
    fi
  done
}

tmp=""
# The `|| true` is load-bearing, not defensive noise. An EXIT trap whose LAST command
# returns non-zero overrides the script's exit status in bash, so the bare
# `[[ ... ]] && rm -f` form made every CLEAN run exit 1 while printing "SCRUB OK" --
# measured. A scrubber that reports success and exits failure is worse than one that
# does neither, because a caller gating on the exit code blocks on clean input and
# the operator is told it passed.
cleanup() {
  if [[ -n "$tmp" && -f "$tmp" ]]; then rm -f "$tmp" || true; fi
  return 0
}
trap cleanup EXIT

for target in "$@"; do
  if [[ "$target" == "-" ]]; then
    tmp="$(mktemp "${TMPDIR:-/var/tmp}/scrub-stdin.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
    cat > "$tmp"
    scan_one "<stdin>" "$tmp"
  else
    [[ -r "$target" ]] || { echo "FATAL: cannot read $target" >&2; exit 2; }
    scan_one "$target" "$target"
  fi
done

# A zero-file run must not read as clean: "nothing was scanned" and "nothing was
# found" are the same exit code otherwise, and only one of them is safe.
if [[ "$files" -eq 0 ]]; then
  echo "FATAL: no files scanned" >&2
  exit 2
fi

if [[ "$exposures" -gt 0 ]]; then
  printf 'SCRUB FAILED: %d exposure(s) in %d file(s)\n' "$exposures" "$files" >&2
  exit 1
fi

printf 'SCRUB OK: 0 exposures in %d file%s\n' "$files" "$([[ "$files" -eq 1 ]] || printf s)"
