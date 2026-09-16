#!/usr/bin/env bash
# Tests for lib/hook-tool-kind.sh — the canonical Devin→Claude tool-kind map
# (issue #8205). Devin's wire names are lowercase (exec, write, edit); hook
# bodies gate on the Claude-canonical kind. One map, consumed by
# lib/hook-input.sh (HOOK_TOOL_KIND) and by own-jq hooks directly.
#
# Measured tool names: knowledge-base/project/specs/
# feat-settings-matcher-devin-audit/envelope-capture.md §7.
#
# Run via:  bash .claude/hooks/hook-tool-kind.test.sh

set -euo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# ------------------------------------------------------------------------
# Test 1: the map file exists and is sourceable.
# ------------------------------------------------------------------------
echo "Test 1: lib/hook-tool-kind.sh exists"
if [[ ! -f "$SCRIPT_DIR/lib/hook-tool-kind.sh" ]]; then
  fail "lib/hook-tool-kind.sh missing"
  echo; echo "=== hook-tool-kind: $PASS passed, $FAIL failed ==="
  exit 1
fi
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/hook-tool-kind.sh"
pass "sourced"

# ------------------------------------------------------------------------
# Test 2: every mapped Devin name returns its Claude-canonical kind.
# ------------------------------------------------------------------------
echo "Test 2: hook_tool_kind mappings"
check_map() {
  local wire="$1" want="$2" got
  got="$(hook_tool_kind "$wire")"
  if [[ "$got" == "$want" ]]; then pass "$wire → $want"; else fail "$wire → $got (want $want)"; fi
}
check_map exec Bash
check_map write Write
check_map edit Edit
check_map multi_edit MultiEdit
check_map notebook_edit NotebookEdit
check_map apply_patch Write
check_map ask_user_question AskUserQuestion
check_map run_subagent Agent
check_map skill Skill

# ------------------------------------------------------------------------
# Test 3: unmapped and already-canonical names pass through unchanged.
# ------------------------------------------------------------------------
echo "Test 3: passthrough"
check_map Bash Bash
check_map Write Write
check_map read read
check_map todo_write todo_write
check_map grep grep
check_map mcp__srv__tool mcp__srv__tool
check_map "" ""

# ------------------------------------------------------------------------
# Test 4: hook_parse_input exports HOOK_TOOL_KIND alongside a byte-exact
# HOOK_TOOL_NAME (A17 stays green: the raw name is not rewritten).
# ------------------------------------------------------------------------
echo "Test 4: hook_parse_input exports HOOK_TOOL_KIND"
. "$SCRIPT_DIR/lib/hook-input.sh"

devin_exec='{"hook_event_name":"PreToolUse","tool_name":"exec","tool_input":{"command":"echo hi"},"session_id":"s","cwd":"/tmp"}'
if hook_parse_input "$devin_exec"; then
  [[ "$HOOK_TOOL_NAME" == "exec" ]] && pass "HOOK_TOOL_NAME byte-exact (exec)" \
    || fail "HOOK_TOOL_NAME mangled: $HOOK_TOOL_NAME"
  [[ "${HOOK_TOOL_KIND-UNSET}" == "Bash" ]] && pass "HOOK_TOOL_KIND=Bash for exec" \
    || fail "HOOK_TOOL_KIND=${HOOK_TOOL_KIND-UNSET} (want Bash)"
else
  fail "hook_parse_input rejected a valid Devin exec envelope"
fi

devin_write='{"hook_event_name":"PreToolUse","tool_name":"write","tool_input":{"file_path":"/tmp/x","content":"c"},"session_id":"s","cwd":"/tmp"}'
hook_parse_input "$devin_write"
[[ "${HOOK_TOOL_KIND-UNSET}" == "Write" ]] && pass "HOOK_TOOL_KIND=Write for write" \
  || fail "HOOK_TOOL_KIND=${HOOK_TOOL_KIND-UNSET} (want Write)"

claude_bash='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"session_id":"s","cwd":"/tmp"}'
hook_parse_input "$claude_bash"
[[ "$HOOK_TOOL_NAME" == "Bash" && "${HOOK_TOOL_KIND-UNSET}" == "Bash" ]] \
  && pass "Claude Bash envelope: name and kind both Bash" \
  || fail "Claude envelope: name=$HOOK_TOOL_NAME kind=${HOOK_TOOL_KIND-UNSET}"

# A Devin name with no mapping yields kind == name (passthrough, not empty).
devin_glob='{"hook_event_name":"PreToolUse","tool_name":"glob","tool_input":{"pattern":"*"},"session_id":"s","cwd":"/tmp"}'
hook_parse_input "$devin_glob"
[[ "${HOOK_TOOL_KIND-UNSET}" == "glob" ]] && pass "unmapped glob → kind=glob" \
  || fail "unmapped glob → kind=${HOOK_TOOL_KIND-UNSET}"

# ------------------------------------------------------------------------
# Test 5: drift guard — security_reminder_hook.py's _TOOL_KIND dict must
# agree with hook_tool_kind() on every mapped name (repo convention:
# duplicated logic gets a parity pin).
# ------------------------------------------------------------------------
echo "Test 5: bash↔python map parity"
if command -v python3 >/dev/null 2>&1; then
  drift=""
  for wire in exec write edit multi_edit notebook_edit apply_patch \
              ask_user_question run_subagent skill __unmapped__; do
    b="$(hook_tool_kind "$wire")"
    p="$(python3 -c "
import sys; sys.path.insert(0, '$SCRIPT_DIR')
import security_reminder_hook as s
print(s.tool_kind('$wire'))")"
    if [[ "$b" != "$p" ]]; then drift="$drift $wire(bash=$b,py=$p)"; fi
  done
  if [[ -z "$drift" ]]; then pass "maps agree"; else fail "map drift:$drift"; fi
else
  echo "  SKIP: python3 missing — parity unchecked"
fi

# Test 5b: the plugin copy (plugins/soleur/hooks/lib/hook-tool-kind.sh) claims
# this pin in its header — make the claim real by sourcing it into a subshell
# and comparing the mapped vocabulary.
echo "Test 5b: bash↔plugin-copy map parity"
PLUGIN_KIND="$SCRIPT_DIR/../../plugins/soleur/hooks/lib/hook-tool-kind.sh"
if [[ -f "$PLUGIN_KIND" ]]; then
  drift=""
  for wire in exec write edit multi_edit notebook_edit apply_patch \
              ask_user_question run_subagent skill __unmapped__; do
    b="$(hook_tool_kind "$wire")"
    p="$( ( . "$PLUGIN_KIND"; hook_tool_kind "$wire" ) )"
    if [[ "$b" != "$p" ]]; then drift="$drift $wire(canon=$b,plugin=$p)"; fi
  done
  if [[ -z "$drift" ]]; then pass "plugin copy agrees"; else fail "plugin map drift:$drift"; fi
else
  fail "plugin kind-map copy missing: $PLUGIN_KIND"
fi

echo; echo "=== hook-tool-kind: $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
