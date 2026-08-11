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
# (cq-assert-anchor-not-bare-token). The empty-state placeholder is matched in ANY cell
# for the same reason: pinning it to a fixed index meant inserting one column to the left
# of the slug made an EMPTY register report a tenant, and Step 0's "STOP, do not
# provision" gate then passed on it.
#
# FAIL-CLOSED. Every unusable input exits 2 rather than reporting a count. A zero that means
# "nothing matched" and a zero that means "I could not read the table" are the same byte, and
# only one of them is safe to act on.
#
# Exit codes:  0 ok   1 assertion failed   2 cannot decide (never a vacuous 0)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTER="$REPO_ROOT/knowledge-base/legal/tenant-dpa-register.md"

# The empty-state placeholder. Matched in ANY cell; it is NOT a tenant.
# COUPLED TO THE REGISTER'S MARKDOWN: if the register's placeholder is reworded and this
# literal is not, the guard counts it as a real tenant row and `assert-empty` reds on an
# empty register. scripts/tenant-dpa-register-guard.test.sh asserts the two agree.
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
    # Escaped pipes are protected before splitting and restored after, so a multi-value cell
    # written `Hetzner \| Cloudflare` does not shift every column to its right.
    function unprot(s) { gsub(/\002/, "|", s); return s }

    # A separator row is one whose EVERY cell is only dashes, colons and spaces. Testing the
    # whole row (rather than prefix-matching `|` + `-`) stops a data row whose first cell
    # begins with a hyphen -- `| -acme | ... |` -- from being eaten as a separator.
    function is_sep(c, k,    j) {
      for (j = 1; j <= k; j++) if (trim(c[j]) !~ /^:?-+:?$/) return 0
      return k > 0
    }

    # SECTION-ANCHORED. The rows table is the one under the "## Rows" heading. Binding to the
    # first Status-bearing table ANYWHERE made a summary table above it capture status_col,
    # which rendered a real signed row invisible while still exiting 0.
    /^##[ \t]+Rows[ \t]*$/ { in_rows = 1; next }
    /^#{1,6}[ \t]/         { in_rows = 0; next }
    !in_rows               { next }

    /^[ \t]*\|/ {
      line = $0
      gsub(/\\\|/, "\002", line)
      sub(/^[ \t]*\|/, "", line)         # strip the outer pipes FIRST so a row with no
      sub(/\|[ \t]*$/, "", line)         # trailing pipe indexes identically to one with it
      n = split(line, cell, "|")

      if (is_sep(cell, n)) {
        if (found_header && !ever_body) { ever_body = 1; in_body = 1 }
        else if (found_header)          { multi = 1 }
        next
      }

      if (!found_header) {
        for (i = 1; i <= n; i++) {
          if (trim(cell[i]) == "Status") { if (status_col) dup = 1; status_col = i; found_header = 1 }
        }
        if (found_header) next
        multi = 1                        # a pipe row before any Status header: ambiguous
        next
      }

      if (in_body) {
        is_placeholder = 0
        for (i = 1; i <= n; i++) if (trim(unprot(cell[i])) == placeholder) is_placeholder = 1
        if (is_placeholder) next   # empty-state sentinel anywhere in the row, not a tenant
        data++
        if (status_col >= 1 && status_col <= n && trim(unprot(cell[status_col])) == signed) sig++
        next
      }
      multi = 1                          # a row outside the resolved body: ambiguous
      next
    }

    END {
      # Every ambiguity is a REFUSAL, never a count. A zero meaning "nothing matched" and a
      # zero meaning "I could not read the table" are the same byte to the caller.
      if (!found_header) { print "ERR_NO_STATUS_COLUMN"; exit 0 }
      if (dup)           { print "ERR_DUPLICATE_STATUS"; exit 0 }
      if (!ever_body)    { print "ERR_NO_SEPARATOR";     exit 0 }
      if (multi)         { print "ERR_MULTIPLE_TABLES";  exit 0 }
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
    ERR_NO_STATUS_COLUMN) die2 "no rows table with a 'Status' column under '## Rows' in $REGISTER" ;;
    ERR_DUPLICATE_STATUS) die2 "the rows table has more than one 'Status' column in $REGISTER" ;;
    ERR_NO_SEPARATOR)     die2 "the rows table header has no |---| separator in $REGISTER" ;;
    ERR_MULTIPLE_TABLES)  die2 "more than one table (or a stray pipe row) under '## Rows' in $REGISTER" ;;
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
    echo "::error::If a tenant DPA was genuinely signed, this is EXPECTED: flip the live check in" >&2
    echo "::error::scripts/test-all.sh from assert-empty to assert-populated in the same PR that adds" >&2
    echo "::error::the row, and escalate to the CLO -- the DPA template §6.1 30-day sub-processor" >&2
    echo "::error::notification clock starts at the first dpa-signed row." >&2
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
