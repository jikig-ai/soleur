---
title: "fix: Agent needs your Input UX is broken"
type: fix
date: 2026-04-10
issue: "#1873"
---

# fix: Agent needs your Input UX -- broken description, buttons, and dismissal

Closes #1873

## Problem Statement

The "Agent needs your Input" review gate UX has three distinct bugs:

1. **No description of what input is required** -- The review gate card displays
   "Agent needs your input" as a generic fallback instead of the actual question
   the agent is asking. The `AskUserQuestion` tool passes a `question` field and
   an `options` array, but the UI does not always surface the question text
   meaningfully.

2. **Clicking buttons doesn't work / throws errors** -- When the user clicks an
   option button on the `ReviewGateCard`, the `sendReviewGateResponse` callback
   fires but the response may fail server-side. The `resolveReviewGate` function
   searches `activeSessions` for the gate ID, but if the agent session has ended
   or timed out (the 5-minute `REVIEW_GATE_TIMEOUT_MS`), the gate resolver no
   longer exists. The error thrown ("Review gate not found or already resolved")
   propagates back through the WebSocket as an `error` message but the card
   remains in its "selected" visual state, giving no feedback that the action
   failed.

3. **The input box never disappears** -- After a user responds to a review gate,
   the `ReviewGateCard` stays in the message list permanently. There is no
   mechanism to dismiss or collapse it after resolution. The card has a `selected`
   state that dims unselected options, but it remains fully visible in the
   conversation flow, cluttering the chat.

## Root Cause Analysis

### Server-side (`agent-runner.ts` lines 600-632)

The `canUseTool` callback intercepts `AskUserQuestion` tool calls and:

- Extracts `toolInput.question` (falls back to "Agent needs your input" if empty)
- Extracts `toolInput.options` (falls back to `["Approve", "Reject"]` if empty array)
- Sends a `review_gate` WebSocket message with `{ gateId, question, options }`
- Creates a promise via `abortableReviewGate` that resolves when the user responds

**Issue 1 root cause**: The `question` field extraction works correctly on the
server side. The problem is that when the SDK's `AskUserQuestion` tool is invoked
by the agent, the `toolInput` object's `question` field contains the actual
question text. However, the client-side `ReviewGateCard` component renders
`{question}` correctly in the amber card. The real issue is that the card's
visual hierarchy makes the question look like a generic label rather than
important contextual information. The question text IS being displayed but may
appear as "Agent needs your input" when the agent invokes `AskUserQuestion`
without a descriptive question string -- the server fallback at line 604 masks
the actual agent intent.

**Issue 2 root cause**: The `resolveReviewGate` function throws an error when:

- The gate ID is not found in any session's `reviewGateResolvers` map (gate
  timed out after 5 minutes, or session was aborted)
- The session key no longer exists in `activeSessions` (session ended)

The error is caught by ws-handler.ts (line 360) and sent back as a WebSocket
`error` message. On the client side, this error message is appended to the
messages array as a generic error bubble, but the `ReviewGateCard` has already
set `selected` to a value and shows the dimmed state. The user sees a selected
button AND an error message but cannot retry because `selected !== null` prevents
further clicks.

**Issue 3 root cause**: The `ReviewGateCard` is rendered as a regular chat
message in the `messages` array. Once added, it persists indefinitely. There is
no mechanism to:

- Remove it from the array after successful resolution
- Collapse or visually dismiss it
- Replace it with a summary of what was selected

## Implementation Plan

### Phase 1: Improve question display (Issue 1)

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [ ] Add a header/title to `ReviewGateCard` that says "Agent needs your input" as a label
- [ ] Display the `question` prop with better visual prominence (larger text, different color)
- [ ] Add a visual icon (question mark or input icon) to differentiate from regular messages
- [ ] If question equals the generic fallback "Agent needs your input", show a more helpful
  message like "The agent is waiting for your decision" with an instruction to select an option

### Phase 2: Fix button click errors (Issue 2)

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [ ] Track gate resolution state: `idle` | `pending` | `resolved` | `error`
- [ ] Show a loading spinner on the selected button while the response is in flight
- [ ] On error (received via WebSocket `error` message for this gate), reset the
  `selected` state to `null` so the user can retry
- [ ] Display the error inline on the card (not as a separate message bubble)
- [ ] Add a timeout indicator showing remaining time before the 5-minute gate expiry

**File: `apps/web-platform/lib/ws-client.ts`**

- [ ] When receiving an `error` message that corresponds to a review gate failure,
  emit a gate-specific error event so the card can handle it locally
- [ ] Add a `gateId` field to the error WSMessage type to enable targeted error
  handling (requires server-side change too)

**File: `apps/web-platform/server/agent-runner.ts`**

- [ ] When `resolveReviewGate` throws, include the `gateId` in the error response
  so the client can match errors to specific gates

**File: `apps/web-platform/server/ws-handler.ts`**

- [ ] Pass `gateId` from the `review_gate_response` handler to the error message
  sent to the client

**File: `apps/web-platform/lib/types.ts`**

