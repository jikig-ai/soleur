---
title: "fix: improve chat-page test determinism and coverage"
type: fix
date: 2026-04-06
issue: "#1485"
---

# Fix: Improve Chat-Page Test Determinism and Coverage

## Problem

The `chat-page.test.tsx` tests (added in PR #1481) have two quality issues flagged by the test design reviewer (grade B, 7.5/10):

1. **Flaky `setTimeout(r, 50)` pattern** at lines 73 and 103: These negative assertions use wall-clock timing to "wait for effects to settle" before asserting `sendMessage` was NOT called. If React effect batching changes (version upgrade, concurrent mode, environment swap), the 50ms window may be insufficient or unnecessary. The `waitFor` pattern used elsewhere in the same file is the correct approach.

2. **Missing test scenarios** from the plan's acceptance criteria:
   - `handleSend` works independently of `sessionConfirmed` (manual input does not depend on server ack)
   - No `?msg=` param baseline: `startSession()` is called but no `sendMessage` fires regardless of `sessionConfirmed`
   - Server error path: `sessionConfirmed` stays `false` when server sends `error` instead of `session_started`

**Location:** `apps/web-platform/test/chat-page.test.tsx:68-106`

## Research Findings

### Repo Context

- **Test environment:** Vitest with happy-dom, `@testing-library/react@^16.3.2`, React 19
- **Setup:** `test/setup-dom.ts` runs RTL cleanup in `afterEach`
- **Existing patterns:** The file already uses `waitFor` from RTL for positive assertions (lines 81, 91). Only the negative assertion paths use `setTimeout`
- **Mock structure:** `wsReturn` object is reassigned in `beforeEach` and mutated before each `renderChatPage()` call. The `useWebSocket` mock returns this mutable ref

### Institutional Knowledge

- **Learning `2026-04-03-useeffect-race-optimistic-flag-vs-server-ack.md`:** Documents why `sessionConfirmed` exists -- it gates the `?msg=` send effect on server acknowledgment instead of an optimistic client flag. Directly relevant to the test scenarios
- **Learning `2026-03-03-timer-based-async-settling-in-bridge-tests.md`:** Documents the same `setTimeout(r, 50)` anti-pattern in `telegram-bridge` tests. Root cause there was fire-and-forget methods without promise handles. In `chat-page.test.tsx` the root cause is different: the mock returns synchronous values, so effects can be flushed deterministically

### Deterministic Flush Approach

For negative assertions ("X was NOT called after effects settle"), the correct RTL pattern is:

```tsx
// Option A: waitFor with timeout (preferred -- RTL-native)
await waitFor(() => {
  expect(mockSendMessage).not.toHaveBeenCalled();
});

// Option B: act() flush (React-native, lower-level)
import { act } from "@testing-library/react";
await act(async () => {});
expect(mockSendMessage).not.toHaveBeenCalled();
```

**Decision: Use `waitFor` (Option A)** because:

- Already used in the same file for positive assertions -- consistency
- RTL `waitFor` retries the assertion on a microtask loop, giving React's scheduler time to flush pending effects
- `act()` from RTL wraps React's `act()` but `await act(async () => {})` is an empty flush that is less idiomatic for assertion-centric tests
- Both are deterministic (no wall-clock dependency), but `waitFor` is the established pattern in this codebase

## Proposed Changes

### Task 1: Replace setTimeout with waitFor

**File:** `apps/web-platform/test/chat-page.test.tsx`

Replace both `setTimeout` occurrences with `waitFor`:

```tsx
// BEFORE (line 73):
await new Promise((r) => setTimeout(r, 50));
expect(mockSendMessage).not.toHaveBeenCalled();

// AFTER:
await waitFor(() => {
  expect(mockSendMessage).not.toHaveBeenCalled();
});
```

```tsx
// BEFORE (line 103):
await new Promise((r) => setTimeout(r, 50));
// Should NOT send again since sessionConfirmed is false after reconnection
expect(mockSendMessage).not.toHaveBeenCalled();

// AFTER:
await waitFor(() => {
  // Should NOT send again since sessionConfirmed is false after reconnection
  expect(mockSendMessage).not.toHaveBeenCalled();
});
```

### Task 2: Add handleSend independence test

**File:** `apps/web-platform/test/chat-page.test.tsx`

Test that manual send works regardless of `sessionConfirmed` state. The `handleSend` function in `page.tsx` only checks `status !== "connected"` -- it does NOT check `sessionConfirmed`.

**Pre-task:** Read the `ChatInput` component (`components/chat/chat-input.tsx`) to determine the submit mechanism (button click, Enter key, form submit) and the input's placeholder text. The test interaction pattern depends on this.

```tsx
it("handleSend works when sessionConfirmed is false and status is connected", async () => {
  wsReturn.sessionConfirmed = false;
  wsReturn.status = "connected";
  await renderChatPage();

  // Interaction pattern depends on ChatInput's rendered output.
  // Read ChatInput before implementation to determine:
  // - Input selector (placeholder text or role)
  // - Submit mechanism (button click, Enter key, form submit)
  // Pseudo-code:
  // const input = screen.getByPlaceholderText(/...placeholder.../i);
  // await userEvent.type(input, "manual message");
  // <submit interaction>

  expect(mockSendMessage).toHaveBeenCalledWith("manual message");
});
```

### Task 3: Add no-msg-param baseline test

**File:** `apps/web-platform/test/chat-page.test.tsx`

Test that when no `?msg=` param is present, `sendMessage` is never called even after `sessionConfirmed` becomes true.

```tsx
it("does not send any message when no ?msg= param is present even after sessionConfirmed", async () => {
  // No mockSearchParams.set("msg", ...) -- default empty params
  wsReturn.sessionConfirmed = true;
  wsReturn.status = "connected";
  await renderChatPage();

  await waitFor(() => {
    expect(mockSendMessage).not.toHaveBeenCalled();
  });
});
```

### Task 4: Add server error path test

**File:** `apps/web-platform/test/chat-page.test.tsx`

Test that when an error occurs before session confirmation, the error card is visible and the initial message is not sent. Since the test file mocks `useWebSocket`, the "server error" scenario is expressed by setting `sessionConfirmed=false` and `lastError` to a non-null value. This tests the page-level behavior (error card rendering + no-send), which is distinct from Task 1 (no error card, just no-send).

```tsx
it("shows error card and does not send msg when server errors before session_started", async () => {
  mockSearchParams.set("msg", "help with pricing");
  wsReturn.sessionConfirmed = false;
  wsReturn.lastError = {
    code: "rate_limited",
    message: "You've been rate limited.",
  };
  await renderChatPage();

  // Error card should be visible
  expect(screen.getByText(/rate limited/i)).toBeInTheDocument();

  // Message should NOT be sent since sessionConfirmed is false
  await waitFor(() => {
    expect(mockSendMessage).not.toHaveBeenCalled();
  });
});
```

## Acceptance Criteria

- [ ] No `setTimeout` used for negative assertions in chat-page tests
- [ ] Test for `handleSend` independence from `sessionConfirmed` exists and passes
- [ ] Test for no-msg-param baseline exists and passes
- [ ] Test for error-before-confirmation exists and passes
- [ ] All existing tests continue to pass (no regressions)
- [ ] All tests pass deterministically with no timing-dependent assertions

## Test Scenarios

- Given `sessionConfirmed=false` and `?msg=` present, when effects settle, then `sendMessage` is not called (deterministic, no setTimeout)
- Given message sent and `sessionConfirmed` reset to `false` on reconnect, when effects settle, then `sendMessage` is not called again (deterministic, no setTimeout)
- Given `sessionConfirmed=false` and `status="connected"`, when user types and submits via ChatInput, then `sendMessage` is called (handleSend independence)
- Given no `?msg=` param and `sessionConfirmed=true`, when effects settle, then `sendMessage` is not called (no-msg-param baseline)
- Given `sessionConfirmed=false` and `lastError` set, when page renders, then error card is visible and `sendMessage` is not called (server error path)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal test quality improvement.

## Implementation Notes

- **Ordering:** Tasks 1, 3, 4 are simple find-and-replace / append operations. Task 2 requires reading ChatInput first (explicit pre-task in the task description)
