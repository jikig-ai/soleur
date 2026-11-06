#!/usr/bin/env bash
# Shared by tests/scripts/test-registry-d10-workflow-wiring.sh (W9) and
# tests/scripts/test-registry-pull-path-health.sh (the A2 exit-code loop): both derive the restore
# engine's exit codes from the engine itself, so they read one extractor instead of three copies.
# Both functions read the ENGINE TEXT on stdin and print one code per line, sorted and unique.
#
# EXIT 1 RULE (identical in both suites): the codes a suite exercises are the header's non-zero
# codes UNION {1}, deduped, so exit 1 is tested whether or not the header lists it. The union is kept
# as a defence. The header lists 1 and the workflow has its arm for it, and the wiring suite's
# header-vs-emit-sites comparison covers 1 like any other code, so dropping the header row for 1,
# or every emit site for 1, turns that suite red.

# The non-zero codes of the engine's leading header table. A row is `#   N  LABEL` (two or more
# spaces after the code, which prose such as `#   1. as a REHEARSAL` or `#   10 attempts` lacks);
# the table ends at the first line that is neither a comment nor blank. Code 0 is the success row.
restore_header_codes() {
  awk '/^[^#]/ { exit } /^#[[:space:]]+[0-9]+[[:space:]][[:space:]]+[A-Za-z]/ { if ($2 != 0) print $2 }' | sort -un
}

# The non-zero codes at the engine's own `die N` / `exit N` sites, comments stripped. LITERAL
# codes only, written with a single space (`die 7`): a computed `die "$x"` or `exit $((n))` is
# not seen by this function. The wiring suite covers such sites separately (w9_computed_sites);
# the pull-path-health A2 loop does not.
restore_emit_codes() {
  grep -vE '^[[:space:]]*#' | grep -oE '(^|[^A-Za-z0-9_])(die|exit) [0-9]+' | grep -oE '[0-9]+$' | sort -un | grep -vx 0
}
