#!/usr/bin/env bash
# Tests for scripts/lint-agents-rule-budget.py.
#
# Issue: #3684. Covers Phase 1 of the rule-budget pre-commit linter plan
# (knowledge-base/project/plans/2026-05-12-chore-agents-md-pre-commit-rule-budget-plan.md):
#   T1: current tree -> WARN tier fires (B_ALWAYS >= 20000), exit 0
#   T2: AGENTS.core.md grown past 23 k -> exit 1 + `B_ALWAYS=... > 23000`
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

# Case T1a: current tree — smoke test (exit 0 + B_ALWAYS reported). Does NOT
# assert which tier fires because B_ALWAYS shifts as rules land/retire.
t1a_current_tree_smoke() {
  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$REPO_ROOT/AGENTS.md" \
    "$REPO_ROOT/AGENTS.core.md" \
    "$REPO_ROOT/AGENTS.docs.md" \
    "$REPO_ROOT/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T1a current tree exit 0" "0" "$rc"
  assert_contains "T1a B_ALWAYS reported" "B_ALWAYS=" "$out"
}

# Case T1b: WARN tier fires at synthetic ~20100 B AGENTS.core.md.
# Padding lives in a comment block OUTSIDE any SECTIONS heading so it
# does NOT trip the per-rule 600 B cap (which only counts `^- ` lines
# under `## <SECTIONS>` headings).
t1b_warn_synth() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"
  local index_size; index_size=$(wc -c < "$tmp/AGENTS.md")
  local target=$((20100 - index_size))
  {
    echo "# AGENTS Core-class"
    echo
    echo "## Hard Rules"
    echo
    echo "- [id: hr-test-pointer] one-line body."
    echo
    echo "<!-- pad:"
    head -c "$target" /dev/zero | tr '\0' 'x'
    echo " -->"
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
  assert_exit "T1b WARN-synth exit 0" "0" "$rc"
  assert_contains "T1b WARN line emitted" "WARN" "$out"
  rm -rf "$tmp"
}

# Case T2: B_ALWAYS > 23000 -> reject.
t2_byte_budget_reject() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  make_core_minimal "$tmp/AGENTS.core.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"
  # Pad AGENTS.core.md to drive B_ALWAYS past 23000. Padding goes in a comment
  # block so the per-rule check does not pre-empt with an "exceeds 600 B" reject.
  printf '\n<!-- pad: ' >> "$tmp/AGENTS.core.md"
  head -c 24000 /dev/zero | tr '\0' 'x' >> "$tmp/AGENTS.core.md"
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
  assert_contains "T2 B_ALWAYS > 23000 reported" "> 23000" "$out"
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

# Case T7: multi-byte UTF-8 — a rule body of <600 chars but >600 bytes
# (e.g., 250 chars of `→` glyph at 3 B each = 750 B) MUST trip the cap.
# Guards against char/byte conflation per plan TR6.
t7_multi_byte_utf8_per_rule() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  : > "$tmp/AGENTS.docs.md"
  : > "$tmp/AGENTS.rest.md"
  {
    echo "# AGENTS Core-class"
    echo
    echo "## Hard Rules"
    echo
    # 250 copies of `→` (U+2192, 3 bytes UTF-8) = 750 B body.
    printf -- "- [id: hr-test-utf8] "
    python3 -c "print('→' * 250, end='')"
    echo " **Why:** padded."
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
  assert_exit "T7 UTF-8 multi-byte per-rule reject exit 1" "1" "$rc"
  assert_contains "T7 exceeds 600 B reported" "exceeds 600 B" "$out"
  rm -rf "$tmp"
}

# Case T8: AGENTS.core.md leading YAML frontmatter is EXCLUDED from B_ALWAYS
# (issue #5999, ADR-086) — the lint measures LOADED bytes (post-strip), matching
# the session loader. Reported B_ALWAYS must equal index + stripped-core bytes,
# and be strictly less than the raw on-disk sum (the frontmatter had bytes).
t8_frontmatter_excluded_from_b_always() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  : > "$tmp/AGENTS.docs.md"; : > "$tmp/AGENTS.rest.md"
  cat > "$tmp/AGENTS.core.md" <<'EOF'
---
last_reviewed: 2026-07-05
review_cadence: monthly
owner: founder
---

# AGENTS Core-class

## Hard Rules

- One-line body for hr-test-pointer with [id: hr-test-pointer]. **Why:** test fixture.
EOF
  local idx_b stripped_b expected reported raw_core_b raw_sum out rc
  idx_b=$(wc -c < "$tmp/AGENTS.md")
  stripped_b=$(python3 "$REPO_ROOT/scripts/lib/frontmatter-strip/strip.py" < "$tmp/AGENTS.core.md" | wc -c)
  expected=$((idx_b + stripped_b))
  set +e
  out=$(python3 "$SUT" "$tmp/AGENTS.md" "$tmp/AGENTS.core.md" "$tmp/AGENTS.docs.md" "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  reported=$(printf '%s' "$out" | grep -oE 'B_ALWAYS=[0-9]+' | head -1 | cut -d= -f2)
  assert_exit "T8 frontmatter tree exit 0" "0" "$rc"
  if [[ "$reported" == "$expected" ]]; then
    pass "T8 B_ALWAYS excludes frontmatter (=$expected)"
  else
    fail "T8 B_ALWAYS excludes frontmatter" "reported=$reported expected=$expected (idx=$idx_b stripped=$stripped_b)"
  fi
  raw_core_b=$(wc -c < "$tmp/AGENTS.core.md")
  raw_sum=$((idx_b + raw_core_b))
  if [[ -n "$reported" ]] && (( reported < raw_sum )); then
    pass "T8 B_ALWAYS < raw on-disk sum (frontmatter bytes not counted)"
  else
    fail "T8 B_ALWAYS < raw on-disk sum" "reported=$reported raw_sum=$raw_sum"
  fi
  rm -rf "$tmp"
}

# Case T9: malformed (unterminated) AGENTS.core.md frontmatter → the strip would
# consume the rule body, so the lint ERRORS (exit 1) rather than reporting a
# falsely-low B_ALWAYS. This is the over-strip fail-hard guard.
t9_malformed_frontmatter_errors() {
  local tmp; tmp=$(mktemp -d)
  make_index "$tmp/AGENTS.md"
  : > "$tmp/AGENTS.docs.md"; : > "$tmp/AGENTS.rest.md"
  cat > "$tmp/AGENTS.core.md" <<'EOF'
---
last_reviewed: 2026-07-05
review_cadence: monthly

# AGENTS Core-class (no closing frontmatter delimiter)

## Hard Rules

- One-line body for hr-test-pointer with [id: hr-test-pointer]. **Why:** test fixture.
EOF
  local out rc
  set +e
  out=$(python3 "$SUT" "$tmp/AGENTS.md" "$tmp/AGENTS.core.md" "$tmp/AGENTS.docs.md" "$tmp/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T9 malformed frontmatter exit 1" "1" "$rc"
  assert_contains "T9 over-strip ERROR reported" "frontmatter-strip removed" "$out"
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

t1a_current_tree_smoke
t1b_warn_synth
t2_byte_budget_reject
t3_per_rule_reject
t4_missing_core
t5_per_rule_in_docs_sidecar
t6_pointer_index_under_cap
t7_multi_byte_utf8_per_rule
t8_frontmatter_excluded_from_b_always
t9_malformed_frontmatter_errors

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
