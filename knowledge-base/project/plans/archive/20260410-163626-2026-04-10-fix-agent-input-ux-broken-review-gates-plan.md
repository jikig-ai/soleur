---
title: "fix: Agent needs your Input UX is broken"
type: fix
date: 2026-04-10
issue: "#1873"
deepened: 2026-04-10
---

# fix: Agent needs your Input UX -- broken description, buttons, and dismissal

Closes #1873

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 5 (Root Cause, Implementation Plan phases 1-4)
**Research sources:** Claude Agent SDK v0.2.80 type definitions, Context7 SDK
documentation, codebase pattern analysis

### Key Improvements

1. **Root cause corrected**: The primary bug is a schema mismatch -- the server
   reads `toolInput.question` and `toolInput.options` but the SDK sends
   `toolInput.questions[0].question` and `toolInput.questions[0].options`
   (objects with `label`/`description`, not flat strings). The response format is
   also wrong: the code returns `{ ...toolInput, answer: selection }` but the SDK
   expects `{ questions, answers: { [questionText]: selection } }`.
2. **Implementation plan restructured**: Phase 0 (SDK schema fix) added as the
   critical first step. Previous phases renumbered. This single fix likely resolves
   all three reported symptoms.
3. **Existing UI component reuse**: `SpinnerIcon` component from
   `components/icons/index.tsx` and `ErrorCard` pattern from
   `components/ui/error-card.tsx` already exist and should be reused.

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

### Research Insights

**SDK Schema Discovery (Critical):** The `AskUserQuestion` tool in
`@anthropic-ai/claude-agent-sdk@0.2.80` uses a structured schema that does NOT
match the current server-side extraction code. The SDK type definitions
(`sdk-tools.d.ts` line 629) and Context7 documentation confirm:

```typescript
// AskUserQuestionInput -- what the SDK sends to canUseTool
interface AskUserQuestionInput {
  questions: Array<{
    question: string;     // "Which library should we use?"
    header: string;       // "Library" (max 12 chars)
    options: Array<{
      label: string;       // "React Query"
      description: string; // "Best for server state management"
      preview?: string;    // Optional preview content
    }>;
    multiSelect: boolean;
  }>;
}

// AskUserQuestionOutput -- what canUseTool must return via updatedInput
interface AskUserQuestionOutput {
  questions: AskUserQuestionInput["questions"];
  answers: Record<string, string>;  // { [questionText]: "selected label" }
}
```

### Server-side (`agent-runner.ts` lines 600-632)

The `canUseTool` callback intercepts `AskUserQuestion` tool calls and:

- Reads `toolInput.question` -- **WRONG**: field does not exist; SDK sends
  `toolInput.questions[0].question`
- Reads `toolInput.options` -- **WRONG**: field does not exist; SDK sends
  `toolInput.questions[0].options` as an array of `{ label, description }` objects,
  not flat strings
- Falls back to `"Agent needs your input"` and `["Approve", "Reject"]` -- these
  fallbacks fire on EVERY call because the correct fields are never read
- Returns `{ ...toolInput, answer: selection }` -- **WRONG**: SDK expects
  `{ questions: toolInput.questions, answers: { [questionText]: selection } }`

**Issue 1 root cause (no description)**: The server reads `toolInput.question`
which is `undefined` (the SDK sends `questions[0].question`). The fallback
`"Agent needs your input"` always fires. The actual question text from the agent
is silently discarded. Similarly, `toolInput.options` is `undefined` so the
fallback `["Approve", "Reject"]` always fires, discarding the agent's actual
options. The client is correctly rendering what the server sends -- the data is
just wrong.

**Issue 2 root cause (button errors)**: Two distinct failure modes:

1. **Schema mismatch in response**: The `updatedInput` returned to the SDK uses
   the wrong format (`{ answer: "..." }` instead of
   `{ questions: [...], answers: { ... } }`). The SDK may reject this or
   misinterpret it, causing the agent session to error.

2. **Gate expiry race condition**: If the user takes longer than 5 minutes to
   respond (`REVIEW_GATE_TIMEOUT_MS`), the `abortableReviewGate` promise rejects
   with "Review gate timed out". When the user then clicks a button, the
   `resolveReviewGate` function cannot find the gate ID (already cleaned up) and
   throws "Review gate not found or already resolved". This error propagates as
   a generic WebSocket error message, but the `ReviewGateCard` has already set
   `selected !== null`, preventing retry.

**Issue 3 root cause (never disappears)**: The `ReviewGateCard` is appended to
the `messages` array as a `ChatMessage` with `type: "review_gate"`. After the
user responds, there is no mechanism to:

- Mark the message as resolved in the messages array
- Collapse or visually dismiss it
- Send a server confirmation that the gate was successfully resolved

