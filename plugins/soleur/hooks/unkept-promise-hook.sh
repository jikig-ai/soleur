#!/usr/bin/env bash

# Stop hook: refuse a turn that ENDS on a promise it did not keep.
#
# THE DEFECT
# ----------
# A turn ends with a sentence naming the next action -- "implementing now",
# "I'll run those next" -- and the action never runs. The operator has to ask
# "why did you stop". Measured 2026-09-07: five times in one session, three of
# them inside the turns building this hook.
#
# Prose already covers it and already failed: `review/SKILL.md` section 6 names
# the shape exactly, and was read and violated repeatedly in the session it
# governs. This repo's record is that every hook exists BECAUSE a rule failed.
#
# Why a Stop hook: every other enforcement here fires on a tool call. This
# failure is the ABSENCE of one, and nothing observed the moment a turn ends.
#
# It matters more for users than for the author. The operator caught it because
# they can read pipeline state; a non-technical user gets a confident summary,
# nothing red, and a half-finished task.
#
# LOOP SAFETY -- `stop_hook_active`, not a counter
# ------------------------------------------------
# The runtime sets `stop_hook_active: true` on a stop that a hook already
# blocked. Honouring it means this hook blocks at most ONCE per stop-chain, so
# it can never wedge a session and needs no persistence.
#
# An earlier revision kept a per-session counter on disk instead, and justified
# it with a comment claiming the runtime "force-stops after 3 successive Stop
# blocks". Corrected twice, so both errors are recorded: the number was wrong
# (the shipped runtime uses CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8), and the
# follow-up claim that the mechanism was UNSOURCED was also wrong -- it exists,
# and `stop-hook.sh`'s HARD_CAP=50 counts ralph-loop ITERATIONS, so it never
# contradicted it. The accurate statement: the runtime caps consecutive Stop
# blocks at 8, and `stop_hook_active` is the tighter per-chain bound, which is
# what makes a local counter redundant. The counter is still deleted, but on the
# real reason rather than an invented one -- it produced every defect this hook
# has had (correlated fixtures, cross-run state leakage, a symlink-followable
# state directory, and a hardlink-truncation primitive that survived its own
# ownership check).

# SCOPING -- the sentence, not a byte window
# ------------------------------------------
# The allow arms are tested against THE SAME SENTENCE as the promise. An earlier
# revision scanned a 700-byte tail for both, so a courtesy closer anywhere in
# the window vetoed a promise anywhere else in it: appending "Let me know if you
# want it different." to any of the three real instances made the hook ALLOW
# them. A guard that stops working when the turn is polite is inert in practice.
#
# VOCABULARY -- `<stop>`, and deliberately NOT the marker one-shot owns
# ---------------------------------------------------------------------
# ONE_SHOT_DONE_MARKER (lib/workflow-fidelity.ts) is bound to "PR merged,
# release green, postmerge verified", and stop-hook.sh treats a match as a
# ralph-loop completion and DELETES the loop state. An earlier revision offered
# that marker as this hook's escape hatch, which would have taught the model to
# forge the pipeline's completion token on a turn that had just been blocked,
# and could kill a live loop. This hook owns `<stop>` and nothing else.
#
# KNOWN RESIDUALS -- this guard is NARROWER than the property it names
# -------------------------------------------------------------------
# Stated here rather than implied away, because a guard that reads complete is
# more dangerous than one whose limits are written down. A structural
# enumeration (2026-09-07) established all of these:
#
#   1. VOCABULARY. The predicate is a regex over a closed set of phrasings.
#      "We'll ...", "Going to ...", "Next: ...", "The plan is to ...",
#      "On to the ...", and any gerund outside GERUND_RE evade it. Broadened
#      below to the highest-frequency forms; NOT complete, and cannot be.
#   2. EVENT COVERAGE. `Stop` does not fire on user interrupt or on an API
#      error (that is `StopFailure`, unregistered here), and subagent turns end
#      on `SubagentStop` (also unregistered). A promise made in a subagent's
#      final message is unobserved.
#   3. INSTALLATION. .claude/settings.json registers no Stop hook, so this
#      repo's own sessions are covered only via the plugin.
#   4. ONE BLOCK PER CHAIN. `stop_hook_active` means a determined turn can
#      restate the promise on the next stop and proceed. That is deliberate --
#      the alternative is a hook that can wedge a session.
#   5. TAG QUESTION. A message ending in '?' is treated as waiting on an
#      answer, so "Implementing now. Reasonable?" buys an exit. The inverse --
#      blocking a genuine question -- pushes the model past information it
#      needs, which is the worse failure.
#   6. SELF-DISARM. A turn quoting this hook's own `<stop>` syntax while
#      explaining it satisfies the escape hatch. Accepted: the alternative is a
#      sentinel nobody can document.
#
# What it DOES buy: the common case, which is a plain closing sentence naming
# the next action. Measured against the five real 2026-09-07 instances, it
# catches the three that were plain prose.

