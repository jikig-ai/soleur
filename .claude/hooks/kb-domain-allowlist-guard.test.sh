#!/usr/bin/env bash
# Tests for kb-domain-allowlist-guard.sh.
# Run via:  bash .claude/hooks/kb-domain-allowlist-guard.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/kb-domain-allowlist-guard.sh"

[[ -x "$HOOK" ]] || { echo "ERROR: $HOOK not executable" >&2; exit 1; }

# Point the on-disk existence check at a synthetic kb root so the test does not
# depend on the operator's real working tree. Absolute paths in payloads carry
# their own prefix, so the guard resolves existence against the prefix directly.
TMP_KB="$(mktemp -d)"
mkdir -p "$TMP_KB/knowledge-base/engineering/security/skill-overrides"
mkdir -p "$TMP_KB/knowledge-base/project/plans"
export CLAUDE_PROJECT_DIR="$TMP_KB"
trap 'rm -rf "$TMP_KB"' EXIT

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

invoke_write() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK"; }
invoke_bash()  { printf '%s' "$1" | jq -Rs '{tool_input: {command: .}}' | bash "$HOOK"; }
decision_of()  { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }

# T1 — NEW unsanctioned top-level dir (relative path) → ask.
echo "T1: new unsanctioned top-level dir → ask"
out=$(invoke_write "knowledge-base/observability/foo.md")
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on knowledge-base/observability/" || fail "out=$out"

# T2 — Re-introducing security/ (the exact Part A anomaly) → ask (regression guard).
echo "T2: re-adding security/ → ask"
out=$(invoke_write "knowledge-base/security/skill-overrides/x.md")
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on re-added security/" || fail "out=$out"

# T3 — Write INTO the relocated, on-disk engineering/security path → pass-through.
echo "T3: write into existing engineering/security/skill-overrides → pass-through"
out=$(invoke_write "$TMP_KB/knowledge-base/engineering/security/skill-overrides/2026-06-02-foo.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision (sanctioned engineering domain)" || fail "out=$out"

# T4 — Sanctioned top-level file → pass-through.
echo "T4: knowledge-base/INDEX.md → pass-through"
out=$(invoke_write "knowledge-base/INDEX.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision on sanctioned file" || fail "out=$out"

# T5 — Write into an existing sanctioned domain (project/) → pass-through.
echo "T5: write into project/plans → pass-through"
out=$(invoke_write "knowledge-base/project/plans/2026-06-02-some-plan.md")
[[ -z "$(decision_of "$out")" ]] && pass "no decision on sanctioned project domain" || fail "out=$out"

# T6 — Malformed JSON → pass-through (fail-open).
echo "T6: malformed JSON → pass-through"
out=$(printf 'not-json' | bash "$HOOK" 2>/dev/null || true)
[[ -z "$(decision_of "$out" 2>/dev/null || echo "")" ]] && pass "fail-open on malformed JSON" || fail "out=$out"

# T7 — Non-KB path → pass-through.
echo "T7: non-KB path → pass-through"
out=$(invoke_write "apps/web-platform/components/kb/file-tree.tsx")
[[ -z "$(decision_of "$out")" ]] && pass "no decision on non-KB path" || fail "out=$out"

# T8 — Bash mkdir of a new unsanctioned top-level dir → ask.
echo "T8: Bash 'mkdir -p knowledge-base/observability' → ask"
out=$(invoke_bash 'mkdir -p knowledge-base/observability')
[[ "$(decision_of "$out")" == "ask" ]] && pass "ask on Bash mkdir new domain" || fail "out=$out"

# T9 — Empty tool_input → pass-through.
echo "T9: empty tool_input → pass-through"
out=$(printf '{"tool_input":{}}' | bash "$HOOK")
[[ -z "$(decision_of "$out")" ]] && pass "no-op on empty tool_input" || fail "out=$out"

echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1
