# Chat Message UX Brainstorm

**Date:** 2026-04-13
**Status:** Complete
**Branch:** feat-chat-message-ux

## What We're Building

A full refactor of the chat message display in the Soleur web app to fix duplicate message bubbles, add clear processing state indicators, and implement a 4-state message lifecycle per agent bubble.

### Problem

When an agent (e.g., "Oleg (CTO)") responds in the chat UI:

1. **Two separate message bubbles appear** -- one with "..." typing indicator, one with the actual text
2. **Content duplicates** within bubbles because the client appends cumulative text instead of replacing
3. **No clear "done" signal** -- users cannot tell if an agent is still processing or has finished

### Root Cause

- **Server** (`agent-runner.ts`) sends both `partial: true` messages (cumulative text snapshots) AND `partial: false` messages (complete text blocks) during the same turn
- **Client** (`ws-client.ts`) blindly appends content from ALL `stream` events, causing cumulative text to be appended as if it were deltas
- The `partial` boolean in the WebSocket protocol is never checked by the client -- both partial and final messages follow the same append path
- `stream_end` removes the leader from `activeLeaderIds` but has no visual "done" indicator
- `session_ended` with `reason: "turn_complete"` is silently swallowed

### Affected Files

| File | Role |
|------|------|
| `apps/web-platform/server/agent-runner.ts` | Streaming loop (lines 350-398) |
| `apps/web-platform/lib/ws-client.ts` | Client stream handler (lines 103-157) |
| `apps/web-platform/lib/types.ts` | WSMessage stream type |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | MessageBubble component |
| `apps/web-platform/test/ws-protocol.test.ts` | Protocol tests (needs streaming state machine tests) |

## Why This Approach

### Hybrid Protocol (Approach C)

We chose the hybrid approach over pure cumulative-replace or pure delta:

- **Server sends cumulative text** for `partial: true` messages (self-healing: if a partial is dropped, the next one has the full text)
- **Server STOPS sending the final `partial: false` duplicate** -- the biggest source of duplication. Instead, `stream_end` signals completion with no content
- **Client replaces** content on `partial: true` instead of appending
- **New `tool_use` event type** for agent status updates (what the agent is doing before text streams)

This gives us reliability (cumulative = self-healing) while eliminating the worst duplication (no final re-send) and having a clean protocol contract.

### 4-State Message Lifecycle

Each message bubble progresses through:

| State | Visual | Trigger |
|-------|--------|---------|
| THINKING | Pulsing bubble border + animated dots | `stream_start` received |
| TOOL_USE | Pulsing bubble + status text (e.g., "Reading pitch document...") | `tool_use` event received |
| STREAMING | Pulsing bubble + text flowing in (raw text) | First `stream` with `partial: true` |
| DONE | No pulse + rendered markdown + subtle checkmark | `stream_end` received |

### Multi-Agent Stream Tracking

Replace the fragile `streamIndexRef` (array index-based) with a stable `leaderId`-to-`messageId` map. This prevents cross-contamination when multiple agents stream in parallel.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Protocol approach | Hybrid (cumulative partials, no final duplicate) | Self-healing + clean contract + eliminates biggest duplication source |
| Client handling of partials | Replace content (not append) | Partials are cumulative snapshots, not deltas |
| Thinking indicator | Status text + pulsing border | Informative (shows what agent is doing) + visually clear (pulsing) |
| Done signal | Pulsing stops + markdown renders + checkmark | Maximum clarity: three signals reinforce each other |
| Stream tracking | leaderId-to-messageId map | Fixes fragile index-based approach for multi-agent parallelism |
| Message IDs | `crypto.randomUUID()` | Replace `Date.now()` to prevent millisecond collision |
| Tool-use status | New WS event type `tool_use` | Backend emits SDK tool events as human-readable status labels |
| Scope | Full UX overhaul (4 states) | User confirmed full scope including tool-use status text |

## Open Questions

- **SDK `includePartialMessages` semantics**: Confirm whether `lastBlock.text` is truly cumulative (expected) or delta. Read SDK source to verify.
- **Tool-use label mapping**: How to map raw SDK tool names (e.g., `Read`, `Bash`) to user-friendly labels (e.g., "Reading document...", "Running command..."). Decide during implementation.
- **Auto-scroll behavior**: When user scrolls up during streaming, should auto-scroll be suppressed? Currently always scrolls to bottom on every update.
- **Timeout per bubble**: If `stream_start` arrives but no `stream` events follow (agent fails silently), should there be a timeout that transitions to an error state?
- **`session_ended` rendering**: Currently renders as a chat bubble. Should it be a status indicator/divider instead of a message?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Confirmed root cause is cumulative-vs-delta ambiguity in the WebSocket protocol. The `partial` boolean exists but the client never checks it. Recommended fixing both server and client with explicit contract (Option C). Flagged `Date.now()` message ID collisions, fragile `streamIndexRef` mutations inside React state updaters, and missing streaming state machine tests in `ws-protocol.test.ts`. Rated the fix as medium complexity (1-2 days).

### Product (CPO)

**Summary:** Rated severity as HIGH -- every conversation exhibits the bug, and this is the primary interaction surface. This fix is prerequisite for Phase 4 founder recruitment (10 founders doing 2-week unassisted usage will not survive garbled text). Recommended immediate protocol fix followed by full lifecycle UX. No additional business validation needed -- this is a correctness fix on an already-validated product surface. Flagged mobile testing as critical for QA gate.
