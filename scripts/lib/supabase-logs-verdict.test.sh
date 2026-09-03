#!/usr/bin/env bash
# Unit tests for scripts/lib/supabase-logs-verdict.sh. Auto-registers via the
# scripts/lib/*.test.sh glob. Deterministic; no network, no fixtures.
#
# The integration harness (tests/scripts/test-supabase-logs-query.sh) drives the
# whole helper. This file covers the parts of the contract that are pure and can
# therefore be asserted exhaustively rather than by example: the reason -> exit
# code map, the derivation of the top-line token FROM that map, and the coverage
# classifier's three outcomes including its two empty-input paths.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/supabase-logs-verdict.sh
. "${REPO_ROOT}/scripts/lib/supabase-logs-verdict.sh"

fails=0
passes=0
pass() { printf '  ok   %s\n' "${1:-}"; passes=$((passes + 1)); }
fail() { printf '  FAIL %s\n       %s\n' "${1:-}" "${2:-}"; fails=$((fails + 1)); }

eq() {
  local label="$1" want="$2" got="$3"
  [[ "$want" == "$got" ]] && { pass "$label"; return; }
  fail "$label" "want '$want' got '$got'"
}

echo "== reason -> exit class =="
for r in FULLY_COVERED TRUNCATED_AUTONARROWED; do
  eq "$r exits 0" 0 "$(verdict_exit_code "$r")"
done
eq "TRANSIENT_5XX exits 1" 1 "$(verdict_exit_code TRANSIENT_5XX)"
for r in CONFIG_ERROR AUTH_ERROR DIALECT_ERROR MALFORMED_RESULT AGGREGATION_FAILED; do
  eq "$r exits 2" 2 "$(verdict_exit_code "$r")"
done
# The headline binding: an INCONCLUSIVE/UNINSTRUMENTED answer exiting 0 is the
# false all-clear re-entering through the one channel nothing else guards.
for r in UNKNOWN_SOURCE UNINSTRUMENTED PARTIAL_COVERAGE \
         WINDOW_PREDATES_RETENTION WINDOW_SIZE_FAILURE ZERO_SOURCE_COVERAGE_UNESTABLISHED TRUNCATION_UNRESOLVED; do
  eq "$r exits 3" 3 "$(verdict_exit_code "$r")"
done
# An unmapped reason is a bug in the caller. It must NOT read as success.
eq "an unknown reason never exits 0" 2 "$(verdict_exit_code SOMETHING_NEW)"
eq "an empty reason never exits 0" 2 "$(verdict_exit_code "")"

echo "== top-line token is DERIVED, never set independently =="
eq "FULLY_COVERED -> COVERED" COVERED "$(verdict_for_reason FULLY_COVERED)"
eq "UNINSTRUMENTED -> INCONCLUSIVE" INCONCLUSIVE "$(verdict_for_reason UNINSTRUMENTED)"
eq "TRANSIENT_5XX -> INCONCLUSIVE" INCONCLUSIVE "$(verdict_for_reason TRANSIENT_5XX)"
eq "an unknown reason -> INCONCLUSIVE" INCONCLUSIVE "$(verdict_for_reason WHATEVER)"

echo "== coverage classifier =="
eq "rows at both edges -> FULL"    FULL    "$(coverage_classify 1000 2000 1000 2000 0)"
eq "within tolerance -> FULL"      FULL    "$(coverage_classify 1100 1900 1000 2000 3600)"
eq "uncovered head -> PARTIAL"     PARTIAL "$(coverage_classify 9000 20000 1000 20000 3600)"
eq "uncovered tail -> PARTIAL"     PARTIAL "$(coverage_classify 1000 9000 1000 20000 3600)"
# The two empty paths are the motivating 12-day case: no row anywhere in the
# window means the window is outside retention, NOT that nothing happened.
eq "no rows observed -> NONE"      NONE    "$(coverage_classify "" "" 1000 2000 3600)"
eq "jq nulls -> NONE"              NONE    "$(coverage_classify null null 1000 2000 3600)"

echo "== the block is one contiguous, multi-line answer =="
V_REASON=UNINSTRUMENTED V_REF=aaaaaaaaaaaaaaaaaaaa V_PROJECT=synthetic-project \
V_ROWS="" V_NEXT="next thing to do" \
  emit_evidence_block >/dev/null 2> "$TMPDIR/slv-block.$$"
