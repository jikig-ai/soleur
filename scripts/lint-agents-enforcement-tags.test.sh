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
  # Assert the COUNTS, not the prose. The previous form asserted the substring
  # "anchor parity", which is present in both a healthy run and a fully
  # vacuous one ("0 anchor parity check(s) resolve") — so truncating the
  # scan left this case green while the gate resolved nothing (#7172's own
  # failure quote, one indirection later).
  hooks=$(printf '%s' "$out" | sed -nE 's/^OK: ([0-9]+) hook .*/\1/p')
  skills=$(printf '%s' "$out" | sed -nE 's/^OK: [0-9]+ hook \+ ([0-9]+) skill .*/\1/p')
  anchors=$(printf '%s' "$out" | sed -nE 's/.* via ([0-9]+) anchor check\(s\)$/\1/p')
  if [[ "$hooks" =~ ^[0-9]+$ && "$hooks" -ge 10 ]]; then
    pass "T1 hook checks performed (>=10, got ${hooks})"
  else fail "T1 hook checks performed" "got '${hooks}'"; fi
  if [[ "$skills" =~ ^[0-9]+$ && "$skills" -ge 30 ]]; then
    pass "T1 skill units performed (>=30, got ${skills})"
  else fail "T1 skill units performed" "got '${skills}'"; fi
  if [[ "$anchors" =~ ^[0-9]+$ && "$anchors" -ge 28 ]]; then
    pass "T1 anchor checks performed (>=28, got ${anchors})"
  else fail "T1 anchor checks performed" "got '${anchors}'"; fi
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
  assert_contains "T16 floor names the below-floor condition" "below the calibrated floor" "$out"
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


# --- Branches that had ZERO coverage, each proven by a surviving mutation ----
# The `hook` and `review-agent` kinds occur exactly once each in the live
# corpus, which made them simultaneously the least-tested and the most likely
# to rot. Each gets a positive AND a negative fixture.

# T18: `+ hook <script>` resolves through hook_resolves (NOT the file resolver).
t18_hook_keyword_positive() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.8 + hook iac-plan-write-guard.sh].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T18 hook keyword positive exit 0" "0" "$rc"
}

# T19: same shape, nonexistent hook -> reject, and the message must name the
# HOOK resolver so this cannot silently become a file-resolver test.
t19_hook_keyword_negative() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.8 + hook no-such-hook-xyz.sh].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T19 hook keyword negative exit 1" "1" "$rc"
  assert_contains "T19 names the hook resolver" "hook script not found" "$out"
}

# T20/T21: review-agent. resolve_agent_name was ~20 lines of NEW code with no
# test at all — replacing its body with `return True` was invisible.
t20_review_agent_positive() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.9 + review-agent silent-failure-hunter].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T20 review-agent positive exit 0" "0" "$rc"
}

t21_review_agent_negative() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.9 + review-agent no-such-agent-xyz].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T21 review-agent negative exit 1" "1" "$rc"
  assert_contains "T21 names the agent resolver" "no agent named" "$out"
}

# T22: a keyword with NO operand is malformed, never a bare anchor. Before the
# fix this resolved because the four letters "hook" appear in the skill body.
t22_keyword_without_operand() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: ship Phase 7 + hook].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T22 keyword without operand exit 1" "1" "$rc"
  # Assert the MESSAGE, not just the exit code. Exit-code-only made this
  # vacuous: removing the malformed branch made `tail.split()[0]` raise
  # IndexError, which is also non-zero, so the case passed on a CRASH.
  assert_contains "T22 names the malformed shape" "does not match any supported" "$out"
}

# T23: glob metacharacters are PATTERN syntax to rglob. `*` resolved to
# "some agent exists", which is not the claim a tag makes.
t23_glob_metachar_refused() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.9 + review-agent *].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T23 glob metachar refused exit 1" "1" "$rc"
}

# T24: pathlib DISCARDS the left operand on an absolute right operand, so a
# leading `/` escaped the repo root entirely.
t24_absolute_path_refused() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [hook-enforced: /etc/passwd].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T24 absolute path refused exit 1" "1" "$rc"
}

# T25: a fabricated tag on an INDENTED sub-bullet must still be checked. The
# first cut of this fix exempted whole lines, so this shape passed here AND
# in the ADR-092 hash gate while still rendering as a real claim to an agent.
t25_indented_subbullet_is_checked() {
  local content="# AGENTS test

## Hard Rules

- real [id: hr-test-pointer] [skill-enforced: plan Phase 1.4].
  - sub [id: hr-sub] [hook-enforced: totally-fake-hook.sh].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T25 indented sub-bullet is checked exit 1" "1" "$rc"
}

# T26: a malformed fragment is an ERROR, not a silently-dropped unit.
t26_malformed_fragment() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: Ship Phase 5.5].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T26 malformed fragment exit 1" "1" "$rc"
  assert_contains "T26 names the malformed shape" "does not match any supported" "$out"
}

# T27: a file-form traversal in the ENFORCER position — a surface this PR
# added, distinct from T17's anchor-position traversal.
t27_file_form_traversal_refused() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: ../../../etc/foo.py].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T27 file-form traversal refused exit 1" "1" "$rc"
}

# T28: the any()-across-a-slash-list semantic, pinned by a fixture where the
# anchor resolves ONLY in the SECOND member. T9 cannot discriminate any-vs-all
# because its anchor resolves in all three.
t28_slash_list_second_member_only() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: compound/plan Phase 1.4].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T28 slash-list second-member-only exit 0" "0" "$rc"
}

# T29: a one-letter agent name must be refused on SHAPE. Without the kebab
# slug guard the whole-token search finds the letter "a" in agent prose and
# `review-agent a` resolves — the substring class this fix exists to close.
# T21's fixture is caught by the token search alone, so it cannot pin this.
t29_short_agent_name_refused() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.9 + review-agent a].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T29 one-letter agent name refused exit 1" "1" "$rc"
}

# T30: glob metachars in the FILE-form position. T23's fixture is refused by
# the agent slug guard, so it does not pin the glob guard itself.
t30_file_form_glob_refused() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: components*.ts AUTONOMOUS_LOOP_SKILLS].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T30 file-form glob refused exit 1" "1" "$rc"
}

# T31: `failure-hunter` is a SUBSTRING of the real `silent-failure-hunter`
# but not a whole token. A bare substring match resolves it; the
# lookaround-anchored token match must not. Nothing else in the suite
# distinguishes substring from whole-token.
t31_agent_substring_not_whole_token() {
  local content="# AGENTS test

## Hard Rules

- placeholder [id: hr-test-pointer] [skill-enforced: plan Phase 2.9 + review-agent failure-hunter].
"
  local out rc; set +e; out=$(run_synth "$content"); rc=$?; set -e
  assert_exit "T31 agent substring is not a whole token exit 1" "1" "$rc"
}

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
t16_vacuity_floor
t17_path_traversal_refused
t18_hook_keyword_positive
t19_hook_keyword_negative
t20_review_agent_positive
t21_review_agent_negative
t22_keyword_without_operand
t23_glob_metachar_refused
t24_absolute_path_refused
t25_indented_subbullet_is_checked
t26_malformed_fragment
t27_file_form_traversal_refused
t28_slash_list_second_member_only
t29_short_agent_name_refused
t30_file_form_glob_refused
t31_agent_substring_not_whole_token

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
