#!/usr/bin/env bash
# Tests for agent-token-tee.sh — PostToolUse hook teeing subagent token
# envelopes to .claude/.session-tokens.jsonl (issue #3494).
#
# Modeled after .claude/hooks/skill-invocation-logger.test.sh.
# The hook reads the empirical PostToolUse(Agent) input shape documented in
# knowledge-base/project/learnings/2026-05-10-claude-code-posttooluse-task-hook-input-shape.md.
#
# Run via:  bash .claude/hooks/agent-token-tee.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/agent-token-tee.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

ROOTS=()
trap 'for r in "${ROOTS[@]}"; do rm -rf "$r"; done' EXIT

make_root() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude"
  echo "$dir"
}

logfile_for() {
  echo "$1/.claude/.session-tokens.jsonl"
}

# Canonical empirical input fixture (Claude Code 2.1.138, 2026-05-10).
# Uses `printf` (not `cat <<EOF`) so the writer completes in a single atomic
# syscall — avoids SIGPIPE on kill-switch tests that close stdin early.
fixture_canonical() {
  local sid="${1:-sess-canonical}"
  local subagent="${2:-Explore}"
  local total_tokens="${3:-25741}"
  local total_tools="${4:-1}"
  local total_dur="${5:-3536}"
  printf '{"session_id":"%s","transcript_path":"/tmp/x.jsonl","cwd":"/tmp","permission_mode":"auto","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"p","subagent_type":"%s"},"tool_response":{"status":"completed","prompt":"p","agentId":"a1","agentType":"%s","content":[{"type":"text","text":"ok"}],"totalDurationMs":%d,"totalTokens":%d,"totalToolUseCount":%d,"usage":{"input_tokens":5,"output_tokens":58},"toolStats":{}},"tool_use_id":"toolu_1","duration_ms":%d}\n' \
    "$sid" "$subagent" "$subagent" "$total_dur" "$total_tokens" "$total_tools" "$total_dur"
}

# ------------------------------------------------------------------------
# Test 1: canonical Agent invocation → JSONL line written with all required fields.
# ------------------------------------------------------------------------
echo "Test 1: canonical Agent input → JSONL line with all fields"
ROOT=$(make_root); ROOTS+=("$ROOT")
fixture_canonical "sess-1" "Explore" 25741 1 3536 \
  | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ ! -f "$LOG" ]]; then
  fail "log file not created"
elif ! jq -e '.schema == 1' "$LOG" >/dev/null 2>&1; then
  fail "missing or wrong schema field: $(cat "$LOG")"
elif ! jq -e '.session_id == "sess-1"' "$LOG" >/dev/null 2>&1; then
  fail "missing session_id: $(cat "$LOG")"
elif ! jq -e '.subagent_type == "Explore"' "$LOG" >/dev/null 2>&1; then
  fail "missing subagent_type: $(cat "$LOG")"
elif ! jq -e '.total_tokens == 25741' "$LOG" >/dev/null 2>&1; then
  fail "wrong total_tokens: $(cat "$LOG")"
elif ! jq -e '.tool_uses == 1' "$LOG" >/dev/null 2>&1; then
  fail "wrong tool_uses: $(cat "$LOG")"
elif ! jq -e '.duration_ms == 3536' "$LOG" >/dev/null 2>&1; then
  fail "wrong duration_ms: $(cat "$LOG")"
elif ! jq -e '.hook_event == "PostToolUse"' "$LOG" >/dev/null 2>&1; then
  fail "wrong hook_event"
elif ! jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$LOG" >/dev/null 2>&1; then
  fail "ts not ISO-8601 UTC"
else
  pass "all 7 fields populated correctly"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 2: kill-switch (SOLEUR_DISABLE_AGENT_TOKEN_TEE=1) writes nothing.
# ------------------------------------------------------------------------
echo "Test 2: kill-switch honored"
ROOT=$(make_root); ROOTS+=("$ROOT")
fixture_canonical \
  | SOLEUR_DISABLE_AGENT_TOKEN_TEE=1 AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ -f "$LOG" ]]; then
  fail "log file created despite kill-switch"
else
  pass "no log file when SOLEUR_DISABLE_AGENT_TOKEN_TEE=1"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 3: missing totalTokens (degraded Claude Code release) → graceful skip,
# no line written, exit 0. Per plan R1 mitigation.
# ------------------------------------------------------------------------
echo "Test 3: missing totalTokens → graceful skip"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
echo '{"session_id":"sess-3","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"subagent_type":"Explore"},"tool_response":{"status":"completed","agentType":"Explore"}}' \
  | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
RC=$?
set -e
LOG=$(logfile_for "$ROOT")
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC (expected 0, hook must fail soft)"
elif [[ -f "$LOG" ]]; then
  fail "log file written despite missing totalTokens (would create fake zero-cost envelopes)"
else
  pass "exit 0, no log file when totalTokens absent"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 4: invalid JSON input fails soft, no log, exit 0.
# ------------------------------------------------------------------------
echo "Test 4: invalid JSON input"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
echo "not-valid-json-at-all" | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
RC=$?
set -e
LOG=$(logfile_for "$ROOT")
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC (expected 0)"
elif [[ -f "$LOG" ]]; then
  fail "log file written despite invalid input"
