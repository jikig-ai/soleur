#!/usr/bin/env bash
# Tests for scripts/lint-agents-enforcement-tags.py (skill-tag anchor-parity
# extension, #3684).
#
# Covers Phase 1 of the parity plan
# (knowledge-base/project/plans/2026-05-12-chore-agents-md-pre-commit-rule-budget-plan.md):
#   T1: current tree -> all 14 existing skill-enforced tag pairs resolve, exit 0
#   T2: tag with nonexistent anchor -> exit 1 + `anchor not resolvable`
#   T3: tolerant matcher (Phase 1.4 -> ### 1.4 normalization)
#   T4: tolerant matcher (hyphen <-> space, Route-Learning-to-Definition)
#   T5: agent-name fallback (review user-impact-reviewer)
#   T6: comma-split parser handles multi-pair tags
#   T7: tolerant matcher strip-leading-Phase variant (work Phase 0 Type-widening cross-consumer grep)
#
# Isolation: each case writes a synthetic AGENTS sidecar under `mktemp -d`
# and invokes the linter from the repo root so the SKILL.md / agent files
# resolve against the real plugins/ tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-agents-enforcement-tags.py"
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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit=$2 actual exit=$3"; fi
}

assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "needle: $2 | haystack: ${3:0:400}"; fi
}

# Run the linter from the real repo root so anchor resolution reaches the
# real plugins/soleur/skills/<skill>/SKILL.md and plugins/soleur/agents/**.
# The synthetic AGENTS file is staged under $REPO_ROOT as a symlink-free
# temp filename to keep the linter's `repo_root_for(path)` traversal honest.
write_synth_agents_in_repo() {
  local content="$1"
  local tmp; tmp=$(mktemp --tmpdir="$REPO_ROOT" "AGENTS.test-$$-XXXX.md")
  printf '%s' "$content" > "$tmp"
  echo "$tmp"
}

run_synth() {
  local content="$1"
  local synth_path; synth_path=$(write_synth_agents_in_repo "$content")
  local out rc
  set +e
  out=$(python3 "$SUT" "$synth_path" 2>&1)
  rc=$?
  set -e
  rm -f "$synth_path"
  printf '%s\n' "$out"
  return "$rc"
}

# Case T1: real tree resolves all 14 pairs.
t1_real_tree() {
  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$REPO_ROOT/AGENTS.md" \
    "$REPO_ROOT/AGENTS.core.md" \
    "$REPO_ROOT/AGENTS.docs.md" \
    "$REPO_ROOT/AGENTS.rest.md" 2>&1)
  rc=$?
  set -e
  assert_exit "T1 real tree exit 0" "0" "$rc"
  # AC5: success line names the parity-check count.
  assert_contains "T1 success line mentions anchor parity" "anchor parity" "$out"
}

# Case T2: nonexistent anchor -> reject.
t2_nonexistent_anchor() {
  local content="# AGENTS test

## Code Quality

- placeholder [id: cq-test-pointer] [skill-enforced: compound nonexistent-anchor].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T2 nonexistent anchor exit 1" "1" "$rc"
  assert_contains "T2 anchor not resolvable reported" "anchor not resolvable" "$out"
}

# Case T3: Phase 1.4 -> ### 1.4 tolerant matcher.
t3_phase_tolerant() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 1.4].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T3 Phase X.Y tolerant exit 0" "0" "$rc"
}

# Case T4: hyphen <-> space tolerant matcher.
t4_hyphen_space_tolerant() {
  local content="# AGENTS test

## Code Quality

- placeholder [id: cq-test-pointer] [skill-enforced: compound Route-Learning-to-Definition].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T4 hyphen<->space tolerant exit 0" "0" "$rc"
}

# Case T5: agent-name fallback.
t5_agent_name_fallback() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: review user-impact-reviewer].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T5 agent-name fallback exit 0" "0" "$rc"
}

# Case T6: comma-split parser handles multi-pair tag.
t6_comma_split() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: brainstorm Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer, preflight Check 6].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T6 comma-split multi-pair exit 0" "0" "$rc"
}

# Case T7: strip-leading-Phase tolerant variant.
t7_strip_leading_phase() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: work Phase 0 Type-widening cross-consumer grep].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T7 strip-leading-Phase exit 0" "0" "$rc"
}

t1_real_tree
t2_nonexistent_anchor
t3_phase_tolerant
t4_hyphen_space_tolerant
t5_agent_name_fallback
t6_comma_split
t7_strip_leading_phase

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
