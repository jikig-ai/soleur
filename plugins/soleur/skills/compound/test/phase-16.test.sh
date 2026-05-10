#!/usr/bin/env bash
# Tests for plugins/soleur/skills/compound/scripts/token-efficiency-report.sh
# (compound Phase 1.6, issue #3494). Plan section: Phase 4 scenarios 6-13 + 14
# (budget assertion).
#
# Each test injects fixture paths via env vars (--fixture-mode flag) and
# verifies the script's output + telemetry emission against a planted
# .rule-incidents.jsonl in a throwaway repo.
#
# Run via:  bash plugins/soleur/skills/compound/test/phase-16.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../scripts/token-efficiency-report.sh"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

ROOTS=()
trap 'for r in "${ROOTS[@]}"; do rm -rf "$r"; done' EXIT

REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../../../.." 2>/dev/null && pwd -P)"

# Fixture builder: a throwaway repo with synthetic AGENTS.md, a git history,
# and optional planted session-tokens / skill-invocations / rule-incidents
# files. All env-var injection uses INCIDENTS_REPO_ROOT (re-using the
# rule-metrics convention) plus our own SESSION_TOKENS_PATH /
# SKILL_INVOCATIONS_PATH / TE_REPORT_REPO_ROOT.
make_fixture() {
  local root
  root=$(mktemp -d)
  mkdir -p "$root/.claude" "$root/plugins/soleur/skills/find-skills" "$root/plugins/soleur/skills/foo"
  printf '# Agent Instructions\n\n## Hard Rules\n\n- A synthetic rule for tests [id: hr-rule-x].\n' \
    > "$root/AGENTS.md"
  # Synthetic SKILL.md fixtures whose payload we sum.
  printf 'SKILL header\n%s\n' "$(printf 'x%.0s' {1..2000})" > "$root/plugins/soleur/skills/find-skills/SKILL.md"
  printf 'SKILL header\n%s\n' "$(printf 'x%.0s' {1..3000})" > "$root/plugins/soleur/skills/foo/SKILL.md"
  # Init a git repo so `git diff --shortstat HEAD~1` works.
  (
    cd "$root"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "v1" > file1
    git add -A && git commit -q -m "initial"
    # Make a real diff so git diff --shortstat HEAD~1 returns lines>0.
    for i in $(seq 1 80); do echo "line $i" >> file1; done
    git add -A && git commit -q -m "second"
  )
  echo "$root"
}

# Plant a session-tokens.jsonl line.
plant_envelope() {
  local root="$1" sid="$2" subagent="$3" total="$4" ts="${5:-2026-04-25T10:00:00Z}"
  printf '{"schema":1,"ts":"%s","session_id":"%s","subagent_type":"%s","total_tokens":%d,"tool_uses":1,"duration_ms":1000,"hook_event":"PostToolUse"}\n' \
    "$ts" "$sid" "$subagent" "$total" >> "$root/.claude/.session-tokens.jsonl"
}

# Plant a skill-invocations.jsonl line.
plant_skill() {
  local root="$1" sid="$2" skill="$3" ts="${4:-2026-04-25T09:00:00Z}"
  printf '{"schema":1,"ts":"%s","skill":"%s","session_id":"%s","hook_event":"PreToolUse"}\n' \
    "$ts" "$skill" "$sid" >> "$root/.claude/.skill-invocations.jsonl"
}

# Common run-script wrapper. Sets all required env vars.
run_script() {
  local root="$1" sid="$2"
  shift 2
  TE_REPORT_REPO_ROOT="$root" \
    INCIDENTS_REPO_ROOT="$root" \
    CLAUDE_CODE_SESSION_ID="$sid" \
    "$@" \
    bash "$SCRIPT" --fixture-mode 2>&1
}

# ------------------------------------------------------------------------
# Scenario 6: skip on small diff (<50 lines).
# ------------------------------------------------------------------------
echo "Scenario 6: skip on small diff"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
# Overwrite file1 with a 3-line diff instead of 80.
(cd "$ROOT" && git reset -q --hard HEAD~1 && echo "tiny" >> file1 && git add -A && git commit -q -m "tiny")
OUT=$(run_script "$ROOT" "sess-small-diff")
if echo "$OUT" | grep -q "skipped"; then
  if [[ -f "$ROOT/.claude/.rule-incidents.jsonl" ]]; then
    fail "rule-incidents written despite skip"
  else
    pass "skipped on small diff, no telemetry emit"
  fi
