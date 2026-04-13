---
title: "feat: Chat message 4-state lifecycle with streaming protocol fix"
type: feat
date: 2026-04-13
---

# feat: Chat message 4-state lifecycle with streaming protocol fix

## Overview

Refactor the chat message display to fix duplicate bubbles, eliminate content
duplication, and add a 4-state visual lifecycle (THINKING, TOOL\_USE, STREAMING,
DONE) per agent message bubble. Fixes the protocol ambiguity where the server
sends cumulative text but the client appends it as deltas.

**Issue:** [#2114](https://github.com/jikig-ai/soleur/issues/2114)
**Branch:** feat-chat-message-ux
**Spec:** `knowledge-base/project/specs/feat-chat-message-ux/spec.md`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-13-chat-message-ux-brainstorm.md`
**Wireframes:** `knowledge-base/product/design/chat/chat-message-bubble-lifecycle.pen`

## Problem Statement

Every agent response in the chat UI produces broken output:

1. **Two bubbles per turn** — one with "..." typing dots, one with the actual
   text — because `stream_start` creates a bubble and the first `stream` event
   creates another instead of populating the existing one
2. **Duplicated text** — the client appends `msg.content` on every `stream`
   event, but the server sends cumulative snapshots (full text so far), not
   deltas. Result: text doubles, triples, etc.
3. **No "done" signal** — users cannot tell if an agent is still working or has
   finished. The `stream_end` event only removes the leader from
   `activeLeaderIds` with no visual change

Root cause: the `partial` boolean on `stream` messages
(`apps/web-platform/lib/types.ts:52-67`) is never checked by the client
(`apps/web-platform/lib/ws-client.ts:195-224`). Both `partial: true`
(cumulative snapshot) and `partial: false` (final text block) follow the same
append path.

## Proposed Solution

**Hybrid protocol** (from brainstorm Approach C):

- Server continues sending cumulative text for `partial: true` (self-healing if
  a partial is dropped)
- Server **stops** sending the final `partial: false` duplicate — `stream_end`
  signals completion with no content
- Client **replaces** content on `partial: true` instead of appending
- New `tool_use` WS event type for agent status updates before text streams

**4-state message lifecycle** per bubble:

| State | Visual | Trigger | Exit |
|-------|--------|---------|------|
| THINKING | Pulsing 2px gold border + animated dots | `stream_start` | `tool_use`, first `stream`, or timeout |
| TOOL\_USE | Pulsing border + status chip (e.g., "Reading file...") | `tool_use` event | First `stream`, `stream_end`, or timeout |
| STREAMING | Pulsing border + raw text replacing previous + cursor `▌` | First `stream` with `partial: true` | `stream_end` or timeout |
| DONE | 1px dim border + rendered markdown + gold checkmark | `stream_end` | Terminal |
| ERROR | 1px red border + error banner + retry button | 30s timeout with no events | Retry → THINKING |

## Technical Approach

### Files to Modify

| File | Changes |
|------|---------|
| `apps/web-platform/lib/types.ts:52-67` | Add `tool_use` WSMessage type, `MessageState` union type, extend `ChatMessage` with `state` field |
| `apps/web-platform/server/agent-runner.ts:1082-1087` | Remove `partial: false` emission for content already sent as partials |
| `apps/web-platform/server/agent-runner.ts:1150-1155` | Keep `partial: true` cumulative emission unchanged |
| `apps/web-platform/server/agent-runner.ts` (new section) | Emit `tool_use` events when SDK invokes tools (Read, Bash, Edit, etc.) |
| `apps/web-platform/lib/ws-client.ts:174-192` | Replace `Date.now()` with `crypto.randomUUID()` for message IDs |
| `apps/web-platform/lib/ws-client.ts:195-224` | Replace append with replace on `partial: true`; add state transitions |
| `apps/web-platform/lib/ws-client.ts` (new) | Add 30s timeout per bubble for stuck THINKING/TOOL\_USE states |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:410-483` | 4-state MessageBubble rendering with state badge, pulsing border, checkmark |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:298` | Replace `isStreaming` boolean with per-message `state` field |
| `apps/web-platform/test/ws-protocol.test.ts` | Add streaming state machine tests, multi-agent interleaving tests |

### Implementation Phases

#### Phase 1: Protocol Contract (Server + Types)

**Goal:** Clean up the WebSocket protocol so the server emits a correct,
non-duplicating event stream.

**TDD: Write failing tests first (steps 1-2), then implement (steps 3-5).**

1. **Write protocol tests RED** (`ws-protocol.test.ts`):
   - Add `stream_start` and `stream_end` to `isServerMessage` helper
   - `stream_start` → `tool_use` → `stream` (partial: true) → `stream_end`
     sequence validation
   - Verify no `partial: false` emission after partials were sent
   - These tests should fail until the server changes in steps 3-5 are made

2. **Add types** (`types.ts`):
   - `tool_use` WSMessage: `{ type: "tool_use"; leaderId: DomainLeaderId; tool: string; label: string }`
   - `MessageState`: `"thinking" | "tool_use" | "streaming" | "done" | "error"`
   - Extend `ChatMessage` interface with `state: MessageState`

3. **Verification step:** Before implementing server changes, run
   `console.log(lastBlock.text)` at `agent-runner.ts:1150` to confirm
   `lastBlock.text` is cumulative (expected) not delta. If delta, the replace
   strategy needs adjustment.

4. **Stop final duplicate** (`agent-runner.ts:1082-1087`):
   - In the `for await` loop, when `msg.type === "assistant"` and content has
     already been streamed via `partial: true`, skip the `partial: false`
     emission. Track whether any partials were sent for this turn with a boolean
     flag.

5. **Emit `tool_use` events** (`agent-runner.ts`):
   - When the SDK invokes a tool (message type contains tool\_use blocks),
     emit a `tool_use` WS event with a human-readable label. Mapping:

     | SDK Tool | Label |
     |----------|-------|
     | `Read` | "Reading file..." |
     | `Bash` | "Running command..." |
     | `Edit` | "Editing file..." |
     | `Write` | "Writing file..." |
     | `WebSearch` | "Searching web..." |
     | `Grep` | "Searching code..." |
     | `Glob` | "Finding files..." |
     | Other | "Working..." |

6. **Run tests GREEN:** All protocol tests from step 1 should now pass.

#### Phase 2: Client State Machine

**Goal:** The client correctly handles the protocol and tracks per-message
state.

**State management:** All state transitions happen via imperative mutations
on the `messages` array inside `ws-client.ts` (co-located with the socket
handler). No `useReducer` — this codebase has no precedent for it and plain
`setMessages` with immutable updates is sufficient. The `msg.state` field is
set in `ws-client.ts` and consumed read-only by `page.tsx` for rendering.

**TDD: Write failing tests first (step 1), then implement (steps 2-6).**

1. **Write client state machine tests RED** (`ws-protocol.test.ts`):
   - State transitions: `stream_start` → thinking, `tool_use` → tool\_use,
     first `stream` → streaming, `stream_end` → done
   - Replace semantics: 3 cumulative partials ("A", "AB", "ABC") = "ABC"
   - Timeout: 30s with no events → error
   - Multi-agent: 2 leaderIds with independent state machines
   - These tests should fail until the handler changes in steps 2-6 are made

2. **Replace append with replace** (`ws-client.ts:195-224`):
   - In the `stream` handler, when `msg.partial === true`, replace
     `messages[idx].content` with `msg.content` instead of appending
   - When `msg.partial === false` (should not happen after Phase 1, but
     defensive), also replace (not append)

3. **Add per-message state tracking** (`ws-client.ts`):
   - On `stream_start`: create bubble with `state: "thinking"`
   - On `tool_use`: set `state: "tool_use"`, store `label` on the message
   - On first `stream`: set `state: "streaming"`
   - On `stream_end`: set `state: "done"`
   - State transitions are one-directional: thinking → tool\_use → streaming →
     done (tool\_use is optional, may repeat for sequential tools — each
     replaces the previous label)

4. **Replace `Date.now()` with `crypto.randomUUID()`** (`ws-client.ts:182,214`):
   - Change message ID generation from `` `stream-${msg.leaderId}-${Date.now()}` ``
     to `` `stream-${msg.leaderId}-${crypto.randomUUID()}` ``
   - Prevents millisecond collision when multiple agents start simultaneously

5. **Add 30s timeout** (`ws-client.ts`):
   - When a bubble enters THINKING or TOOL\_USE, start a 30s timer
     (via `setTimeout`, stored in a `Map<string, NodeJS.Timeout>` keyed by
     leaderId alongside `activeStreamsRef`)
   - Each incoming event for that leaderId resets the timer
   - If timer fires: set `state: "error"`, display error banner
   - On retry: reset to `state: "thinking"`, clear content, restart timer
   - Clear timer on `stream_end`
   - Clear all timers in the `useEffect` cleanup (covers component unmount
     and React strict mode double-mount)

6. **Multiple sequential `tool_use` events**:
   - Each new `tool_use` event replaces the previous label (no accumulation)
   - Status text shows only the most recent tool being used

7. **Run tests GREEN:** All client state machine tests from step 1 should
   now pass.

#### Phase 3: Visual Lifecycle (Component + CSS)

**Goal:** MessageBubble renders 4+1 visual states per the wireframes.

Reference wireframes:
`knowledge-base/product/design/chat/chat-message-bubble-lifecycle.pen`

1. **State-driven rendering** (`page.tsx:410-483`):
   - Replace the `isStreaming` boolean check at line 298 with `msg.state`
   - Render based on `msg.state`:
     - `thinking`: `<ThinkingDots />` (existing component) + pulsing border
     - `tool_use`: Tool status chip + pulsing border
     - `streaming`: Raw text + pulsing border + cursor character `▌`
     - `done`: `<MarkdownRenderer>` + checkmark icon + dim border
     - `error`: Error banner + retry button + red border

2. **Pulsing border animation** (CSS):
   - Add `@keyframes pulse-border` animation in the components layer
   - Active states (thinking, tool\_use, streaming): `2px solid` gold with
     pulse animation
   - Done: `1px solid` dim (`#2A2A2A`) with no animation
   - Error: `1px solid` red (`#5C2020`)

3. **State badge chip** (top-right corner of bubble):
   - Small chip showing current state label for parallel agent contexts
   - Warm dark background (`#1E1A12`) with 1px gold stroke
   - Visible in TOOL\_USE and STREAMING states, hidden in THINKING and DONE

4. **Checkmark on DONE**:
   - Subtle gold checkmark icon (`✓`) in top-right of bubble
   - `aria-label="Response complete"` for accessibility
   - Positioned where the state badge was during active states

5. **Empty DONE state**:
   - When content is empty but state is `done`, show a tool-log chip listing
     tools used during the turn (e.g., "Used: read\_file, search\_web")
   - Prevents a blank bubble with only a checkmark

6. **Tool status chip** (TOOL\_USE state):
   - Icon (file, terminal, search, etc.) + label text
   - Replaces `<ThinkingDots />` content area
   - Animated dots after the label text ("Reading file...")

#### Phase 4: Tests & QA

1. **Streaming state machine tests** (`ws-protocol.test.ts`):
   - Full lifecycle: `stream_start` → `tool_use` → `stream` → `stream_end`
   - State transitions: verify each event sets the correct `MessageState`
   - Replace semantics: verify `partial: true` replaces (not appends) content
   - Timeout: verify 30s with no events transitions to `error`
   - UUID: verify message IDs use UUID format, no collisions

2. **Multi-agent interleaving tests**:
   - Two agents streaming simultaneously via different leaderIds
   - Verify no cross-contamination of content between agents
   - Verify independent state machines per leaderId
   - Verify `activeStreamsRef` map correctly tracks both agents

3. **Regression tests**:
   - No duplicate bubbles: `stream_start` + `stream` = 1 bubble (not 2)
   - No duplicate content: 3 cumulative partials = final text (not 3x)
   - `stream_end` transitions to `done` (not stuck in streaming)

4. **Mobile QA** (Playwright):
   - Single agent response on mobile viewport
   - Verify pulsing animation renders correctly
   - Verify checkmark and state badge are visible
   - Screenshot each state for PR evidence

## Acceptance Criteria

- [ ] Single bubble per agent turn (no duplicate bubbles)
- [ ] No duplicated text content in any streaming scenario
- [ ] Pulsing indicator visible during THINKING, TOOL\_USE, and STREAMING states
- [ ] Status text shows what agent is doing during TOOL\_USE state (human-readable labels)
- [ ] Checkmark and markdown rendering appear when agent is DONE
- [ ] Multiple agents streaming in parallel do not cross-contaminate bubbles
- [ ] 30s timeout transitions stuck bubble to ERROR state with retry button
- [ ] Existing `ws-protocol.test.ts` passes + new streaming state machine tests added
- [ ] Mobile QA with screenshots
- [ ] Checkmark has `aria-label="Response complete"`
- [ ] Empty DONE state shows tool-log chip instead of blank bubble

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a user sends a message, when one agent responds, then exactly one
  bubble appears and progresses through THINKING → STREAMING → DONE
- Given an agent uses Read then Bash then responds, when events arrive, then
  the bubble shows "Reading file..." then "Running command..." then streams text
- Given two agents respond simultaneously, when both stream in parallel, then
  each bubble has independent state and content (no cross-contamination)
- Given an agent starts (stream\_start) but sends no events for 30s, when the
  timeout fires, then the bubble transitions to ERROR with a retry button
- Given three cumulative partials ("A", "AB", "ABC"), when the client renders,
  then the bubble shows "ABC" (not "AABABC")
- Given an agent uses tools but produces no text, when stream\_end arrives, then
  the bubble shows a tool-log chip with checkmark (not a blank bubble)

### Integration Verification

- **Browser:** Navigate to chat, send a message, verify single bubble appears
  with pulsing border, verify text streams without duplication, verify checkmark
  appears on completion
- **Mobile:** Resize viewport to 375px width, repeat above, screenshot each
  state

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Confirmed root cause is cumulative-vs-delta ambiguity in the
WebSocket protocol. The `partial` boolean exists but client never checks it.
Recommended fixing both server and client with explicit contract (Option C).
Flagged `Date.now()` message ID collisions, fragile `streamIndexRef` mutations,
and missing streaming state machine tests. Rated medium complexity (1-2 days).

### Product/UX Gate

**Tier:** advisory (user chose full review)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### SpecFlow Findings

| Gap | Severity | Resolution |
|-----|----------|------------|
| Timeout/error state for stuck THINKING bubble | Critical | Added ERROR state with 30s timeout + retry (Phase 2, step 4) |
| Network disconnect + reconnect behavior | Critical | Deferred — existing reconnect in ws-client.ts handles connection; stale bubbles timeout to ERROR via the 30s timer |
| Multiple sequential `tool_use` events | Important | Each new `tool_use` replaces previous label (Phase 2, step 6) |
| Empty DONE state (no text content) | Important | Tool-log chip shows tools used (Phase 3, step 5) |
| Parallel stream ordering on completion | Important | Bubbles maintain insertion (DOM) order, no reorder (existing behavior preserved) |
| Scroll anchoring during STREAMING | Important | Deferred — file as separate issue |
| Interrupted session history state | Important | Out of scope per NG2 — history loads as complete text from DB |
| Checkmark accessibility | Nice to have | Added `aria-label="Response complete"` (Phase 3, step 4) |

#### CPO Assessment

Severity HIGH — every conversation exhibits the bug. This fix is prerequisite
for Phase 3 closure (due 2026-04-17) and Phase 4 founder recruitment. The
4-state lifecycle reinforces the brand's "full AI organization at work"
positioning by making agent activity legible. No product concerns with scope or
direction.

#### UX Wireframes

Three frames produced in Pencil:

1. **Single agent 4-state lifecycle** — THINKING (gold pulse + dots) →
   TOOL\_USE (pulse + status chip) → STREAMING (pulse + text + cursor) →
   DONE (dim border + markdown + checkmark)
2. **Parallel agents** — 3 bubbles in different states, DOM order preserved
3. **Edge cases** — empty DONE (tool-log chip), ERROR (red border + retry)

Design decisions: border color is primary state signal (gold active, dim done,
red error). State badge chip in top-right for parallel contexts. Tool status
chip uses warm dark background with gold stroke.

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| `lastBlock.text` might be delta not cumulative | Phase 1 step 5: verify with console.log before implementing replace strategy |
| State management complexity | No `useReducer` — plain `setMessages` with immutable updates in ws-client.ts; state consumed read-only by page.tsx |
| Pulsing animation performance on mobile | Use CSS-only animation (no JS requestAnimationFrame); test on throttled mobile viewport |
| 30s timeout too aggressive for slow agents | Make timeout configurable via constant; start with 30s, adjust based on QA |
| Parallel agents with many simultaneous bubbles | Cap at 5 visible active bubbles; older ones scroll off naturally |

## Learnings Applied

- Guard every `await` in ws-client.ts with `readyState` check before modifying
  shared state (TOCTOU learning: `2026-03-20-websocket-first-message-auth-toctou-race.md`)
- Use sentinel value for thinking→streaming transition
  (`2026-03-02-telegram-streaming-repurpose-status-message.md`)
- New message types should follow typed error codes pattern — types in
  `types.ts`, not `agent-runner.ts`
  (`2026-03-18-typed-error-codes-websocket-key-invalidation.md`)
- Keepalive ping and auth patterns in ws-client.ts are load-bearing — do not
  break them (`2026-03-17-websocket-cloudflare-auth-debugging.md`)

## References

- Spec: `knowledge-base/project/specs/feat-chat-message-ux/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-13-chat-message-ux-brainstorm.md`
- Wireframes: `knowledge-base/product/design/chat/chat-message-bubble-lifecycle.pen`
- Server streaming: `apps/web-platform/server/agent-runner.ts:1058-1186`
- Client handler: `apps/web-platform/lib/ws-client.ts:96-232`
- Types: `apps/web-platform/lib/types.ts:52-67`
- Component: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:410-483`
- Tests: `apps/web-platform/test/ws-protocol.test.ts`