else
  pass "exit 0, no log file"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 5: missing tool_name (or non-Agent tool slipping through matcher).
# ------------------------------------------------------------------------
echo "Test 5: non-Agent tool input"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
echo '{"session_id":"x","tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
RC=$?
set -e
LOG=$(logfile_for "$ROOT")
if [[ "$RC" -ne 0 ]]; then
  fail "exit code $RC (expected 0)"
elif [[ -f "$LOG" ]]; then
  fail "log file written for non-Agent tool"
else
  pass "no log when tool_name != Agent"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 6: 50 concurrent fires under flock → 50 valid lines.
# ------------------------------------------------------------------------
echo "Test 6: 50 concurrent fires under flock"
ROOT=$(make_root); ROOTS+=("$ROOT")
for i in $(seq 1 50); do
  (
    fixture_canonical "sess-conc-$i" "Explore" "$((1000 + i))" 1 100 \
      | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
  ) &
done
wait
LOG=$(logfile_for "$ROOT")
if [[ ! -f "$LOG" ]]; then
  fail "no log file after concurrent fires"
else
  LINES=$(wc -l < "$LOG")
  VALID=$(jq -c '.session_id' "$LOG" 2>/dev/null | wc -l)
  UNIQ=$(jq -r '.session_id' "$LOG" 2>/dev/null | sort -u | wc -l)
  if [[ "$LINES" -ne 50 ]]; then
    fail "expected 50 lines, got $LINES (interleaving / torn writes?)"
  elif [[ "$VALID" -ne 50 ]]; then
    fail "expected 50 parseable lines, got $VALID"
  elif [[ "$UNIQ" -ne 50 ]]; then
    fail "expected 50 unique session_ids, got $UNIQ (drops + duplicates?)"
  else
    pass "50 lines, all parse, all session_ids distinct"
  fi
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 7: empty stdin → exit 0, no log.
# ------------------------------------------------------------------------
echo "Test 7: empty stdin"
ROOT=$(make_root); ROOTS+=("$ROOT")
set +e
: | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
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
# Test 8: tool_response.totalTokens == 0 with status=completed is treated as
# missing (R1 mitigation: never count zero-cost envelopes — they indicate
# upstream shape drift, not a real zero-cost subagent).
# ------------------------------------------------------------------------
echo "Test 8: totalTokens=0 treated as missing (R1)"
ROOT=$(make_root); ROOTS+=("$ROOT")
fixture_canonical "sess-8" "Explore" 0 1 100 \
  | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ -f "$LOG" ]]; then
  fail "log file written with totalTokens=0 (would mask shape drift)"
else
  pass "no log when totalTokens=0"
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
# Test 9: defensive fallbacks for tool_uses / duration_ms (both absent).
# Hook still writes line because totalTokens IS present.
# ------------------------------------------------------------------------
echo "Test 9: defensive fallback for tool_uses / duration_ms"
ROOT=$(make_root); ROOTS+=("$ROOT")
echo '{"session_id":"sess-9","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"subagent_type":"Explore"},"tool_response":{"status":"completed","agentType":"Explore","totalTokens":12345}}' \
  | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ ! -f "$LOG" ]]; then
  fail "no log file (totalTokens present, should write)"
elif ! jq -e '.total_tokens == 12345 and .tool_uses == 0 and .duration_ms == 0' "$LOG" >/dev/null 2>&1; then
  fail "expected total_tokens=12345, tool_uses=0, duration_ms=0; got $(cat "$LOG")"
else
  pass "defensive fallback to 0 for missing tool_uses / duration_ms"
fi
rm -rf "$ROOT"


# ------------------------------------------------------------------------
# Test 10: SUBAGENT_TYPE length cap (>64 chars truncates).
# Length cap is the simplest assertion to verify in the test environment.
# Control-char and U+2028/U+2029 stripping is exercised by code review +
# the hooks shell sanitizer (tr -d + sed) — embedding those bytes in test
# JSON is fragile because (a) the Edit tool rewrites U+2028/U+2029 in
# source files per cq-regex-unicode-separators-escape-only, and (b) bare
# control bytes in JSON are spec-invalid so jq rejects the input.
# ------------------------------------------------------------------------
echo "Test 10: SUBAGENT_TYPE length cap"
ROOT=$(make_root); ROOTS+=("$ROOT")
LONG_NAME="overflow-name-$(printf 'x%.0s' {1..120})"   # 134 chars, ≫64
fixture_canonical "sess-10" "$LONG_NAME" 50000 1 1000 \
  | AGENT_TOKEN_TEE_REPO_ROOT="$ROOT" bash "$HOOK"
LOG=$(logfile_for "$ROOT")
if [[ ! -f "$LOG" ]]; then
  fail "no log file"
else
  STORED_LEN=$(jq -r ".subagent_type | length" "$LOG" 2>/dev/null)
  if [[ -z "$STORED_LEN" ]] || (( STORED_LEN > 64 )); then
    fail "subagent_type not capped at 64 chars (got \"$STORED_LEN\")"
  else
    pass "length capped to $STORED_LEN chars (<=64)"
  fi
fi
rm -rf "$ROOT"

# ------------------------------------------------------------------------
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
