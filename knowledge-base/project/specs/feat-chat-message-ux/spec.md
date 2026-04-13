# Spec: Chat Message UX Refactor

**Issue:** #2114
**Branch:** feat-chat-message-ux
**Brainstorm:** [2026-04-13-chat-message-ux-brainstorm.md](../../brainstorms/2026-04-13-chat-message-ux-brainstorm.md)

## Problem Statement

The chat message display in the Soleur web app has three UX bugs:

1. Agent responses produce two separate message bubbles (one typing indicator, one text)
2. Content duplicates within bubbles due to appending cumulative snapshots as deltas
3. No visual indicator of when an agent is done processing vs still working

Root cause: protocol ambiguity between server (sends cumulative text) and client (treats all messages as deltas and appends).

## Goals

- G1: Single message bubble per agent turn with unified lifecycle
- G2: 4-state visual lifecycle per bubble (THINKING, TOOL_USE, STREAMING, DONE)
- G3: Clean WebSocket protocol contract for streaming (hybrid: cumulative partials, no final duplicate)
- G4: Stable multi-agent stream tracking via leaderId-to-messageId map
- G5: Tool-use status text showing what the agent is doing before text streams

## Non-Goals

- NG1: Multi-turn context persistence (tracked separately in #1044)
- NG2: Conversation history rendering changes (history loads from DB as complete text, already correct)
- NG3: Mobile-specific layout changes (but mobile must be tested in QA)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | When `stream_start` is received, create a single bubble in THINKING state (pulsing border + animated dots) |
| FR2 | When `tool_use` event is received, transition bubble to TOOL_USE state (pulsing + human-readable status text) |
| FR3 | When first `stream` (partial: true) is received, transition to STREAMING state (pulsing + text replacing previous content) |
| FR4 | When `stream_end` is received, transition to DONE state (no pulse + markdown rendering + subtle checkmark) |
| FR5 | Server stops sending `partial: false` duplicate of already-streamed content |
| FR6 | Server emits `tool_use` WebSocket events with human-readable labels for SDK tool invocations |
| FR7 | Multi-agent parallel streaming uses leaderId-to-messageId map instead of array indices |
| FR8 | Message IDs use `crypto.randomUUID()` instead of `Date.now()` |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | New WSMessage type `tool_use` added to `lib/types.ts` |
| TR2 | `agent-runner.ts` streaming loop emits `tool_use` events for SDK tool invocations |
| TR3 | `agent-runner.ts` stops emitting `partial: false` for content already sent as cumulative partials |
| TR4 | `ws-client.ts` replaces content on `partial: true` instead of appending |
| TR5 | `ws-client.ts` uses `useReducer` or dedicated state machine for per-message state |
| TR6 | MessageBubble component renders 4 visual states with appropriate indicators |
| TR7 | `ws-protocol.test.ts` covers the partial-to-stream_end transition and multi-agent interleaving |
| TR8 | Mobile QA with screenshots before shipping |

## Acceptance Criteria

- [ ] Single bubble per agent turn (no duplicate bubbles)
- [ ] No duplicated text content in any streaming scenario
- [ ] Pulsing indicator visible during THINKING, TOOL_USE, and STREAMING states
- [ ] Status text shows what agent is doing during TOOL_USE state
- [ ] Checkmark and markdown rendering appear when agent is DONE
- [ ] Multiple agents streaming in parallel do not cross-contaminate bubbles
- [ ] Existing `ws-protocol.test.ts` passes + new streaming state machine tests added
- [ ] Mobile QA with screenshots
