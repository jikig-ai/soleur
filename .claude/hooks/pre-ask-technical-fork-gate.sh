#!/usr/bin/env bash
# PreToolUse hook on AskUserQuestion. Denies questions that ask the OPERATOR to pick between
# TECHNICAL INVESTIGATION paths — reading a runbook, checking a file, asking an owner. Soleur
# operators are non-technical by design; a question they cannot answer is not a question, it is
# the agent declining to do its job and stalling the pipeline until someone guesses.
#
# WHAT IS AND IS NOT THE OPERATOR'S CALL — the distinction this hook encodes:
#
#   THEIRS (allow):     an irreversible or production-mutating action (merge, replace, destroy,
#                       arm, flip, delete, force-push, deploy, rotate, revoke), money, scope,
#                       priority, or schedule. These need authority the agent does not have.
#   NOT THEIRS (deny):  which file to read, which hypothesis to chase, whether to consult the
#                       runbook/ADR/issue, who to ask. These need only effort the agent has.
#
# **Why:** 2026-08-19 — mid-cutover the agent asked "read the runbook properly first, or ask
# whoever owns #7462's cutover section?". The runbook was two commands away and answered the
# question definitively, including that the immediately preceding operator action had been wrong.
# Three days of dead-ends preceded it, all downstream of an ordered sequence in the linked issue
# that was never opened. `hr-exhaust-all-automated-options-before` and
# `hr-never-label-any-step-as-manual-without` already forbid this; prose did not hold, so this is
# the mechanical form.
#
# CONSERVATIVE BY CONSTRUCTION. The deny needs an investigative signal AND the absence of any
# authority signal. A question that mentions BOTH ("investigate, or merge with [ack-destroy]?")
# is ALLOWED — an ask that carries a real authorization is never blocked on the strength of one
# co-occurring word. This fails toward permitting, because a wrongly-blocked authorization is a
# production action taken without consent, which is strictly worse than a wrongly-permitted
# question.
#
# Escape hatch: SOLEUR_ACK_TECHNICAL_FORK=1 — announced, never silent.
#
# Fail-open: any infrastructure error exits 0 (allow), reporting itself via systemMessage and an
# incident row. A hook must never wedge the turn on its own bug.
set -uo pipefail

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$_LIB_DIR/incidents.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/incidents.sh"
fi
export SOLEUR_HOOK_NAME="pre-ask-technical-fork-gate"

command -v jq >/dev/null 2>&1 || {
  printf 'pre-ask-technical-fork-gate: SKIPPED — jq unavailable, question NOT scanned\n' >&2
  exit 0
}

# shellcheck source=lib/hook-input.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
declare -f hook_parse_input >/dev/null 2>&1 || {
  echo "[pre-ask-technical-fork-gate] hook-input helper missing — guard did NOT run" >&2
  exit 0
}

INPUT=$(cat)
__HI_RAW="$INPUT"
# ADR-156/157 canonical parse-failure block: report, then let the DESIGNATED RESPONDER ask.
# guardrails.sh is registered on this tool too (A9) and is the one that emits the ask; this hook
# reports and exits 0. Deviating here is how a hook ends up silently un-gated (#7164 defect 2).
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "pre-ask-technical-fork-gate"
  hook_input_should_ask && { hook_input_emit_ask "pre-ask-technical-fork-gate"; exit 0; }
  exit 0
fi

[[ "$HOOK_TOOL_NAME" == "AskUserQuestion" ]] || exit 0

if [[ "${SOLEUR_ACK_TECHNICAL_FORK:-}" == "1" ]]; then
  jq -n '{systemMessage:"pre-ask-technical-fork-gate: disarmed by SOLEUR_ACK_TECHNICAL_FORK=1"}' 2>/dev/null
  exit 0
fi

# Flatten every operator-visible string: question text, option labels, option descriptions. The
# label alone is too thin — "Option A" carries no signal while its description says "read the
# runbook", and the description is what the operator actually reads.
CORPUS="$(printf '%s' "$__HI_RAW" | jq -r '
  ( .tool_input.questions // [] )[]
  | (.question // ""), ( (.options // [])[] | (.label // ""), (.description // "") )
' 2>/dev/null | tr '\n' ' ' | tr '[:upper:]' '[:lower:]')"
[[ -n "$CORPUS" ]] || exit 0

# AUTHORITY signal — a real operator decision. Checked FIRST and wins outright.
AUTHORITY_RE='(ack-destroy|authori[sz]|approve|merge|replace|destroy|delete|force-push|deploy|dispatch|apply |arm the|flip |rotate|revoke|spend|cost|budget|price|priorit|scope|schedule|which (issue|feature|milestone)|proceed with the (merge|replace|destroy|apply|cutover))'
if grep -qE "$AUTHORITY_RE" <<<"$CORPUS"; then exit 0; fi

# INVESTIGATIVE signal — work the agent can do itself.
INVESTIGATIVE_RE='(read the |re-?read |check whether|check if|investigate|look at |look into|find out|diagnose|figure out|ask (the )?(owner|author|whoever)|consult the |search (the )?(repo|codebase|issue)|inspect the |grep |open the (runbook|adr|issue|plan|spec)|(runbook|adr|issue|plan|spec) first)'
if ! grep -qE "$INVESTIGATIVE_RE" <<<"$CORPUS"; then exit 0; fi

REASON="BLOCKED: this AskUserQuestion asks the operator to choose between TECHNICAL INVESTIGATION paths.

Soleur operators are non-technical. They cannot pick between 'read the runbook' and 'ask the owner', and asking stalls the pipeline until someone guesses. That choice is yours, and the work is cheap.

Resolve it yourself, in this order, before asking anything:
  1. The linked ISSUE's own ordered sequence   (gh issue view <N>)
  2. The RUNBOOK for the operation             (knowledge-base/engineering/operations/runbooks/)
  3. The ADR that owns the decision            (knowledge-base/engineering/architecture/decisions/)
  4. The guard's / script's own comments       (the code refusing you usually says why)

Then ACT on what you find.

Ask the operator ONLY for: authorization for an irreversible or production-mutating action, money, scope, priority, or schedule.

If this question genuinely carries an authorization and the wording tripped the classifier, re-word it to name the action being authorized — or re-run with SOLEUR_ACK_TECHNICAL_FORK=1.

See hr-exhaust-all-automated-options-before and hr-never-label-any-step-as-manual-without."

declare -f emit_incident >/dev/null 2>&1 && \
  emit_incident pre-ask-technical-fork-gate deny "technical fork put to a non-technical operator" "$CORPUS" 2>/dev/null || true

jq -n --arg r "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
