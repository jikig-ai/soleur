#!/usr/bin/env bash
# PostToolUse hook on Bash + Monitor. Tracks ASYNC WORK THAT WAS DISPATCHED BUT NEVER WATCHED,
# and nags on every subsequent tool call until a Monitor is armed.
#
# THE FAILURE THIS EXISTS FOR IS SILENCE, WHICH IS WHY A PROSE RULE CANNOT HOLD IT. Firing a
# workflow and not watching it produces no error, no red, and no output — it is indistinguishable
# from waiting. The agent then narrates a plan while the answer already sits in a finished run.
# Measured 2026-08-19: a cutover readiness spine failed at gate 2.0 in ~2 seconds and sat unread
# while the agent wrote several paragraphs about what it would do next; the operator had to ask
# "are you monitoring the run?" twice in one session.
#
# It CANNOT block — the dispatch has already happened by PostToolUse, and blocking after the fact
# would be theatre. It converts an omission that is silent into one that is loud on every
# subsequent turn, which is the strongest honest lever at this point in the tool lifecycle.
#
# RESOLUTION IS ANY Monitor CALL, not a matching one. Correlating a monitor to its dispatch would
# need the monitor's command to name the run id, which is a convention this hook cannot enforce
# and which would produce false nags the moment someone watched via a different handle (a log
# tail, a Bash until-loop). A cleared flag on any Monitor is the honest approximation: it says
# "you are now watching something", not "you are watching the right thing".
#
# Also cleared by a FOREGROUND read of the same dispatch (gh run view/watch, gh pr checks) — an
# agent that immediately reads the result did not lose it, and nagging there would train the
# operator to ignore the nag, which is how a gate dies.
#
# Fail-open and silent on error: this hook must never cost a turn.
set -uo pipefail

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
[[ -f "$_LIB_DIR/incidents.sh" ]] && { source "$_LIB_DIR/incidents.sh"; } || true
export SOLEUR_HOOK_NAME="post-dispatch-watch-gate"

command -v jq >/dev/null 2>&1 || exit 0
# DELIBERATELY DOES NOT SOURCE lib/hook-input.sh. That helper exists for the ADR-156/157
# ask-machinery: a PreToolUse hook whose stdin failed to parse must hand off to the designated
# responder (guardrails.sh) to ASK the operator. This is a PostToolUse observer — it cannot ask
# and cannot deny, the tool call is already finished — so the machinery has nothing to do here,
# and sourcing it would put this file inside a trust-boundary contract (hook-input-contract.test.sh
# A9/A13/A18b) whose properties are all vacuous for an observer.
#
# The one property that DOES matter is ADR-156's: stdin is model-controlled, so a non-string field
# must never be coerced. `jq -r ... // ""` with an explicit `type == "string"` test is that check
# in its local form — an array-valued `command` yields "" and this hook no-ops, rather than
# rendering across lines and matching a dispatch pattern it was never given.
INPUT=$(cat)
_field() { jq -r --arg k "$1" 'getpath($k | split(".")) | if type == "string" then . else "" end' <<<"$INPUT" 2>/dev/null || printf ''; }
HOOK_TOOL_NAME="$(_field 'tool_name')"
HOOK_CWD="$(_field 'cwd')"
HOOK_CMD="$(_field 'tool_input.command')"
[[ -n "$HOOK_TOOL_NAME" ]] || exit 0

