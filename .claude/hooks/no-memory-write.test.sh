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

# Helper: invoke with a Write/Edit-shape payload.
invoke_write() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK"
}
# Helper: invoke with a NotebookEdit-shape payload (notebook_path field).
invoke_notebook() {
  printf '{"tool_input":{"notebook_path":"%s"}}' "$1" | bash "$HOOK"
}
# Helper: invoke with a Bash-shape payload (command field).
invoke_bash() {
  # Escape embedded quotes via jq for arbitrary command strings.
  printf '%s' "$1" | jq -Rs '{tool_input: {command: .}}' | bash "$HOOK"
}

# ------------------------------------------------------------------------
# T1 — Write to memory path: deny + reason mentions rule + source file.
# ------------------------------------------------------------------------
echo "T1: Write to ~/.claude/projects/<slug>/memory/foo.md → deny"
out=$(invoke_write "/home/jean/.claude/projects/-home-jean-git-repositories-jikig-ai-soleur/memory/feedback_x.md")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
if [[ "$decision" == "deny" ]] \
   && [[ "$reason" == *"hr-never-write-to-claude-code-memory-claude"* ]] \
   && [[ "$reason" == *"Source: AGENTS.core.md"* ]] \
   && [[ "$reason" == *"knowledge-base/project/learnings"* ]] \
   && [[ "$reason" == *"knowledge-base/project/constitution.md"* ]]; then
  pass "deny + rule + source-file + remediation"
else
  fail "decision=$decision reason_head=${reason:0:120}"
fi

# ------------------------------------------------------------------------
# T2 — Write to repo path: pass-through.
# ------------------------------------------------------------------------
echo "T2: Write to repo path → pass-through"
out=$(invoke_write "/home/jean/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/foo.md")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ -z "$decision" ]] && pass "no decision for repo paths" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T3 — Write to memory/MEMORY.md (index) → deny.
# ------------------------------------------------------------------------
echo "T3: Write to memory/MEMORY.md (index) → deny"
out=$(invoke_write "/home/jean/.claude/projects/-some-project/memory/MEMORY.md")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ "$decision" == "deny" ]] && pass "deny on memory index" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T4 — Write to other ~/.claude/ paths (not memory) → pass-through.
# ------------------------------------------------------------------------
echo "T4: Write to ~/.claude/settings.json → pass-through"
out=$(invoke_write "/home/jean/.claude/settings.json")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ -z "$decision" ]] && pass "no decision for settings.json" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T5 — Empty tool_input → pass-through (no-op).
# ------------------------------------------------------------------------
echo "T5: empty tool_input → pass-through"
out=$(printf '{"tool_input":{}}' | bash "$HOOK")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ -z "$decision" ]] && pass "no-op on empty tool_input" || fail "out=$out"

# ------------------------------------------------------------------------
# T6 — Adversarial: 'memory' substring outside projects/<slug>/memory/.
# ------------------------------------------------------------------------
echo "T6: false-positive guard for unrelated 'memory'"
out=$(invoke_write "/home/jean/code/memory-allocator/main.rs")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ -z "$decision" ]] && pass "no false-positive on 'memory-allocator'" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T7 — Bare-`$` end-anchor: path ends at /memory with no trailing segment.
# Exercises the `$` branch of the regex's `(/|$|["'\''[:space:]])`
# alternation that prior tests only hit via `/<file>` cases.
# ------------------------------------------------------------------------
echo "T7: bare /memory end-anchor → deny"
out=$(invoke_write "/home/jean/.claude/projects/-slug/memory")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ "$decision" == "deny" ]] && pass "deny on bare /memory (no trailing segment)" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T8 — NotebookEdit: notebook_path (not file_path) → deny.
# Closes the field-shape gap arch-strategist flagged.
# ------------------------------------------------------------------------
echo "T8: NotebookEdit notebook_path → deny"
out=$(invoke_notebook "/home/jean/.claude/projects/-some-project/memory/notes.ipynb")
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ "$decision" == "deny" ]] && pass "deny on NotebookEdit notebook_path" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T9 — Bash bypass: `cat > <memory path> <<EOF` → deny.
# Closes the redirection/copy bypass class security-sentinel flagged P2.
# ------------------------------------------------------------------------
echo "T9: Bash cat-redirect to memory path → deny"
out=$(invoke_bash 'cat > /home/jean/.claude/projects/-slug/memory/leak.md <<EOF
content
EOF')
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ "$decision" == "deny" ]] && pass "deny on Bash cat-redirect bypass attempt" || fail "decision=$decision out=$out"

# ------------------------------------------------------------------------
# T10 — Bash with memory path quoted differently (tee with double-quote).
# ------------------------------------------------------------------------
echo "T10: Bash tee to quoted memory path → deny"
out=$(invoke_bash 'echo x | tee "/home/jean/.claude/projects/-slug/memory/note.md"')
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ "$decision" == "deny" ]] && pass "deny on Bash tee bypass" || fail "decision=$decision out=$out"

# ------------------------------------------------------------------------
# T11 — Bash command that mentions 'memory' but NOT the projects/<slug>/memory
# shape → pass-through. Defends against over-blocking benign commands.
# ------------------------------------------------------------------------
echo "T11: Bash with unrelated 'memory' word → pass-through"
out=$(invoke_bash 'free -m  # check memory usage')
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
[[ -z "$decision" ]] && pass "no false-positive on 'memory' as a word in command" || fail "decision=$decision"

# ------------------------------------------------------------------------
# T12 — Malformed JSON → pass-through (fail-open, not fail-closed).
# A malformed harness payload should not silently block every tool call.
# ------------------------------------------------------------------------
echo "T12: malformed JSON → pass-through (fail-open)"
out=$(printf 'not-json' | bash "$HOOK" 2>/dev/null || true)
decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || echo "")
[[ -z "$decision" ]] && pass "fail-open on malformed JSON" || fail "decision=$decision"

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