The card has a `selected` state that dims unselected options but remains fully
visible. Since the SDK response format is also wrong (Issue 2), the agent
session may error after the user responds, leaving the card in a permanently
ambiguous state.

## Implementation Plan

### Phase 0: Fix SDK schema mismatch (Root cause -- fixes all three issues)

This is the critical fix. The current code reads wrong fields and returns a wrong
response format. Fixing this alone likely resolves Issues 1 and 2. Issue 3
(card persistence) requires additional UI work.

**File: `apps/web-platform/server/agent-runner.ts` (lines 600-632)**

- [x] Extract question from SDK schema: read `toolInput.questions[0].question`
  instead of `toolInput.question`
- [x] Extract header from SDK schema: read `toolInput.questions[0].header` for
  the card title
- [x] Extract options from SDK schema: read `toolInput.questions[0].options` and
  map `option.label` to get string labels; send `option.description` alongside
  for richer UI
- [x] Handle multi-question case: iterate over `toolInput.questions` array
  (currently only the first question is surfaced as a gate; for MVP, show all
  questions sequentially or support only the first)
- [x] Fix response format: return
  `{ behavior: "allow", updatedInput: { questions: toolInput.questions, answers: { [questionText]: selection } } }`
  instead of `{ ...toolInput, answer: selection }`
- [x] Keep fallback for backward compatibility: if `toolInput.questions` is
  undefined (older SDK or direct tool invocation), fall back to the current
  `toolInput.question` / `toolInput.options` extraction

```typescript
// BEFORE (broken):
const question = (toolInput.question as string) || "Agent needs your input";
const rawOptions = Array.isArray(toolInput.options)
  ? (toolInput.options as unknown[]).filter((o): o is string => typeof o === "string")
  : [];
const gateOptions = rawOptions.length > 0 ? rawOptions : ["Approve", "Reject"];
// ...
return { behavior: "allow" as const, updatedInput: { ...toolInput, answer: selection } };

// AFTER (correct):
const questions = toolInput.questions as Array<{
  question: string; header: string;
  options: Array<{ label: string; description: string }>;
  multiSelect: boolean;
}> | undefined;

const firstQ = questions?.[0];
const question = firstQ?.question
  || (toolInput.question as string)
  || "Agent needs your input";
const header = firstQ?.header || "Input needed";
const rawOptions = firstQ?.options
  ? firstQ.options.map(o => o.label)
  : Array.isArray(toolInput.options)
    ? (toolInput.options as unknown[]).filter((o): o is string => typeof o === "string")
    : [];
const optionDescriptions = firstQ?.options
  ? Object.fromEntries(firstQ.options.map(o => [o.label, o.description]))
  : {};
const gateOptions = rawOptions.length > 0 ? rawOptions : ["Approve", "Reject"];

sendToClient(userId, {
  type: "review_gate",
  gateId,
  question,
  header,
  options: gateOptions,
  descriptions: optionDescriptions,
});
// ...
return {
  behavior: "allow" as const,
  updatedInput: questions
    ? { questions, answers: { [question]: selection } }
    : { ...toolInput, answer: selection },
};
```

**File: `apps/web-platform/lib/types.ts`**

- [x] Extend the `review_gate` WSMessage type with optional `header` and
  `descriptions` fields:

```typescript
| { type: "review_gate"; gateId: string; question: string;
    header?: string; options: string[];
    descriptions?: Record<string, string> }
```

**File: `apps/web-platform/server/review-gate.ts`**

- [x] No changes needed -- the review gate promise mechanics are correct.
  `validateSelection` already validates against the offered `options` array
  which will now contain actual option labels from the SDK.

### Phase 1: Improve question display (Issue 1 -- UI polish)

With Phase 0 in place, the question text and options are now correct. This phase
improves the visual rendering.

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [x] Update `ReviewGateCard` props to accept `header` and `descriptions`
- [x] Display the `header` (e.g., "Library", "Approach") as a small tag/chip
  above the question
- [x] Display option descriptions as subtext below each button label
- [x] Increase visual prominence of the question text (use `text-base` instead
  of `text-sm`, `font-medium` already applied)
- [x] Add a question mark icon (SVG inline) to differentiate review gate cards
  from regular messages

**File: `apps/web-platform/lib/ws-client.ts`**

- [x] Extend `ChatMessage` to carry `header` and `descriptions` fields for
  review gate messages
- [x] In the `review_gate` handler (line 209), map the new fields from the
  WSMessage to the ChatMessage

### Phase 2: Fix button click errors (Issue 2)

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [x] Replace `selected: string | null` state with a state machine:
  `{ status: "idle" | "pending" | "resolved" | "error"; selection: string | null; error?: string }`
