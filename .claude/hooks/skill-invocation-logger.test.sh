#!/usr/bin/env bash
# Tests for skill-invocation-logger.sh.
#
# Mirrors the bash-test pattern from pre-merge-rebase.test.sh and
# security_reminder_hook.test.sh. Runs the hook with a controlled
# SKILL_LOGGER_REPO_ROOT so writes don't touch the operator's real
# .claude/.skill-invocations.jsonl.
#
# Run via:  bash .claude/hooks/skill-invocation-logger.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/skill-invocation-logger.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Track all temp roots so an unexpected `set -e` exit still cleans them up.
ROOTS=()
trap 'for r in "${ROOTS[@]}"; do rm -rf "$r"; done' EXIT

# Each test gets its own SKILL_LOGGER_REPO_ROOT so they don't interfere.
# Caller must `ROOTS+=("$ROOT")` after `ROOT=$(make_root); ROOTS+=("$ROOT")` so the trap can
# clean up — the array push must happen in the parent shell, not the
# command-substitution subshell.
make_root() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude"
  echo "$dir"
}

logfile_for() {
  echo "$1/.claude/.skill-invocations.jsonl"
}

# ------------------------------------------------------------------------
# Test 1: skill-name extraction from canonical Skill tool input shape.
# ------------------------------------------------------------------------
echo "Test 1: skill-name extraction"
ROOT=$(make_root); ROOTS+=("$ROOT")
echo '{"tool_name":"Skill","tool_input":{"skill":"soleur:plan","args":"x"},"session_id":"sess-1"}' \
  | SKILL_LOGGER_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ ! -f "$LOG" ]]; then
  fail "log file not created"
elif ! jq -e '.skill == "soleur:plan"' "$LOG" >/dev/null 2>&1; then
  fail "expected .skill == \"soleur:plan\", got $(cat "$LOG")"
elif ! jq -e '.schema == 1' "$LOG" >/dev/null 2>&1; then
  fail "missing or wrong schema field"
elif ! jq -e '.session_id == "sess-1"' "$LOG" >/dev/null 2>&1; then
  fail "missing session_id"
elif ! jq -e '.hook_event == "PreToolUse"' "$LOG" >/dev/null 2>&1; then
  fail "wrong hook_event"
elif ! jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$LOG" >/dev/null 2>&1; then
  fail "ts not ISO-8601 UTC"
else
  pass "skill, schema, session_id, hook_event, ts all correct"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 2: kill-switch (SOLEUR_DISABLE_SKILL_LOGGER=1) writes nothing.
# ------------------------------------------------------------------------
echo "Test 2: kill-switch honored"
ROOT=$(make_root); ROOTS+=("$ROOT")
echo '{"tool_name":"Skill","tool_input":{"skill":"soleur:should-not-log"}}' \
  | SOLEUR_DISABLE_SKILL_LOGGER=1 SKILL_LOGGER_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ -f "$LOG" ]]; then
  fail "log file created despite kill-switch (contents: $(cat "$LOG"))"
else
  pass "no log file when SOLEUR_DISABLE_SKILL_LOGGER=1"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 3: invalid JSON input fails soft, no log written, exit 0.
# ------------------------------------------------------------------------
echo "Test 3: invalid JSON input"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
echo "not-valid-json-at-all" | SKILL_LOGGER_REPO_ROOT="$ROOT" bash "$HOOK"
RC=$?
set -e
LOG=$(logfile_for "$ROOT")
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC (expected 0, hook must always fail soft)"
elif [[ -f "$LOG" ]]; then
  fail "log file written despite invalid input"
else
  pass "exit 0, no log file"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 4: missing tool_input.skill (e.g., non-Skill tool slipping through
# matcher) writes nothing, exit 0.
# ------------------------------------------------------------------------
echo "Test 4: missing tool_input.skill"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | SKILL_LOGGER_REPO_ROOT="$ROOT" bash "$HOOK"
RC=$?
set -e
LOG=$(logfile_for "$ROOT")
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC (expected 0)"
elif [[ -f "$LOG" ]]; then
  fail "log file written for non-Skill tool input"
else
  pass "no log when tool_input.skill missing"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 5: 50 concurrent fires produce 50 valid lines (flock interlocks).
# ------------------------------------------------------------------------
echo "Test 5: 50 concurrent fires under flock"
ROOT=$(make_root); ROOTS+=("$ROOT")
for i in $(seq 1 50); do
  (
    echo "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"soleur:concurrent-$i\"}}" \
      | SKILL_LOGGER_REPO_ROOT="$ROOT" bash "$HOOK"
  ) &
done
wait
LOG=$(logfile_for "$ROOT")
if [[ ! -f "$LOG" ]]; then
  fail "no log file after concurrent fires"
else
  LINES=$(wc -l < "$LOG")
  VALID=$(jq -c '.skill' "$LOG" 2>/dev/null | wc -l)
  if [[ "$LINES" -ne 50 ]]; then
    fail "expected 50 lines, got $LINES"
  elif [[ "$VALID" -ne 50 ]]; then
    fail "expected 50 parseable JSON lines, got $VALID (corruption under flock?)"
  else
    pass "50 lines, all parse as JSON (no torn writes)"
  fi
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 6: empty stdin → exit 0, no log
# ------------------------------------------------------------------------
echo "Test 6: empty stdin"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
: | SKILL_LOGGER_REPO_ROOT="$ROOT" bash "$HOOK"
RC=$?
set -e
LOG=$(logfile_for "$ROOT")
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC (expected 0)"
elif [[ -f "$LOG" ]]; then
  fail "log file written for empty stdin"
else
  pass "exit 0, no log file"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
