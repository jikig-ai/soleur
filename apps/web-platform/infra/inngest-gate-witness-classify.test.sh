#!/usr/bin/env bash
# inngest-gate-witness-classify.test.sh (#8080) — decision-table + lib-token
# census suite for scripts/inngest-gate-witness-classify.sh, the extracted
# verdict→action classifier of the satisfiability-witness arm in
# .github/workflows/scheduled-inngest-health.yml.
#
# WHY THE CENSUS IS LIB-DERIVED. The token vocabulary is the `_ihdg_verdict
# "<literal>"` call sites inside tests/scripts/lib/inngest-host-dark-gate.sh —
# read from the lib at run time, never pinned here (same idiom as
# cutover-inngest-workflow.test.sh: "every token the lib can emit has an arm
# in BOTH"). A new lib token lands UNMAPPED: the census reddens, because the
# classifier may only answer satisfy/refusal/suppressed for tokens it can
# name, and an unknown token must answer refusal — never satisfy.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUT="$REPO_ROOT/scripts/inngest-gate-witness-classify.sh"
LIB="$REPO_ROOT/tests/scripts/lib/inngest-host-dark-gate.sh"
WF="$REPO_ROOT/.github/workflows/scheduled-inngest-health.yml"

SCRATCH=()
scratch_cleanup() { [[ ${#SCRATCH[@]} -gt 0 ]] && rm -rf "${SCRATCH[@]}" 2>/dev/null || true; }
trap scratch_cleanup EXIT

# The repo-wide path guard (byte-identical to every tracked copy): refuses an
# empty, relative, `..`-bearing or synthetic-fs operand before a write.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/igw-classify.XXXXXXXX")"
SCRATCH+=("$FIXTURE_DIR")
assert_fixture_dir "$FIXTURE_DIR"

PASS=0; FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

_ST_P=$PASS; _ST_F=$FAIL
assert "self-test: a FALSE condition fails (expected FAIL below)" "false"
if [[ "$FAIL" -ne $((_ST_F + 1)) || "$PASS" -ne "$_ST_P" ]]; then
  echo "  FATAL: assert() does not fail on a false condition — every row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (assert self-test OK — deliberate FAIL above is expected and subtracted)"

echo "== SUT presence =="
assert "classifier exists and is executable" "[[ -x '$SUT' ]]"
assert "--selftest prints the discoverability line" \
  "[[ \"\$(bash '$SUT' --selftest)\" == *'inngest-gate-witness-classify selftest: ok'* ]]"

EV=0
c_case() { # $1 desc, $2 token, $3 flag, $4 expected
  local got; got="$(bash "$SUT" "$2" "$3")"
  EV=$((EV + 1))
  assert "classify: $1 -> $4" "[[ '$got' == '$4' ]]"
}

echo "== decision table =="
c_case "dark + preflip flag is satisfy"                 "dark"          "rolled-back" "satisfy"
c_case "dark + empty flag is satisfy"                   "dark"          ""            "satisfy"
c_case "flag_armed verdict is suppressed"               "flag_armed"    "rolled-back" "suppressed"
c_case "armed-class flag suppresses a refusal token"    "stale_row"     "armed"       "suppressed"
c_case "flipping flag suppresses"                       "silent"        "flipping"    "suppressed"
c_case "flushed flag suppresses"                        "silent"        "flushed"     "suppressed"
c_case "done flag suppresses (self-retirement)"         "host_serving"  "done"        "suppressed"
c_case "armed flag suppresses even a dark token"        "dark"          "armed"       "suppressed"
c_case "preflip flag + refusal token is refusal"        "stale_row"     "aborted"     "refusal"
c_case "unknown-flag-class + refusal token is refusal"  "host_serving"  "unknown"     "refusal"
c_case "host_serving counts as a refusal"               "host_serving"  "rolled-back" "refusal"
c_case "unreadable is a refusal"                        "unreadable"    "aborted"     "refusal"
c_case "fsm_silent is a refusal"                        "fsm_silent"    "aborted"     "refusal"
# Guard-2 row 4: a token absent from the lib's vocabulary must classify
# refusal, never satisfy or suppressed (fail-closed default).
c_case "an unknown token fails closed to refusal"       "not_a_token"   "aborted"     "refusal"
c_case "a sentinel-ish token fails closed to refusal"   "__none__"      "aborted"     "refusal"
assert "decision-table rows dispatched (>=14)" "[[ '$EV' -ge 14 ]]"

# Harness canary: c_case must be able to FAIL.
_C_P=$PASS; _C_F=$FAIL
c_case "harness canary: wrong expectation MUST fail (expected FAIL below)" "dark" "aborted" "refusal"
if [[ "$FAIL" -ne $((_C_F + 1)) || "$PASS" -ne "$_C_P" ]]; then
  echo "  FATAL: c_case does not compare against the SUT — every row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (c_case harness canary OK — deliberate FAIL above is expected and subtracted)"

echo "== lib-token census (derived, not pinned) =="
# Every `_ihdg_verdict "<token>"` literal the lib can emit. Guard-2 row 6: a
# neutered census (zero tokens) is vacuity, not green — the floor below reds it.
TOKENS="$(grep -oE '_ihdg_verdict "[a-z_]+"' "$LIB" | sed -E 's/.*"([a-z_]+)".*/\1/' | sort -u)"
N_TOKENS="$(printf '%s\n' "$TOKENS" | grep -c . || true)"
assert "the lib census is non-vacuous (>=10 tokens, got $N_TOKENS)" "[[ '$N_TOKENS' -ge 10 ]]"

# Expected mapping, evaluated with a PREFLIP flag so suppression cannot mask a
# token row: dark→satisfy, flag_armed→suppressed, everything else→refusal.
CV=0
while IFS= read -r tok; do
  [[ -n "$tok" ]] || continue
  case "$tok" in
    dark)       want="satisfy" ;;
    flag_armed) want="suppressed" ;;
    *)          want="refusal" ;;
  esac
  got="$(bash "$SUT" "$tok" "rolled-back")"
  CV=$((CV + 1))
  assert "census: lib token '$tok' -> $want (got '$got')" "[[ '$got' == '$want' ]]"
done <<< "$TOKENS"
assert "census dispatched every lib token (got $CV)" "[[ '$CV' -eq '$N_TOKENS' ]]"

# Every refusal-class lib token also has a LITERAL arm in the classifier's
# case table (Guard-2 row 1): deleting an arm falls through to `*)` — still
# `refusal`, but the token is no longer NAMED, which this grep census reds.
NV=0
while IFS= read -r tok; do
  [[ -n "$tok" ]] || continue
  NV=$((NV + 1))
  assert "named arm: '$tok' appears as a literal in the classifier" \
    "grep -qF '$tok' '$SUT'"
done <<< "$TOKENS"

echo "== suppression source =="
# The partition is the lib's own `_erg_flag_class` — the classifier sources the
# lib rather than re-listing flag values (a flag-vocabulary addition lands in
# both places via the lib).
assert "the classifier reuses _erg_flag_class (no re-typed flag set)" \
  "grep -qF '_erg_flag_class' '$SUT'"
assert "the classifier sources the dark-gate lib (override honored)" \
  "grep -qF 'INNGEST_HOST_DARK_GATE_LIB' '$SUT'"
# A classifier that cannot load the lib must not silently suppress: with a
# nonexistent lib path, an armed flag still yields refusal.
INNGEST_HOST_DARK_GATE_LIB="$FIXTURE_DIR/nonexistent-lib.sh"
export INNGEST_HOST_DARK_GATE_LIB
assert "unloadable lib fails closed: armed flag -> refusal, not suppressed" \
  "[[ \"\$(bash '$SUT' stale_row armed)\" == 'refusal' ]]"
unset INNGEST_HOST_DARK_GATE_LIB

echo "== workflow wiring (assembly, text-level) =="
assert "the workflow calls inngest_execute_registry_gate (never the retired host_dark_gate)" \
  "grep -qF 'inngest_execute_registry_gate' '$WF' && ! grep -qF 'inngest_host_dark_gate' '$WF'"
assert "the witness arm reads the streak artifact via monitor-streak-state.sh" \
  "grep -qF 'inngest-gate-witness-streak' '$WF'"
assert "the witness emits the #8080 verdict log line" \
  "grep -qF '#8080 gate-witness token=' '$WF'"
assert "the witness files under ci/inngest-gate-witness" \
  "grep -qF 'ci/inngest-gate-witness' '$WF'"
assert "the witness files action-required + priority/p2-medium" \
  "grep -qF 'label priority/p2-medium' '$WF'"
assert "the witness classifies via the extracted script (no inline second copy)" \
  "grep -qF 'scripts/inngest-gate-witness-classify.sh' '$WF'"
assert "a crashed witness is detected via steps.witness.OUTCOME" \
  "grep -qF \"steps.witness.outcome != 'success'\" '$WF'"

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
# WHOLE-SUITE EXACT FLOOR (ordered comparison + contiguous simple assignment,
# per guard-vacuity-floor's recognition contract).
EXPECTED_ASSERTIONS=52
if (( PASS + FAIL < EXPECTED_ASSERTIONS )) || (( PASS + FAIL > EXPECTED_ASSERTIONS )); then
  printf '  FAIL: suite dispatched %s assertions, expected exactly %s — an assertion was added, removed or skipped.\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
printf '  PASS: exact assertion floor (%s dispatched)\n' "$EXPECTED_ASSERTIONS"