else
  fail "expected 'skipped' output, got: $OUT"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 7: subagent overshoot → te-subagent-overshoot warn emitted.
# ------------------------------------------------------------------------
echo "Scenario 7: subagent overshoot triggers te-subagent-overshoot"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
plant_envelope "$ROOT" "sess-7" "general-purpose" 120000
run_script "$ROOT" "sess-7" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
if [[ ! -f "$INC" ]]; then
  fail "no rule-incidents written"
elif ! grep -q '"te-subagent-overshoot"' "$INC"; then
  fail "expected te-subagent-overshoot in $(cat "$INC")"
elif ! grep -q '"warn"' "$INC"; then
  fail "expected event_type=warn"
else
  pass "te-subagent-overshoot warn emitted"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 8: skill-payload-floor outlier (>200k chars summed).
# ------------------------------------------------------------------------
echo "Scenario 8: skill-payload-floor triggers"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
# Bloat one of the skill SKILL.md files past the floor.
printf '%s\n' "$(printf 'y%.0s' {1..220000})" >> "$ROOT/plugins/soleur/skills/foo/SKILL.md"
plant_skill "$ROOT" "sess-8" "soleur:foo"
run_script "$ROOT" "sess-8" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
if [[ ! -f "$INC" ]]; then
  fail "no rule-incidents written"
elif ! grep -q '"te-skill-payload-floor"' "$INC"; then
  fail "expected te-skill-payload-floor in $(cat "$INC")"
else
  pass "te-skill-payload-floor warn emitted"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 9a: ratio code path with RATIO_EMIT_ENABLED=0 → no emit.
# ------------------------------------------------------------------------
echo "Scenario 9a: ratio gated off (RATIO_EMIT_ENABLED=0) → no te-agents-md-turn-cost"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
# 80k envelope, ~80 lines diff → ratio_x1000 = 80000*1000/80 = 1_000_000 (>>2000). Flag off → no emit.
plant_envelope "$ROOT" "sess-9a" "general-purpose" 80000
RATIO_EMIT_ENABLED=0 run_script "$ROOT" "sess-9a" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
if [[ -f "$INC" ]] && grep -q '"te-agents-md-turn-cost"' "$INC"; then
  fail "te-agents-md-turn-cost emitted with flag off: $(cat "$INC")"
else
  pass "ratio path computed but not emitted"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 9b: same fixture with RATIO_EMIT_ENABLED=1 → emit fires.
# ------------------------------------------------------------------------
echo "Scenario 9b: ratio gated on (RATIO_EMIT_ENABLED=1) → emit fires"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
plant_envelope "$ROOT" "sess-9b" "general-purpose" 80000
RATIO_EMIT_ENABLED=1 run_script "$ROOT" "sess-9b" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
if [[ ! -f "$INC" ]]; then
  fail "no rule-incidents written"
elif ! grep -q '"te-agents-md-turn-cost"' "$INC"; then
  fail "expected te-agents-md-turn-cost: $(cat "$INC")"
else
  pass "te-agents-md-turn-cost warn emitted"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 10: missing session-tokens.jsonl → graceful, no spurious emit.
# ------------------------------------------------------------------------
echo "Scenario 10: missing .session-tokens.jsonl"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
# No envelopes planted at all — file simply doesn't exist.
run_script "$ROOT" "sess-10" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
if [[ -f "$INC" ]] && grep -q '"te-subagent-overshoot"' "$INC"; then
  fail "te-subagent-overshoot emitted from missing file"
else
  pass "no spurious emit when session-tokens absent"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 11 (R7): first-commit-on-branch fallback uses merge-base.
