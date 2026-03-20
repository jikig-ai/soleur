#!/usr/bin/env bash

# Tests for scripts/lint-bot-synthetic-statuses.sh
# Run: bash plugins/soleur/test/lint-bot-synthetic-statuses.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Resolve lint script relative to repo root (3 levels up from plugins/soleur/test/)
REPO_ROOT="$SCRIPT_DIR/../../.."
LINT_SCRIPT="$REPO_ROOT/scripts/lint-bot-synthetic-statuses.sh"

echo "=== lint-bot-synthetic-statuses Tests ==="
echo ""

# --- Helpers ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

setup_wf_dir() {
  local dir="$TMPDIR_BASE/$1/.github/workflows"
  mkdir -p "$dir"
  echo "$dir"
}

# --- Tests ---

# Test 1: File with gh pr create and both contexts passes
echo "Test 1: File with gh pr create and both contexts passes"
WF=$(setup_wf_dir "test1")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f state=success -f context=cla-check -f description="ok"
          gh api repos/foo/statuses/$SHA -f state=success -f context=test -f description="ok"
          gh pr create --title "test" --base main
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when both contexts present"
assert_contains "$output" "ok:" "reports passing file"
assert_contains "$output" "All 1 scheduled" "reports summary"
echo ""

# Test 2: Missing context=test fails
echo "Test 2: File missing context=test fails"
WF=$(setup_wf_dir "test2")
cat > "$WF/scheduled-no-test.yml" << 'YAML'
name: NoTest
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=cla-check
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when context=test missing"
assert_contains "$output" "context=test" "reports missing context=test"
echo ""

# Test 3: Missing context=cla-check fails
echo "Test 3: File missing context=cla-check fails"
WF=$(setup_wf_dir "test3")
cat > "$WF/scheduled-no-cla.yml" << 'YAML'
name: NoCla
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=test
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when context=cla-check missing"
assert_contains "$output" "context=cla-check" "reports missing context=cla-check"
echo ""

# Test 4: Missing both contexts fails
echo "Test 4: File missing both contexts fails"
WF=$(setup_wf_dir "test4")
cat > "$WF/scheduled-no-both.yml" << 'YAML'
name: NoBoth
on: schedule
jobs:
  run:
    steps:
      - run: gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when both contexts missing"
assert_contains "$output" "context=cla-check" "reports missing cla-check"
assert_contains "$output" "context=test" "reports missing test"
assert_contains "$output" "2 missing" "reports correct failure count"
echo ""

# Test 5: File without gh pr create is skipped (passes)
echo "Test 5: File without gh pr create is skipped"
WF=$(setup_wf_dir "test5")
cat > "$WF/scheduled-no-pr.yml" << 'YAML'
name: NoPR
on: schedule
jobs:
  run:
    steps:
      - run: echo "no PR creation here"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no gh pr create present"
echo ""

# Test 6: Empty directory (no scheduled-*.yml files) passes
echo "Test 6: Empty workflow directory passes"
WF=$(setup_wf_dir "test6")
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no scheduled-*.yml files exist"
echo ""

# Test 7: Multi-file aggregation (one passing, one failing)
echo "Test 7: Multi-file directory aggregates failures correctly"
WF=$(setup_wf_dir "test7")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          gh api repos/foo/statuses/$SHA -f context=cla-check
          gh api repos/foo/statuses/$SHA -f context=test
          gh pr create --title "test"
YAML
cat > "$WF/scheduled-bad.yml" << 'YAML'
name: Bad
on: schedule
jobs:
  run:
    steps:
      - run: gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when one file fails in multi-file directory"
assert_contains "$output" "ok:" "reports passing file"
assert_contains "$output" "scheduled-bad.yml" "names the failing file"
echo ""

# Test 8: File using shared post-bot-statuses.sh script passes
echo "Test 8: File using shared post-bot-statuses.sh passes"
WF=$(setup_wf_dir "test8")
cat > "$WF/scheduled-shared.yml" << 'YAML'
name: Shared
on: schedule
jobs:
  run:
    steps:
      - run: |
          SHA=$(git rev-parse HEAD)
          bash scripts/post-bot-statuses.sh "$SHA"
          gh pr create --title "test" --base main
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when using shared script"
assert_contains "$output" "ok:" "reports passing file"
echo ""

print_results
