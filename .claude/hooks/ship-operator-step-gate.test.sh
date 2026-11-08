#!/usr/bin/env bash
# Pattern-only tests for ship-operator-step-gate.sh. Asserts the gate's
# expanded detection regex catches every phrasing that slipped past the
# narrower /ship Phase 5.5 regex in PR #4227, and that the command-trigger
# regex catches `gh pr ready` + `gh pr merge --auto` (and chained forms).
#
# The regex rows mirror the hook's own regexes (DETECT_RE and the command trigger CMD_RE),
# both DERIVED from it at runtime. The
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
# shellcheck disable=SC2034 # read by the eval of the hook's DETECT_RE line below
GROUP_A=$(derive_group GROUP_A)
# shellcheck disable=SC2034 # read by the eval of the hook's DETECT_RE line below
GROUP_B=$(derive_group GROUP_B)
# shellcheck disable=SC2034 # read by the eval of the hook's DETECT_RE line below
GROUP_C=$(derive_group GROUP_C)
# shellcheck disable=SC2034 # read by the eval of the hook's DETECT_RE line below
GROUP_D=$(derive_group GROUP_D)
DETECT_LINE=$(grep -E '^DETECT_RE=' "$HOOK" || true)
if [[ -z "$DETECT_LINE" ]]; then
  echo "FATAL: no '^DETECT_RE=' line in the hook" >&2
  exit 1
fi
eval "$DETECT_LINE"
# The shared wrapper-boundary fragment (#10248) — the same source the gate's own
# incidents.sh chain provides, so the hook's trigger line evaluates to the same regex here.
# unset-first per the lib contract: an inherited env value must not masquerade
# as the loaded fragment after a failed source.
# shellcheck source=../../plugins/soleur/scripts/lib/wrapper-boundary.sh
unset SOLEUR_ENV_ASN_RE SOLEUR_LAUNCHER_RE SOLEUR_RTK_RE SOLEUR_BOUNDARY_PFX SOLEUR_BOUNDARY_PFX_LOADED
source "$SCRIPT_DIR/../../plugins/soleur/scripts/lib/wrapper-boundary.sh" 2>/dev/null || true
# CMD_RE is DERIVED from the hook too, never restated. The hook's trigger is the one
# `if ! grep -qE <pattern> <<<"$SCAN"; then` line; the pattern is a shell word that splices
# in ${SOLEUR_BOUNDARY_PFX:-}, so evaluate it as an assignment (as DETECT_RE is above).
# Fail loudly unless exactly one such line exists and it carries a non-empty pattern.
TRIGGER_PAT='^if ! grep -qE .* <<<"[$]SCAN"; then$'
TRIGGER_N=$(grep -cE "$TRIGGER_PAT" "$HOOK" || true)
if [[ "$TRIGGER_N" != 1 ]]; then
  echo "FATAL: expected exactly one 'if ! grep -qE <pattern> <<<\"\$SCAN\"; then' trigger line in the hook, found $TRIGGER_N" >&2
  exit 1
