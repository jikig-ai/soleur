#!/usr/bin/env bash
# Tests for cat-infra-config-state.sh — the state reporter for /hooks/infra-config-status.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTER="${SCRIPT_DIR}/cat-infra-config-state.sh"

PASS=0
FAIL=0
TMPDIR_ROOT=""

setup() {
  TMPDIR_ROOT=$(mktemp -d)
  export INFRA_CONFIG_STATE="${TMPDIR_ROOT}/infra-config-apply.state"
}

teardown() {
  rm -rf "$TMPDIR_ROOT"
  unset INFRA_CONFIG_STATE
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test 1: No state file returns no_prior_apply sentinel ---
test_no_state_file() {
  echo "TEST: no state file — returns no_prior_apply"
  setup

  local output
  output=$(bash "$REPORTER" 2>/dev/null)
  local exit_code reason
  exit_code=$(echo "$output" | jq -r '.exit_code' 2>/dev/null || echo "MISSING")
  reason=$(echo "$output" | jq -r '.reason' 2>/dev/null || echo "MISSING")

  assert_eq "exit_code is -2" "-2" "$exit_code"
  assert_eq "reason is no_prior_apply" "no_prior_apply" "$reason"

  teardown
}

# --- Test 2: Corrupt state file returns corrupt_state sentinel ---
test_corrupt_state() {
  echo "TEST: corrupt state file — returns corrupt_state"
  setup

  echo "this is not json {{{" > "$INFRA_CONFIG_STATE"

  local output
  output=$(bash "$REPORTER" 2>/dev/null)
  local exit_code reason
  exit_code=$(echo "$output" | jq -r '.exit_code' 2>/dev/null || echo "MISSING")
  reason=$(echo "$output" | jq -r '.reason' 2>/dev/null || echo "MISSING")

  assert_eq "exit_code is -3" "-3" "$exit_code"
  assert_eq "reason is corrupt_state" "corrupt_state" "$reason"

  teardown
}

# --- Test 3: Valid state file returns JSON verbatim ---
test_valid_state() {
  echo "TEST: valid state file — returns JSON verbatim"
  setup

  local input='{"start_ts":1716912000,"end_ts":1716912001,"exit_code":0,"files_written":8,"files_failed":0,"files":[]}'
  echo "$input" > "$INFRA_CONFIG_STATE"

  local output
  output=$(bash "$REPORTER" 2>/dev/null)
  local exit_code files_written
  exit_code=$(echo "$output" | jq -r '.exit_code' 2>/dev/null || echo "MISSING")
  files_written=$(echo "$output" | jq -r '.files_written' 2>/dev/null || echo "MISSING")

  assert_eq "exit_code is 0" "0" "$exit_code"
  assert_eq "files_written is 8" "8" "$files_written"

  teardown
}

# --- Run all tests ---
echo "=== cat-infra-config-state.sh test suite ==="
test_no_state_file
test_corrupt_state
test_valid_state
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
