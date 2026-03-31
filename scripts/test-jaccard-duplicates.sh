#!/usr/bin/env bash
# test-jaccard-duplicates.sh -- Tests for Phase 2.5 Jaccard duplicate detection
# in rule-audit.sh.
#
# Usage: bash scripts/test-jaccard-duplicates.sh
#
# Creates temporary AGENTS.md and constitution.md with known rules,
# runs rule-audit.sh in dry-run mode, and verifies output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# --- Test Helpers ---

setup_test_env() {
  TEST_DIR=$(mktemp -d)
  trap 'rm -rf "$TEST_DIR"' EXIT

  mkdir -p "$TEST_DIR/knowledge-base/project"
  mkdir -p "$TEST_DIR/.claude/hooks"

  # Create a dummy hook script so Phase 2 doesn't report broken refs
  touch "$TEST_DIR/.claude/hooks/guardrails.sh"
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    Expected to find: $needle"
    echo "    In output (first 20 lines):"
    echo "$haystack" | head -n 20 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    echo "  FAIL: $label"
    echo "    Expected NOT to find: $needle"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

# --- Test 1: Known duplicate pair scores >= 0.6 ---

test_duplicate_pair_detected() {
  echo "Test 1: Known duplicate pair is detected"

  cat > "$TEST_DIR/AGENTS.md" << 'EOF'
# Agent Instructions

## Hard Rules

- Never commit directly to main [hook-enforced: guardrails.sh Guard 1]
- Never rm -rf on the current directory
EOF

  cat > "$TEST_DIR/knowledge-base/project/constitution.md" << 'EOF'
# Project Constitution

## Code Quality

- Do not commit directly to main branch
- Always run linting before pushing
EOF

  local output
  output=$(REPO_ROOT="$TEST_DIR" bash "$SCRIPT_DIR/rule-audit.sh" 2>&1) || true

  assert_contains "Output contains Suspected Duplicates section" \
    "$output" "Suspected Duplicates"
  assert_contains "Duplicate pair is listed" \
    "$output" "commit directly"
}

# --- Test 2: Unrelated pair is NOT flagged ---

test_unrelated_pair_not_flagged() {
  echo "Test 2: Unrelated pair does not appear"

  cat > "$TEST_DIR/AGENTS.md" << 'EOF'
# Agent Instructions

## Hard Rules

- Never commit directly to main [hook-enforced: guardrails.sh Guard 1]
EOF

  cat > "$TEST_DIR/knowledge-base/project/constitution.md" << 'EOF'
# Project Constitution

## Code Quality

- Always run linting before pushing
EOF

  local output
  output=$(REPO_ROOT="$TEST_DIR" bash "$SCRIPT_DIR/rule-audit.sh" 2>&1) || true

  # "linting" and "commit" are unrelated — should not appear as a pair
  assert_not_contains "Unrelated rules not flagged as duplicates" \
    "$output" "| 0."
}

# --- Test 3: Colon-containing rule parses correctly ---

test_colon_in_rule_text() {
  echo "Test 3: Rule with colons parses without truncation"

  cat > "$TEST_DIR/AGENTS.md" << 'EOF'
# Agent Instructions

## Hard Rules

- Priority chain for services: (1) MCP tools, (2) CLI tools, (3) REST APIs
EOF

  cat > "$TEST_DIR/knowledge-base/project/constitution.md" << 'EOF'
# Project Constitution

## Code Quality

- Service priority chain: (1) MCP tools, (2) CLI tools, (3) REST APIs
EOF

  local output
  output=$(REPO_ROOT="$TEST_DIR" bash "$SCRIPT_DIR/rule-audit.sh" 2>&1) || true

  assert_contains "Colon-containing rule appears in duplicates" \
    "$output" "priority chain"
  assert_contains "Rule text not truncated at first colon" \
    "$output" "MCP tools"
}

# --- Run All Tests ---

setup_test_env
echo "Running Jaccard duplicate detection tests..."
echo ""

test_duplicate_pair_detected
echo ""
test_unrelated_pair_not_flagged
echo ""
test_colon_in_rule_text
echo ""

echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
