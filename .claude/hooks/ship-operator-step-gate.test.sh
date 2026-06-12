#!/usr/bin/env bash
# Pattern-only tests for ship-operator-step-gate.sh. Asserts the gate's
# expanded detection regex catches every phrasing that slipped past the
# narrower /ship Phase 5.5 regex in PR #4227, and that the command-trigger
# regex catches `gh pr ready` + `gh pr merge --auto` (and chained forms).
#
# Does NOT exercise the gh-API path (no network in tests); the gate's
# fail-open behaviour on missing PR is exercised separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-operator-step-gate.sh"

PASS=0
FAIL=0
TOTAL=0

GROUP_A='[Oo]perator\s*:|[Oo]perator\s+(run|create|provision|configure|paste|cop(y|ies)|verif(y|ies)|confirm|check|file|set|install|upload|audit|click)s?|manual\s+gate|post-merge\s+operator'
GROUP_B='T\+[0-9]+\s*(min|m|h|hour|d|day|wk|week)s?\b.*(verif|check|confirm|file|run)'
GROUP_C='[Ww]ithin\s+[0-9]+\s*(min|m|h|hour|d|day|wk|week)s?(\s+of\s+merge)?\s*:.*(file|run|verif|check|confirm|create|provision|set)'
GROUP_D='AC-PM[0-9]+'
DETECT_RE="^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+(\[[[:space:]xX]\][[:space:]]+)?(\*\*)?(${GROUP_A}|${GROUP_B}|${GROUP_C}|${GROUP_D})"
CMD_RE='(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'

t() {
  TOTAL=$((TOTAL + 1))
  local label="$1" pattern="$2" input="$3" expected="$4"  # expected: match|no-match
  local got="no-match"
  if echo "$input" | grep -qE "$pattern"; then got="match"; fi
  if [[ "$got" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $label"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label  (expected $expected, got $got)"
    echo "  input: $input"
  fi
}

# --- DETECT_RE tests (PR-body line patterns) -------------------------------

t "Operator-colon bullet (PR #4227 phrasing #1)" "$DETECT_RE" \
  "- **Operator: Doppler prd secrets** — verify OAUTH_PROBE_GITHUB_CLIENT_ID is set" match
t "Operator-verify (PR #4227 #2)" "$DETECT_RE" \
  "- Operator verifies pre-deploy" match
t "T+90 min verification bullet" "$DETECT_RE" \
  "- T+90 min: confirm Sentry ok check-in" match
t "T+24h verification bullet" "$DETECT_RE" \
  "- T+24h: confirm Sentry issue auto-resolves" match
t "Within Nh of merge: file bullet" "$DETECT_RE" \
  "- Within 48h: file TR9 PR-4 follow-up issue per AC25" match
t "AC-PM3 token (legacy)" "$DETECT_RE" \
  "- [ ] **AC-PM3** Operator creates the foo bucket" match
t "Operator run (original gate keyword)" "$DETECT_RE" \
  "- Operator runs the bootstrap script" match
t "Operator file (extended verb)" "$DETECT_RE" \
  "- Operator files the tracking issue" match
t "Operator check (extended verb)" "$DETECT_RE" \
  "- Operator checks the dashboard" match

# Negatives: prose mentions in body text should not fire.
t "Prose: 'the operator's choice' (no list marker)" "$DETECT_RE" \
  "  This document mentions the operator's choice in mid-paragraph." no-match
t "Prose without bullet" "$DETECT_RE" \
  "The operator runs the script ONCE post-merge." no-match
t "AC25 (not AC-PM25) — non-PM AC stays prose-noise" "$DETECT_RE" \
  "- AC25 is satisfied by inline-execution" no-match

# --- CMD_RE tests (which bash commands the gate triggers on) ---------------

t "gh pr ready 4227" "$CMD_RE" "gh pr ready 4227" match
t "gh pr merge --squash --auto" "$CMD_RE" "gh pr merge --squash --auto" match
t "chained: gh pr ready 1 && gh pr merge --auto" "$CMD_RE" \
  "gh pr ready 1 && gh pr merge --auto" match
t "gh pr merge (no --auto) — direct merge, NOT this gate's scope" "$CMD_RE" \
  "gh pr merge 4227 --squash" no-match
t "gh pr view — read-only, not gated" "$CMD_RE" \
  "gh pr view 4227" no-match
t "echo containing 'gh pr ready' substring — word-bounded safe" "$CMD_RE" \
  "echo 'remember to gh pr ready when done'" no-match

# --- #5192: commit-body / heredoc strip → CMD_RE no longer fires -----------
# A `git commit` whose MESSAGE documents `gh pr ready` must NOT trip the gate.
# Mirror the hook's pre-detection strip, then assert CMD_RE no-match on the
# result — and that a REAL chained `gh pr merge --auto` after a heredoc
# terminator still fires (post-terminator preservation).
# shellcheck source=lib/incidents.sh
source "$SCRIPT_DIR/lib/incidents.sh" 2>/dev/null || true
FP_SCAN=$(strip_command_bodies $'git add . && git commit -m "ship note\ngh pr ready must not be hand-rolled\n"')
t "commit-body gh pr ready stripped → CMD_RE no-match (#5192)" "$CMD_RE" "$FP_SCAN" no-match
REAL_SCAN=$(strip_command_bodies $'git commit -F - <<EOF\nbody\nEOF\n && gh pr merge 7 --squash --auto')
t "real gh pr merge --auto after heredoc still fires (#5192)" "$CMD_RE" "$REAL_SCAN" match

# --- Hook script syntax check (no real invocation; lacks gh + PR context) --

if bash -n "$HOOK"; then
  PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))
  echo "PASS: hook script syntax OK"
else
  FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
  echo "FAIL: hook script syntax error"
fi

echo ""
echo "=== $PASS/$TOTAL pass ($FAIL fail) ==="
[[ $FAIL -eq 0 ]]
