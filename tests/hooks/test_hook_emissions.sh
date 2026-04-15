#!/usr/bin/env bash
# End-to-end test: each deny branch in the hook scripts emits a jsonl
# incident line with the expected rule_id. Drives the hooks by piping
# synthetic tool-input JSON to stdin, the same contract claude-code-action
# uses (see .github/workflows/test-pretooluse-hooks.yml).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pass=0; fail=0

# Isolate the jsonl file per run so we don't contaminate dev telemetry.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Mirror the repo layout so BASH_SOURCE resolution inside the hooks lands
# in $WORK instead of the real repo.
mkdir -p "$WORK/.claude/hooks/lib"
cp "$REPO_ROOT/.claude/hooks/lib/incidents.sh" "$WORK/.claude/hooks/lib/"
cp "$REPO_ROOT/.claude/hooks/guardrails.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/.claude/hooks/pencil-open-guard.sh" "$WORK/.claude/hooks/"
cp "$REPO_ROOT/.claude/hooks/worktree-write-guard.sh" "$WORK/.claude/hooks/"
chmod +x "$WORK/.claude/hooks/"*.sh

FILE="$WORK/.claude/.rule-incidents.jsonl"

_check() {
  local label="$1" rid="$2"
  if [[ -s "$FILE" ]] && jq -e --arg r "$rid" 'select(.rule_id == $r)' < "$FILE" >/dev/null 2>&1; then
    pass=$((pass + 1))
    echo "[ok] $label → emitted $rid"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label (expected rule_id=$rid)" >&2
    echo "  file contents:" >&2
    cat "$FILE" >&2 || true
  fi
  : > "$FILE"  # reset between cases
}

# --- guardrails: block-stash-in-worktrees (uses real CWD → must be a worktree path)
# We fabricate a worktree-like path under $WORK and call the hook with .cwd set.
mkdir -p "$WORK/.worktrees/fake/inner"
echo '{"tool_name":"Bash","tool_input":{"command":"git stash"},"cwd":"'"$WORK/.worktrees/fake/inner"'"}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: git stash in worktree" "hr-never-git-stash-in-worktrees"

# --- guardrails: bypass preflight (--no-verify should emit without blocking)
echo '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: --no-verify bypass preflight" "cq-never-skip-hooks"

# --- guardrails: bypass preflight (LEFTHOOK=0)
echo '{"tool_name":"Bash","tool_input":{"command":"LEFTHOOK=0 git commit -m foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: LEFTHOOK=0 bypass preflight" "cq-when-lefthook-hangs-in-a-worktree-60s"

# --- guardrails: rm -rf worktrees
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf .worktrees/foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: rm -rf worktrees" "guardrails-block-rm-rf-worktrees"

# --- guardrails: require-milestone
echo '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title foo"}}' \
  | bash "$WORK/.claude/hooks/guardrails.sh" >/dev/null 2>&1 || true
_check "guardrails: require-milestone" "guardrails-require-milestone"

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