- [x] On click: set status to `pending` with the selected option, call
  `onSelect(gateId, option)`
- [x] Show the existing `SpinnerIcon` (from `components/icons/index.tsx`) inline
  on the clicked button during `pending` state
- [x] On `resolved` confirmation: set status to `resolved`
- [x] On error: set status to `error`, display error text inline on the card
  (red text below buttons, similar to `ErrorCard` pattern), reset to `idle`
  after 3 seconds so user can retry

**File: `apps/web-platform/lib/ws-client.ts`**

- [x] Add `gateError` field to `ChatMessage` for review gate messages
- [x] When receiving an `error` message with a `gateId`, find the matching
  review gate message in the array and set its `gateError` field instead of
  appending a generic error bubble

**File: `apps/web-platform/lib/types.ts`**

- [x] Extend the `error` WSMessage type to optionally include `gateId`:
  `| { type: "error"; message: string; errorCode?: WSErrorCode; gateId?: string }`

**File: `apps/web-platform/server/ws-handler.ts`**

- [x] In the `review_gate_response` handler (line 336), pass `gateId` when
  sending error to client:

```typescript
case "review_gate_response": {
  try {
    // ...existing validation...
    await resolveReviewGate(userId, session.conversationId, msg.gateId, msg.selection);
  } catch (err) {
    sendToClient(userId, {
      type: "error",
      message: sanitizeErrorForClient(err),
      gateId: msg.gateId,  // NEW: enables client-side targeted error handling
    });
  }
  break;
}
```

### Phase 3: Dismiss resolved review gates (Issue 3)

**File: `apps/web-platform/lib/ws-client.ts`**

- [x] After sending `review_gate_response`, optimistically mark the message as
  `resolved` with `selectedOption` set to the chosen option
- [x] Add `resolved?: boolean` and `selectedOption?: string` fields to `ChatMessage`

```typescript
const sendReviewGateResponse = useCallback(
  (gateId: string, selection: string) => {
    send({ type: "review_gate_response", gateId, selection });
    // Optimistically mark as resolved
    setMessages((prev) => prev.map((m) =>
      m.gateId === gateId
        ? { ...m, resolved: true, selectedOption: selection }
        : m
    ));
  },
  [send],
);
```

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [x] When `resolved === true`, render a compact single-line summary instead of
  the full card:

```tsx
if (resolved) {
  return (
    <div className="flex items-center gap-2 rounded-lg border border-neutral-800
                    bg-neutral-900/50 px-4 py-2 text-sm text-neutral-400">
      <svg className="h-4 w-4 text-green-500" /* check icon */ />
      <span>Selected: <strong className="text-neutral-200">{selectedOption}</strong></span>
    </div>
  );
}
```

- [x] Use CSS `transition-all duration-300` for smooth height change
- [x] If an error later overrides the optimistic resolution (server sends back
  an error with the `gateId`), revert to the full card with error state

### Phase 4: Server-side resilience (stretch)

**File: `apps/web-platform/server/agent-runner.ts`**

- [ ] When the review gate times out (5 minutes), send a `review_gate_expired`
  WebSocket message to the client so the UI can update proactively:

```typescript
// In the abortableReviewGate timeout callback, before rejecting:
sendToClient(userId, {
  type: "review_gate_expired",
  gateId,
});
```

Note: This requires restructuring the timeout handler since `sendToClient`
is not currently available in the `abortableReviewGate` function. Consider
passing a `onTimeout` callback to `abortableReviewGate`, or handling the
timeout rejection in the `canUseTool` callback's catch block.

**File: `apps/web-platform/lib/types.ts`**

- [ ] Add `review_gate_expired` to the `WSMessage` union type:
  `| { type: "review_gate_expired"; gateId: string }`

**File: `apps/web-platform/lib/ws-client.ts`**

- [ ] Handle `review_gate_expired` messages: find the matching review gate
  message and mark it with an `expired: true` field

**File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**

- [ ] When a gate is expired, show a dimmed card with "This question has expired"
  text and disabled buttons

## Acceptance Criteria

- [x] Server correctly extracts `questions[0].question`, `questions[0].header`,
  and `questions[0].options[].label` from the SDK's `AskUserQuestion` tool input
- [x] Server returns `{ questions, answers: { [question]: selection } }` as the
  `updatedInput` to the SDK (matching `AskUserQuestionOutput` type)
- [x] Review gate cards display the agent's actual question text prominently
  with the header tag shown above it
- [x] Option buttons show both the label and description text from the SDK
- [x] When no question is provided (fallback), a helpful default message appears
- [x] Clicking a review gate button shows a `SpinnerIcon` loading state on the
  clicked button while the response is processed
