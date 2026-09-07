#!/usr/bin/env bash

# Stop hook: refuse a turn that ENDS on a promise it did not keep.
#
# THE DEFECT THIS EXISTS FOR
# --------------------------
# A turn ends with a sentence naming the next action -- "implementing now",
# "I'll run those next" -- and the action never runs. The operator has to say
# "why did you stop". Measured 2026-09-07: three times in ONE session, the third
# inside the turn that was building this hook.
#
# Why prose could not fix it: `review/SKILL.md` §6 already names the shape
# ("the deferral does not announce itself as one -- it reads as a status report
# with a clean summary, so nothing feels skipped"). That rule was read and
# violated twice in the session it governs. This repo's own record is that every
# PreToolUse hook exists BECAUSE a prose rule failed first.
#
# Why a Stop hook and not another rule: every other enforcement here fires on a
# tool call. This defect is the ABSENCE of one. The enforcement surface was
# inverted relative to the failure -- nothing observed the moment a turn ended.
#
# WHY IT MATTERS MORE FOR USERS THAN FOR THE AUTHOR
# -------------------------------------------------
# The operator caught this because they could read the pipeline state. A
# non-technical Soleur user gets a confident summary, nothing red, and a
# half-finished task. For them the failure is silent by construction, which is
# the definition of the class this repo exists to close.
#
# INPUT CONTRACT
# --------------
# Reads `.last_assistant_message` from the Stop payload on stdin. That field is
# PROVEN in this codebase -- `stop-hook.sh` has read it since 2026-03-09, and
# learning `2026-03-09-stop-hook-path-resolution-and-api-simplification.md`
# records it as the stable API surface that replaced transcript parsing.
#
# It deliberately does NOT depend on `.tool_calls`. The Stop payload is
# documented to carry it, but nothing in this repo reads it, so it is unproven
# here -- and a hook keyed on a field that turns out to be absent silently never
# fires, which is exactly the fail-open class this hook exists to prevent. If a
# future change proves the field, tighten the predicate then; do not assume it.
#
# OUTPUT CONTRACT
# ---------------
# `{"decision":"block","reason":...}` -- the shape `stop-hook.sh` already uses
# successfully in this plugin, not the `permissionDecision` shape the public
# docs describe. Proven beats documented.
#
# WEDGE SAFETY
# ------------
# Claude Code force-stops after 3 successive Stop blocks, so a wrong predicate
# costs at most a few turns and can never trap a session. A local counter adds a
# second bound so a persistent false positive degrades to a warning rather than
# a repeated block.

set -uo pipefail

# ---------------------------------------------------------------------------
# Fail OPEN on every infrastructure problem. This hook's job is to catch a
# behavioural defect; it must never be the reason a session cannot end.
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || exit 0

HOOK_INPUT=$(cat 2>/dev/null) || exit 0
[[ -n "$HOOK_INPUT" ]] || exit 0

LAST_MSG=$(printf '%s' "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null) || exit 0
[[ -n "$LAST_MSG" ]] || exit 0

SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null || echo nosession)
# Sanitise: the value lands in a filename.
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd '[:alnum:]._-'); SESSION_ID=${SESSION_ID:-nosession}

# ---------------------------------------------------------------------------
# STATE DIRECTORY -- hostile-/tmp safe.
#
# The stand-down counter has to persist BETWEEN turns, so `mktemp -d` per
# invocation is not available and the path is necessarily predictable. On a
# shared machine with a world-writable /tmp that is two real primitives:
#
#   * `mkdir -p` SUCCEEDS THROUGH A SYMLINK (measured), so a pre-created
#     /tmp/soleur-unkept-promise -> /somewhere/else turns the counter write into
#     a file-clobber at an attacker-chosen path;
#   * a pre-seeded <session>.count silently disables the guard, which for a
#     security-adjacent workflow control is the worse of the two.
#
# Prefer XDG_RUNTIME_DIR (per-user, mode 0700, not shared) and fall back to
# TMPDIR. Then REFUSE unless the directory is a real directory, not a symlink,
# and owned by us. Fail OPEN on refusal -- this hook must never be the reason a
# session cannot end.
# ---------------------------------------------------------------------------
STATE_BASE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
STATE_DIR="${STATE_BASE}/soleur-unkept-promise"
# Not `mkdir -p -m 700`: with -p the mode applies only to the DEEPEST directory
# created (SC2174), so a created parent would keep the default umask. The base
# is expected to exist already, so create just the leaf with an explicit mode.
if [[ ! -d "$STATE_DIR" ]]; then
  mkdir -m 700 "$STATE_DIR" 2>/dev/null || exit 0
fi
# `-d` follows symlinks, so the `! -L` arm is what rejects a pre-created
# symlink; `-O` rejects a directory planted by another user.
[[ -d "$STATE_DIR" && ! -L "$STATE_DIR" && -O "$STATE_DIR" ]] || exit 0
chmod 700 "$STATE_DIR" 2>/dev/null || true
COUNTER_FILE="${STATE_DIR}/${SESSION_ID}.count"
# A counter file that is a symlink or not ours is refused the same way.
if [[ -e "$COUNTER_FILE" || -L "$COUNTER_FILE" ]]; then
  [[ -f "$COUNTER_FILE" && ! -L "$COUNTER_FILE" && -O "$COUNTER_FILE" ]] || exit 0
fi

# ---------------------------------------------------------------------------
# ESCAPE HATCH -- declaring a stop is always legal; stopping SILENTLY is not.
#
# A turn that genuinely hands off (an operator credential entry, a merge queue,
# a question the operator must answer) says so with the sentinel. That converts
# an invisible stop into an auditable one, which is the actual goal: the hook
# does not exist to force infinite work, it exists to make every handoff
# explicit.
# ---------------------------------------------------------------------------
if printf '%s' "$LAST_MSG" | grep -qiE '<promise>[[:space:]]*(OPERATOR-GATE|DONE|BLOCKED)'; then
  rm -f "$COUNTER_FILE" 2>/dev/null
  exit 0
