#!/usr/bin/env bash

# Tests for resolve-git-root.sh helper
# Run: bash plugins/soleur/test/resolve-git-root.test.sh

set -euo pipefail

# Clear git env vars that leak when this test runs inside a git hook
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
HELPER="$SCRIPT_DIR/../scripts/resolve-git-root.sh"

echo "=== resolve-git-root.sh Tests ==="
echo ""

# --- Tests ---

# Test 1: Normal (non-bare) repo sets GIT_ROOT and IS_BARE=false
echo "Test 1: Normal repo sets GIT_ROOT and IS_BARE=false"
TEST_DIR=$(mktemp -d)
git -C "$TEST_DIR" init -q
RESULT=$(cd "$TEST_DIR" && source "$HELPER" && echo "GIT_ROOT=$GIT_ROOT IS_BARE=$IS_BARE")
assert_contains "$RESULT" "GIT_ROOT=$TEST_DIR" "GIT_ROOT points to repo root"
assert_contains "$RESULT" "IS_BARE=false" "IS_BARE is false for normal repo"
rm -rf "$TEST_DIR"
echo ""

# Test 2: Bare repo sets GIT_ROOT and IS_BARE=true
echo "Test 2: Bare repo sets GIT_ROOT and IS_BARE=true"
TEST_DIR=$(mktemp -d)
git init --bare -q "$TEST_DIR/bare.git"
RESULT=$(cd "$TEST_DIR/bare.git" && source "$HELPER" && echo "GIT_ROOT=$GIT_ROOT IS_BARE=$IS_BARE")
assert_contains "$RESULT" "IS_BARE=true" "IS_BARE is true for bare repo"
assert_contains "$RESULT" "GIT_ROOT=" "GIT_ROOT is set"
rm -rf "$TEST_DIR"
echo ""

# Test 3: Non-git directory returns error (return 1, not exit)
echo "Test 3: Non-git directory returns 1"
TEST_DIR=$(mktemp -d)
# Run in subshell to catch the return code without exiting this script
STDERR=$(cd "$TEST_DIR" && source "$HELPER" 2>&1) && EXIT=0 || EXIT=$?
assert_eq "1" "$EXIT" "returns 1 outside a git repo"
assert_contains "$STDERR" "Not inside a git repository" "error message mentions git repository"
rm -rf "$TEST_DIR"
echo ""

# Test 4: Direct execution (not sourced) prints error and exits 1
echo "Test 4: Direct execution prints usage error"
STDERR=$(bash "$HELPER" 2>&1) && EXIT=0 || EXIT=$?
assert_eq "1" "$EXIT" "exits 1 when executed directly"
assert_contains "$STDERR" "must be sourced" "error mentions sourcing"
echo ""

# Test 5: GIT_ROOT points to an existing directory
echo "Test 5: GIT_ROOT points to an existing directory"
TEST_DIR=$(mktemp -d)
git -C "$TEST_DIR" init -q
EXISTS=$(cd "$TEST_DIR" && source "$HELPER" && [[ -d "$GIT_ROOT" ]] && echo "yes" || echo "no")
assert_eq "yes" "$EXISTS" "GIT_ROOT is a valid directory"
rm -rf "$TEST_DIR"
echo ""

# Test 6: Subdirectory resolves GIT_ROOT to repo root
echo "Test 6: Subdirectory resolves GIT_ROOT to repo root"
TEST_DIR=$(mktemp -d)
git -C "$TEST_DIR" init -q
mkdir -p "$TEST_DIR/a/b/c"
RESULT=$(cd "$TEST_DIR/a/b/c" && source "$HELPER" && echo "$GIT_ROOT")
assert_eq "$TEST_DIR" "$RESULT" "GIT_ROOT from subdirectory equals repo root"
rm -rf "$TEST_DIR"
echo ""

# Test 7: Helper does not modify shell options (no set -e/u/o)
echo "Test 7: Helper does not modify caller's shell options"
TEST_DIR=$(mktemp -d)
git -C "$TEST_DIR" init -q
# Capture shell options before and after sourcing
OPTS=$(cd "$TEST_DIR" && set +euo pipefail 2>/dev/null; BEFORE=$(set +o); source "$HELPER"; AFTER=$(set +o); [[ "$BEFORE" == "$AFTER" ]] && echo "unchanged" || echo "changed")
assert_eq "unchanged" "$OPTS" "shell options unchanged after sourcing"
rm -rf "$TEST_DIR"
echo ""

# --- Results ---

print_results
