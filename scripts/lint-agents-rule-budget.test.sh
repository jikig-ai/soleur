#!/usr/bin/env bash
# Tests for scripts/lint-agents-rule-budget.sh.
#
# Covers Phase 3 of the AGENTS.md pre-commit-hook plan (issue #3684):
#   T1: payload at 19,500 B → exit 0, no annotation on stderr
#   T2: payload at 21,000 B → exit 0, ::warning:: annotation on stderr
#   T3: payload at 22,500 B → exit 1, ::error:: annotation on stderr
#   T4: thresholds are env-var overridable (AGENTS_BUDGET_WARN_BYTES,
#       AGENTS_BUDGET_CRITICAL_BYTES)
#   T5: AGENTS_INDEX_PATH/AGENTS_CORE_PATH point at fixture files (not CWD)
#
# Isolation: each test builds a tempdir with synthetic AGENTS.md and
# AGENTS.core.md files of controlled byte length and points the script at
# them via the AGENTS_*_PATH env-var overrides defined in the shared
# library scripts/lib/agents-payload-bytes.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-agents-rule-budget.sh"

PASS=0
FAIL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  needle:   $needle"
    echo "  haystack: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  needle (unwanted): $needle"
    echo "  haystack:          $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# Build a fixture pair with the requested total payload byte count.
# Splits ~half/half between AGENTS.md (index) and AGENTS.core.md (core).
make_fixture() {
  local total_bytes="$1" tmpdir
  tmpdir=$(mktemp -d)
  local half=$((total_bytes / 2))
  local rem=$((total_bytes - half))
  head -c "$half" </dev/zero | tr '\0' '#' > "$tmpdir/AGENTS.md"
  head -c "$rem"  </dev/zero | tr '\0' '#' > "$tmpdir/AGENTS.core.md"
  echo "$tmpdir"
}

echo
echo "=== T1: payload at 19,500 B (under warn) → exit 0, silent ==="
TMP=$(make_fixture 19500)
OUT=$(AGENTS_INDEX_PATH="$TMP/AGENTS.md" AGENTS_CORE_PATH="$TMP/AGENTS.core.md" bash "$SUT" 2>&1); RC=$?
assert_eq "T1.exit_code" "0" "$RC"
assert_not_contains "T1.no_warning" "::warning" "$OUT"
assert_not_contains "T1.no_error" "::error" "$OUT"
rm -rf "$TMP"

echo
echo "=== T2: payload at 21,000 B (warn band) → exit 0, ::warning:: ==="
TMP=$(make_fixture 21000)
OUT=$(AGENTS_INDEX_PATH="$TMP/AGENTS.md" AGENTS_CORE_PATH="$TMP/AGENTS.core.md" bash "$SUT" 2>&1); RC=$?
assert_eq "T2.exit_code" "0" "$RC"
assert_contains "T2.warning_annotation" "::warning" "$OUT"
assert_not_contains "T2.no_error" "::error" "$OUT"
rm -rf "$TMP"

echo
echo "=== T3: payload at 22,500 B (over critical) → exit 1, ::error:: ==="
TMP=$(make_fixture 22500)
OUT=$(AGENTS_INDEX_PATH="$TMP/AGENTS.md" AGENTS_CORE_PATH="$TMP/AGENTS.core.md" bash "$SUT" 2>&1); RC=$?
assert_eq "T3.exit_code" "1" "$RC"
assert_contains "T3.error_annotation" "::error" "$OUT"
assert_contains "T3.error_names_bytes" "22500" "$OUT"
rm -rf "$TMP"

echo
echo "=== T4: thresholds env-var overridable ==="
TMP=$(make_fixture 5000)
OUT=$(AGENTS_INDEX_PATH="$TMP/AGENTS.md" AGENTS_CORE_PATH="$TMP/AGENTS.core.md" \
      AGENTS_BUDGET_WARN_BYTES=4000 AGENTS_BUDGET_CRITICAL_BYTES=4500 \
      bash "$SUT" 2>&1); RC=$?
assert_eq "T4.exit_code" "1" "$RC"
assert_contains "T4.error_annotation" "::error" "$OUT"
rm -rf "$TMP"

echo
echo "=== T5: AGENTS_INDEX_PATH/AGENTS_CORE_PATH redirect bytes source ==="
TMP=$(make_fixture 100)
OUT=$(AGENTS_INDEX_PATH="$TMP/AGENTS.md" AGENTS_CORE_PATH="$TMP/AGENTS.core.md" bash "$SUT" 2>&1); RC=$?
assert_eq "T5.exit_code" "0" "$RC"
assert_not_contains "T5.no_warning" "::warning" "$OUT"
rm -rf "$TMP"

echo
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "ALL TESTS PASSED"
