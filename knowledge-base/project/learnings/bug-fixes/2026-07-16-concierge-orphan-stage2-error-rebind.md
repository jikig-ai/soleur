---
title: "Concierge orphan Stage-2 error rebind while tools still live"
date: 2026-07-16
category: bug-fixes
module: web-platform/chat-state-machine
tags:
  - concierge
  - stuck-watchdog
  - tool_progress
  - hard-cap
  - harness-reliability
related:
  - knowledge-base/project/plans/2026-07-16-fix-concierge-agent-stop-mid-run-plan.md
  - knowledge-base/project/learnings/best-practices/2026-06-12-idle-watchdog-reset-on-sdk-heartbeat-and-upstream-fix-exposes-downstream-timeout.md
  - knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md
---

# Learning: Concierge orphan Stage-2 error rebind while tools still live

## Problem

Operator saw Concierge paint a terminal red banner —

> Agent stopped responding after: Working…

— while Debug stream / tools (grep, find, ls, mkdir) continued. Looks like the product gave up mid-one-shot. Banner copy comes from client `messageState === "error"` (`message-bubble.tsx`), not server `runner_runaway` ("The agent went idle without finishing…").

Prior heartbeats were already shipped and live on prod:

- Server: `tool_progress` → `armRunaway` (idle 90s)
- Client feed: cc `onToolProgress`
- Client: debug_event single-leader liveness + `MAX_LIVENESS_REARMS`

Re-shipping those does not fix the residual.

## Root cause

1. `applyTimeout` Stage-2 sets `state: "error"`, **deletes** the leader from `activeStreams`, clears the timer.
2. For leader `cc_router`, later `tool_use` when `!activeStreams.has("cc_router")` takes the **chip-only** branch (Stage 4) — appends `tool_use_chip`, never heals the error bubble, no `timerAction`.
3. `tool_progress` with unknown leader was an **inert no-op**.
4. Secondary: `DEFAULT_MAX_TURN_DURATION_MS` was 10 min absolute (not re-armed on activity) — long multi-step Concierge turns hit `max_turn_duration` with different copy.

## Solution

### Path A — rebind recoverable error tip

`findRecoverableErrorBubble(messages, leaderId)`: reverse walk; recover only when the **latest text bubble** for that leader is still `error`. Newer non-error tip → no rebind.

On liveness (`tool_use`, `tool_progress`, `stream`, `stream_start`, `command_stream`, single-orphan `debug_event`):

- Re-insert leader into `activeStreams` at that index
- Set transitional state (`tool_use` / `streaming` / `thinking`)
- Clear `retrying` + reset `livenessRearms`
- `timerAction: reset`

Cold `cc_router` tool_use without an error tip still spawns chips (Stage 4 preserved).

Fail-closed: silence after Stage-2 stays error; after rebind, two more `applyTimeout`s escalate again (no permanent amnesty).

### Path C — hard-cap product budget

Raise `DEFAULT_MAX_TURN_DURATION_MS` to **45 minutes**. Idle 90s unchanged. **`tool_progress` still never re-arms `turnHardCap`** (chatty-stall defense; ADR-022 amendment 2026-07-16).

## Key Insight

**A terminal UI state that races a still-live backend needs recovery, not only better heartbeats.** Heartbeats that only re-arm timers while the leader is *already in* `activeStreams` cannot clear a banner after Stage-2 eviction. The cc_router chip path is the load-bearing trap: "not in activeStreams" was overloaded to mean both "pre-stream cold start" and "post-error orphan."

## Session Errors

1. **Sentry issue API path returned project-not-found during plan observability self-pull.** Recovery: fall back to structured logs + `GET /health` + unit classification. **Prevention:** Prefer health + existing `reportSilentFallback` ops over guessing Sentry project paths; keep `hr-no-dashboard-eyeball`.

2. **Prior session misrouted the same symptom to nav-rail product work.** Recovery: operator re-stated harness reliability intent. **Prevention:** Grep banner copy / `applyTimeout` before routing product UI issues; treat conversation titles as workspace names, not work targets.

## Tags

category: bug-fixes  
module: web-platform/chat-state-machine, soleur-go-runner
