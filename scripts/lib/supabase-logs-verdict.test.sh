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
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

eq() {
  local label="$1" want="$2" got="$3"
  [[ "$want" == "$got" ]] && { pass "$label"; return; }
  fail "$label" "want '$want' got '$got'"
}

echo "== reason -> exit class =="
for r in FULLY_COVERED ZERO_WITH_FULL_COVERAGE TRUNCATED_AUTONARROWED; do
  eq "$r exits 0" 0 "$(verdict_exit_code "$r")"
done
eq "TRANSIENT_5XX exits 1" 1 "$(verdict_exit_code TRANSIENT_5XX)"
for r in CONFIG_ERROR AUTH_ERROR DIALECT_ERROR MALFORMED_RESULT; do
  eq "$r exits 2" 2 "$(verdict_exit_code "$r")"
done
# The headline binding: an INCONCLUSIVE/UNINSTRUMENTED answer exiting 0 is the
# false all-clear re-entering through the one channel nothing else guards.
for r in UNKNOWN_SOURCE UNINSTRUMENTED PARTIAL_COVERAGE \
         WINDOW_PREDATES_RETENTION WINDOW_SIZE_FAILURE TRUNCATION_UNRESOLVED; do
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
  emit_evidence_block 2> "$TMPDIR/slv-block.$$"
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
  emit_evidence_block 2> "$TMPDIR/slv-pat.$$"
if grep -qF 'sbp_abcdefghijklmnopqrstuvwxyz012345' "$TMPDIR/slv-pat.$$"; then
  fail "scrub_pat" "the token survived the renderer"
else
  pass "scrub_pat redacts at the print site"
fi
rm -f "$TMPDIR/slv-block.$$" "$TMPDIR/slv-pat.$$"

echo ""
if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
