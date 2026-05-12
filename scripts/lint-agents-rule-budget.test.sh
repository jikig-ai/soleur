#!/usr/bin/env bash
# Tests for scripts/lint-agents-rule-budget.py.
#
# Issue: #3684. Covers Phase 1 of the rule-budget pre-commit linter plan
# (knowledge-base/project/plans/2026-05-12-chore-agents-md-pre-commit-rule-budget-plan.md):
#   T1: current tree -> WARN tier fires (B_ALWAYS=21985 >= 20000), exit 0
#   T2: AGENTS.core.md grown past 22 k -> exit 1 + `B_ALWAYS=... > 22000`
#   T3: one rule body > 600 B -> exit 1 + `exceeds 600 B`
#   T4: AGENTS.core.md missing on disk -> exit 2 + `AGENTS.core.md missing`
#   T5: per-rule cap fires across all four sidecars (not just AGENTS.core.md)
#   T6: pointer index lines short by construction -> never cap-rejected
#
# Isolation: each case builds a throwaway tree via `mktemp -d`, populates a
# minimal AGENTS.{md,core.md,docs.md,rest.md} pair, and runs the linter.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-agents-rule-budget.py"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit=$expected actual exit=$actual"
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "needle: $needle | haystack: ${haystack:0:400}"
  fi
}

make_index() {
  cat > "$1" <<'EOF'
# Agent Instructions — Index

Pointer index.

## Hard Rules

- [id: hr-test-pointer] → core
EOF
}

make_core_minimal() {
  cat > "$1" <<'EOF'
# AGENTS Core-class

## Hard Rules

- One-line body for hr-test-pointer with [id: hr-test-pointer]. **Why:** test fixture.
EOF
}

# Case T1: current tree.
t1_current_tree() {
  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$REPO_ROOT/AGENTS.md" \
    "$REPO_ROOT/AGENTS.core.md" \
    "$REPO_ROOT/AGENTS.docs.md" \
    "$REPO_ROOT/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T1 current tree exit 0" "0" "$rc"
  # WARN tier expected because measured B_ALWAYS = 21985 >= 20000
  assert_contains "T1 WARN line emitted" "WARN" "$out"
  assert_contains "T1 B_ALWAYS reported" "B_ALWAYS=" "$out"
}

# Case T2: B_ALWAYS > 22000 -> reject.
t2_byte_budget_reject() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  make_core_minimal "$tmp/AGENTS.core.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"
  # Pad AGENTS.core.md to drive B_ALWAYS past 22000. Padding goes in a comment
  # block so the per-rule check does not pre-empt with an "exceeds 600 B" reject.
  printf '\n<!-- pad: ' >> "$tmp/AGENTS.core.md"
  head -c 23000 /dev/zero | tr '\0' 'x' >> "$tmp/AGENTS.core.md"
  printf ' -->\n' >> "$tmp/AGENTS.core.md"

  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$tmp/AGENTS.md" \
    "$tmp/AGENTS.core.md" \
    "$tmp/AGENTS.docs.md" \
    "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T2 byte-budget reject exit 1" "1" "$rc"
  assert_contains "T2 B_ALWAYS > 22000 reported" "> 22000" "$out"
  rm -rf "$tmp"
}

# Case T3: per-rule body > 600 B -> reject.
t3_per_rule_reject() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"
  # AGENTS.core.md with one rule body line at 700 B.
  {
    echo "# AGENTS Core-class"
    echo
    echo "## Hard Rules"
    echo
    printf -- "- "
    head -c 700 /dev/zero | tr '\0' 'x'
    echo " [id: hr-test-pointer] **Why:** padded."
  } > "$tmp/AGENTS.core.md"

  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$tmp/AGENTS.md" \
    "$tmp/AGENTS.core.md" \
    "$tmp/AGENTS.docs.md" \
    "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T3 per-rule reject exit 1" "1" "$rc"
  assert_contains "T3 exceeds 600 B reported" "exceeds 600 B" "$out"
  rm -rf "$tmp"
}

# Case T4: AGENTS.core.md missing -> exit 2.
t4_missing_core() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"

  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$tmp/AGENTS.md" \
    "$tmp/AGENTS.core.md" \
    "$tmp/AGENTS.docs.md" \
    "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T4 missing core exit 2" "2" "$rc"
  assert_contains "T4 AGENTS.core.md missing reported" "AGENTS.core.md missing" "$out"
  rm -rf "$tmp"
}

# Case T5: per-rule cap fires in AGENTS.docs.md (not just core).
t5_per_rule_in_docs_sidecar() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  make_core_minimal "$tmp/AGENTS.core.md"
  : > "$tmp/AGENTS.rest.md"
  {
    echo "# AGENTS Docs-class"
    echo
    echo "## Code Quality"
    echo
    printf -- "- "
    head -c 700 /dev/zero | tr '\0' 'x'
    echo " [id: cq-test-overflow] **Why:** padded."
  } > "$tmp/AGENTS.docs.md"

  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$tmp/AGENTS.md" \
    "$tmp/AGENTS.core.md" \
    "$tmp/AGENTS.docs.md" \
    "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T5 docs sidecar per-rule reject exit 1" "1" "$rc"
  assert_contains "T5 AGENTS.docs.md flagged" "AGENTS.docs.md" "$out"
  rm -rf "$tmp"
}

# Case T6: pointer index lines (short by construction) are never cap-rejected.
t6_pointer_index_under_cap() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  make_core_minimal "$tmp/AGENTS.core.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"

  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$tmp/AGENTS.md" \
    "$tmp/AGENTS.core.md" \
    "$tmp/AGENTS.docs.md" \
    "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T6 minimal tree exit 0" "0" "$rc"
  rm -rf "$tmp"
}

if [[ ! -f "$SUT" ]]; then
  echo "SKIP: $SUT not yet present (Phase 1 RED — implementation lands in Phase 2)"
  exit 0
fi

t1_current_tree
t2_byte_budget_reject
t3_per_rule_reject
t4_missing_core
t5_per_rule_in_docs_sidecar
t6_pointer_index_under_cap

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