- [x] If the gate has expired or the session has ended, the user sees a clear
  error inline on the card itself (not a separate error bubble) and buttons
  reset to allow retry
- [x] After successful resolution, the review gate card collapses to a compact
  summary showing the selected option with a check icon
- [x] All existing review gate tests continue to pass
  (`apps/web-platform/test/review-gate.test.ts`)
- [x] New tests cover: SDK schema extraction, correct response format, error
  recovery with retry, card collapse, `gateId`-targeted error routing

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

## Test Scenarios

### Phase 0: SDK schema fix

- Given the SDK calls `AskUserQuestion` with `{ questions: [{ question: "Which approach?", header: "Approach", options: [{ label: "A", description: "desc A" }, { label: "B", description: "desc B" }], multiSelect: false }] }`, when `canUseTool` processes it, then the `review_gate` WebSocket message contains `question: "Which approach?"`, `header: "Approach"`, and `options: ["A", "B"]`
- Given the SDK calls `AskUserQuestion` without a `questions` field (legacy/direct invocation), when `canUseTool` processes it, then it falls back to `toolInput.question` and `toolInput.options`
- Given the user selects option "A" for question "Which approach?", when the server builds `updatedInput`, then the result is `{ questions: [...], answers: { "Which approach?": "A" } }`

### Phase 1: Question display

- Given a review gate with question "Which library?" and header "Library", when rendered, then the header appears as a tag/chip and the question is prominently displayed
- Given options with labels and descriptions, when rendered, then each button shows the label and description text below it

### Phase 2: Button error handling

- Given the user clicks a review gate button, when the response is being sent, then the button shows a `SpinnerIcon` loading indicator
- Given the user clicks a review gate button, when the server returns an error with matching `gateId`, then the error is shown inline on the card and buttons reset to clickable after 3 seconds
- Given a generic error (no `gateId`), when received, then it appears as a normal error bubble (no change to review gate card)

### Phase 3: Card dismissal

- Given the user successfully responds to a review gate, when the response is sent, then the card optimistically collapses to "Selected: [option]"
- Given an optimistic collapse, when the server later returns an error for that `gateId`, then the card reverts to full display with error state

### Phase 4: Expiry (stretch)

- Given a review gate is pending, when 5 minutes pass, then the server sends `review_gate_expired` and the card shows "This question has expired" with disabled buttons

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
- **SDK schema**: `AskUserQuestionInput` uses `{ questions: [...] }` (array of
  question objects with `question`, `header`, `options[]`, `multiSelect`).
  `AskUserQuestionOutput` expects `{ questions: [...], answers: { [q]: "..." } }`.
  The current code uses the wrong field names and response format.
- **Existing reusable components**: `SpinnerIcon` at `components/icons/index.tsx`
  line 82 (used in connect-repo and KB search), `ErrorCard` at
  `components/ui/error-card.tsx` (used on chat page and dashboard).

### Edge Cases to Handle

- **Multiple questions**: The SDK supports 1-4 questions per `AskUserQuestion`
  call. The current UI shows a single gate card. For MVP, show only the first
  question but log a warning if multiple questions are received.
- **Multi-select**: The SDK supports `multiSelect: true` where users can select
  multiple options. For MVP, treat all gates as single-select. Multi-select
  support can be added later.
- **Preview content**: Options can include a `preview` field with rich content
  (code snippets, mockups). For MVP, ignore preview content. A future enhancement
  could render previews in an expandable section.
- **Race condition on disconnect/reconnect**: If the WebSocket reconnects while
  a review gate is pending, the gate may have expired server-side but the client
  still shows it as active. The client should treat any pending review gate as
  potentially expired after reconnection.

## MVP

**Phase 0 is the critical fix.** It corrects the SDK schema mismatch that causes
all three reported symptoms. Phases 1-3 are UI polish that improves the
experience but may not be strictly necessary if Phase 0 resolves the visible
bugs.

**Priority order:** Phase 0 (SDK fix) > Phase 2 (error handling) > Phase 3
(card dismissal) > Phase 1 (visual polish) > Phase 4 (server-side resilience).

Phase 4 (server-side resilience with `review_gate_expired` messages) can be
deferred. The client should at minimum handle the case where the gate has
already expired when the user clicks (Phase 2 covers this via error handling).

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Replace review gates with inline chat responses | Simpler UX, no special components | Loses structured option selection, harder to parse free-text | Rejected -- structured options are valuable |
| Add a free-text input field alongside buttons | More flexibility for user responses | Complicates validation, `AskUserQuestion` tool has defined options | Deferred -- consider post-MVP |
| Remove review gate timeout entirely | Eliminates timeout errors | Gates could hang indefinitely, blocking the agent session | Rejected -- timeout is a safety mechanism |
