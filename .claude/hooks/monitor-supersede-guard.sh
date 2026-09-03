#!/usr/bin/env bash
# PreToolUse hook on Monitor|TaskStop.
# REPORTS — never blocks — arming a Monitor on a target this session already
# armed one for and never stopped.
#
# Source rule: hr-monitor-not-run-in-background-for-polling (AGENTS.rules.md) —
# that rule governs WHICH tool polls. This hook governs the tool's LIFETIME,
# which nothing enforced: a monitor is a resource, and re-scoping what you watch
# means stopping the old watcher, not layering a new one beside it.
#
# Why: 2026-09-02 — a single session ran THREE monitors against `gh pr checks
# 7753` simultaneously. Each time the scope changed (CI -> infra+CI -> CI) a new
# monitor was armed and the superseded one was left running. None self-terminated,
# because each only exits when the polled state goes terminal — which had not
# happened yet. Three API calls per 45s interval against one endpoint, and three
# chances to report the same result. The operator noticed; no gate did.
#
# WHY THIS REPORTS INSTEAD OF BLOCKING — the load-bearing part, and the thing to
# re-read before anyone "restores" the deny:
#
# The gate a deny needs is "is the prior monitor still running". This hook cannot
# answer that, by either available route, and both were measured on 2026-09-03:
#
#   1. INFERRED from the clock. A hook sees arms and TaskStops, never completions,
#      so "inside its declared timeout" was used as a proxy. Monitors mostly end
#      by early exit (their loop breaks on a terminal state) or by harness reap —
#      neither writes a stop record. The proxy therefore decays into "armed
#      recently", and the gate denied on recency while claiming liveness. A 50%
#      fraction was added to blunt it; that only made the wrong predicate quieter.
#      Concretely it denied ship Phase 7's own fix-and-retry path, which re-polls
#      one PR after pushing a fix — same session, same signature, same window.
#
#   2. MEASURED from the process table. `pgrep -f <signature>` looks decisive and
#      is not: the agent's own Bash calls routinely carry the PR number, so the
#      probe matches the very command asking the question. Verified — a control
#      probe for a signature with NO monitor matched its own shell. Liveness by
#      process inspection is contaminated by ordinary session activity.
#
# A gate whose central predicate is unmeasurable must not deny. And it does not
# need to: the audience is an agent that reads tool output, so a message at the
# moment of the arm is as effective as a block, and only the block can wedge the
# pipeline. False notice costs one paragraph; false deny cost a ship run.
#
# What survives is honest and still useful: the notice names the prior arm, its
# age, and the remedy, at exactly the moment the mistake is made.
#
# Detection (AND-gated; anything missing falls through to silence):
#   tool_name == Monitor
#   AND a TARGET SIGNATURE can be extracted from .tool_input.command / .ws.url
#   AND this session already armed a monitor with the SAME signature
#   AND that arm is still inside its own declared timeout_ms  (recency, not liveness)
#   AND no TaskStop has been observed since that arm
#
# Signature is deliberately narrow — a PR/issue number, a workflow name, an
# absolute path, or a ws:// URL. Two monitors watching genuinely different things
# never collide, and a command with no extractable target is never reported.
#
# There is no override marker. Nothing blocks, so nothing needs escaping; case 20
# pins that the hook emits no permissionDecision on any input shape.
#
# Hook stdin: JSON payload with session_id + tool_name + tool_input.
# Hook stdout: JSON {systemMessage: "..."} when reporting; silent otherwise.
# Hook exit code: 0 always.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="${SOLEUR_MONITOR_LEDGER:-$PROJECT_DIR/.claude/.monitor-arms.jsonl}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() {
  if command -v emit_incident >/dev/null 2>&1; then emit_incident "$@" || true; fi
}

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || exit 0
NOW=$(date +%s 2>/dev/null) || exit 0

mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || exit 0

# A TaskStop clears the "still layered" condition for this session. It cannot be
# correlated to a specific signature (the arm predates the task id), so it clears
# broadly — deliberately, since over-clearing only ever allows.
if [ "$TOOL" = "TaskStop" ]; then
  printf '{"event":"stop","session":"%s","ts":%s}\n' "$SESSION" "$NOW" >> "$LEDGER" 2>/dev/null || true
  exit 0
fi

