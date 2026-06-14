#!/usr/bin/env bash
# Fixture tests for check-sweep-completeness.sh (#5269).
#
# Drives the REAL executor offline via its `$2` changeset-file argument
# (never `gh`, never the live registry). Each case builds a SYNTHETIC temp
# registry + changeset so the suite is deterministic and survives growth of
# the real .github/enforcement-contracts.json. Covers TS1-TS8 from the plan.
#
# When the SUT's contract changes, update this fixture in the same PR.

set -uo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
EXEC="$DIR/../check-sweep-completeness.sh"

PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Synthetic on-disk files the registries reference (absolute paths so the
# executor's `test -f` self-consistency check resolves regardless of CWD).
mkdir -p "$TMP/src" "$TMP/test"
TRIG="$TMP/src/cron-manifest.ts"
TRIG2="$TMP/src/other-manifest.ts"
DEP1="$TMP/test/cron-safe-commit-parity.test.ts"
DEP2="$TMP/test/cron-shared.test.ts"
DEP3="$TMP/test/other.test.ts"
LEGACY="$TMP/src/legacy-cron-manifest.ts"
MISSING="$TMP/test/does-not-exist.test.ts"   # intentionally NOT created
touch "$TRIG" "$TRIG2" "$DEP1" "$DEP2" "$DEP3" "$LEGACY"

# --- Registries ---
reg() { printf '%s' "$1" > "$TMP/$2"; echo "$TMP/$2"; }

REG_ONE=$(reg "{\"sibling_sets\":[{\"name\":\"set-a\",\"trigger\":[\"$TRIG\"],\"dependents\":[\"$DEP1\",\"$DEP2\"]}]}" reg_one.json)
REG_EMPTY=$(reg '{"sibling_sets":[]}' reg_empty.json)
REG_NOKEY=$(reg '{}' reg_nokey.json)
REG_MALFORMED=$(reg '{bad json' reg_malformed.json)
REG_EMPTYDEPS=$(reg "{\"sibling_sets\":[{\"name\":\"d\",\"trigger\":[\"$TRIG\"],\"dependents\":[]}]}" reg_emptydeps.json)
REG_MISSING=$(reg "{\"sibling_sets\":[{\"name\":\"m\",\"trigger\":[\"$TRIG\"],\"dependents\":[\"$MISSING\"]}]}" reg_missing.json)
REG_TWO=$(reg "{\"sibling_sets\":[{\"name\":\"set-a\",\"trigger\":[\"$TRIG\"],\"dependents\":[\"$DEP1\"]},{\"name\":\"set-b\",\"trigger\":[\"$TRIG2\"],\"dependents\":[\"$DEP3\"]}]}" reg_two.json)

# --- Changesets ---
cs() { printf '%s\n' "${@:2}" > "$TMP/$1"; echo "$TMP/$1"; }

CS_TRIGONLY=$(cs cs_trigonly.txt "$TRIG")
CS_ALL=$(cs cs_all.txt "$TRIG" "$DEP1" "$DEP2")
CS_DEPONLY=$(cs cs_deponly.txt "$DEP1")
CS_LEGACY=$(cs cs_legacy.txt "$LEGACY")
CS_BOTH_TRIG=$(cs cs_both_trig.txt "$TRIG" "$TRIG2")
CS_A_SAT_B_VIOL=$(cs cs_a_sat_b_viol.txt "$TRIG" "$DEP1" "$TRIG2")

# --- Harness ---
RC=0
OUT=""
run_check() { OUT=$(bash "$EXEC" "$1" "$2" 2>&1); RC=$?; }

ok() { echo "PASS [$1]"; PASS=$((PASS + 1)); }
bad() { echo "FAIL [$1]: $2"; echo "  rc=$RC out=$OUT"; FAIL=$((FAIL + 1)); }

assert_rc() { # name expected
  if [[ "$RC" -eq "$2" ]]; then ok "$1"; else bad "$1" "expected rc=$2 got rc=$RC"; fi
}
assert_out() { # name substring
  if grep -Fq "$2" <<<"$OUT"; then ok "$1"; else bad "$1" "expected output to contain '$2'"; fi
}

# TS1 — RED: trigger changed, both dependents missing → exit 1, names both
run_check "$REG_ONE" "$CS_TRIGONLY"
assert_rc "TS1-rc" 1
assert_out "TS1-names-dep1" "$DEP1"
assert_out "TS1-names-dep2" "$DEP2"

# TS2 — GREEN: trigger + all dependents → exit 0
run_check "$REG_ONE" "$CS_ALL"
assert_rc "TS2-rc" 0

# TS3 — no false positive: only a dependent changed (no trigger) → exit 0
run_check "$REG_ONE" "$CS_DEPONLY"
assert_rc "TS3-rc" 0

# TS4 — anchoring: a path containing the trigger's basename as a substring
# must NOT count as the trigger (exact full-path match only) → exit 0
run_check "$REG_ONE" "$CS_LEGACY"
assert_rc "TS4-rc" 0

# TS5 — registry integrity
run_check "$REG_EMPTY" "$CS_ALL";       assert_rc "TS5a-empty-array" 0
run_check "$REG_MALFORMED" "$CS_ALL";   assert_rc "TS5b-malformed" 1
run_check "$REG_NOKEY" "$CS_ALL";       assert_rc "TS5c-absent-key" 0
run_check "$REG_EMPTYDEPS" "$CS_TRIGONLY"; assert_rc "TS5d-empty-deps" 1
run_check "$REG_MISSING" "$CS_TRIGONLY"
assert_rc "TS5e-missing-path-rc" 1
assert_out "TS5e-missing-path-named" "$MISSING"

# TS6 — multi-set aggregation: both sets violated → exit 1, names deps from both
run_check "$REG_TWO" "$CS_BOTH_TRIG"
assert_rc "TS6-rc" 1
assert_out "TS6-names-dep1" "$DEP1"
assert_out "TS6-names-dep3" "$DEP3"

# TS7 — no masking: set A satisfied, set B violated → exit 1
run_check "$REG_TWO" "$CS_A_SAT_B_VIOL"
assert_rc "TS7-rc" 1
assert_out "TS7-names-dep3" "$DEP3"

# TS8 — fail-closed: no $2 and PR_NUMBER unset → exit 1 (never exit 0)
OUT=$(env -u PR_NUMBER bash "$EXEC" "$REG_ONE" 2>&1); RC=$?
assert_rc "TS8-fail-closed-rc" 1

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
