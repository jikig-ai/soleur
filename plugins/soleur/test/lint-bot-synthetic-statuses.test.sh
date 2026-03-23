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

# Test 1: File with gh pr create and no [skip ci] passes
echo "Test 1: File with gh pr create and no [skip ci] passes"
WF=$(setup_wf_dir "test1")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit"
          gh pr create --title "test" --base main
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no [skip ci] present"
assert_contains "$output" "ok:" "reports passing file"
assert_contains "$output" "All 1 scheduled" "reports summary"
echo ""

# Test 2: File with [skip ci] in commit message fails
echo "Test 2: File with [skip ci] in commit message fails"
WF=$(setup_wf_dir "test2")
cat > "$WF/scheduled-skip-ci.yml" << 'YAML'
name: SkipCI
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when [skip ci] present"
assert_contains "$output" "[skip ci]" "reports [skip ci] as the problem"
echo ""

# Test 3: File with [skip ci] but no gh pr create is skipped
echo "Test 3: File with [skip ci] but no gh pr create is skipped"
WF=$(setup_wf_dir "test3")
cat > "$WF/scheduled-no-pr.yml" << 'YAML'
name: NoPR
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "ci: update [skip ci]"
          echo "no PR creation"
YAML
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no gh pr create present"
echo ""

# Test 4: File without gh pr create is skipped
echo "Test 4: File without gh pr create is skipped"
WF=$(setup_wf_dir "test4")
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

# Test 5: Empty directory (no scheduled-*.yml files) passes
echo "Test 5: Empty workflow directory passes"
WF=$(setup_wf_dir "test5")
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "exits 0 when no scheduled-*.yml files exist"
echo ""

# Test 6: Multi-file directory aggregates failures correctly
echo "Test 6: Multi-file directory aggregates failures correctly"
WF=$(setup_wf_dir "test6")
cat > "$WF/scheduled-good.yml" << 'YAML'
name: Good
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit"
          gh pr create --title "test"
YAML
cat > "$WF/scheduled-bad.yml" << 'YAML'
name: Bad
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: weekly audit [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when one file has [skip ci] in multi-file directory"
assert_contains "$output" "ok:" "reports passing file"
assert_contains "$output" "scheduled-bad.yml" "names the failing file"
echo ""

# Test 7: Multiple [skip ci] files reports correct count
echo "Test 7: Multiple [skip ci] files reports correct count"
WF=$(setup_wf_dir "test7")
cat > "$WF/scheduled-bad1.yml" << 'YAML'
name: Bad1
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "docs: audit [skip ci]"
          gh pr create --title "test"
YAML
cat > "$WF/scheduled-bad2.yml" << 'YAML'
name: Bad2
on: schedule
jobs:
  run:
    steps:
      - run: |
          git commit -m "ci: update [skip ci]"
          gh pr create --title "test"
YAML
output=$(WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" 2>&1) || true
rc=0; WORKFLOW_DIR="$WF" bash "$LINT_SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "exits 1 when multiple files have [skip ci]"
assert_contains "$output" "2 workflow(s)" "reports correct failure count"
echo ""

print_results
