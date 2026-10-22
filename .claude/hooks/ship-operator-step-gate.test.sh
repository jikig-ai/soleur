#!/usr/bin/env bash
# Pattern-only tests for ship-operator-step-gate.sh. Asserts the gate's
# expanded detection regex catches every phrasing that slipped past the
# narrower /ship Phase 5.5 regex in PR #4227, and that the command-trigger
# regex catches `gh pr ready` + `gh pr merge --auto` (and chained forms).
#
# The regex rows mirror the hook's own regex, DERIVED from it at runtime. The
# "REAL hook" rows run the shipped hook with a stub gh on a private PATH dir (no
# network), so an allow/deny verdict is the hook's, not a restated copy's.

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-operator-step-gate.sh"

PASS=0
FAIL=0
TOTAL=0

# DETECT_RE is DERIVED from the hook at runtime, never hand-copied: a restated copy
# stays green while the hook's own regex drifts, which is the vacuity this suite
# exists to prevent. The hook assigns GROUP_A..GROUP_D as single-quoted literals and
# builds DETECT_RE from them, so read the four literals, strip the outer quotes, and
# evaluate the hook's own DETECT_RE assignment line against them.
derive_group() {
  local name="$1" n v
  n=$(grep -c "^${name}=" "$HOOK" || true)
  if [[ "$n" != 1 ]]; then
    echo "FATAL: expected exactly one '^${name}=' line in the hook, found $n" >&2
    exit 1
  fi
  v=$(sed -n "s/^${name}=//p" "$HOOK")
  if [[ "$v" != \'*\' ]]; then
    echo "FATAL: ${name} in the hook is not a single-quoted literal: $v" >&2
    exit 1
  fi
  v=${v#\'}
  v=${v%\'}
  printf '%s' "$v"
}
GROUP_A=$(derive_group GROUP_A)
GROUP_B=$(derive_group GROUP_B)
GROUP_C=$(derive_group GROUP_C)
GROUP_D=$(derive_group GROUP_D)
DETECT_LINE=$(grep -E '^DETECT_RE=' "$HOOK" || true)
if [[ -z "$DETECT_LINE" ]]; then
  echo "FATAL: no '^DETECT_RE=' line in the hook" >&2
  exit 1
fi
eval "$DETECT_LINE"
# The shared wrapper-boundary fragment (#10248) — same source the gate's own
# incidents.sh chain provides; restated here so CMD_RE stays a faithful copy.
# unset-first per the lib contract: an inherited env value must not masquerade
# as the loaded fragment after a failed source.
# shellcheck source=../../plugins/soleur/scripts/lib/wrapper-boundary.sh
unset SOLEUR_ENV_ASN_RE SOLEUR_LAUNCHER_RE SOLEUR_RTK_RE SOLEUR_BOUNDARY_PFX SOLEUR_BOUNDARY_PFX_LOADED
source "$SCRIPT_DIR/../../plugins/soleur/scripts/lib/wrapper-boundary.sh" 2>/dev/null || true
CMD_RE='(^|&&|\|\||;)\s*('"${SOLEUR_BOUNDARY_PFX:-}"'[[:space:]]+)*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'

t() {
  TOTAL=$((TOTAL + 1))
  local label="$1" pattern="$2" input="$3" expected="$4"  # expected: match|no-match
  local got="no-match"
  if echo "$input" | grep -ciE >/dev/null "$pattern"; then got="match"; fi
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

# Delegated-act authoring form (ruling F1 + R4, detection unchanged): the gate counts
# phrasing, so a CTO-performed act under a recorded Standing Delegation is written
# `Delegated act (CTO, Standing Delegation <url>, envelope <path#title>, command "<line>"): ...`
# and does not start with the word Operator. A bullet that starts with the word Operator
# and a verb still matches even when it cites a delegation URL: no URL or keyword
# exemption exists. The rows here are regex mirrors (the regex is derived from the hook);
# the rows further down run the REAL hook.
DELEG_URL="https://github.com/example-org/example-repo/issues/1#issuecomment-1"
DELEG_BULLET="Delegated act (CTO, Standing Delegation ${DELEG_URL}, envelope example/envelope.md#Example, command \"example --flag value\"): flip the link"
t "Delegated act (CTO, Standing Delegation ...) bullet does NOT match" "$DETECT_RE" \
  "- ${DELEG_BULLET}" no-match
t "Delegated act as an unchecked checklist item does NOT match" "$DETECT_RE" \
  "- [ ] ${DELEG_BULLET}" no-match
t "Operator-runs bullet citing a delegation URL STILL matches (no URL exemption)" "$DETECT_RE" \
  "- Operator runs the flip under Standing Delegation ${DELEG_URL}" match
t "Operator: heading bullet citing a delegation URL STILL matches" "$DETECT_RE" \
  "- **Operator: flip under Standing Delegation ${DELEG_URL}**" match
t "mirror is case-insensitive like the hook (-i): lowercase 'operator:' bullet matches" "$DETECT_RE" \
  "- operator: flip the link" match

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
t "rtk gh pr merge --auto (wrapper prefix, #10248)" "$CMD_RE" "rtk gh pr merge --auto" match
t "rtk gh pr ready (wrapper prefix, #10248)" "$CMD_RE" "rtk gh pr ready 4227" match
t "rtk-foo gh pr merge --auto (glued suffix is not rtk)" "$CMD_RE" "rtk-foo gh pr merge --auto" no-match
t "rtk run -c 'gh pr merge --auto' (string payload — lexical-limit class)" "$CMD_RE" \
  "rtk run -c 'gh pr merge --auto'" no-match
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

# --- Option (d): the deny reason must name soleur:operator-bootstrap ---------
# The gate is the one place the undeferred steps are enumerated, so it is the
# one place the bootstrap script the rules mandate can be produced. A reason
# that offers only "file, cite or attest" hands the operator three ways to
# record the step and none to remove it (review P2-16).
d_line=$(grep -E 'REASON_LINES\+=\("  \(d\) ' "$HOOK" || true)
if [[ -n "$d_line" ]] \
   && grep -q 'soleur:operator-bootstrap' <<<"$d_line" \
   && grep -qE '(2\+|≥2|two or more)' <<<"$d_line" \
   && grep -qiE 'same credential' <<<"$d_line"; then
  PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))
  echo "PASS: deny reason offers option (d) naming soleur:operator-bootstrap with its 2+-steps-same-credential precondition"
else
  FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
  echo "FAIL: deny reason lacks option (d) naming soleur:operator-bootstrap with its precondition"
fi

# --- REAL hook runs (stub gh on a private PATH dir) -------------------------
# The mirror rows above prove the regex; these prove the SHIPPED hook allows the
# Delegated-act form and still denies the Operator forms. gh is a stub that logs
# every argv, answers only the exact calls the hook makes, and exits 64 on any other
# argv. The hook swallows gh failures (fail-open), so an allow is only evidence when
# the log proves the PR-body call was reached and nothing unexpected was called.
STUB_DIR=$(mktemp -d -p "${SOLEUR_TEST_INCIDENT_ROOT:?incident sandbox not initialised}" stubgh-XXXXXX)
GH_STUB_LOG="$STUB_DIR/calls.log"
GH_STUB_BAD="$STUB_DIR/unexpected.log"
GH_STUB_BODY="$STUB_DIR/body.md"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_LOG"
case "$*" in
  "pr view 7 --json body --jq .body") cat "$GH_STUB_BODY" ;;
  "issue view 5 --json state --jq .state") echo OPEN ;;
  "issue view 5 --json body --jq .body") echo "deferred-automation backlog item" ;;
  *) printf '%s\n' "$*" >> "$GH_STUB_BAD"; echo "gh stub: unexpected argv: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$STUB_DIR/gh"