fi
TRIGGER_LINE=$(grep -E "$TRIGGER_PAT" "$HOOK" || true)
TRIGGER_ARG=${TRIGGER_LINE#'if ! grep -qE '}
TRIGGER_ARG=${TRIGGER_ARG%' <<<"$SCAN"; then'}
if [[ "$TRIGGER_ARG" != \'* || "$TRIGGER_ARG" != *\' ]]; then
  echo "FATAL: the hook's trigger pattern is not a quoted word: $TRIGGER_ARG" >&2
  exit 1
fi
eval "CMD_RE=$TRIGGER_ARG"
if [[ -z "$CMD_RE" || "$CMD_RE" != *'gh\s+pr\s+'* ]]; then
  echo "FATAL: derived CMD_RE is empty or lacks the gh pr arm: $CMD_RE" >&2
  exit 1
fi

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
# Delegated-act form, still denies the Operator forms, fires on BOTH trigger arms
# (`gh pr ready`, `gh pr merge --auto`) and not on a plain merge, and clears a
# match only through the Tracks companion path. gh is a stub that logs every argv,
# answers only the exact calls the hook makes, and exits 64 on any other argv. The
# hook swallows gh failures (fail-open), so a verdict is only evidence when the log
# proves which calls were made and that nothing unexpected was called.
#   issue #5: OPEN, body carries the deferred-automation sentinel
#   issue #6: CLOSED
#   issue #7: OPEN, body lacks the sentinel
#   PR #7 labels: whatever the row sets in LABELS; PR #8: the label read always fails (exit 1)
STUB_DIR=$(mktemp -d -t soleur-run.$$.XXXXXXXX)
# Own the stub dir, and keep the sandbox helper's cleanup in the same trap: a bare `trap ... EXIT`
# here would replace the one lib/test-incident-sandbox.sh composed and leak the sandbox root.
trap 'rm -rf "$STUB_DIR"; _soleur_inc_sb_cleanup' EXIT
GH_STUB_LOG="$STUB_DIR/calls.log"
GH_STUB_BAD="$STUB_DIR/unexpected.log"
GH_STUB_BODY="$STUB_DIR/body.md"
GH_STUB_LABELS="$STUB_DIR/labels.txt"
GH_STUB_CURPR="$STUB_DIR/curpr.txt"        # the current branch's PR number (`gh pr view --json number`)
GH_STUB_PARKED="$STUB_DIR/parked-count.txt" # how many open PRs carry `parked` (`gh pr list --label parked`)
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_LOG"
case "$*" in
  "pr view 7 --json body --jq .body") cat "$GH_STUB_BODY" ;;
  "pr view 7 --json labels --jq .labels[].name"|"pr view 7 --repo o/r --json labels --jq .labels[].name") cat "$GH_STUB_LABELS" ;;
  "pr view 8 --json labels --jq .labels[].name") exit 1 ;;
  "pr view 9 --json labels --jq .labels[].name") exec sleep 5 ;;
  "pr view "[0-9]*" --json labels --jq .labels[].name") : ;;   # any other PR: unlabelled (prints nothing)
  "pr view --json number --jq .number")
    v=$(cat "$GH_STUB_CURPR")
    if [[ "$v" == FAIL ]]; then echo "gh: HTTP 502" >&2; exit 1; fi
    if [[ "$v" == NONE ]]; then echo 'no pull requests found for branch "x"' >&2; exit 1; fi
    printf '%s' "$v" ;;
  "pr list --label parked --state open --json number --jq length"|"pr list --label parked --state open --repo o/r --json number --jq length")
    v=$(cat "$GH_STUB_PARKED")
    if [[ "$v" == fail ]]; then echo "gh: HTTP 502" >&2; exit 1; fi
    if [[ "$v" == garbage ]]; then echo "not-a-number"; exit 0; fi
    printf '%s' "$v" ;;
  "issue view 5 --json state --jq .state") echo OPEN ;;
  "issue view 5 --json body --jq .body") echo "deferred-automation backlog item" ;;
  "issue view 6 --json state --jq .state") echo CLOSED ;;
  "issue view 7 --json state --jq .state") echo OPEN ;;
  "issue view 7 --json body --jq .body") echo "an ordinary feature request, no deferral context" ;;
  *) printf '%s\n' "$*" >> "$GH_STUB_BAD"; echo "gh stub: unexpected argv: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$STUB_DIR/gh"

PR_BODY_CALL="pr view 7 --json body --jq .body"
LABELS_CALL="pr view 7 --json labels --jq .labels[].name"
# Per-row inputs for the parked barrier: LABELS is what the stub prints as PR #7's labels (one per line);
# FORBID is a stub argv that must NOT appear in the log. Both are reset after every row.
LABELS=""
FORBID=""
HOOK_ENV=""
CURPR=""          # the current branch's PR number the stub reports (default 99, an unlabelled PR)
PARKED_COUNT=""   # open PRs carrying `parked` the stub reports (default 0)
CWD_OVERRIDE=""   # the hook payload's cwd (default: the stub dir, a valid absolute directory)

