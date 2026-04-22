#!/usr/bin/env bash

# Tests for worktree-manager.sh create_for_feature() spec-dir location.
# Regression test for #2815: spec dir must land inside the worktree, not at the bare root.
# Run: bash plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook or worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh feature spec-dir location ==="
echo ""

# Setup: create a synthetic bare repo with an initial commit on main
# that contains knowledge-base/ (mirrors the real soleur repo layout).
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

git init -q -b main "$TEST_DIR/seed"
git -C "$TEST_DIR/seed" config user.email "test@test.local"
git -C "$TEST_DIR/seed" config user.name "Test"
mkdir -p "$TEST_DIR/seed/knowledge-base/project/specs"
touch "$TEST_DIR/seed/knowledge-base/.gitkeep"
git -C "$TEST_DIR/seed" add .
git -C "$TEST_DIR/seed" commit -q -m "seed"
git clone -q --bare "$TEST_DIR/seed" "$TEST_DIR/bare.git"

# Simulate real-world bare repo state: knowledge-base/ sits at the bare root
# as a stale on-disk copy (originally created by the pre-fix code path itself).
# Without this, the current buggy `[[ -d "$GIT_ROOT/knowledge-base" ]]` guard
# silently skips spec creation in the synthetic test bare repo, masking the bug.
mkdir -p "$TEST_DIR/bare.git/knowledge-base/project/specs"

# Branch name derives from the `feat-` prefix in worktree-manager.sh `create_for_feature()`.
WORKTREE="$TEST_DIR/bare.git/.worktrees/feat-acme-widget"
WORKTREE_SPEC="$WORKTREE/knowledge-base/project/specs/feat-acme-widget"
BARE_SPEC="$TEST_DIR/bare.git/knowledge-base/project/specs/feat-acme-widget"

# Surface non-zero exits from the SUT instead of swallowing them — a crash unrelated
# to spec placement would otherwise present as "dir missing" and mislead diagnosis.
run_feature() {
  local log="$TEST_DIR/run-$1.log"
  if ! bash "$SCRIPT" --yes feature acme-widget >"$log" 2>&1; then
    echo "  WARN: worktree-manager.sh exited non-zero on invocation $1:"
    sed 's/^/    /' "$log"
  fi
}

# Test 1: feature <name> creates spec dir inside the worktree
echo "Test 1: spec dir created inside worktree"
cd "$TEST_DIR/bare.git"
run_feature 1

assert_eq "true" "$([[ -d "$WORKTREE_SPEC" ]] && echo true || echo false)" \
  "spec dir exists inside worktree"
echo ""

# Test 2: spec dir does NOT exist at bare root (fix's core assertion)
echo "Test 2: spec dir does NOT exist at bare root"
assert_eq "false" "$([[ -d "$BARE_SPEC" ]] && echo true || echo false)" \
  "spec dir does not exist at bare root"
echo ""

# Test 3: idempotency — second invocation is a no-op
echo "Test 3: idempotency (second invocation)"
run_feature 2
assert_eq "true" "$([[ -d "$WORKTREE_SPEC" ]] && echo true || echo false)" \
  "spec dir still exists after second invocation"
assert_eq "false" "$([[ -d "$BARE_SPEC" ]] && echo true || echo false)" \
  "still no spec dir at bare root after second invocation"
echo ""

print_results
