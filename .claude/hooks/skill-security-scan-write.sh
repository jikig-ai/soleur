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

# Path classification. Override-artifact writes get their own ask-by-default
# branch (agent-native review P1: agents could otherwise self-author override
# artifacts to bypass HIGH-RISK denials).
file_kind="none"
case "$file_path" in
  *knowledge-base/security/skill-overrides/*.md)
    file_kind="override" ;;
  *.claude/skills/*SKILL.md|*plugins/soleur/skills/*SKILL.md|*.claude/agents/*.md|*plugins/soleur/agents/*.md)
    file_kind="skill" ;;
  *)
    echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
    exit 0
    ;;
esac

# Derive the slug from the SKILL/agent path (used for per-skill binding).
path_to_slug() {
  local p="$1"
  case "$p" in
    *plugins/soleur/skills/*/SKILL.md)
      p="${p##*plugins/soleur/skills/}"; echo "${p%/SKILL.md}" ;;
    *.claude/skills/*/SKILL.md)
      p="${p##*.claude/skills/}"; echo "${p%/SKILL.md}" ;;
    *.claude/agents/*.md|*plugins/soleur/agents/*.md)
      echo "$(basename "$p" .md)" ;;
    *) echo "" ;;
  esac
}

# Override-artifact writes never auto-allow. Operator must explicitly approve
# their creation in the same way they approve the underlying HIGH-RISK skill.
if [ "$file_kind" = "override" ]; then
  emit skill-security-scan applied "override-artifact-write"
  jq -cn '{hookSpecificOutput: {permissionDecision: "ask", permissionDecisionReason: "skill-security-scan: override artifact write requires explicit operator confirmation. Auto-approval is not permitted (agent-native parity gate)."}}'
  exit 0
fi

if [ -z "$content" ]; then
  echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  exit 0
fi

if [ ! -f "$SCANNER" ]; then
  # Scanner missing → ask, not allow. At single-user-incident threshold a
  # silently-removed scanner must surface for operator approval rather than
  # silently disable enforcement. (Architecture review F4.)
  emit skill-security-scan applied "scanner-missing"
  jq -cn '{hookSpecificOutput: {permissionDecision: "ask", permissionDecisionReason: "skill-security-scan: scanner not installed; cannot evaluate. Approve only if you have manually reviewed the content."}}'
  exit 0
fi

# Run scanner against the proposed content. printf '%s' avoids echo's
# backslash interpretation (security review P2-1) which could split lines and
# hide regex matches.
verdict="$(printf '%s' "$content" | SKILL_SECURITY_SCAN_OFFLINE=1 bash "$SCANNER" 2>/dev/null | head -1 | grep -oE 'HIGH-RISK|REVIEW|LOW-RISK' || echo 'UNKNOWN')"

slug="$(path_to_slug "$file_path")"

case "$verdict" in
  HIGH-RISK)
    # Per-skill override binding: the matched artifact's `skill:` field must
    # equal the slug derived from $file_path. Any-override acceptance was a
    # P1 bypass.
    override_ok=0
    if [ -f "$PARSE_OVERRIDE" ] && [ -n "$slug" ]; then
      base="$(git merge-base HEAD origin/main 2>/dev/null || echo "main")"
      parser_out="$(bash "$PARSE_OVERRIDE" --base "$base" --head HEAD 2>/dev/null || echo '{}')"
      if echo "$parser_out" | jq -e --arg s "$slug" '.matched | map(.skill) | index($s)' >/dev/null 2>&1; then
        override_ok=1
      fi
    fi
    if [ "$override_ok" = "1" ]; then
      emit skill-security-scan applied "high-risk-with-override"
      jq -cn --arg s "$slug" '{hookSpecificOutput: {permissionDecision: "allow", permissionDecisionReason: ("skill-security-scan: HIGH-RISK with valid override artifact for skill=" + $s + " (proceeding).")}}'
    else
      emit skill-security-scan applied "high-risk-no-override"
      reason="BLOCKED: skill-security-scan HIGH-RISK on $file_path (slug=$slug) without matching override artifact. Required: knowledge-base/security/skill-overrides/YYYY-MM-DD-${slug}.md with frontmatter skill: ${slug}. See plugins/soleur/skills/skill-security-scan/references/override-mechanism.md"
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
    # Unknown verdict → ask, not allow. At single-user-incident threshold a
    # broken scanner must surface for operator review rather than silently
    # disable enforcement. (Architecture review F8.)
    emit skill-security-scan applied "unknown-verdict"
    jq -cn '{hookSpecificOutput: {permissionDecision: "ask", permissionDecisionReason: "skill-security-scan returned UNKNOWN verdict; manual review required."}}'
    ;;
esac

exit 0
