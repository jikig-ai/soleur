---
title: "Terminal-frame → terminal-UI-state mappings must validate the frame's reason-set; success affordances must wait for server confirmation"
date: 2026-06-14
category: best-practices
modules: [web-platform, chat, ws-client]
issue: 5282
pr: 5299
tags: [state-machine, websocket, reconnect, honesty-surface, plan-deviation, optimistic-render]
---

# Terminal-frame → terminal-UI-state: validate the reason-set, and confirm before showing success

## Problem

#5282 added a client-side reconnect state machine to the chat surface, with a sticky
`unrecoverable` connection phase (State 3, "your session was reset") and a transient
"workspace restored" notice (State 4). Two design traps surfaced — one caught at `/work`
(by tracing producers), one caught at multi-agent review.

### Trap 1 — a "terminal" wire frame is not a terminal *error* signal until you read its reason-set

The plan (AC3/FR4) prescribed: map the `session_ended` WS frame → `connection_change(unrecoverable)`.
That reads plausible ("the session ended → show the session-ended state"). But `session_ended`
is the NORMAL turn-completion frame: its `reason` is a free-form string whose live values are
`turn_complete` (fires on EVERY successful turn), `user_aborted`, `closed`, terminal-workflow
statuses (recoverable via a new turn), and `session_revoked` (which has its own dedicated 4012
close-code terminal screen). Mapping it unconditionally to State 3 would flash "your session was
reset and can't continue" after every normal answer.

The genuinely-unrecoverable case (in-flight session reclaimed after the disconnect grace window)
happens **server-side while the client is disconnected** (`ws-handler.ts` grace-expiry →
`abortSession` + `streamReplayBuffer.clear`). The client never receives a frame at that moment;
it learns of the loss on the *next* reconnect via `stream_replay{incomplete}`. So the correct
unrecoverable signals are `stream_replay{incomplete}` + a non-transient socket close without a
redirect target — NOT `session_ended`.

### Trap 2 — an optimistic success affordance shown before server confirmation is the inverse of the invariant you're protecting

The first implementation set State 4's `resumedAt` optimistically inside the `auth_ok` reconnect
handler — before the server confirmed the resume actually succeeded. On a failed resume the
sequence was: `auth_ok` → green "workspace restored" (State 4) → ~1 RTT later
`stream_replay{incomplete}` → red "session was reset" (State 3). The feature exists to stop the
UI lying about whether the session survived; the sticky guard blocked the 3→4 direction, but the
optimistic render created the same trust-destroying lie in the 4→3 direction.

## Solution

- **Trap 1:** Do NOT map `session_ended` to a terminal UI state. Wire the honest signal
  (`stream_replay{incomplete}` + non-transient close w/o redirect). Lock the deliberate
  non-mapping with an inline comment at the handler AND reconcile the plan text, so a future
  maintainer doesn't "fix" it back to the broken plan.
- **Trap 2:** Defer the success affordance until confirmed. `auth_ok` arms a
  `reattachPendingRef` and dispatches `live` *without* `resumedAt`; the first genuinely-rendered
  post-reattach frame (a real replayed/live frame, past the seq-dedup gate) confirms the resume
  and sets `resumedAt`. Cleared on `stream_replay{incomplete}` (failed resume) and on
  session_started/resumed boundaries so it can't leak across turns.

## Key Insight

When mapping a wire frame to a terminal/error UI state, **enumerate the frame's full reason/status
set first** — a frame that fires on the success path cannot be a terminal-error signal. And a
"success" affordance (resumed/restored/saved) must be gated on positive server confirmation, never
shown optimistically on the action that merely *requests* the success — otherwise you reproduce
the exact false-state the honesty feature was built to prevent, just in the opposite direction.

## Session Errors

1. **Plan AC3/FR4 prescribed `session_ended → unrecoverable`.** Recovery: traced every server
   `session_ended` emit site, found all live reasons recoverable; wired `stream_replay{incomplete}`
   + non-transient-close instead. Prevention: when a plan maps a wire frame to a terminal UI state,
   `/work` and `/plan` must grep the frame's producer reason-set before accepting the mapping.
2. **State-4 `resumedAt` set optimistically on `auth_ok`.** Recovery: review (user-impact-reviewer)
   flagged the 4→3 flicker; reworked to confirm-then-show via `reattachPendingRef`. Prevention:
   review's user-impact lens already catches "false success before confirmation" on single-user-
   incident surfaces — keep that agent in the review set for honesty-surface PRs.
3. Plan over-estimated the fixture sweep (~18 vs 4 actual). One-off; the plan already says to trust
   `tsc --noEmit` TS2741 as the canonical enumerator.
4. Plan-file Edit hit "modified since read" once; re-read + retried. One-off.
5. one-shot collision-gate fired on the closed contextual ref `#5273`; handled via the documented
   freeform-prose carve-out (the work target `#5282` was OPEN). One-off, already-documented.
