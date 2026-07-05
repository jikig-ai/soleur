#!/usr/bin/env bash
# Discoverability probe for the context-reviewed audit gate (#5999, ADR-086).
#
# Two-case scratch-repo probe run WITHOUT ssh (satisfies the plan's
# `discoverability_test.command` contract + preflight Check 10 executable form):
#   1. a `last_reviewed` bump committed WITHOUT a `Context-Reviewed:` trailer
#      MUST make the gate emit `"permissionDecision":"deny"`;
#   2. the same bump WITH the trailer MUST NOT be denied.
# Emits exactly one stable token on the last line: `DISCOVERABILITY: PASS` when
# both hold, `DISCOVERABILITY: FAIL (...)` otherwise. No shell-active tokens on
# the caller side — invoke as `bash scripts/context-reviewed-gate-discoverability.sh`.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
HOOK="${ROOT}/.claude/hooks/context-reviewed-gate.sh"
if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v perl >/dev/null 2>&1 || [[ ! -x "$HOOK" ]]; then
  echo "DISCOVERABILITY: SKIP (missing jq/git/perl or hook absent)"
  exit 0
fi

r="$(mktemp -d)"
trap 'rm -rf "$r"' EXIT
git -C "$r" init -q
git -C "$r" config user.email t@t.dev
git -C "$r" config user.name t
git -C "$r" config commit.gpgsign false
printf 'last_reviewed: 2026-01-01\n' > "$r/doc.md"
git -C "$r" add doc.md
git -C "$r" commit -q -m init
printf 'last_reviewed: 2026-07-05\n' > "$r/doc.md"
git -C "$r" add doc.md

in1="$(jq -n --arg c "git -C $r commit -m bump" --arg w "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}')"
out1="$(printf '%s' "$in1" | INCIDENTS_REPO_ROOT="$r" bash "$HOOK" 2>/dev/null)"
in2="$(jq -n --arg c "git -C $r commit -m bump -m 'Context-Reviewed: all'" --arg w "$r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}')"
out2="$(printf '%s' "$in2" | INCIDENTS_REPO_ROOT="$r" bash "$HOOK" 2>/dev/null)"

# Parse the decision with jq (the gate emits pretty-printed JSON — a substring
# match on `"permissionDecision":"deny"` would miss the `: ` colon-space form).
dec1="$(printf '%s' "$out1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo allow)"
dec2="$(printf '%s' "$out2" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo allow)"
d1=0; [[ "$dec1" == "deny" ]] && d1=1
d2=0; [[ "$dec2" == "deny" ]] && d2=1

if [[ "$d1" == "1" && "$d2" == "0" ]]; then
  echo "DISCOVERABILITY: PASS"
else
  echo "DISCOVERABILITY: FAIL (deny-no-trailer=$d1 deny-with-trailer=$d2)"
  exit 1
fi