# h <label> <expected: allow|deny> <PR body (may be multi-line)>
h() {
  TOTAL=$((TOTAL + 1))
  local label="$1" expected="$2" body="$3" json out got="allow" why=""
  printf '%s\n' "$body" > "$GH_STUB_BODY"
  : > "$GH_STUB_LOG"; : > "$GH_STUB_BAD"
  json=$(jq -nc --arg c "gh pr ready 7" --arg d "$STUB_DIR" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}')
  out=$(env -u SOLEUR_SKIP_OPERATOR_STEP_GATE PATH="$STUB_DIR:$PATH" \
    GH_STUB_LOG="$GH_STUB_LOG" GH_STUB_BAD="$GH_STUB_BAD" GH_STUB_BODY="$GH_STUB_BODY" \
    bash "$HOOK" <<<"$json" 2>/dev/null || true)
  [[ "$(jq -r '.decision // empty' <<<"$out" 2>/dev/null || true)" == "deny" ]] && got="deny"
  grep -qxF "pr view 7 --json body --jq .body" "$GH_STUB_LOG" || why="stub never saw the PR-body call; "
  [[ ! -s "$GH_STUB_BAD" ]] || why="${why}stub saw an unexpected argv: $(head -1 "$GH_STUB_BAD"); "
  if [[ "$got" == "$expected" && -z "$why" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $label"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label  (expected $expected, got $got) ${why}"
    echo "  output: $out"
  fi
}

h "REAL hook: Delegated-act bullet (R4 form) is allowed" allow \
  "- ${DELEG_BULLET}"
h "REAL hook: Delegated-act checklist item is allowed" allow \
  "- [ ] ${DELEG_BULLET}"
h "REAL hook: '- Operator runs ... under Standing Delegation <url>' is denied (no URL exemption)" deny \
  "- Operator runs the flip under Standing Delegation ${DELEG_URL}"
h "REAL hook: '- **Operator: ...**' heading bullet is denied" deny \
  "- **Operator: flip under Standing Delegation ${DELEG_URL}**"
h "REAL hook: Delegated-act bullet does not shield an Operator bullet in the same body" deny \
  "$(printf '%s\n%s' "- ${DELEG_BULLET}" "- Operator confirms the dashboard")"
h "REAL hook: Operator bullet with an OPEN deferred-automation Tracks companion is allowed (stub control)" allow \
  "- Operator runs the flip Tracks #5"
rm -rf "$STUB_DIR"

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

# Anti-vacuity floor: a suite that silently stops running rows (a sourced helper that
# exits early, a deleted block) must not read as green. Raise this whenever rows are
# added, derived from a green run's TOTAL (37 at the R4 edit).
ROW_FLOOR=37
if (( TOTAL < ROW_FLOOR )); then
  echo "FAIL: only $TOTAL rows ran; the floor is $ROW_FLOOR (rows were dropped or never ran)"
  exit 1
fi
[[ $FAIL -eq 0 ]]
