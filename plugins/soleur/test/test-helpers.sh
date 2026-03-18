#!/usr/bin/env bash
# Shared test helpers for bash test suites.
# Source this file at the top of each .test.sh file.

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="$2"

  if [[ -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local path="$1"
  local msg="$2"

  if [[ ! -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file still exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

print_results() {
  echo "=== Results ==="
  echo "Passed: $PASS"
  echo "Failed: $FAIL"
  echo ""

  if [[ $FAIL -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
  else
    echo "ALL TESTS PASSED"
    exit 0
  fi
}