# ------------------------------------------------------------------------
echo "Scenario 11 (R7): first-commit-on-branch falls back to merge-base"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
# Reset to one commit only — HEAD~1 won't resolve.
(cd "$ROOT" && git reset -q --hard $(git rev-list --max-parents=0 HEAD))
# Add a >50-line diff in a new commit.
(cd "$ROOT" && for i in $(seq 1 80); do echo "newline $i"; done > newfile && git add -A && git commit -q -m "feat: add many lines")
plant_envelope "$ROOT" "sess-11" "general-purpose" 120000
OUT=$(run_script "$ROOT" "sess-11")
INC="$ROOT/.claude/.rule-incidents.jsonl"
if echo "$OUT" | grep -q "skipped"; then
  fail "skipped despite >50-line first-commit (R7 fallback broken)"
elif [[ ! -f "$INC" ]] || ! grep -q '"te-subagent-overshoot"' "$INC"; then
  fail "expected te-subagent-overshoot for >50-line first-commit; got: $OUT"
else
  pass "first-commit-on-branch counted via merge-base fallback"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 12 (R6): recursive self-exclusion via compound_entry_ts.
# ------------------------------------------------------------------------
echo "Scenario 12 (R6): self-exclusion of post-compound-entry envelopes"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
# Plant compound entry timestamp via skill-invocations.
plant_skill "$ROOT" "sess-12" "soleur:compound" "2026-04-25T12:00:00Z"
# Pre-entry envelope (counted): 50k tokens.
plant_envelope "$ROOT" "sess-12" "general-purpose" 50000 "2026-04-25T11:30:00Z"
# Post-entry envelope (excluded): 200k tokens — would trigger overshoot if counted.
plant_envelope "$ROOT" "sess-12" "deviation-analyst" 200000 "2026-04-25T12:30:00Z"
run_script "$ROOT" "sess-12" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
# Only the pre-entry 50k envelope counts → MAX_ENVELOPE=50000 → no overshoot.
if [[ -f "$INC" ]] && grep -q '"te-subagent-overshoot"' "$INC"; then
  fail "post-entry envelope leaked into MAX_ENVELOPE: $(cat "$INC")"
else
  pass "post-compound-entry envelopes excluded"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 13: non-namespaced skill path resolution (find-skills, no plugin: prefix).
# ------------------------------------------------------------------------
echo "Scenario 13: unscoped skill name resolves via find fallback"
ROOT=$(make_fixture); ROOTS+=("$ROOT")
plant_skill "$ROOT" "sess-13" "find-skills"
# Bloat find-skills SKILL.md past the floor so we can verify the case-statement
# fall-through path actually located the file.
printf '%s\n' "$(printf 'z%.0s' {1..220000})" >> "$ROOT/plugins/soleur/skills/find-skills/SKILL.md"
run_script "$ROOT" "sess-13" >/dev/null
INC="$ROOT/.claude/.rule-incidents.jsonl"
if [[ ! -f "$INC" ]]; then
  fail "no telemetry emit (find-fallback didn't locate find-skills SKILL.md?)"
elif ! grep -q '"te-skill-payload-floor"' "$INC"; then
  fail "expected te-skill-payload-floor: $(cat "$INC")"
else
  pass "unscoped skill name resolved + payload counted"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Scenario 14: SKILL.md Phase 1.6 budget — sentinel-delimited region ≤ 1200 bytes.
# ------------------------------------------------------------------------
echo "Scenario 14: SKILL.md Phase 1.6 budget ≤ 1200 bytes"
if [[ ! -f "$SKILL_MD" ]]; then
  fail "SKILL.md not found at $SKILL_MD"
elif ! grep -q '<!-- phase-1.6-start -->' "$SKILL_MD"; then
  fail "phase-1.6-start sentinel missing"
elif ! grep -q '<!-- phase-1.6-end -->' "$SKILL_MD"; then
  fail "phase-1.6-end sentinel missing"
else
  BYTES=$(awk '/<!-- phase-1.6-start -->/,/<!-- phase-1.6-end -->/' "$SKILL_MD" | wc -c)
  if [[ "$BYTES" -gt 1200 ]]; then
    fail "Phase 1.6 section is $BYTES bytes (limit 1200)"
  else
    pass "Phase 1.6 section is $BYTES bytes (≤1200 budget)"
  fi
fi

# ------------------------------------------------------------------------
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
