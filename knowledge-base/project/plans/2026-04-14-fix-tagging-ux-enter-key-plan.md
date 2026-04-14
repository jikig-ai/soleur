---
title: "fix: Enter key selects autocomplete item instead of sending message"
type: fix
date: 2026-04-14
deepened: 2026-04-14
---

# fix: Enter key selects autocomplete item instead of sending message

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** 6
**Research sources used:** WAI-ARIA Authoring Practices Guide (combobox pattern), React.dev event handling docs, Vercel React Best Practices, project learnings (tag-and-route architecture, a11y patterns)

### Key Improvements

1. Added WAI-ARIA combobox keyboard interaction compliance analysis -- the fix aligns with the W3C standard where Enter on the input selects the active option when the popup is open
2. Added accessibility improvements: `aria-expanded`, `aria-activedescendant`, and `Tab` key handling for the dropdown hint footer
3. Added edge case analysis: empty filtered list, rapid typing race conditions, Tab key behavior, and IME composition
4. Strengthened test scenarios with integration-level tests that exercise both components together

### New Considerations Discovered

- The current `AtMentionDropdown` registers its keyboard handler on `document` instead of the `<textarea>` -- this deviates from the WAI-ARIA combobox pattern where the input element owns the keyboard handler. The chosen fix (prop approach) works correctly without changing this, but a future refactor could move the keyboard logic into `ChatInput` for full combobox compliance.
- The dropdown footer shows keyboard hints for up/down but not for Enter or Escape -- adding `Enter to select` would improve discoverability.
- The `Tab` key currently does nothing when the dropdown is open -- per WAI-ARIA, Tab should close the popup and move focus normally.

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

### Research Insights: Event Propagation

**React synthetic events vs native DOM events:** React attaches event handlers to the root DOM node (not individual elements). React's synthetic `onKeyDown` on the textarea fires during React's internal dispatch, which happens during the bubble phase. The `document.addEventListener("keydown")` in `AtMentionDropdown` fires after all element-level handlers have completed bubbling. This ordering is deterministic and well-documented in React.dev -- it is not a race condition but a guaranteed ordering problem.

**WAI-ARIA combobox pattern (W3C APG):** The standard combobox keyboard interaction pattern places ALL keyboard handling on the input element itself:

> "When focus is within the combobox, the Enter key accepts the focused option and closes the popup."

The current architecture splits keyboard handling between the textarea (`ChatInput`) and `document` (`AtMentionDropdown`). The fix consolidates the Enter decision into `ChatInput` by checking `atMentionVisible`, which matches the WAI-ARIA intent: the input element decides whether Enter submits or selects.

## Proposed Solution

Pass a prop or signal to `ChatInput` indicating whether the `@mention` dropdown is currently visible. When visible, suppress the Enter-to-send behavior so the dropdown's own Enter handler can select the highlighted leader.

### Implementation approach: Add `atMentionVisible` prop to ChatInput

**Why this approach:** The parent component (`ChatPage`) already tracks `atVisible` state. Passing it as a prop is the simplest change with zero architectural overhead. The dropdown already handles Enter correctly via its `document` listener -- the only issue is that `ChatInput` races it.

### Files to modify

1. **`apps/web-platform/components/chat/chat-input.tsx`**
   - Add `atMentionVisible?: boolean` to `ChatInputProps` interface
   - In `handleKeyDown`, check `atMentionVisible` before calling `handleSubmit()` on Enter
   - Add `atMentionVisible` to `handleKeyDown` dependency array

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
| **Move dropdown keydown to textarea `onKeyDown`** | Single handler, no race, WAI-ARIA compliant | Couples dropdown logic into ChatInput, violates component separation | Over-engineering for this fix; consider as future refactor |
| **Use `useRef` to share "dropdown active" state** | No prop drilling | Ref is mutable, harder to test, same information as a prop | Unnecessary indirection |
| **Capture phase listener in dropdown** | Fires before textarea | Requires `addEventListener("keydown", fn, true)` which is fragile and harder to reason about | Fragile, non-standard React pattern |

## Acceptance Criteria

