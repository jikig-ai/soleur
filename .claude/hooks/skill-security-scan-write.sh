#!/usr/bin/env bash
# PreToolUse hook on Write tool for skill-security-scan (#2719).
#
# THIS is the load-bearing gate (Kieran P0-1: agent prose alone cannot enforce
# a security gate). The hook fires on every Write to .claude/skills/**,
# .claude/agents/**, plugins/soleur/skills/**/SKILL.md, and
# plugins/soleur/agents/**/*.md. It runs the scanner against the proposed
# tool_input.content (NOT the on-disk file) and decides:
#
#   HIGH-RISK + no override artifact → permissionDecision: deny
#   HIGH-RISK + valid override artifact → permissionDecision: allow (logged)
#   REVIEW                          → permissionDecision: ask
#   LOW-RISK                        → permissionDecision: allow (silent)
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {permissionDecision, permissionDecisionReason}}.
# Hook exit code: 0 always (the JSON output is what controls the gate).

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SCANNER="$PROJECT_DIR/plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh"
PARSE_OVERRIDE="$PROJECT_DIR/plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

# Read the hook payload from stdin (Claude Code provides JSON).
payload="$(cat)"

tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
content="$(echo "$payload" | jq -r '.tool_input.content // empty' 2>/dev/null)"

# Only fire on Write to relevant paths.
if [ "$tool_name" != "Write" ]; then
  echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  exit 0
fi

case "$file_path" in
  *.claude/skills/*SKILL.md|*.claude/agents/*.md|*plugins/soleur/skills/*SKILL.md|*plugins/soleur/agents/*.md) ;;
  *)
    echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
    ;;
esac

if [ -z "$content" ]; then
  echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  exit 0
fi

if [ ! -f "$SCANNER" ]; then
  # Scanner not installed — fail OPEN with informational allow (cannot block
  # without the scanner; downstream lefthook + CI gates remain).
  echo '{"hookSpecificOutput":{"permissionDecision":"allow","permissionDecisionReason":"skill-security-scan: scanner not installed; relying on downstream gates."}}'
  exit 0
fi

# Run scanner against the proposed content.
verdict="$(echo "$content" | SKILL_SECURITY_SCAN_OFFLINE=1 bash "$SCANNER" 2>/dev/null | head -1 | grep -oE 'HIGH-RISK|REVIEW|LOW-RISK' || echo 'UNKNOWN')"

case "$verdict" in
  HIGH-RISK)
    # Check for valid override artifact in current branch.
    override_ok=0
    if [ -f "$PARSE_OVERRIDE" ]; then
      base="$(git merge-base HEAD origin/main 2>/dev/null || echo "main")"
      if bash "$PARSE_OVERRIDE" --base "$base" --head HEAD >/dev/null 2>&1; then
        override_ok=1
      fi
    fi
    if [ "$override_ok" = "1" ]; then
      emit skill-security-scan applied "high-risk-with-override"
      jq -cn '{hookSpecificOutput: {permissionDecision: "allow", permissionDecisionReason: "skill-security-scan: HIGH-RISK with valid override artifact (proceeding)."}}'
    else
      emit skill-security-scan applied "high-risk-no-override"
      reason="BLOCKED: skill-security-scan HIGH-RISK on $file_path without override artifact under knowledge-base/security/skill-overrides/. See plugins/soleur/skills/skill-security-scan/references/override-mechanism.md"
      jq -cn --arg r "$reason" '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
    fi
    ;;
  REVIEW)
    emit skill-security-scan applied "review"
    jq -cn '{hookSpecificOutput: {permissionDecision: "ask", permissionDecisionReason: "skill-security-scan REVIEW finding(s); see scan output above."}}'
    ;;
  LOW-RISK)
    emit skill-security-scan applied "low-risk"
    echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    ;;
  *)
    # Unknown verdict — fail open but log for review.
    emit skill-security-scan applied "unknown-verdict"
    echo '{"hookSpecificOutput":{"permissionDecision":"allow","permissionDecisionReason":"skill-security-scan returned UNKNOWN verdict; falling back to allow."}}'
    ;;
esac

exit 0
