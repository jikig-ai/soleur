---
title: "A liveness watchdog's INPUT set must be as broad as the CLAIM it makes"
date: 2026-06-15
category: bug-fixes
tags: [state-machine, chat, watchdog, liveness, false-positive, concurrency]
issue: 5240
pr: 5306
module: apps/web-platform/lib/chat-state-machine.ts
---

# A liveness watchdog's INPUT set must be as broad as the CLAIM it makes

## Problem

The Concierge chat showed a red **"Agent stopped responding after: <label>"** error on an
in-flight message bubble while the agent was demonstrably still working — the connection badge
read "Connected", the Debug stream was still emitting tool events, and (in a second screenshot)
a *sibling* leader was still streaming new tool chips below the errored bubble. Two operator
screenshots, ~6 min apart, each independently proved the false positive.

The just-merged reconnect-hardening work (#5290 stream-replay, #5299 connection-vs-activity
precedence) did NOT cover this: #5299 gave **connection** state precedence over the activity
watchdog (`reconnecting` → "Connection lost…" wins), but when the socket is `live` the
per-message stuck-watchdog (`applyTimeout`) still ran and escalated to `error`.

## Root Cause

The watchdog's claim ("the agent stopped responding") was broader than its input set ("same-bubble
main-stream `tool_use` for THIS leaderId"). Two structural gaps made the false positive inevitable:

1. **The Debug stream reset nothing.** `debug_event` carries no `leaderId` and deliberately emitted
   no `timerAction`, so live debug-stream activity — visible proof the agent is alive — never reset
   the watchdog.
2. **Per-message keying.** Each bubble's watchdog escalated independently; a *different* leader
   streaming new activity below an errored bubble did not clear it.

## Solution

Widen the **liveness input set** to any evidence the *leader* is alive, WITHOUT widening what the
error ultimately means (a genuinely silent turn must still surface):

- **Single-leader debug heartbeat:** when `activeStreams.size === 1`, a `debug_event{kind:"tool_use"}`
  emits a new `reset_all` timerAction (re-arms the one armed timer) and clears the stale "No response
  yet" chip. Gated to `size === 1` because an unattributed debug event is ambiguous across ≥2 leaders.
- **Bounded cross-leader gate:** `applyTimeout`'s Stage-2 escalation is suppressed while ANOTHER
  leader is active — but only `MAX_LIVENESS_REARMS = 3` times, then it escalates regardless. A busy
  sibling is a *bounded grace*, not proof THIS leader is alive (A and its workspace can hang
  independently of B).

## Key Insight

When a signal's *name* asserts a global property ("the agent stopped responding") but its
*implementation* only observes a narrow slice (one stream, one leader), the gap ships as a
false positive the moment a second valid liveness source exists. The fix is to enumerate every
liveness source the claim implicitly covers — **and** to keep the original exit by making any
relaxation BOUNDED (name the ceiling; never remove the genuine-failure exit). See
[[2026-05-05-defense-relaxation-must-name-new-ceiling]].

Corollary for the opposite-direction regression: widening liveness inputs risks masking a real
hang forever. The named ceiling (`MAX_LIVENESS_REARMS`) is what makes "another leader is active"
a safe grace rather than a blank check — and the cross-feature invariant that makes the debug
heartbeat sound (debug events are never replay-buffered) must be *enforced* (here: a compiler-checked
`BUFFERED_FRAME_TYPE_MAP` excludes `debug_event`), not merely asserted in a comment.

## Session Errors

1. **Subagent secret-token false-trip (one-off).** The plan+deepen subagent hit a PreToolUse
   secret-write gate on a benign `secrets set` substring inside a negative-scan grep + plan prose.
   Recovery: rephrased to avoid the literal token. Prevention: none warranted — the gate is working
   as designed; subagent prose that quotes a guarded command shape will occasionally trip it.
2. **ugrep parses leading-dash regex as options (recurring, minor).** `grep -nE '- \[ \] ...'`
   failed (`invalid option`) because the host `grep` is ugrep. Recovery: `grep -nE -- '<pattern>'`.
   Prevention: when grepping a pattern that begins with `-` on this host, always pass `--` before the
   pattern. Not worth a hook — `--` is the one-token fix and the failure is loud + immediate.
