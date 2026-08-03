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
# Corpus-grammar extension (#7172). The rule corpus uses a richer tag
# vocabulary than the original one-skill-one-anchor grammar could parse:
#   T8:  prose/blockquote lines (the tag legend) are NOT tags
#   T9:  `/`-joined skill list resolves when the anchor lands in >=1 skill
#   T10: `/`-joined list with a nonexistent skill -> reject
#   T11: ` + `-joined enforcer segments (phase anchor + hook script)
#   T12: ` + `-joined with a nonexistent hook segment -> reject
#   T13: file-form enforcer with a symbol (components.test.ts SYMBOL)
#   T14: file-form enforcer whose symbol is absent -> reject
#   T15: `§X.Y` -> `### X.Y` normalization
#   T16: vacuity floor — a file with zero tags is an ERROR, not a pass
#   T17: path-traversal anchors stay refused
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
  # Defense: if assertions or python3 abort mid-case, the trap removes the
  # synth file so a stale `AGENTS.test-*.md` cannot pollute the worktree
  # and contaminate subsequent lefthook runs (which glob AGENTS*.md).
  trap 'rm -f "$synth_path"' RETURN
  local out rc
  set +e
  out=$(python3 "$SUT" "$synth_path" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$out"
  return "$rc"
}

# Case T1: real tree resolves all 14 pairs.
t1_real_tree() {
  local out rc
  set +e
  out=$(python3 "$SUT" \
    "$REPO_ROOT/AGENTS.md" \
    "$REPO_ROOT/AGENTS.rules.md" 2>&1)
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

# --- Corpus-grammar extension (#7172) ---------------------------------------

# Case T8: the tag legend is prose, not a tag. A blockquote line naming the
# tag syntax must not be parsed as a tag (it was the 13th "failure" on main,
# introduced by the PR that documented the marker). A real body tag is
# included so the vacuity floor (T16) does not fire instead.
t8_prose_line_is_not_a_tag() {
  local content="# AGENTS test

> **Tag legend.** \`[hook-enforced: …]\`, \`[skill-enforced: …]\` are descriptive.

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 1.4].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T8 prose legend line is not a tag" "0" "$rc"
}

# Case T9: `/`-joined skill list; anchor need only resolve in one member.
t9_slash_joined_skills() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan/work/ship gates].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T9 slash-joined skill list exit 0" "0" "$rc"
}

# Case T10: a nonexistent skill anywhere in the list is still a reject.
t10_slash_joined_bad_skill() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan/nosuchskill gates].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T10 slash-joined bad skill exit 1" "1" "$rc"
  assert_contains "T10 names the missing skill" "nosuchskill" "$out"
}

# Case T11: ` + `-joined segments — a phase anchor plus a hook script.
t11_plus_joined_segments() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.8 + iac-plan-write-guard.sh].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T11 plus-joined segments exit 0" "0" "$rc"
}

# Case T12: a ` + ` segment naming a nonexistent hook is a reject.
t12_plus_joined_bad_hook() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.8 + no-such-hook-xyz.sh].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T12 plus-joined bad hook exit 1" "1" "$rc"
}

# Case T13: file-form enforcer with a symbol.
t13_file_form_enforcer() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: components.test.ts AUTONOMOUS_LOOP_SKILLS].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T13 file-form enforcer exit 0" "0" "$rc"
}

# Case T14: file-form enforcer whose symbol is absent -> reject.
t14_file_form_bad_symbol() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: components.test.ts NO_SUCH_SYMBOL_XYZ].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T14 file-form bad symbol exit 1" "1" "$rc"
}

# Case T15: `§X.Y` normalizes to `### X.Y`, mirroring the Phase X.Y variant.
t15_section_sign_normalization() {
  local content="# AGENTS test

## Code Quality

- placeholder [id: cq-test-pointer] [skill-enforced: plan §1.8].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T15 section-sign normalization exit 0" "0" "$rc"
}

# Case T16: VACUITY FLOOR. A file with zero enforcement tags must be an
# ERROR. "Scanned nothing" is the failure class this gate exists to catch —
# it is indistinguishable from "everything resolved" without this floor.
t16_vacuity_floor() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] with no enforcement tag at all.
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T16 vacuity floor exit 1" "1" "$rc"
  assert_contains "T16 floor names the zero-tag condition" "zero enforcement tag" "$out"
}

# Case T17: path-traversal anchors stay refused after the grammar widening.
t17_path_traversal_refused() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan ../../etc/passwd].
"
  local out rc
  set +e
  out=$(run_synth "$content")
  rc=$?
  set -e
  assert_exit "T17 path-traversal anchor exit 1" "1" "$rc"
}

if [[ ! -f "$SUT" ]]; then
  echo "SKIP: $SUT not yet present (Phase 1 RED — implementation lands in Phase 3)"
  exit 0
fi

t1_real_tree
t2_nonexistent_anchor
t3_phase_tolerant
t4_hyphen_space_tolerant
t5_agent_name_fallback
t6_comma_split
t7_strip_leading_phase
t8_prose_line_is_not_a_tag
t9_slash_joined_skills
t10_slash_joined_bad_skill
t11_plus_joined_segments
t12_plus_joined_bad_hook
t13_file_form_enforcer
t14_file_form_bad_symbol
t15_section_sign_normalization
t16_vacuity_floor
t17_path_traversal_refused

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
