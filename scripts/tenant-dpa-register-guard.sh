#!/usr/bin/env bash
# tenant-dpa-register-guard.sh -- the single predicate over the tenant DPA register.
#
# WHY THIS EXISTS. Two call sites previously re-implemented this check inline in markdown,
# and both were guard-shaped no-ops (#7349 A1/A2):
#
#   knowledge-base/legal/tenant-dpa-register.md    grep -c 'status: dpa-signed'
#       The Status vocabulary uses the BARE token `dpa-signed`, so no table row could ever
#       carry the `status: `-prefixed form. Measured: 0 even with a signed row planted.
#
#   .../runbooks/tenant-provisioning.md            grep -c '^|' | test {} -ge 3
#       "header + separator + >=1 data row". The EMPTY register has exactly 3 pipe-lines,
#       because the `| _(none yet)_ |` placeholder is itself a pipe-line. Vacuously true on
#       the empty set -- it would have kept passing until the first real tenant.
#
# A guard that reads as coverage while providing none is worse than no guard, so the fix is
# one script both sites call rather than two prose predicates that drift apart again.
#
# ANCHORED ON THE COLUMN, NOT THE TOKEN. The Status column is resolved by NAME from the
# header row, so a tenant slug or a Notes cell containing the literal `dpa-signed` is not
# counted, and adding a column upstream does not silently shift the match
# (cq-assert-anchor-not-bare-token).
#
# FAIL-CLOSED. Every unusable input exits 2 rather than reporting a count. A zero that means
# "nothing matched" and a zero that means "I could not read the table" are the same byte, and
# only one of them is safe to act on.
#
# Exit codes:  0 ok   1 assertion failed   2 cannot decide (never a vacuous 0)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTER="$REPO_ROOT/knowledge-base/legal/tenant-dpa-register.md"

# The empty-state placeholder. Its first cell is the sentinel; it is NOT a tenant.
PLACEHOLDER_CELL='_(none yet)_'
SIGNED_STATUS='dpa-signed'

usage() {
  cat <<'EOF'
tenant-dpa-register-guard.sh [--register PATH] <subcommand>

Subcommands:
  count-data-rows    print the number of real tenant rows (excludes the empty-state placeholder)
  count-signed       print the number of rows whose Status column is exactly `dpa-signed`
  assert-empty       exit 0 iff the register holds no tenant rows (the DPA template §6.1 baseline)
  assert-populated   exit 0 iff the register holds at least one tenant row

Exit codes: 0 ok, 1 assertion failed, 2 cannot decide.
EOF
}

die2() { echo "::error::tenant-dpa-register-guard: $1" >&2; exit 2; }

subcommand=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --register) [[ $# -ge 2 ]] || die2 "--register needs a path"; REGISTER="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die2 "unknown option: $1" ;;
    *)          [[ -z "$subcommand" ]] || die2 "more than one subcommand given"; subcommand="$1"; shift ;;
  esac
done

[[ -n "$subcommand" ]] || { usage >&2; die2 "no subcommand given"; }
[[ -f "$REGISTER" && -r "$REGISTER" ]] || die2 "register not readable: $REGISTER"

# ---------------------------------------------------------------------------------------
# Parse the rows table. The header row is the first pipe-line whose cells include a cell
# named exactly "Status"; rows are the pipe-lines after its separator. Resolving the column
# by name is what makes the token match column-anchored rather than free-floating.
# ---------------------------------------------------------------------------------------
parse() {
  awk -v want="$1" -v placeholder="$PLACEHOLDER_CELL" -v signed="$SIGNED_STATUS" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

    # A markdown table separator, e.g. |---|---|
    /^[ \t]*\|[ \t]*:?-+/ { if (in_header) { in_header = 0; in_body = 1 } ; next }

    /^[ \t]*\|/ {
      n = split($0, cell, "|")
      if (!found_header && !in_body) {
        for (i = 2; i < n; i++) {
          if (trim(cell[i]) == "Status") { status_col = i; found_header = 1; in_header = 1 }
        }
        if (found_header) next
      }
      if (in_body) {
        if (trim(cell[2]) == placeholder) { next }   # empty-state sentinel, not a tenant
        data++
        if (status_col > 0 && status_col < n && trim(cell[status_col]) == signed) sig++
      }
      next
    }

    # A blank line ends the table body.
    /^[ \t]*$/ { if (in_body) in_body = 0 }

    END {
      if (!found_header) { print "ERR_NO_STATUS_COLUMN"; exit 0 }
      if (want == "data")   { print data + 0; exit 0 }
      if (want == "signed") { print sig + 0;  exit 0 }
      print "ERR_BAD_WANT"
    }
  ' "$REGISTER"
}

read_count() {
  local out
  out="$(parse "$1")" || die2 "failed to parse $REGISTER"
  case "$out" in
    ERR_NO_STATUS_COLUMN) die2 "no rows table with a 'Status' column found in $REGISTER" ;;
    ERR_BAD_WANT)         die2 "internal: bad parse selector" ;;
    ''|*[!0-9]*)          die2 "unparseable count '$out' from $REGISTER" ;;
  esac
  printf '%s' "$out"
}

case "$subcommand" in
  count-data-rows)
    count="$(read_count data)"
    printf '%s\n' "$count"
    ;;
  count-signed)
    count="$(read_count signed)"
    printf '%s\n' "$count"
    ;;
  assert-empty)
    count="$(read_count data)"
    if [[ "$count" == "0" ]]; then
      echo "tenant DPA register is empty (0 tenant rows) -- DPA template §6.1 30-day clock not triggered."
      exit 0
    fi
    echo "::error::register holds ${count} tenant row(s); expected the empty baseline." >&2
    exit 1
    ;;
  assert-populated)
    count="$(read_count data)"
    if (( count >= 1 )); then
      echo "tenant DPA register holds ${count} tenant row(s)."
      exit 0
    fi
    echo "::error::register holds no tenant rows. Step 0 requires a signed, recorded DPA before any provider account is created on behalf of a tenant. STOP -- do not proceed to Step 1." >&2
    exit 1
    ;;
  *)
    usage >&2
    die2 "unknown subcommand: $subcommand"
    ;;
esac