BLOCK="$TMPDIR/slv-block.$$"
if [[ "$(grep -c '' "$BLOCK")" -ge 10 ]]; then
  pass "the block keeps its newlines (a single-line block is the count separated from its verdict, arrived at from the other side)"
else
  fail "block newlines" "expected a multi-line block, got $(grep -c '' "$BLOCK") line(s)"
fi
grep -qx 'verdict=INCONCLUSIVE' "$BLOCK" && pass "top-line token present" || fail "token" "no verdict= line"
grep -qx 'rows=UNAVAILABLE' "$BLOCK" && pass "an unavailable count is never rendered as 0" || fail "rows" "$(grep '^rows=' "$BLOCK")"
grep -qx 'project=synthetic-project' "$BLOCK" && pass "project identity on a FAILURE path" || fail "project" "missing"

echo "== a PAT can never survive a print site =="
V_REASON=FULLY_COVERED V_REF=aaaaaaaaaaaaaaaaaaaa V_PROJECT=synthetic-project \
V_ROWS=5 V_NEXT="token sbp_abcdefghijklmnopqrstuvwxyz012345 leaked into a message" \
  emit_evidence_block >/dev/null 2> "$TMPDIR/slv-pat.$$"
if grep -qF 'sbp_abcdefghijklmnopqrstuvwxyz012345' "$TMPDIR/slv-pat.$$"; then
  fail "scrub_pat" "the token survived the renderer"
else
  pass "scrub_pat redacts at the print site"
fi

echo "== human mode also puts the verdict on STDOUT =="
# The block owns stderr so stdout stays pipeable, which meant `helper > f` left f
# EMPTY with exit 0 whenever the source was quiet -- a reader of f sees a file
# with nothing wrong in it. One verdict line on stdout closes that, and the COUNT
# must NOT follow it there: a second quotable copy of rows= outside the block is
# the separation this lib exists to prevent.
V_REASON=UNINSTRUMENTED V_REF=aaaaaaaaaaaaaaaaaaaa V_PROJECT=synthetic-project \
V_ROWS=0 V_NEXT="next thing to do" \
  emit_evidence_block > "$TMPDIR/slv-out.$$" 2> "$TMPDIR/slv-err.$$"
OUT="$TMPDIR/slv-out.$$"
grep -qx 'verdict=INCONCLUSIVE reason=UNINSTRUMENTED' "$OUT" \
  && pass "stdout carries the verdict, so a redirect cannot yield an empty file and exit 0" \
  || fail "stdout verdict" "got: $(cat "$OUT")"
eq "stdout carries exactly ONE line" 1 "$(grep -c '' "$OUT")"
if grep -qE '^rows=' "$OUT"; then
  fail "stdout has no second copy of the count" "rows= leaked onto stdout, outside the block that qualifies it"
else
  pass "the COUNT stays inside the stderr block; only the verdict is duplicated"
fi

rm -f "$TMPDIR/slv-block.$$" "$TMPDIR/slv-pat.$$" "$TMPDIR/slv-out.$$" "$TMPDIR/slv-err.$$"

# ---------------------------------------------------------------------------
# HARNESS SELF-CHECK. Every assertion above dispatches through fail(), and the
# gate below reads a counter fail() maintains, so `fail() { :; }` turns this file
# into "all checks passed", exit 0. Prove the reporters still move their own
# counters, then subtract the probes. Dispatched by a BARE echo+exit, never
# through fail(), or the check would be neutered by the same edit.
# ---------------------------------------------------------------------------
_p0=$passes; _f0=$fails
pass "__self-check (expected; not a real check)"
fail "__self-check (expected; not a real failure)" "harness self-check probe"
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  echo "FAIL: pass()/fail() are not discriminating (+$((passes - _p0))/+$((fails - _f0)); expected +1/+1). A neutered reporter reports every assertion above as green." >&2
  exit 1
fi
passes=$_p0; fails=$_f0

echo ""
printf 'supabase-logs-verdict: %d passed, %d failed\n' "$passes" "$fails"

# MINIMUM CARDINALITY. Set to the FULL count of a green run, not a slack value:
# a floor trailing its population lets the newest assertion be deleted unnoticed.
# `-lt` (a floor, never `-eq`) so ADDING assertions stays free.
MIN_ASSERTIONS=34
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((passes + fails)) assertions ran, expected >= ${MIN_ASSERTIONS}. A file that asserts nothing must not exit 0." >&2
  exit 1
fi

if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
