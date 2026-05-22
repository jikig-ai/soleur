#!/usr/bin/env bash
# Tests for no-memory-write.sh.
# Run via:  bash .claude/hooks/no-memory-write.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/no-memory-write.sh"

[[ -x "$HOOK" ]] || { echo "ERROR: $HOOK not executable" >&2; exit 1; }

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: invoke the hook with a synthetic Write/Edit payload and capture
# (a) the stdout JSON, (b) the exit code.
invoke() {
  local file_path="$1"
  printf '{"tool_input":{"file_path":"%s"}}' "$file_path" | bash "$HOOK"
}

# ------------------------------------------------------------------------
# T1 — write to memory path: deny + permissionDecisionReason mentions rule.
# ------------------------------------------------------------------------
echo "T1: write to ~/.claude/projects/<slug>/memory/foo.md → deny"
out=$(invoke "/home/jean/.claude/projects/-home-jean-git-repositories-jikig-ai-soleur/memory/feedback_x.md")
rc=$?
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
if [[ "$rc" == "0" ]] \
   && [[ "$decision" == "deny" ]] \
   && [[ "$reason" == *"hr-never-write-to-claude-code-memory-claude"* ]] \
   && [[ "$reason" == *"knowledge-base/project/learnings"* ]]; then
  pass "deny + rule + remediation in reason"
else
  fail "rc=$rc decision=$decision reason_head=${reason:0:80}"
fi

# ------------------------------------------------------------------------
# T2 — write to repo path: pass-through (no decision emitted).
# ------------------------------------------------------------------------
echo "T2: write to repo path → pass-through"
out=$(invoke "/home/jean/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/foo.md")
rc=$?
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$rc" == "0" ]] && [[ -z "$decision" ]]; then
  pass "no decision emitted for repo paths"
else
  fail "rc=$rc decision=$decision out=$out"
fi

# ------------------------------------------------------------------------
# T3 — write to memory MEMORY.md (the index) → deny.
# ------------------------------------------------------------------------
echo "T3: write to memory/MEMORY.md (index) → deny"
out=$(invoke "/home/jean/.claude/projects/-some-project/memory/MEMORY.md")
rc=$?
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$rc" == "0" ]] && [[ "$decision" == "deny" ]]; then
  pass "deny on memory index too"
else
  fail "rc=$rc decision=$decision"
fi

# ------------------------------------------------------------------------
# T4 — write to ~/.claude/<other>/foo.md (NOT under projects/<slug>/memory)
#       → pass-through. The regex requires the projects/<slug>/memory shape.
# ------------------------------------------------------------------------
echo "T4: write to other ~/.claude/ paths → pass-through"
out=$(invoke "/home/jean/.claude/settings.json")
rc=$?
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$rc" == "0" ]] && [[ -z "$decision" ]]; then
  pass "no decision for settings.json (not a memory path)"
else
  fail "rc=$rc decision=$decision"
fi

# ------------------------------------------------------------------------
# T5 — empty file_path → pass-through (no-op).
# ------------------------------------------------------------------------
echo "T5: empty file_path → pass-through"
out=$(printf '{"tool_input":{}}' | bash "$HOOK")
rc=$?
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$rc" == "0" ]] && [[ -z "$decision" ]]; then
  pass "no-op on missing file_path"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T6 — adversarial: file path containing 'memory' as a substring but NOT
#       under projects/<slug>/memory/ → pass-through (false-positive guard).
# ------------------------------------------------------------------------
echo "T6: false-positive guard for unrelated 'memory' substrings"
out=$(invoke "/home/jean/code/memory-allocator/main.rs")
rc=$?
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$rc" == "0" ]] && [[ -z "$decision" ]]; then
  pass "no false-positive on unrelated 'memory' in path"
else
  fail "rc=$rc decision=$decision"
fi

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