- [ ] Extend the `error` WSMessage type to optionally include `gateId` for
  gate-specific error routing

### Phase 3: Dismiss resolved review gates (Issue 3)

**File: `apps/web-platform/lib/ws-client.ts`**

- [ ] After sending a successful `review_gate_response`, mark the corresponding
  message as resolved in the messages array
- [ ] Add a `resolved` boolean field to `ChatMessage` for review gate messages

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [ ] After successful resolution, collapse the `ReviewGateCard` to a single-line
  summary: "You selected: [option]" with a subtle visual style
- [ ] Add a smooth CSS transition for the collapse animation
- [ ] Keep the collapsed summary visible (don't fully remove) so conversation
  context is preserved for review

### Phase 4: Server-side resilience

**File: `apps/web-platform/server/agent-runner.ts`**

- [ ] When the review gate times out (5 minutes), send a `review_gate_expired`
  message to the client so the UI can update proactively
- [ ] Consider extending the timeout or making it configurable per-gate

**File: `apps/web-platform/lib/types.ts`**

- [ ] Add `review_gate_expired` to the `WSMessage` union type
- [ ] Add `review_gate_resolved` to the `WSMessage` union type for confirmation

## Acceptance Criteria

- [ ] Review gate cards display the agent's actual question text prominently
- [ ] When no question is provided, a helpful default message appears instead of generic text
- [ ] Clicking a review gate button shows a loading state while the response is processed
- [ ] If the gate has expired or the session has ended, the user sees a clear error on the card itself (not a separate error bubble) and can see the card auto-dismiss or retry
- [ ] After successful resolution, the review gate card collapses to a compact summary
- [ ] Expired gates are proactively dismissed on the client when the 5-minute timeout elapses
- [ ] All existing review gate tests continue to pass
- [ ] New tests cover: error recovery, card collapse, timeout expiry UI

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

## Test Scenarios

- Given a review gate with a descriptive question, when rendered, then the question text is prominently displayed above the option buttons
- Given a review gate with no question (fallback), when rendered, then a helpful default message appears instead of "Agent needs your input"
- Given the user clicks a review gate button, when the response is being sent, then the button shows a loading indicator
- Given the user clicks a review gate button, when the server returns an error (gate expired), then the error is shown inline on the card and buttons become clickable again
- Given the user successfully responds to a review gate, when the server accepts, then the card collapses to a one-line summary showing the selected option
- Given a review gate is pending, when 5 minutes pass without response, then the card shows an "expired" state proactively
- Given the WebSocket reconnects after a disconnection, when a review gate was pending, then the expired gate is shown in an appropriate state

## Context

### Relevant Files

| File | Role |
|------|------|
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | Chat page with `ReviewGateCard` component (lines 409-451) |
| `apps/web-platform/lib/ws-client.ts` | WebSocket client hook handling `review_gate` messages (lines 209-224) |
| `apps/web-platform/server/agent-runner.ts` | `canUseTool` intercepts `AskUserQuestion` (lines 600-632), `resolveReviewGate` (lines 951-988) |
| `apps/web-platform/server/ws-handler.ts` | Routes `review_gate_response` messages (lines 336-363) |
| `apps/web-platform/server/review-gate.ts` | `abortableReviewGate` promise with timeout (full file) |
| `apps/web-platform/lib/types.ts` | `WSMessage` union type (lines 34-48) |
| `apps/web-platform/test/review-gate.test.ts` | Unit tests for review gate promise mechanics |
| `apps/web-platform/test/chat-page.test.tsx` | Chat page component tests |

### Key Architecture Notes

- The `AskUserQuestion` tool from the Claude Agent SDK is intercepted by the
  `canUseTool` callback in `agent-runner.ts`. It never actually runs the tool --
  instead, it creates a review gate promise and sends a WebSocket message to
  the client.
- The review gate uses a `Map<string, ReviewGateEntry>` on the `AgentSession`
  object, keyed by `gateId` (UUID). The entry contains a `resolve` function
  and the offered `options` array.
- The `validateSelection` function enforces that the selected option exactly
  matches one of the offered options (case-sensitive, no whitespace tolerance).
- The `canUseTool` callback returns `{ behavior: "allow", updatedInput: { ...toolInput, answer: selection } }`
  after the user responds, which feeds the answer back to the SDK.

## MVP

Focus on Phases 1-3. Phase 4 (server-side resilience with `review_gate_expired`
messages) can be deferred if timeline is tight, but the client should at minimum
handle the case where the gate has already expired when the user clicks.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Replace review gates with inline chat responses | Simpler UX, no special components | Loses structured option selection, harder to parse free-text | Rejected -- structured options are valuable |
| Add a free-text input field alongside buttons | More flexibility for user responses | Complicates validation, `AskUserQuestion` tool has defined options | Deferred -- consider post-MVP |
| Remove review gate timeout entirely | Eliminates timeout errors | Gates could hang indefinitely, blocking the agent session | Rejected -- timeout is a safety mechanism |
