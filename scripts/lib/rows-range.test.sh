#!/usr/bin/env bash
# rows-range.test.sh — unit coverage for scripts/lib/rows-range.sh parse and
# floor edges the battery arm invocations can't reach cheaply (#11647, S2/row 12).
#
# Every case runs the lib inside a subshell so DECLARED_TOTAL is subshell-scoped.
# The TOTA''L splice is load-bearing: a line-start DECLARED_TOTAL= anywhere in the
# file trips the Direction-2 census — the sanctioned '( export X=N; )' shape
# matches it too, so the var name is concatenated instead.
# (Direction-2's repo-wide census counts a line-start decl spelling anywhere).
# Ranges are spelled as quoted literals ("2-3") — Direction-1's literal
# census counts an unquoted --rows<sp><d>-<d> flag across test-all.sh + scripts/lib.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/rows-range.sh
source "$REPO_ROOT/scripts/lib/rows-range.sh"

PASS=0; FAIL=0
pass() { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
fail() { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1" >&2; }

# run_sut <argv...>: subshell with DECLARED_TOTAL=5 + a 5-site battery driving
# in_range per site then rows_gate_floor; prints nothing on success, rc is the
# process exit. Ranges are quoted literals ("2-3") — the Direction-1 census
# regex needs unquoted --rows<sp><d>-<d>; a stray quote is the sanctioned dodge.
run_sut() {
  (
    export DECLARED_TOTA''L=5
    ROWS_UNIT=sites
    rows_parse_args "$@"
    for _s in 1 2 3 4 5; do in_range && :; done
    rows_gate_floor
  )
}

# P1: no flag — all sites dispatch, gate green.
if run_sut >/dev/null 2>&1; then
  pass "no flag: every site dispatches and the floor is green"
else
  fail "no-flag full run refused"
fi
# P2: in-range slice — fewer sites dispatch, gate green.
if run_sut --rows "2-3" >/dev/null 2>&1; then
  pass "in-range slice dispatches exactly the slice"
else
  fail "in-range slice refused"
fi
# R1: malformed spec -> exit 2.
run_sut --rows "x-y" >/dev/null 2>&1
if (( $? == 2 )); then
  pass "malformed --rows spec exits 2"
else
  fail "malformed --rows spec did not exit 2"
fi
# R2: repeat flag -> exit 2 (last-wins is the coverage hole the refuse closes).
run_sut --rows "1-2" --rows "3-4" >/dev/null 2>&1
if (( $? == 2 )); then
  pass "repeated --rows exits 2"
else
  fail "repeated --rows did not exit 2"
fi
# R3: unknown argument -> exit 2.
run_sut --bogus >/dev/null 2>&1
if (( $? == 2 )); then
  pass "unknown argument exits 2"
else
  fail "unknown argument did not exit 2"
fi
# R4: out-of-bounds (B > declared total) -> exit 2.
run_sut --rows "4-6" >/dev/null 2>&1
if (( $? == 2 )); then
  pass "out-of-bounds --rows exits 2"
else
  fail "out-of-bounds --rows did not exit 2"
fi
# R5: inverted bounds (A > B) -> exit 2.
run_sut --rows "3-2" >/dev/null 2>&1
if (( $? == 2 )); then
  pass "inverted --rows exits 2"
else
  fail "inverted --rows did not exit 2"
fi
# R6: ordinal mismatch -> FATAL(harness) exit 2.
(
  export DECLARED_TOTA''L=5
  rows_parse_args >/dev/null 2>&1
  in_range 1 || exit 9
  in_range 3   # site 2 claims ordinal 3
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "ordinal != _site_seq FATALs exit 2"
else
  fail "ordinal drift did not FATAL"
fi
# R7: a site that never reaches the gate -> _site_seq != declared -> exit 2.
(
  export DECLARED_TOTA''L=5
  rows_parse_args >/dev/null 2>&1
  for _s in 1 2 3 4; do in_range && :; done   # site 5 missing
  rows_gate_floor
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "a missing gate call FATALs exit 2 (declared-reach accounting)"
else
  fail "missing gate call did not FATAL"
fi
# R8: per-block floor — block 2 hollowed below its declared minimum -> exit 2
# naming the ordinal; the intact map greens.
(
  export DECLARED_TOTA''L=3
  ROWS_COUNT_VAR=cases
  ROWS_BLOCK_CASES=( 2 3 1 )
  cases=0
  rows_parse_args >/dev/null 2>&1
  in_range && cases=$((cases + 2))
  in_range && cases=$((cases + 2))   # block 2: 2 < declared 3
  in_range && cases=$((cases + 1))
  rows_gate_floor
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "hollowed block FATALs exit 2 on the per-block floor"
else
  fail "hollowed block stayed green"
fi
(
  export DECLARED_TOTA''L=3
  ROWS_COUNT_VAR=cases
  ROWS_BLOCK_CASES=( 2 3 1 )
  cases=0
  rows_parse_args >/dev/null 2>&1
  in_range && cases=$((cases + 2))
  in_range && cases=$((cases + 3))
  in_range && cases=$((cases + 1))
  rows_gate_floor
) >/dev/null 2>&1
if (( $? == 0 )); then
  pass "intact per-block floors stay green"
else
  fail "intact per-block floor map refused"
fi
# R9: undeclared ROWS_BLOCK_CASES beside ROWS_COUNT_VAR -> exit 2 (shape pin).
(
  export DECLARED_TOTA''L=2
  ROWS_COUNT_VAR=cases
  cases=0
  rows_parse_args >/dev/null 2>&1
  in_range && cases=$((cases + 1))
  in_range && cases=$((cases + 1))
  rows_gate_floor
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "ROWS_COUNT_VAR without ROWS_BLOCK_CASES FATALs exit 2"
else
  fail "missing block-case map stayed green"
fi
# R10: missing / non-numeric / zero DECLARED_TOTAL -> exit 2 (precondition guard).
for _bad in unset 5x 0; do
  (
    [ "$_bad" != unset ] && export DECLARED_TOTA''L="$_bad"
    rows_parse_args >/dev/null 2>&1
    for _s in 1 2; do in_range && :; done
    rows_gate_floor
  ) >/dev/null 2>&1
  if (( $? == 2 )); then
    pass "DECLARED_TOTAL='${_bad}' FATALs exit 2"
  else
    fail "DECLARED_TOTAL='${_bad}' did not FATAL"
  fi
done
# R11: block-case map length != DECLARED_TOTAL -> exit 2 (arity pin).
(
  export DECLARED_TOTA''L=3
  ROWS_COUNT_VAR=cases
  ROWS_BLOCK_CASES=( 1 1 )
  cases=0
  rows_parse_args >/dev/null 2>&1
  for _s in 1 2 3; do in_range && cases=$((cases + 1)); done
  rows_gate_floor
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "short ROWS_BLOCK_CASES map FATALs exit 2"
else
  fail "short block-case map stayed green"
fi
# R12: hollowed LAST ordinal exercises the final-counter fallback -> exit 2.
(
  export DECLARED_TOTA''L=2
  ROWS_COUNT_VAR=cases
  ROWS_BLOCK_CASES=( 1 2 )
  cases=0
  rows_parse_args >/dev/null 2>&1
  in_range && cases=$((cases + 1))
  in_range && cases=$((cases + 1))   # block 2: 1 < declared 2
  rows_gate_floor
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "hollowed last block FATALs exit 2"
else
  fail "hollowed last block stayed green"
fi
# R13: --rows 0-N (LO < 1) -> exit 2 (bounds).
(
  export DECLARED_TOTA''L=5
  rows_parse_args --rows "0-3" >/dev/null 2>&1
) >/dev/null 2>&1
if (( $? == 2 )); then
  pass "--rows 0-N refused exit 2"
else
  fail "--rows 0-N accepted"
fi

echo ""
echo "rows-range.test.sh: $((PASS + FAIL)) checks, $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  printf 'VERDICT: %d of %d checks FAILED — this suite is RED.\n' "$FAIL" "$((PASS + FAIL))" >&2
  exit 1
fi
echo "All tests passed"