fi

# ---------------------------------------------------------------------------
# Scope the scan to the CLOSING of the message.
#
# The defect is a turn that ENDS on an unkept promise. The same phrasing mid-
# message is ordinary narration of work that then happened ("I'll check X" ->
# followed by checking X and reporting it). Only the sign-off is evidence about
# where the turn stopped, so anchoring on the tail is what keeps this from
# firing on every explanatory paragraph.
# ---------------------------------------------------------------------------
TAIL=$(printf '%s' "$LAST_MSG" | tail -c 700)

# ---------------------------------------------------------------------------
# CONDITIONAL promises are legitimate and must NOT fire.
#
# "Say the word and I'll run it", "if you'd rather X, I'll do Y", "once you
# rotate the token I'll ..." are all correct stopping points: they are waiting
# on the operator by construction. This check runs FIRST and wins, because a
# false positive here trains the operator to ignore the hook -- which is worse
# than the defect (this repo's own reasoning about gates that cannot pass).
# ---------------------------------------------------------------------------
CONDITIONAL_RE='(say the word|if you|once you|when you|whenever you|let me know|tell me|your call|shall i|would you like|do you want|either way|up to you|on your (go|signal|say))'
if printf '%s' "$TAIL" | grep -qiE "$CONDITIONAL_RE"; then
  rm -f "$COUNTER_FILE" 2>/dev/null
  exit 0
fi

# A promise whose completion depends on something ALREADY IN FLIGHT and outside
# this turn -- a running agent, a queued merge, a CI run -- is a correct stop.
# "I'll report what they find" is not the defect; the turn genuinely cannot
# proceed. Without this arm the hook fires on every honest "waiting on X" line,
# which is the over-firing that gets a gate routed around.
PENDING_RE='(report (what|back|it)|(when|once|as soon as|after) (it|they|that|the|ci|those)|(they|it|those) (find|finds|land|lands|complete|completes|merge|merges|return|returns|come back)|still running|in flight|notification arrives|rather than assume)'
if printf '%s' "$TAIL" | grep -qiE "$PENDING_RE"; then
  rm -f "$COUNTER_FILE" 2>/dev/null
  exit 0
fi

# A trailing question is a genuine stop -- the turn is waiting on an answer.
if printf '%s' "$TAIL" | tr -d '[:space:]' | grep -qE '\?$'; then
  rm -f "$COUNTER_FILE" 2>/dev/null
  exit 0
fi

# ---------------------------------------------------------------------------
# THE PREDICATE: an unconditional, first-person, imminent commitment.
#
# Every alternative is a promise the turn is ending on rather than keeping.
# Kept deliberately narrow -- it is better to miss an instance than to fire on
# a correct handoff, for the reason above.
# ---------------------------------------------------------------------------
# Broad detection, narrow allowlist -- deliberately this way round. The allow
# arms above (escape hatch, conditional, trailing question, pending-external)
# carry the false-positive load; this arm carries the miss load. Measured: the
# three real instances had NO common temporal marker ("...verbatim now",
# "I'll run those rather than describe them", "I'll probe them ... then build"),
# so a predicate requiring one missed two of three. Over-firing costs at most
# two turns (stand-down below, plus the runtime's own 3-block ceiling); a miss
# costs the operator having to ask "why did you stop".
PROMISE_RE="(i'll |i will |i'm going to |im going to |let me (now )?[a-z]+)"
GERUND_RE='(^|[.!?][[:space:]]+)(implementing|running|building|writing|committing|pushing|shipping|fixing|creating|adding|executing|starting|continuing|proceeding)\b'

FIRED=""
if printf '%s' "$TAIL" | grep -qiE "$PROMISE_RE"; then
  FIRED="a first-person commitment to act"
elif printf '%s' "$TAIL" | grep -qiE "$GERUND_RE"; then
  FIRED="a bare gerund announcement (\"<verb>ing ...\")"
fi

[[ -n "$FIRED" ]] || { rm -f "$COUNTER_FILE" 2>/dev/null; exit 0; }

# ---------------------------------------------------------------------------
# Second bound on top of the runtime's 3-block ceiling. If the predicate is
# wrong about this particular turn, degrade to silence rather than fight the
# operator.
# ---------------------------------------------------------------------------
COUNT=0
if [[ -f "$COUNTER_FILE" ]]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
  [[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0
fi

if [[ "$COUNT" -ge 2 ]]; then
  echo "unkept-promise-hook: predicate fired ${COUNT}x consecutively; standing down (assume false positive)." >&2
  rm -f "$COUNTER_FILE" 2>/dev/null
  exit 0
fi

printf '%s' "$((COUNT + 1))" > "$COUNTER_FILE" 2>/dev/null

REASON="Your closing text names an action you have not taken -- ${FIRED} -- and the turn is ending.

Do the thing you just said, in THIS turn. Writing the next action down is not doing it.

If the stop is legitimate, say why in the message using one of:
  <promise>OPERATOR-GATE: what you are waiting on</promise>
  <promise>BLOCKED: what is blocking</promise>
  <promise>DONE</promise>

Stopping is allowed. Stopping silently is not -- an operator who cannot see the
pipeline has no way to tell a finished task from an abandoned one."

jq -n --arg r "$REASON" \
  '{"decision":"block","reason":$r,"systemMessage":"unkept-promise-hook: turn ended on an unexecuted commitment"}' 2>/dev/null \
  || exit 0

exit 0