ROOT="${HOOK_CWD:-$PWD}"
GITDIR="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" || exit 0
[[ -n "$GITDIR" ]] || exit 0
case "$GITDIR" in /*) ;; *) GITDIR="$ROOT/$GITDIR" ;; esac
STATE="$GITDIR/soleur-pending-dispatch"

# --- Monitor armed: everything pending is now considered watched -----------------------------
#
# ARMED IS NOT THE SAME AS REPORTING. This hook, and both monitor hard rules, only ever asked that
# a Monitor EXIST. Measured on #7778: a monitor was armed whose every `echo` sat behind a
# terminal-state branch (merged / failed / cancelled / timed out). It ran for ~50 minutes emitting
# nothing, and the operator had to ask why the monitor showed no progress — the exact outcome
# hr-dispatch-async-must-arm-watch names in its own rationale ("Unwatched async work is silent,
# not pending"), reached while fully satisfying that rule.
#
# So: still clear the flag (a monitor IS armed — that is honest), and separately WARN when the
# command has no emission the healthy path can reach. Warn-only, never deny, for the reason this
# file's header already gives about false nags killing a gate: this is a heuristic over shell
# text, it cannot see through a called script, and it is wrong on any loop whose progress line
# comes from a helper. The allowlist below is why `monitor-pr-checks.sh` exists — a script
# invocation is checkable where a hand-rolled loop is not.
if [[ "$HOOK_TOOL_NAME" == "Monitor" ]]; then
  rm -f "$STATE" 2>/dev/null || true
  MON_CMD="$(_field 'tool_input.command')"
  if [[ -n "$MON_CMD" ]]; then
    # Delegating to a known-good reporter, or a naturally-streaming source, needs no check.
    if grep -qE 'monitor-pr-checks\.sh|tail -f|inotifywait|websocat' <<<"$MON_CMD"; then
      exit 0
    fi
    # A loop is present but every emission is conditional => the healthy path is silent.
    # HERE-STRINGS, NOT `printf | grep -q` (#6992, enforced by grep-q-pipe-guard.test.sh):
    # `grep -q` exits on its first match and SIGPIPEs the producer, which under `pipefail` is
    # rc=141 — inside a policy-gate hook that is an unexplained failure, not a verdict.
    if grep -qE '\b(while|until|for)\b' <<<"$MON_CMD" \
       && ! grep -qE '^[[:space:]]*(echo|printf)' <<<"$MON_CMD" ; then
      emit_incident post-dispatch-watch-gate warn \
        "monitor armed with no unconditional progress emission" "${MON_CMD:0:50}" 2>/dev/null || true
      jq -n '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
        ("post-dispatch-watch-gate: the Monitor you just armed has a poll loop whose every emission " +
         "looks conditional. If nothing prints on the HEALTHY still-running path, silence will be " +
         "indistinguishable from a dead watch for the whole run (#7778).\n" +
         "Prefer: bash plugins/soleur/scripts/monitor-pr-checks.sh <PR>\n" +
         "Or add one unconditional progress line per poll, before the terminal-state branches.")}}'
      exit 0
    fi
  fi
  exit 0
fi

[[ "$HOOK_TOOL_NAME" == "Bash" ]] || exit 0
CMD="$HOOK_CMD"
[[ -n "$CMD" ]] || exit 0

# A FOREGROUND read of run state counts as watching. Checked BEFORE the dispatch match so a
# combined "dispatch && then read it" line does not immediately arm a nag it already answered.
FOREGROUND_READ_RE='gh (run (view|watch)|pr checks)'
if grep -qE "$FOREGROUND_READ_RE" <<<"$CMD"; then
  rm -f "$STATE" 2>/dev/null || true
  exit 0
fi

# --- did this call dispatch async work? -------------------------------------------------------
DISPATCH_RE='gh workflow run|gh run rerun|gh pr merge[^|;&]*--auto'
if grep -qE "$DISPATCH_RE" <<<"$CMD"; then
  label="$(grep -oE 'gh workflow run [A-Za-z0-9._-]+|gh run rerun [0-9]+|gh pr merge [0-9]+' <<<"$CMD" | head -1)"
  printf '%s\t%s\n' "$(date +%s 2>/dev/null || echo 0)" "${label:-async dispatch}" >> "$STATE" 2>/dev/null || true
  exit 0
fi

# --- pending and unwatched: nag ----------------------------------------------------------------
[[ -s "$STATE" ]] || exit 0
n="$(grep -c . "$STATE" 2>/dev/null || echo 0)"
[[ "$n" =~ ^[0-9]+$ ]] || n=0
(( n > 0 )) || exit 0
first="$(head -1 "$STATE" 2>/dev/null | cut -f2)"

declare -f emit_incident >/dev/null 2>&1 && \
  emit_incident post-dispatch-watch-gate warn "dispatched async work with no Monitor armed" "$first" 2>/dev/null || true

jq -n --arg n "$n" --arg f "${first:-async dispatch}" '{systemMessage:
  ("post-dispatch-watch-gate: \($n) dispatched job(s) with NO Monitor armed — oldest: \($f).\n" +
   "Async work that is not watched is SILENT, not pending: it finishes, and nothing tells you.\n" +
   "Arm a Monitor now, or read it in the foreground (gh run view/watch). Do not narrate the plan first.")}'
exit 0