# h <label> <expected: allow|deny> <PR body (may be multi-line)> [command] [required log line ...]
#   command defaults to `gh pr ready 7`. Required log lines default to the PR-body call;
#   a single `--none` asserts the stub was NEVER called (the hook exited at the trigger).
h() {
  TOTAL=$((TOTAL + 1))
  local label="$1" expected="$2" body="$3" cmd="${4:-gh pr ready 7}" json out got="allow" why="" line
  shift 3 || true
  shift || true
  local required=("$@")
  [[ ${#required[@]} -gt 0 ]] || required=("$PR_BODY_CALL")
  printf '%s\n' "$body" > "$GH_STUB_BODY"
  printf '%s' "$LABELS" > "$GH_STUB_LABELS"
  printf '%s' "${CURPR:-99}" > "$GH_STUB_CURPR"
  printf '%s' "${PARKED_COUNT:-0}" > "$GH_STUB_PARKED"
  : > "$GH_STUB_LOG"; : > "$GH_STUB_BAD"
  json=$(jq -nc --arg c "$cmd" --arg d "${CWD_OVERRIDE:-$STUB_DIR}" \
    '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}')
  # shellcheck disable=SC2086 # HOOK_ENV is zero or one NAME=value word, deliberately unquoted
  out=$(env -u SOLEUR_SKIP_OPERATOR_STEP_GATE $HOOK_ENV PATH="$STUB_DIR:$PATH" \
    GH_STUB_LOG="$GH_STUB_LOG" GH_STUB_BAD="$GH_STUB_BAD" GH_STUB_BODY="$GH_STUB_BODY" GH_STUB_LABELS="$GH_STUB_LABELS" \
    GH_STUB_CURPR="$GH_STUB_CURPR" GH_STUB_PARKED="$GH_STUB_PARKED" \
    bash "$HOOK" <<<"$json" 2>/dev/null || true)
  [[ "$(jq -r '.decision // empty' <<<"$out" 2>/dev/null || true)" == "deny" ]] && got="deny"
  if [[ "${required[0]}" == "--none" ]]; then
    [[ ! -s "$GH_STUB_LOG" ]] || why="stub was called but the hook should have exited at the trigger: $(head -1 "$GH_STUB_LOG"); "
  else
    for line in "${required[@]}"; do
      grep -qxF "$line" "$GH_STUB_LOG" || why="${why}stub never saw '$line'; "
    done
  fi
  [[ ! -s "$GH_STUB_BAD" ]] || why="${why}stub saw an unexpected argv: $(head -1 "$GH_STUB_BAD"); "
  if [[ -n "$FORBID" ]] && grep -qxF "$FORBID" "$GH_STUB_LOG"; then why="${why}stub saw '$FORBID', which this row forbids; "; fi
  LABELS=""; FORBID=""; HOOK_ENV=""; CURPR=""; PARKED_COUNT=""; CWD_OVERRIDE=""
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

# Trigger arms, through the shipped hook: `gh pr merge --auto` is gated like `gh pr ready`,
# and a plain `gh pr merge` (no --auto) is NOT gated even over a body the gate would deny.
h "REAL hook: 'gh pr merge 7 --auto' with an Operator bullet is denied (merge --auto arm)" deny \
  "- Operator confirms the dashboard" "gh pr merge 7 --auto"
FORBID="$PR_BODY_CALL"
h "REAL hook: 'gh pr merge 7 --squash' (no --auto) on an UNLABELLED PR is NOT body-gated, even over an Operator bullet (it reads the labels, never the body)" allow \
  "- Operator confirms the dashboard" "gh pr merge 7 --squash" "$LABELS_CALL"

# Companion path: a match is cleared only by (Tracks|Refs) #N on an OPEN issue whose body
# carries the sentinel. The control row proves the companion path ran (both issue-view calls
# are in the log), so its allow is not the vacuous allow of a gate that never looked.
h "REAL hook: Operator bullet with an OPEN deferred-automation Tracks companion is allowed (control; state AND body checked)" allow \
  "- Operator runs the flip Tracks #5" "" \
  "$PR_BODY_CALL" "issue view 5 --json state --jq .state" "issue view 5 --json body --jq .body"
h "REAL hook: Operator bullet whose Tracks issue is CLOSED is denied (state call seen in the log)" deny \
  "- Operator runs the flip Tracks #6" "" \
  "$PR_BODY_CALL" "issue view 6 --json state --jq .state"
h "REAL hook: Operator bullet whose Tracks issue is OPEN but lacks the sentinel is denied (state and body checked)" deny \
  "- Operator runs the flip Tracks #7" "" \
  "$PR_BODY_CALL" "issue view 7 --json state --jq .state" "issue view 7 --json body --jq .body"

# --- The parked barrier (#12197, CTO ruling A): no agent session merges, enqueues or un-parks a PR that carries `parked` -----
# `parked` is the existing "reviewed draft held until an approved window; do not merge or arm auto-merge" label. Any `gh pr merge`
# that is not `--disable-auto` (plain, --auto, --admin, chained, a `gh api` merge) is denied while the PR carries it, and so is
# removing the label. Not overridable by SOLEUR_SKIP_OPERATOR_STEP_GATE: the operator clears it in the UI or their own terminal.
CLEAN="A normal body, no operator steps."
LABELS=$'parked\nbug'
h "REAL hook: parked: plain 'gh pr merge 7 --squash' is denied (labels read)" deny "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: 'gh pr merge 7 --squash --auto' is denied" deny "$CLEAN" "gh pr merge 7 --squash --auto" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: chained 'gh pr ready 7 && gh pr merge 7 --auto' is denied" deny "$CLEAN" "gh pr ready 7 && gh pr merge 7 --auto" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: 'gh pr merge 7 --admin' is denied" deny "$CLEAN" "gh pr merge 7 --admin" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: a flag before the number ('gh pr merge --squash 7') is denied" deny "$CLEAN" "gh pr merge --squash 7" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: 'gh api -X PUT repos/o/r/pulls/7/merge' is denied" deny "$CLEAN" "gh api -X PUT repos/o/r/pulls/7/merge" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: a wrapper-prefixed 'rtk gh pr merge 7' is denied" deny "$CLEAN" "rtk gh pr merge 7" "$LABELS_CALL"
LABELS=$'bug\nenhancement'
h "REAL hook: an UNLABELLED PR (other labels only) merges past the barrier (control: the labels were read)" allow "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
LABELS=$'parked'
h "REAL hook: parked: '--disable-auto' is allowed (it un-arms; the stub is never called)" allow "$CLEAN" "gh pr merge 7 --disable-auto" --none
LABELS=$'parked'
h "REAL hook: parked: 'gh pr ready 7' is NOT blocked by the barrier (ready is allowed, the label stays)" allow "$CLEAN" "gh pr ready 7" "$PR_BODY_CALL"
h "REAL hook: parked: a label read that FAILS for a resolved PR number is denied (fail closed)" deny "$CLEAN" "gh pr merge 8 --squash" "pr view 8 --json labels --jq .labels[].name"
h "REAL hook: parked: removing the label ('gh pr edit 7 --remove-label parked') is denied, stub never called" deny "$CLEAN" "gh pr edit 7 --remove-label parked" --none
h "REAL hook: parked: removing it among others ('--remove-label bug,parked') is denied" deny "$CLEAN" "gh pr edit 7 --remove-label bug,parked" --none
h "REAL hook: parked: 'gh issue edit 7 --remove-label parked' is denied" deny "$CLEAN" "gh issue edit 7 --remove-label parked" --none
h "REAL hook: parked: 'gh api -X DELETE repos/o/r/issues/7/labels/parked' is denied" deny "$CLEAN" "gh api -X DELETE repos/o/r/issues/7/labels/parked" --none
h "REAL hook: adding the label ('--add-label parked') or removing another one is allowed, stub never called" allow "$CLEAN" "gh pr edit 7 --add-label parked && gh pr edit 7 --remove-label bug" --none
LABELS=$'parked'
HOOK_ENV="SOLEUR_SKIP_OPERATOR_STEP_GATE=1"
h "REAL hook: parked: the override env var, set in the hook's own environment, does NOT lift the barrier" deny "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
HOOK_ENV="SOLEUR_SKIP_OPERATOR_STEP_GATE=1"
h "REAL hook (control): the same override env var DOES lift the body gate on an unlabelled PR, so the row above tested the barrier and not an unset variable" allow "- Operator confirms the dashboard" "gh pr ready 7" --none

# --- Review round 1 (CTO ruling T2, 2026-11-08): the evasion shapes the panel reproduced against the first barrier ---------------
# Every row here was ALLOWED by the first version. PR 7 is the parked PR; PR 99 (the stub's current-branch PR) and every other
# number are unlabelled, so a deny can only come from the barrier reading the right PR. The LABELS_CALL lines prove the read.
PARKED_LAB=$'parked'
# quoted / wrapped forms: the barrier now reads quoted text, because `bash -c "gh pr merge 7"` is a command
LABELS=$PARKED_LAB; h "REAL hook: parked: 'bash -c \"gh pr merge 7 --squash\"' is denied (quoted payload is a command)" deny "$CLEAN" 'bash -c "gh pr merge 7 --squash"' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: 'eval \"gh pr merge 7\"' is denied" deny "$CLEAN" 'eval "gh pr merge 7"' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: a quoted number ('gh pr merge \"7\"') is denied" deny "$CLEAN" 'gh pr merge "7" --squash' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: a parenthesised '(gh pr merge 7)' is denied" deny "$CLEAN" '(gh pr merge 7)' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: a command substitution 'x=\$(gh pr merge 7)' is denied" deny "$CLEAN" 'x=$(gh pr merge 7)' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: an absolute path '/usr/bin/gh pr merge 7' is denied" deny "$CLEAN" '/usr/bin/gh pr merge 7' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: a pipe-adjacent 'true|gh pr merge 7' is denied" deny "$CLEAN" 'true|gh pr merge 7' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: the number glued to a pipe ('gh pr merge 7|cat') is denied" deny "$CLEAN" 'gh pr merge 7|cat' "$LABELS_CALL"
LABELS=$'bug'; h "REAL hook: an UNLABELLED PR inside 'bash -c' merges past the barrier (control: the denial above is the label, not the quotes)" allow "$CLEAN" 'bash -c "gh pr merge 7 --squash"' "$LABELS_CALL"
# the target PR is read from the invocation, not from the current branch
LABELS=$PARKED_LAB; h "REAL hook: parked: a PR URL ('gh pr merge https://github.com/o/r/pull/7') is denied (the number is read from the URL)" deny "$CLEAN" 'gh pr merge https://github.com/o/r/pull/7 --squash' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: 'gh -R o/r pr merge 7' is denied and the label read carries --repo" deny "$CLEAN" 'gh -R o/r pr merge 7 --squash' "pr view 7 --repo o/r --json labels --jq .labels[].name"
LABELS=$PARKED_LAB; FORBID="pr view 712 --json labels --jq .labels[].name"
h "REAL hook: parked: two numbers ('gh pr merge 7 --subject 12') are two candidates, never fused into 712" deny "$CLEAN" 'gh pr merge 7 --subject 12' "$LABELS_CALL"
LABELS=$PARKED_LAB; FORBID="pr view 1234 --json labels --jq .labels[].name"
h "REAL hook: parked: the parked PR is the number AFTER a flag value ('gh pr merge -t 1234 7'); the 1234 is a subject, never read as a PR" deny "$CLEAN" 'gh pr merge -t 1234 7' "$LABELS_CALL"
# the --disable-auto exemption is a whole flag, not a substring
LABELS=$PARKED_LAB; h "REAL hook: parked: a merge chained AFTER a '--disable-auto' statement ('&&') is denied (the statements are split)" deny "$CLEAN" 'gh pr merge 7 --disable-auto && gh pr merge 7 --squash' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: the same chained with ';' is denied" deny "$CLEAN" 'gh pr merge 7 --disable-auto; gh pr merge 7 --squash' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: '--disable-auto' in a trailing comment does not exempt the merge" deny "$CLEAN" 'gh pr merge 7 --squash # --disable-auto' "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: '--subject=--disable-auto' is a flag VALUE, not the flag" deny "$CLEAN" 'gh pr merge 7 --subject=--disable-auto' "$LABELS_CALL"
# a decoy label is not the label
LABELS=$'parked-old'; h "REAL hook: a PR labelled 'parked-old' is NOT held (exact label match; control: the labels were read)" allow "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
LABELS=$'Parked'; h "REAL hook: parked: the label match is case-insensitive ('Parked' holds)" deny "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
# un-parking by other means
h "REAL hook: parked: a QUOTED removal ('--remove-label \"parked\"') is denied, stub never called" deny "$CLEAN" 'gh pr edit 7 --remove-label "parked"' --none
h "REAL hook: parked: a quoted removal among others (\"bug,parked\") is denied" deny "$CLEAN" "gh pr edit 7 --remove-label 'bug,parked'" --none
h "REAL hook: parked: '--remove-label=parked' is denied" deny "$CLEAN" 'gh pr edit 7 --remove-label=parked' --none
h "REAL hook: parked: '--remove-label Parked' (case) is denied" deny "$CLEAN" 'gh pr edit 7 --remove-label Parked' --none
h "REAL hook: parked: 'gh label delete parked --yes' is denied" deny "$CLEAN" 'gh label delete parked --yes' --none
h "REAL hook: parked: 'gh label edit parked --name held' is denied" deny "$CLEAN" 'gh label edit parked --name held' --none
h "REAL hook: another label is untouched ('gh label delete other') and allowed, stub never called" allow "$CLEAN" 'gh label delete other --yes' --none
LABELS=$PARKED_LAB; h "REAL hook: parked: replacing the whole label set ('gh api -X PUT .../issues/7/labels') is denied" deny "$CLEAN" "gh api -X PUT repos/o/r/issues/7/labels -f 'labels[]=bug'" "$LABELS_CALL"
LABELS=$PARKED_LAB; h "REAL hook: parked: clearing the label set ('gh api -X DELETE .../issues/7/labels') is denied" deny "$CLEAN" 'gh api -X DELETE repos/o/r/issues/7/labels' "$LABELS_CALL"
LABELS=$'bug'; h "REAL hook: a label write on an UNLABELLED PR is allowed (control: the labels were read)" allow "$CLEAN" "gh api -X PUT repos/o/r/issues/7/labels -f 'labels[]=bug'" "$LABELS_CALL"
# a merge whose target is not a literal number is held while ANY PR is parked
PARKED_COUNT=1; h "REAL hook: parked: 'gh pr merge \"\$N\"' (a variable target) is denied while a PR is parked" deny "$CLEAN" 'gh pr merge "$N" --squash --auto' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=0; h "REAL hook: a variable target is allowed when NO PR is parked (control: the list was read)" allow "$CLEAN" 'gh pr merge "$N" --squash' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=1; h "REAL hook: parked: a branch-name target ('gh pr merge feat-x') is denied while a PR is parked" deny "$CLEAN" 'gh pr merge feat-x --squash' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=1; h "REAL hook: parked: a variable inside the api path ('gh api -X PUT .../pulls/\$PR/merge') is denied while a PR is parked" deny "$CLEAN" 'gh api -X PUT repos/o/r/pulls/$PR/merge' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=1; h "REAL hook: parked: a GraphQL 'mergePullRequest' mutation is denied while a PR is parked" deny "$CLEAN" "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"X\"}) { clientMutationId } }'" "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=0; h "REAL hook: a GraphQL read ('query { viewer { login } }') is allowed (control: no merge mutation, stub never called)" allow "$CLEAN" "gh api graphql -f query='query { viewer { login } }'" --none
PARKED_COUNT=1; h "REAL hook: a redirection token is not a target ('gh pr merge --squash 2>&1' reads the current-branch PR only, never the parked list)" allow "$CLEAN" 'gh pr merge --squash 2>&1' "pr view --json number --jq .number" "pr view 99 --json labels --jq .labels[].name"
# a bare merge targets the current branch's PR
CURPR=7; LABELS=$PARKED_LAB; h "REAL hook: parked: a bare 'gh pr merge --squash' on the parked PR's own branch is denied (current-branch PR read)" deny "$CLEAN" 'gh pr merge --squash' "pr view --json number --jq .number" "$LABELS_CALL"
CURPR=99; h "REAL hook: a bare merge on an unlabelled branch is allowed (control: the current-branch PR and its labels were read)" allow "$CLEAN" 'gh pr merge --squash' "pr view --json number --jq .number" "pr view 99 --json labels --jq .labels[].name"
# fail closed: a hung label read, a missing cwd
LABELS=$PARKED_LAB; HOOK_ENV="SOLEUR_PARKED_GH_TIMEOUT=1"; h "REAL hook: parked: a label read that HANGS is bounded by the timeout and denied" deny "$CLEAN" 'gh pr merge 9 --squash' "pr view 9 --json labels --jq .labels[].name"
LABELS=$PARKED_LAB; CWD_OVERRIDE="relative/dir"; h "REAL hook: parked: a relative cwd does not skip the barrier (it runs in the current directory)" deny "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
LABELS=$PARKED_LAB; CWD_OVERRIDE="/nonexistent-soleur-dir"; h "REAL hook: parked: a missing cwd does not skip the barrier" deny "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"

# --- Fix round 1 (security seat P1-1/P2-1/P2-2/P3, test-design seat survivors; 2026-11-08) -----------------------------------
# The barrier reads only what the shell would RUN. Quoted text that merely MENTIONS a merge is not a command (the first rewrite denied
# `git commit -m "... gh pr merge 7 ..."` while any PR was parked, which blocked ordinary work on this very feature); the quoted
# argument of `bash -c` / `eval` is a command. LABELS=parked everywhere below, so an ALLOW can only come from the parse, and `--none`
# proves the stub was never asked (nothing was mistaken for a merge).
PL=$'parked'
LABELS=$PL; h "REAL hook: parked: a commit message that MENTIONS the merge is allowed ('git commit -m \"... gh pr merge 7 ...\"')" allow "$CLEAN" 'git commit -m "docs: the hook denies gh pr merge 7 on parked PRs"' --none
LABELS=$PL; h "REAL hook: parked: a single-quoted commit message that mentions the merge is allowed" allow "$CLEAN" "git commit -m 'harden gh pr merge 7 barrier'" --none
LABELS=$PL; h "REAL hook: parked: an echo that mentions the merge is allowed" allow "$CLEAN" 'echo "never gh pr merge 7 a parked pr"' --none
LABELS=$PL; h "REAL hook: parked: a grep for the merge text is allowed" allow "$CLEAN" "grep -n 'gh pr merge' README.md" --none
LABELS=$PL; h "REAL hook: parked: 'grep -c \"gh pr merge 7\" f' is NOT a shell -c payload, so it is allowed" allow "$CLEAN" 'grep -c "gh pr merge 7" f' --none
LABELS=$PL; h "REAL hook: parked: a PR body that mentions the merge is allowed ('gh pr edit 99 --body \"... gh pr merge 7 ...\"')" allow "$CLEAN" 'gh pr edit 99 --body "see gh pr merge 7 docs"' --none
LABELS=$PL; h "REAL hook: parked: an issue body that mentions an un-park is allowed ('gh issue create --body \"... --remove-label parked ...\"')" allow "$CLEAN" 'gh issue create --body "gh pr edit 1 --remove-label parked is denied"' --none
LABELS=$PL; h "REAL hook: parked: a PR comment that mentions the merge is allowed" allow "$CLEAN" 'gh pr comment 7 --body "do not run gh pr merge 7"' --none
LABELS=$PL; h "REAL hook: parked: a heredoc commit message (-F - <<EOF) that mentions the merge is allowed (heredoc bodies are stripped)" allow "$CLEAN" $'git commit -F - <<\'EOF\'\nfix: x\ngh pr merge 7 is blocked\nEOF' --none
LABELS=$PL; h "REAL hook: parked: a \$(cat <<EOF) commit message that mentions the merge is allowed" allow "$CLEAN" $'git commit -m "$(cat <<\'EOF\'\ngh pr merge 7 is blocked\nEOF\n)"' --none
# the quoted payload of -c / eval, a command substitution in double quotes, and wrapper words are commands
LABELS=$PL; h "REAL hook: parked: 'sh -c \\'gh pr merge 7\\'' is denied" deny "$CLEAN" "sh -c 'gh pr merge 7'" "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: a double-quoted command substitution (echo \"\$(gh pr merge 7)\") is denied" deny "$CLEAN" 'echo "$(gh pr merge 7)"' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: a backtick substitution is denied" deny "$CLEAN" '`gh pr merge 7`' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: 'timeout 60 gh pr merge 7' is denied" deny "$CLEAN" 'timeout 60 gh pr merge 7' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: 'env X=1 gh pr merge 7' is denied" deny "$CLEAN" 'env X=1 gh pr merge 7' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: 'with_lock merge-main 600 -- gh pr merge 7 --squash --auto' is denied" deny "$CLEAN" 'with_lock merge-main 600 -- gh pr merge 7 --squash --auto' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: 'find . -exec gh pr merge 7 \;' is denied" deny "$CLEAN" 'find . -exec gh pr merge 7 \;' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: a backslash-newline continuation ('gh pr \\<newline> merge 7') is denied" deny "$CLEAN" $'gh pr \\\n merge 7' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: a redirection before the number ('gh pr merge 2>&1 7') still reads the 7" deny "$CLEAN" 'gh pr merge 2>&1 7' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: a quoted '#7' target is read as PR 7" deny "$CLEAN" "gh pr merge '#7' --squash" "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: a '#1' subject does not hide the target ('--subject \"#1\" 7')" deny "$CLEAN" 'gh pr merge --subject "#1" 7' "$LABELS_CALL"
# a flag value is never a target, so an ordinary merge is not falsely denied while some OTHER PR is parked
PARKED_COUNT=1; FORBID="pr list --label parked --state open --json number --jq length"
h "REAL hook: another PR is parked, this one is not: 'gh pr merge 99 --subject \"fix: x\"' is allowed (the literal 99 is read; the list is never needed)" allow "$CLEAN" 'gh pr merge 99 --subject "fix: x"' "pr view 99 --json labels --jq .labels[].name"
PARKED_COUNT=1; FORBID="pr list --label parked --state open --json number --jq length"
h "REAL hook: a subject on a bare merge ('gh pr merge --squash --subject \"feat: x\"') reads the current-branch PR and allows" allow "$CLEAN" 'gh pr merge --squash --subject "feat: x"' "pr view --json number --jq .number" "pr view 99 --json labels --jq .labels[].name"
PARKED_COUNT=1; FORBID="pr list --label parked --state open --json number --jq length"
h "REAL hook: '--match-head-commit abc123' is a flag value, not a branch-name target" allow "$CLEAN" 'gh pr merge --squash --match-head-commit abc123' "pr view --json number --jq .number" "pr view 99 --json labels --jq .labels[].name"
PARKED_COUNT=1; h "REAL hook: parked: a variable target is still held while a PR is parked ('--match-head-commit \"\$SHA\" \"\$PR_URL\"')" deny "$CLEAN" 'gh pr merge --squash --match-head-commit "$SHA" "$PR_URL"' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=1; h "REAL hook: parked: a hidden target ('gh pr merge 7\$(echo 2)') is held while a PR is parked" deny "$CLEAN" 'gh pr merge 7$(echo 2)' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=1; h "REAL hook: parked: a repo-scoped variable target ('gh pr merge -R o/r \"\$N\"') lists the parked PRs of that repo" deny "$CLEAN" 'gh pr merge -R o/r "$N"' "pr list --label parked --state open --repo o/r --json number --jq length"
LABELS=$PL; h "REAL hook: parked: the long '--repo' form before the subcommand ('gh --repo o/r pr merge 7') is denied" deny "$CLEAN" 'gh --repo o/r pr merge 7' "pr view 7 --repo o/r --json labels --jq .labels[].name"
LABELS=$PL; h "REAL hook: parked: 'gh pr merge 7 --repo o/r' (the flag after) is denied" deny "$CLEAN" 'gh pr merge 7 --repo o/r' "pr view 7 --repo o/r --json labels --jq .labels[].name"
LABELS=$PL
h "REAL hook: parked: the single '&' is a statement separator ('gh pr merge 99 & gh pr merge 7': both statements are read)" deny "$CLEAN" 'gh pr merge 99 & gh pr merge 7' "pr view 99 --json labels --jq .labels[].name" "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: an earlier statement joined by a single '&' does not hide the merge ('echo go & gh pr merge 7')" deny "$CLEAN" 'echo go & gh pr merge 7' "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: an UNQUOTED mention after a word that is not a wrapper ('echo gh pr merge 7') is not a command" allow "$CLEAN" 'echo gh pr merge 7' --none
# listing the parked PRs fails closed
PARKED_COUNT=fail; h "REAL hook: parked: a failed parked-PR list is denied (fail closed)" deny "$CLEAN" 'gh pr merge "$N"' "pr list --label parked --state open --json number --jq length"
PARKED_COUNT=garbage; h "REAL hook: parked: an unreadable parked-PR list is denied (fail closed)" deny "$CLEAN" 'gh pr merge "$N"' "pr list --label parked --state open --json number --jq length"
# the current-branch read fails closed unless the branch simply has no PR
CURPR=FAIL; PARKED_COUNT=1; h "REAL hook: parked: a bare merge whose current-branch read FAILS is held while a PR is parked" deny "$CLEAN" 'gh pr merge --squash' "pr view --json number --jq .number" "pr list --label parked --state open --json number --jq length"
CURPR=FAIL; PARKED_COUNT=0; h "REAL hook: a bare merge whose current-branch read FAILS is allowed when no PR is parked (control: the list was read)" allow "$CLEAN" 'gh pr merge --squash' "pr view --json number --jq .number" "pr list --label parked --state open --json number --jq length"
CURPR=NONE; PARKED_COUNT=1; FORBID="pr list --label parked --state open --json number --jq length"
h "REAL hook: a bare merge on a branch with NO pull request is not held by the list ('no pull requests found' is an answer, not a failed read)" allow "$CLEAN" 'gh pr merge --squash' "pr view --json number --jq .number"
# gh api: label writes, issue writes and GraphQL, one probe per name
LABELS=$PL; h "REAL hook: parked: 'gh api --method DELETE .../issues/7/labels/parked' is denied, stub never called" deny "$CLEAN" 'gh api --method DELETE repos/o/r/issues/7/labels/parked' --none
LABELS=$PL; h "REAL hook: parked: 'gh api -X PATCH .../issues/7/labels' (replaces the label set) is denied" deny "$CLEAN" "gh api -X PATCH repos/o/r/issues/7/labels -f 'labels[]=bug'" "$LABELS_CALL"
LABELS=$PL; h "REAL hook: parked: 'gh api --method=PATCH .../issues/7' (an edit of the parked object) is denied" deny "$CLEAN" 'gh api --method=PATCH repos/o/r/issues/7 -f state=closed' "$LABELS_CALL"
PARKED_COUNT=1; h "REAL hook: parked: a variable inside an issue path ('gh api -X PUT .../issues/\$N/labels') is held while a PR is parked" deny "$CLEAN" 'gh api -X PUT repos/o/r/issues/$N/labels' "pr list --label parked --state open --json number --jq length"
h "REAL hook: parked: renaming the label object ('gh api -X PATCH .../labels/parked -f new_name=held') is denied" deny "$CLEAN" 'gh api -X PATCH repos/o/r/labels/parked -f new_name=held' --none
h "REAL hook: renaming ANOTHER label ('gh api -X PATCH .../labels/other') is allowed, stub never called" allow "$CLEAN" 'gh api -X PATCH repos/o/r/labels/other -f new_name=x' --none
h "REAL hook: a GET of the issue labels ('gh api .../issues/7/labels') is allowed, stub never called" allow "$CLEAN" 'gh api repos/o/r/issues/7/labels' --none
h "REAL hook: a comment POST on a PR ('gh api .../issues/7/comments -f body=x') is allowed, stub never called" allow "$CLEAN" 'gh api repos/o/r/issues/7/comments -f body=x' --none
for gq in mergePullRequest enablePullRequestAutoMerge enqueuePullRequest removeLabelsFromLabelable clearLabelsFromLabelable updateIssue updatePullRequest deleteLabel updateLabel; do
  PARKED_COUNT=1; h "REAL hook: parked: a GraphQL '$gq' mutation is denied while a PR is parked" deny "$CLEAN" "gh api graphql -f query='mutation { $gq(input: {}) { clientMutationId } }'" "pr list --label parked --state open --json number --jq length"
done
# the incident row: a deny leaves a record in the (sandboxed) ledger
INC_BEFORE=$(wc -l < "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
LABELS=$PARKED_LAB; h "REAL hook: parked: a deny (control for the incident row below)" deny "$CLEAN" "gh pr merge 7 --squash" "$LABELS_CALL"
INC_AFTER=$(wc -l < "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" 2>/dev/null || echo 0)
TOTAL=$((TOTAL + 1))
if (( INC_AFTER > INC_BEFORE )); then PASS=$((PASS + 1)); echo "PASS: a parked-barrier deny writes an incident row ($INC_BEFORE -> $INC_AFTER)"
else FAIL=$((FAIL + 1)); echo "FAIL: a parked-barrier deny wrote no incident row ($INC_BEFORE -> $INC_AFTER)"; fi
TOTAL=$((TOTAL + 1))
LAST_ID=$(tail -1 "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl" 2>/dev/null | jq -r '.rule_id // empty' 2>/dev/null || true)
if [[ "$LAST_ID" == "parked-merge-barrier" ]]; then PASS=$((PASS + 1)); echo "PASS: the incident row carries the barrier's own id ($LAST_ID), not another rule's"
else FAIL=$((FAIL + 1)); echo "FAIL: the incident row id is '$LAST_ID', expected parked-merge-barrier"; fi

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
# added, derived from a green run's TOTAL (41 at the second-round review edit, 59 after the first parked barrier, 102 after review round 1, 157 after the fix round).
ROW_FLOOR=157
if (( TOTAL < ROW_FLOOR )); then
  echo "FAIL: only $TOTAL rows ran; the floor is $ROW_FLOOR (rows were dropped or never ran)"
  exit 1
fi
[[ $FAIL -eq 0 ]]
