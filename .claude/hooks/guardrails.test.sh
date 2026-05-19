#!/usr/bin/env bash
# Smoke-tests for guardrails.sh: primarily the guardrails:block-stash-in-worktrees rule.
# Issue #3135: git stash hook did not fire in a 2026-05-04 session — these tests
# verify the deny payload is emitted and the incidents JSONL is written correctly.
#
# Also covers: hook registration in settings.json (integration smoke test).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/guardrails.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

make_payload() {
  local cwd="${1:-/tmp}" cmd="$2"
  jq -nc --arg c "$cwd" --arg x "$cmd" '{tool_name: "Bash", tool_input: {command: $x}, cwd: $c}'
}

assert_deny() {
  local name="$1" incidents="$2" out="$3" exit_code="$4" expected_rule="${5:-}"
  TOTAL=$((TOTAL + 1))
  local decision
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  local seen_rule="" seen_event=""
  if [[ -f "$jsonl" ]]; then
    seen_rule=$(jq -r 'select(.rule_id != null) | .rule_id' < "$jsonl" 2>/dev/null | tail -1 || echo "")
    seen_event=$(jq -r 'select(.event_type != null) | .event_type' < "$jsonl" 2>/dev/null | tail -1 || echo "")
  fi
  if [[ "$exit_code" -eq 0 && "$decision" == "deny" ]]; then
    if [[ -n "$expected_rule" && "$seen_rule" != "$expected_rule" ]]; then
      echo "FAIL: $name (rule_id mismatch: got='$seen_rule' expected='$expected_rule')"
      FAIL=$((FAIL + 1))
    else
      echo "PASS: $name"
      PASS=$((PASS + 1))
    fi
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code decision='$decision' seen_rule='$seen_rule' seen_event='$seen_event'"
    FAIL=$((FAIL + 1))
  fi
}

assert_pass() {
  local name="$1" incidents="$2" out="$3" exit_code="$4"
  TOTAL=$((TOTAL + 1))
  local decision
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  local denied_rows=0
  local jsonl="$incidents/.claude/.rule-incidents.jsonl"
  if [[ -f "$jsonl" ]]; then
    denied_rows=$(grep -c '"event_type":"deny"' "$jsonl" 2>/dev/null || echo 0)
  fi
  if [[ "$exit_code" -eq 0 && "$decision" != "deny" && "$denied_rows" -eq 0 ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  exit=$exit_code decision='$decision' denied_rows=$denied_rows"
    FAIL=$((FAIL + 1))
  fi
}

run_hook() {
  local incidents="$1" payload="$2"
  printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null
}

# T1: plain `git stash` → DENY with correct rule_id
t1_git_stash_plain_deny() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"; mkdir -p "$incidents"
  local payload out exit_code=0
  payload=$(make_payload "$tmp" "git stash")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T1 git stash plain" "$incidents" "$out" "$exit_code" "hr-never-git-stash-in-worktrees"
  rm -rf "$tmp"
}

# T2: `git stash pop` → DENY (restore half of the issue #3135 command)
t2_git_stash_pop_deny() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"; mkdir -p "$incidents"
  local payload out exit_code=0
  payload=$(make_payload "$tmp" "git stash pop")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T2 git stash pop" "$incidents" "$out" "$exit_code" "hr-never-git-stash-in-worktrees"
  rm -rf "$tmp"
}

# T3: chained form — the exact command from issue #3135 that was not blocked
t3_chained_stash_deny() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"; mkdir -p "$incidents"
  local cmd='git stash && bash plugins/soleur/test/schedule-skill-once.test.sh 2>&1 | grep -E "FAIL|Passed|Failed" | tail -5; echo "---restoring---"; git stash pop'
  local payload out exit_code=0
  payload=$(make_payload "$tmp" "$cmd")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T3 chained git stash (issue #3135 exact form)" "$incidents" "$out" "$exit_code" "hr-never-git-stash-in-worktrees"
  rm -rf "$tmp"
}

# T4: `git stash list` → DENY (any git stash subcommand is blocked)
t4_git_stash_list_deny() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"; mkdir -p "$incidents"
  local payload out exit_code=0
  payload=$(make_payload "$tmp" "git stash list")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  exit_code=${exit_code:-0}
  assert_deny "T4 git stash list" "$incidents" "$out" "$exit_code" "hr-never-git-stash-in-worktrees"
  rm -rf "$tmp"
}

# T5: `git status` → PASS (non-stash command passes through)
t5_git_status_pass() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"; mkdir -p "$incidents"
  local payload out exit_code=0
  payload=$(make_payload "$tmp" "git status")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  exit_code=${exit_code:-0}
  assert_pass "T5 git status passthrough" "$incidents" "$out" "$exit_code"
  rm -rf "$tmp"
}

# T6: deny reason cites the expected blocked message
t6_deny_reason_content() {
  local tmp; tmp=$(mktemp -d)
  local incidents="$tmp/incidents"; mkdir -p "$incidents"
  TOTAL=$((TOTAL + 1))
  local payload out exit_code=0
  payload=$(make_payload "$tmp" "git stash")
  out=$(run_hook "$incidents" "$payload") || exit_code=$?
  exit_code=${exit_code:-0}
  local reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  if [[ "$reason" == *"BLOCKED: git stash"* ]]; then
    echo "PASS: T6 deny reason cites 'BLOCKED: git stash'"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T6 deny reason missing expected text: '$reason'"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$tmp"
}

# T7: settings.json registers guardrails.sh as a PreToolUse/Bash hook
t7_settings_json_registration() {
  TOTAL=$((TOTAL + 1))
  local settings="$REPO_ROOT/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo "FAIL: T7 settings.json not found at $settings"
    FAIL=$((FAIL + 1))
    return
  fi
  local registered
  registered=$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$settings" 2>/dev/null \
    | grep -c "guardrails.sh" || echo 0)
  if [[ "$registered" -ge 1 ]]; then
    echo "PASS: T7 guardrails.sh registered in settings.json PreToolUse/Bash hooks"
    PASS=$((PASS + 1))
  else
    echo "FAIL: T7 guardrails.sh not found in settings.json PreToolUse/Bash hooks"
    FAIL=$((FAIL + 1))
  fi
}

t1_git_stash_plain_deny
t2_git_stash_pop_deny
t3_chained_stash_deny
t4_git_stash_list_deny
t5_git_status_pass
t6_deny_reason_content
t7_settings_json_registration

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]] || exit 1