[ "$TOOL" = "Monitor" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
WSURL=$(printf '%s' "$INPUT" | jq -r '.tool_input.ws.url // ""' 2>/dev/null) || true
# `tr -d '\n\t'` is a MESSAGE normaliser, not a safety fix, and the distinction is
# load-bearing for anyone re-testing this line. The crash it looks like it prevents
# is prevented by `head -1` at the READ site instead: this value reaches the ledger
# through `jq -nc --arg d`, which escapes a newline to an in-string `\n` and emits a
# valid single-line record either way. Measured — replacing this `tr` with `cat`
# leaves the suite green (an equivalent mutant), while reverting the read-side
# `head -1` reddens case 19. What it buys is the deny TEXT: without it a multi-line
# description renders as its first line only, because `head -1` is what truncates.
DESC=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null | tr -d '\n\t' | cut -c1-200) || true
TIMEOUT_MS=$(printf '%s' "$INPUT" | jq -r '.tool_input.timeout_ms // 300000' 2>/dev/null) || TIMEOUT_MS=300000
PERSISTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.persistent // false' 2>/dev/null) || PERSISTENT=false

# A persistent monitor has no timeout; treat its window as the max Monitor ceiling
# so it ages out rather than blocking this session forever.
case "$TIMEOUT_MS" in ''|*[!0-9]*) TIMEOUT_MS=300000 ;; esac
[ "$PERSISTENT" = "true" ] && TIMEOUT_MS=3600000
WINDOW_S=$(( TIMEOUT_MS / 1000 ))

# ---- signature extraction (first match wins; no match => allow) --------------
SIG=""
if [ -n "$WSURL" ]; then
  SIG="ws:$WSURL"
else
  # A PR / issue number under a gh subcommand that takes one.
  n=$(printf '%s' "$CMD" | grep -oE 'gh (pr|issue) [a-z-]+ [0-9]+' | grep -oE '[0-9]+$' | head -1)
  if [ -n "$n" ]; then
    SIG="pr:$n"
  else
    w=$(printf '%s' "$CMD" | grep -oE '\-\-workflow[= ][A-Za-z0-9._-]+' | head -1 | sed 's/.*[= ]//')
    if [ -n "$w" ]; then
      SIG="workflow:$w"
    else
      p=$(printf '%s' "$CMD" | grep -oE '/(var/tmp|tmp)/[A-Za-z0-9._/-]+' | head -1)
      [ -n "$p" ] && SIG="path:$p"
    fi
  fi
fi

if [ -z "$SIG" ]; then
  exit 0
fi

# ---- is there a RECENT prior arm on this signature? --------------------------
PRIOR=""
if [ -r "$LEDGER" ]; then
  # `-R 'fromjson? // empty'` reads line-at-a-time and DROPS unparseable lines
  # instead of failing the whole read. A torn or hand-edited line then costs one
  # record, not the entire gate.
  PRIOR=$(jq -R 'fromjson? // empty' "$LEDGER" 2>/dev/null | jq -s --arg s "$SESSION" --arg sig "$SIG" --argjson now "$NOW" -r '
    ( [ .[] | select(.event == "stop" and .session == $s) | .ts ] | max // 0 ) as $laststop
    | [ .[]
        | select(.event == "arm" and .session == $s and .sig == $sig)
        | select(.ts + (.window // 300) > $now)
        | select(.ts > $laststop)
      ] | last // empty
    | "\(.ts)\t\(.desc)"
  ') || PRIOR=""
fi

if [ -n "$PRIOR" ]; then
  prior_ts=$(printf '%s' "$PRIOR" | head -1 | cut -f1)
  prior_desc=$(printf '%s' "$PRIOR" | head -1 | cut -f2-)
  # A non-numeric ts means the record is unusable; say nothing rather than abort.
  case "$prior_ts" in ''|*[!0-9]*) prior_ts="" ;; esac
  if [ -n "$prior_ts" ]; then
    age=$(( NOW - prior_ts ))
    emit monitor-supersede warn "recent prior monitor on $SIG" "$CMD" 2>/dev/null || true
    # `systemMessage` is the exit-0 channel: Claude Code DISCARDS a PreToolUse
    # hook's stderr when it allows, so a stderr-only notice reaches nobody.
    # Same reasoning as pre-merge-auto-close-scan.sh's `allow_exit`.
    jq -n --arg sig "$SIG" --arg d "$prior_desc" --arg age "$age" '
      { systemMessage: (
          "monitor-supersede: this session armed a monitor on " + $sig + " " + $age +
          "s ago — \"" + $d + "\" — and never stopped it.\n" +
          "If it is still running, two watchers are now on one target — for a poll " +
          "loop that is duplicate requests every interval, for a ws:// stream a " +
          "second subscription — and two reports of the same result. " +
          "TaskStop the prior one unless it has already returned.\n" +
          "(This hook cannot see a monitor finish, so it reports the arm, not a fault.)"
        ) }' 2>/dev/null || true
  fi
fi

# ---- allow, and record the arm ----------------------------------------------
jq -nc --arg s "$SESSION" --arg sig "$SIG" --arg d "$DESC" \
       --argjson ts "$NOW" --argjson w "$WINDOW_S" \
  '{event:"arm", session:$s, sig:$sig, desc:$d, ts:$ts, window:$w}' >> "$LEDGER" 2>/dev/null || true
exit 0
