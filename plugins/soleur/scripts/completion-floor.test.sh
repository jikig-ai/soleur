#!/usr/bin/env bash
# completion-floor.test.sh — basic contract tests
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/completion-floor.sh"

pass=0; fail=0
run() { "$@"; }
assert_exit() {
  local expected="$1"; shift
  "$@" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" -eq "$expected" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: expected exit $expected got $rc for: $*"; fi
}

# unknown phase -> exit 2
assert_exit 2 "$VERIFIER" --phase bogus

# missing --phase -> exit 2
assert_exit 2 "$VERIFIER"

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