- [x] Pressing Enter while the `@mention` dropdown is visible selects the highlighted leader (does not send the message)
- [x] Pressing Enter while the `@mention` dropdown is NOT visible sends the message (existing behavior preserved)
- [x] Arrow keys continue to navigate the dropdown
- [x] Escape dismisses the dropdown
- [x] Shift+Enter still inserts a newline regardless of dropdown state
- [x] Clicking a leader in the dropdown still works
- [x] Mobile `@` button still triggers the dropdown

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

### Research Insights: Additional Test Scenarios

**Edge cases from WAI-ARIA combobox pattern analysis:**

- Given the `@mention` dropdown is visible but the filtered list is empty (query matches no leader), when the user presses Enter, then the message should be sent normally (no leader to select)
- Given the user types `@cto` and the dropdown shows one match, when the user presses Enter, then "cto" is selected -- verify the dropdown closes and the cursor is positioned after the inserted `@cto`
- Given the user is composing with an IME (e.g., Japanese input), when `isComposing` is true on the KeyboardEvent, then Enter should NOT trigger send or select (it finalizes the IME composition)

**Integration test (both components rendered together):**

- Render `ChatPage` (or a minimal wrapper with both `ChatInput` and `AtMentionDropdown`), type `@`, verify dropdown appears, press Enter, verify `onSend` was NOT called and the leader was inserted into the input text

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

### chat-input.tsx change (interface)

```typescript
interface ChatInputProps {
  onSend: (message: string, attachments?: AttachmentRef[]) => void;
  onAtTrigger: (query: string, cursorPosition: number) => void;
  onAtDismiss: () => void;
  disabled?: boolean;
  placeholder?: string;
  conversationId?: string;
  insertRef?: React.MutableRefObject<((text: string, replaceFrom: number) => void) | null>;
  /** When true, Enter key defers to the @mention dropdown instead of sending. */
  atMentionVisible?: boolean;
}
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

### Research Insights: Performance Considerations

**`rerender-dependencies` (Vercel React Best Practices):** The `atMentionVisible` boolean is a primitive value, so adding it to the `useCallback` dependency array is cheap -- React can compare it by value without triggering unnecessary re-renders. This is the correct pattern per the Vercel guidelines: "Use primitive dependencies in effects."

**`client-event-listeners` (Vercel React Best Practices):** The `AtMentionDropdown` currently adds/removes a `document` keydown listener on every visibility change. This is correct behavior (cleanup on `visible=false`), but if the component re-renders frequently, consider moving to the `useLatest` ref pattern for the callback to avoid listener churn. Not needed for this fix since the listener lifecycle is already gated on `visible`.

### Research Insights: Accessibility Improvements (Deferred)

The following improvements align with the WAI-ARIA combobox pattern but are out of scope for this bug fix. File as separate issues if desired:

1. **`aria-expanded` on textarea:** When the dropdown is visible, the textarea should have `aria-expanded="true"` and reference the listbox via `aria-controls`. This lets screen readers announce that a popup is available.

2. **`aria-activedescendant` on textarea:** When a dropdown item is highlighted, set `aria-activedescendant` on the textarea to the `id` of the active option. This lets screen readers announce the focused option without moving DOM focus.

3. **`Tab` key closes dropdown:** Per WAI-ARIA, pressing Tab when the popup is open should close the popup and move focus normally. Currently Tab does nothing special when the dropdown is open.

4. **Dropdown footer hint update:** The footer shows `up/down to navigate` but does not mention `Enter to select` or `Esc to dismiss`. Adding these hints improves discoverability.

## References

- Related issue: #2160
- WAI-ARIA Combobox Pattern: [W3C APG Combobox](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/)
- React Event Handling: [React.dev Responding to Events](https://react.dev/learn/responding-to-events)
- AtMentionDropdown component: `apps/web-platform/components/chat/at-mention-dropdown.tsx`
- ChatInput component: `apps/web-platform/components/chat/chat-input.tsx`
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- Learning: `knowledge-base/project/learnings/2026-03-27-tag-and-route-multi-leader-architecture.md`
- Learning: `knowledge-base/project/learnings/2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md`
