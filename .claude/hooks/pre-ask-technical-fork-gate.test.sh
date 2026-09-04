#!/usr/bin/env bash
# Fixture tests for pre-ask-technical-fork-gate.sh.
#
# The gate sits in front of the ONE tool that stalls a pipeline waiting on a human, so both
# directions are load-bearing and neither is the "happy path":
#   a wrongly-ALLOWED investigative question costs a stalled pipeline and an operator guess;
#   a wrongly-DENIED authorization question costs a production action taken without consent.
# The second is worse, which is why the gate requires an investigative signal AND the absence of
# any authority signal, and why the A-cases below outnumber the D-cases.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only) but the two headline cases are
# verbatim from 2026-08-19: D1 is the question that prompted this hook, A1 is the ack-destroy
# authorization from the same session that must keep working.
set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pre-ask-technical-fork-gate.sh"
PASS=0; FAIL=0; TOTAL=0
[[ -x "$HOOK" ]] || { echo "FATAL: hook not executable at $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

# payload <question> <label1> <desc1> [<label2> <desc2>]
payload() {
  jq -nc --arg q "$1" --arg l1 "${2:-}" --arg d1 "${3:-}" --arg l2 "${4:-}" --arg d2 "${5:-}" '
    {tool_name:"AskUserQuestion", cwd:".", session_id:"t",
     tool_input:{questions:[{question:$q, options:[{label:$l1,description:$d1},{label:$l2,description:$d2}]}]}}'
}

run_case() { # name expect(allow|deny) payload...
  local name="$1" expect="$2"; shift 2
  TOTAL=$((TOTAL+1))
  local out dec
  out=$(payload "$@" | "$HOOK" 2>/dev/null)
  dec=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null || echo allow)
  if [[ "$dec" == "$expect" ]]; then printf '  PASS: %s (%s)\n' "$name" "$dec"; PASS=$((PASS+1))
  else printf '  FAIL: %s — got %s want %s\n' "$name" "$dec" "$expect" >&2; FAIL=$((FAIL+1)); fi
}

echo "== pre-ask-technical-fork-gate =="

# --- DENY: investigative forks the agent must resolve itself ---------------------------------
run_case "D1 the verbatim 2026-08-19 question" deny \
  "How should I resolve the cutover path?" \
  "Read the runbook properly first" "Find the documented order for a cold host rather than reasoning it out from guard comments." \
  "Ask whoever owns the cutover section" "The plan deferred the cutover window to numbered steps I have not read."
run_case "D2 which file to inspect" deny \
  "Which source should I check?" "Check whether the ADR says" "look at the decision record" "Grep the codebase" "search the repo for callers"
run_case "D3 hypothesis selection" deny \
  "How do we find the cause?" "Investigate the pooler" "diagnose the connection path" "Look into the guard" "read the guard comments"

# --- ALLOW: real operator decisions --------------------------------------------------------
run_case "A1 the ack-destroy authorization from the same session" allow \
  "This merge fires a production apply. How do you want to proceed?" \
  "Merge WITH [ack-destroy]" "Authorizes replacing terraform_data.journald_persistent on production web-1." \
  "Hold" "Leave the PR open."
run_case "A2 destructive host replace" allow \
  "Dispatch the host replace?" "Replace the host" "destroys and re-creates the production inngest host" "Wait" "leave it dark"
run_case "A3 cost" allow \
  "This adds a recurring vendor cost. Proceed?" "Approve the spend" "about 20 EUR/month" "Decline" "find a free tier"
run_case "A4 scope/priority" allow \
  "Which should I do first?" "Fix the P1" "priority order" "Ship the feature" "scope for this milestone"
# The mixed case is the one a careless implementation gets wrong: an authorization that happens
# to mention reading something must still reach the operator.
run_case "A5 MIXED — authorization that also mentions reading" allow \
  "Merge with [ack-destroy], or investigate further?" \
  "Merge with [ack-destroy]" "authorize the production apply" \
  "Investigate first" "read the runbook before merging"

# --- ALLOW: not our tool / empty ------------------------------------------------------------
TOTAL=$((TOTAL+1))
out=$(jq -nc '{tool_name:"Bash",cwd:".",tool_input:{command:"read the runbook"}}' | "$HOOK" 2>/dev/null)
if [[ -z "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"${out:-{\}}" 2>/dev/null)" ]]; then
  echo "  PASS: N1 non-AskUserQuestion tool is untouched"; PASS=$((PASS+1))
else echo "  FAIL: N1 hook fired on the wrong tool" >&2; FAIL=$((FAIL+1)); fi

# --- the hatch -------------------------------------------------------------------------------
TOTAL=$((TOTAL+1))
out=$(payload "How?" "Read the runbook" "read the runbook first" "Ask the owner" "ask the owner" | SOLEUR_ACK_TECHNICAL_FORK=1 "$HOOK" 2>/dev/null)
if [[ "$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}" 2>/dev/null)" == "allow" ]] \
   && grep -q 'SOLEUR_ACK_TECHNICAL_FORK' <<<"${out:-}"; then
  echo "  PASS: H1 hatch allows AND announces itself"; PASS=$((PASS+1))
else echo "  FAIL: H1 hatch silent or ineffective" >&2; FAIL=$((FAIL+1)); fi

# --- anti-vacuity ----------------------------------------------------------------------------
TOTAL=$((TOTAL+1))
if [[ "$TOTAL" -eq 11 ]]; then echo "  PASS: V1 full inventory ran (11 cases)"; PASS=$((PASS+1))
else echo "  FAIL: V1 expected 11 cases, ran $TOTAL" >&2; FAIL=$((FAIL+1)); fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
(( FAIL > 0 )) && exit 1
echo "OK"