set -uo pipefail

# Fail OPEN on every infrastructure problem: this must never be the reason a
# session cannot end.
command -v jq >/dev/null 2>&1 || exit 0
HOOK_INPUT=$(cat 2>/dev/null) || exit 0
[[ -n "$HOOK_INPUT" ]] || exit 0

# Already blocked once in this stop-chain -- do not block again.
ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[[ "$ACTIVE" == "true" ]] && exit 0

LAST_MSG=$(printf '%s' "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null) || exit 0
[[ -n "$LAST_MSG" ]] || exit 0

# Split into sentences, newest last. Markdown bullets and headings end a line
# without punctuation, so line breaks are sentence boundaries too.
# Drop fenced blocks first: wg-end-of-work-emit-resume-prompt REQUIRES a fenced
# resume prompt as the final block of every /work and /one-shot turn -- the very
# class this defect lives in. Left in, it becomes the "closing sentences" and
# hides the promise above it. Also drop leading markdown bullet/emphasis markers
# so a "Next steps:" list is not invisible to the sentence-initial anchors.
# Bound the input before any pipeline touches it. Only the closing sentences are
# ever used, and an unbounded message costs real time on every turn end
# (measured on the prior revision: 20 MB -> 6.5 s, 186 MB RSS). It also removes
# the SIGPIPE hazard below at the source.
BOUNDED=$(printf '%s' "$LAST_MSG" | tail -c 8000)
PROSE=$(printf '%s' "$BOUNDED" | awk '/^[[:space:]]*```/{f=!f; next} !f')
# Newlines are folded to RS so a sentence-ending period followed by a line break
# still splits, then folded BACK with `tr` -- not `sed`. `tr` interprets \036 as
# an octal escape and `sed` does not, so `sed 's/\036/\n/g'` silently matched
# nothing: the separators survived, the whole message stayed ONE "sentence", and
# per-sentence scoping was inert for any newline-separated text. Every fixture
# used ". " separators, so the suite could not see it.
SENTENCES=$(printf '%s' "$PROSE" | tr '\n' '\036' \
            | sed 's/\([.!?]\)[[:space:]]/\1\n/g' \
            | tr '\036' '\n' \
            | sed 's/^[[:space:]]*//; s/^[-*+][[:space:]]*//; s/^\*\*//; s/[[:space:]]*$//' \
            | grep -v '^$' || true)
[[ -n "$SENTENCES" ]] || exit 0

# Only the closing few sentences are evidence about where the turn STOPPED.
CLOSING=$(printf '%s' "$SENTENCES" | tail -n 4)

# Escape hatch, scanned over the CLOSING sentences only -- deliberately the same
# scope as the predicate.
#
# An earlier revision scanned the whole message, which was wrong twice over.
# (a) ASYMMETRY: a turn that merely DISCUSSED the sentinel -- documenting it,
#     reviewing this hook, quoting a user's paste -- disarmed the guard while
#     still closing on a promise. That silently exempted exactly the sessions
#     that edit this file, including this PR's own turns.
# (b) SIGPIPE: `printf "$BIG" | grep -q` under `set -o pipefail` returns 141
#     when grep exits on first match, so the `if` read a MATCH as a NON-match.
#     Measured on the prior revision: a valid sentinel was ignored at >=64 KB,
#     non-deterministically at the pipe-buffer boundary -- i.e. the only way to
#     declare a legitimate stop failed precisely on long closing messages.
# Both are closed by scoping to CLOSING, which is a handful of short lines.
# Narrower still: the FINAL sentence. Declaring a stop is a closing act, so a
# sentinel merely mentioned earlier -- documenting it, reviewing this hook,
# quoting a paste -- no longer disarms the guard. CLOSING alone was not enough:
# in a two-sentence message both the mention and the promise sit inside it.
if printf '%s' "$CLOSING" | tail -n 1 | grep -qiE '<stop>[[:space:]]*(OPERATOR-GATE|BLOCKED)'; then
  exit 0
fi

# A turn ENDING in a question is waiting on an answer, whatever else it said.
# This one arm is message-level, not per-sentence: blocking it would push the
# model past a question it needs answered, and produce work built on a guess.
# The cost is a named residual -- a tag question ("Implementing now. Reasonable?")
# buys an exit. Accepted: forcing a real question through is the worse failure.
if printf '%s' "$PROSE" | sed 's/[[:space:]]*$//' | tail -c 2 | grep -q '?'; then
  exit 0
fi

PROMISE_RE="(i'll |i will |i am going to |i'm going to |im going to |we'll |we will |let me [a-z]+|going to [a-z]+|about to [a-z]+|next:|next step|the plan is to |on to the |time to [a-z]+)"
GERUND_RE='^(implementing|running|building|writing|committing|pushing|shipping|fixing|creating|adding|executing|starting|continuing|proceeding|applying|updating|wiring|merging|deploying|verifying|refactoring|drafting|opening|rebasing|patching|migrating|landing|testing|checking|investigating|finishing|queuing|spawning|handing)\b'

# Allow arms, evaluated PER SENTENCE against the sentence that carries the
# promise -- never against the window, which is what let a closer veto a promise
# it had nothing to do with.
#   conditional : the promise is contingent on the operator
#   pending     : the promise is contingent on work already in flight
# `let me know` is matched by PROMISE_RE, so CONDITIONAL must be tested first.
CONDITIONAL_RE='(say the word|if you|once you|when you|whenever you|let me know|tell me|your call|up to you|on your (go|signal|say))'
PENDING_RE='(report (what|back)|(when|once|as soon as|after) (it|they|those|the (run|tests|ci|build|merge))|(they|it|those) (find|finds|land|lands|complete|completes|merge|merges|return|returns)|still running|in flight|notification arrives)'

FIRED=""
while IFS= read -r s; do
  [[ -n "$s" ]] || continue
  printf '%s' "$s" | grep -qiE "$CONDITIONAL_RE" && continue
  printf '%s' "$s" | grep -qiE "$PENDING_RE" && continue
  if printf '%s' "$s" | grep -qiE "$PROMISE_RE"; then
    FIRED="a first-person commitment to act"; break
  fi
  if printf '%s' "$s" | grep -qiE "$GERUND_RE"; then
    FIRED="a bare gerund announcement"; break
  fi
done <<< "$CLOSING"

[[ -n "$FIRED" ]] || exit 0

REASON="Your closing text names an action you have not taken -- ${FIRED} -- and the turn is ending.

Do it now, in THIS turn. Writing the next action down is not doing it.

If the stop is legitimate, say why:
  <stop>OPERATOR-GATE: what you are waiting on</stop>
  <stop>BLOCKED: what is blocking</stop>

Stopping is allowed. Stopping silently is not -- an operator who cannot see the
pipeline has no way to tell a finished task from an abandoned one."

jq -n --arg r "$REASON" \
  '{"decision":"block","reason":$r,"systemMessage":"unkept-promise-hook: turn ended on an unexecuted commitment"}' 2>/dev/null \
  || exit 0
exit 0
