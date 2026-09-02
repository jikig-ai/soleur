#!/usr/bin/env bash
# PreToolUse hook on Monitor|TaskStop.
# Blocks arming a SECOND Monitor on a target this session is already watching,
# and redirects to TaskStop-then-rearm.
#
# Source rule: hr-monitor-not-run-in-background-for-polling (AGENTS.rules.md) —
# that rule governs WHICH tool polls. This hook governs the tool's LIFETIME,
# which nothing enforced: a monitor is a resource, and re-scoping what you watch
# means stopping the old watcher, not layering a new one beside it.
#
# Why: 2026-09-02 — a single session ran THREE monitors against `gh pr checks
# 7753` simultaneously. Each time the scope changed (CI → infra+CI → CI) a new
# monitor was armed and the superseded one was left running. None self-terminated,
# because each only exits when the polled state goes terminal — which had not
# happened yet. Three API calls per 45s interval against one endpoint, and three
# chances to report the same result. The operator noticed; no gate did.
#
# Detection (AND-gated; a missing signature falls through to allow):
#   tool_name == Monitor
#   AND a TARGET SIGNATURE can be extracted from .tool_input.command / .ws.url
#   AND this session already armed a monitor with the SAME signature
#   AND that arm is still inside its own declared timeout_ms
#   AND no TaskStop has been observed since that arm
#
# The last two conjuncts are what keep this from false-blocking. A monitor that
# has aged past its timeout is gone; a TaskStop since the arm means the agent
# already cleaned up. Both err toward ALLOW, which is the correct direction for a
# deny gate whose false positives cost real work.
#
# Signature is deliberately narrow — a PR/issue number, a workflow name, an
# absolute path, or a ws:// URL. Two monitors watching genuinely different things
# never collide, and a command with no extractable target is never blocked.
#
# Known limit, stated rather than papered over: a monitor that EXITS EARLY (breaks
# its loop on a terminal marker well before its timeout) still looks live to this
# hook, because a hook cannot observe task completion. Re-arming on that same
# target inside the original timeout window is the one false-positive case. The
# override marker below is the escape, and TaskStop is the better one.
#
# Override hatch: add the literal comment
#   # gate-override: monitor-supersede
# anywhere in the monitor command.
#
# Hook stdin: JSON payload with session_id + tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {...}} on deny; silent on allow.
# Hook exit code: 0 always. Fail-open on any missing field — a no-op hook is
# never a false block.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="${SOLEUR_MONITOR_LEDGER:-$PROJECT_DIR/.claude/.monitor-arms.jsonl}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

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
DESC=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null) || true
TIMEOUT_MS=$(printf '%s' "$INPUT" | jq -r '.tool_input.timeout_ms // 300000' 2>/dev/null) || TIMEOUT_MS=300000
PERSISTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.persistent // false' 2>/dev/null) || PERSISTENT=false

# A persistent monitor has no timeout; treat its window as the max Monitor ceiling
# so it ages out rather than blocking this session forever.
case "$TIMEOUT_MS" in ''|*[!0-9]*) TIMEOUT_MS=300000 ;; esac
[ "$PERSISTENT" = "true" ] && TIMEOUT_MS=3600000
WINDOW_S=$(( TIMEOUT_MS / 1000 ))

# Override hatch.
case "$CMD" in
  *"gate-override: monitor-supersede"*) exit 0 ;;
esac

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

# ---- is a prior arm on this signature still live? ---------------------------
PRIOR=""
if [ -r "$LEDGER" ]; then
  PRIOR=$(jq -rs --arg s "$SESSION" --arg sig "$SIG" --argjson now "$NOW" '
    ( [ .[] | select(.event == "stop" and .session == $s) | .ts ] | max // 0 ) as $laststop
    | [ .[]
        | select(.event == "arm" and .session == $s and .sig == $sig)
        | select(.ts + (.window // 300) > $now)
        | select(.ts > $laststop)
      ] | last // empty
    | "\(.ts)\t\(.desc)"
  ' "$LEDGER" 2>/dev/null) || PRIOR=""
fi

if [ -n "$PRIOR" ]; then
  prior_ts=$(printf '%s' "$PRIOR" | cut -f1)
  prior_desc=$(printf '%s' "$PRIOR" | cut -f2)
  age=$(( NOW - prior_ts ))
  emit deny monitor-supersede "duplicate monitor on $SIG" 2>/dev/null || true
  jq -n --arg sig "$SIG" --arg d "$prior_desc" --arg age "$age" --arg new "$DESC" '
    {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: (
          "BLOCKED: this session already has a monitor watching " + $sig +
          " — \"" + $d + "\", armed " + $age + "s ago and still inside its timeout.\n\n" +
          "Arming \"" + $new + "\" beside it means two watchers polling one target: " +
          "duplicate API calls every interval and two reports of the same result. " +
          "A monitor is a resource with a lifetime — re-scoping what you watch means " +
          "STOPPING the old one, not layering a new one.\n\n" +
          "Do one of:\n" +
          "  1. TaskStop the prior monitor, then arm this one (usually correct);\n" +
          "  2. keep the prior monitor and drop this call, if it already covers you;\n" +
          "  3. if the prior monitor already exited early, add the literal comment\n" +
          "     `# gate-override: monitor-supersede` to this command."
        )
      }
    }' 2>/dev/null || true
  exit 0
fi

# ---- allow, and record the arm ----------------------------------------------
jq -nc --arg s "$SESSION" --arg sig "$SIG" --arg d "$DESC" \
       --argjson ts "$NOW" --argjson w "$WINDOW_S" \
  '{event:"arm", session:$s, sig:$sig, desc:$d, ts:$ts, window:$w}' >> "$LEDGER" 2>/dev/null || true
exit 0
