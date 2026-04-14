---
title: "fix: Enter key selects autocomplete item instead of sending message"
type: fix
date: 2026-04-14
---

# fix: Enter key selects autocomplete item instead of sending message

## Overview

When a user types `@` in the chat input to mention a leader, an autocomplete dropdown appears. Arrow keys navigate the list correctly, but pressing Enter sends the message instead of selecting the highlighted leader. This breaks the core tagging UX flow.

## Problem Statement

The `ChatInput` component has an `onKeyDown` handler on the `<textarea>` element that intercepts Enter and calls `handleSubmit()`. The `AtMentionDropdown` component has a separate `document.addEventListener("keydown")` that intercepts Enter and calls `onSelect()`.

**Event propagation order causes the bug:**

1. User presses Enter while the `@mention` dropdown is visible
2. The `<textarea>` React `onKeyDown` handler fires first (target phase / bubble to React root)
3. `ChatInput.handleKeyDown` calls `e.preventDefault()` + `handleSubmit()` -- message is sent
4. The `document`-level `keydown` listener from `AtMentionDropdown` fires second -- too late, message already sent

The `AtMentionDropdown` test ("selects with Enter key") passes because it fires `fireEvent.keyDown(document, ...)` directly on `document`, bypassing the textarea handler entirely. The integration between the two components was never tested together.

## Proposed Solution

Pass a prop or signal to `ChatInput` indicating whether the `@mention` dropdown is currently visible. When visible, suppress the Enter-to-send behavior so the dropdown's own Enter handler can select the highlighted leader.

### Implementation approach: Add `atMentionVisible` prop to ChatInput

**Why this approach:** The parent component (`ChatPage`) already tracks `atVisible` state. Passing it as a prop is the simplest change with zero architectural overhead. The dropdown already handles Enter correctly via its `document` listener -- the only issue is that `ChatInput` races it.

### Files to modify

1. **`apps/web-platform/components/chat/chat-input.tsx`**
   - Add `atMentionVisible?: boolean` to `ChatInputProps` interface
   - In `handleKeyDown`, check `atMentionVisible` before calling `handleSubmit()` on Enter

2. **`apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`**
   - Pass `atMentionVisible={atVisible}` to the `<ChatInput>` component

3. **`apps/web-platform/test/chat-input.test.tsx`**
   - Add test: "does not send on Enter when atMentionVisible is true"
   - Add test: "sends on Enter when atMentionVisible is false (default)"

4. **`apps/web-platform/test/at-mention-dropdown.test.tsx`**
   - Update "selects with Enter key" test to verify integration scenario (optional, but valuable for regression)

### Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **Prop `atMentionVisible`** (chosen) | Simple, explicit, no DOM coupling | One more prop | Chosen -- minimal change, clear intent |
| **`e.stopPropagation()` in dropdown** | No prop needed | Dropdown uses `document` listener, not React event -- `stopPropagation` from document level cannot stop the textarea handler that fires first | Does not work -- wrong propagation direction |
| **Move dropdown keydown to textarea `onKeyDown`** | Single handler, no race | Couples dropdown logic into ChatInput, violates component separation | Over-engineering for this fix |
| **Use `useRef` to share "dropdown active" state** | No prop drilling | Ref is mutable, harder to test, same information as a prop | Unnecessary indirection |
| **Capture phase listener in dropdown** | Fires before textarea | Requires `addEventListener("keydown", fn, true)` which is fragile and harder to reason about | Fragile, non-standard React pattern |

## Acceptance Criteria

- [ ] Pressing Enter while the `@mention` dropdown is visible selects the highlighted leader (does not send the message)
- [ ] Pressing Enter while the `@mention` dropdown is NOT visible sends the message (existing behavior preserved)
- [ ] Arrow keys continue to navigate the dropdown
- [ ] Escape dismisses the dropdown
- [ ] Shift+Enter still inserts a newline regardless of dropdown state
- [ ] Clicking a leader in the dropdown still works
- [ ] Mobile `@` button still triggers the dropdown

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a straightforward event handling bug fix. The architectural pattern (parent passes visibility state to child) is already used throughout the codebase (e.g., `disabled` prop on ChatInput). No infrastructure or schema changes needed. Low risk, high impact on usability.

## Test Scenarios

- Given the `@mention` dropdown is visible with leaders listed, when the user presses Enter, then the highlighted leader is selected and inserted into the input (message is NOT sent)
- Given the `@mention` dropdown is NOT visible, when the user presses Enter with text in the input, then the message is sent normally
- Given the `@mention` dropdown is visible, when the user presses ArrowDown then Enter, then the second leader in the list is selected
- Given the `@mention` dropdown is visible, when the user presses Escape, then the dropdown closes and Enter sends the message
- Given the `@mention` dropdown is visible, when the user presses Shift+Enter, then a newline is inserted (not a selection, not a send)

## MVP

### chat-input.tsx change (handleKeyDown)

```typescript
const handleKeyDown = useCallback(
  (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      if (atMentionVisible) return; // Let dropdown handle Enter
      e.preventDefault();
      handleSubmit();
    }
  },
  [handleSubmit, atMentionVisible],
);
```

### chat page change (prop pass-through)

```tsx
<ChatInput
  onSend={handleSend}
  conversationId={conversationId}
  onAtTrigger={(query, pos) => {
    setAtQuery(query);
    setAtPosition(pos);
    setAtVisible(true);
  }}
  onAtDismiss={() => setAtVisible(false)}
  atMentionVisible={atVisible}
  disabled={status !== "connected"}
  placeholder={...}
  insertRef={insertRef}
/>
```

## References

- Related issue: #2160
- AtMentionDropdown component: `apps/web-platform/components/chat/at-mention-dropdown.tsx`
- ChatInput component: `apps/web-platform/components/chat/chat-input.tsx`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Learning: `knowledge-base/project/learnings/2026-03-27-tag-and-route-multi-leader-architecture.md`
