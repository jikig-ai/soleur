---
title: "fix: chat input vertical alignment and placeholder consolidation"
type: fix
date: 2026-04-12
---

# fix: Chat input vertical alignment and placeholder consolidation

## Problem

The chat input bar has two visual defects:

1. **Vertical misalignment:** The textarea input sits higher than the attachment button (paperclip) and send button (orange arrow). All three elements should be vertically centered on the same baseline.
2. **Hint text placement:** The "Type @ to switch leader" text renders as a separate element below the input bar. It should be part of the textarea placeholder text, alongside "Follow up or ask another question...".

Screenshot reference: `/home/jean/Pictures/Screenshots/Screenshot From 2026-04-12 18-26-24.png`

## Root Cause Analysis

### Issue 1: Vertical misalignment

In `apps/web-platform/components/chat/chat-input.tsx`, line 389:

```tsx
<div className="flex items-end gap-2">
```

The flex container uses `items-end` (align-items: flex-end), which aligns elements to the bottom of the container. The textarea has `py-3` padding while the buttons have a fixed `h-[44px]`. Because the textarea's natural height (driven by content + padding) differs from the button height, `items-end` does not produce visual centering -- the textarea appears to float higher.

**Fix:** Change `items-end` to `items-center` so all three elements (attachment button, textarea, send button) are vertically centered in the flex row.

### Issue 2: Hint text outside input

In `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`, lines 348-361:

```tsx
<div className="mx-auto mt-1 flex max-w-3xl items-center justify-between text-xs text-neutral-400">
  <span className="md:hidden">
    {/* mobile usage data */}
  </span>
  <span className="ml-auto hidden md:inline">Type @ to switch leader</span>
</div>
```

The "Type @ to switch leader" text is a separate `<span>` in a `<div>` below the `ChatInput` component. It should be merged into the placeholder prop passed to `ChatInput`.

**Fix:** Remove the desktop hint span and append the text to the placeholder string. The mobile usage data `<span>` (lines 349-358) still needs a container, but the desktop `@` hint moves into the placeholder.

## Implementation

### File 1: `apps/web-platform/components/chat/chat-input.tsx`

**Change:** Line 389, change `items-end` to `items-center`.

```diff
- <div className="flex items-end gap-2">
+ <div className="flex items-center gap-2">
```

### File 2: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

**Change 1:** Update the placeholder prop on `ChatInput` (around line 341) to include the `@` hint:

```diff
  placeholder={
    status === "connected"
-     ? "Follow up or ask another question..."
+     ? "Follow up or ask another question... Type @ to switch leader"
      : "Reconnecting..."
  }
```

**Change 2:** Remove the desktop-only `@` hint span (line 360):

```diff
  <div className="mx-auto mt-1 flex max-w-3xl items-center justify-between text-xs text-neutral-400">
    <span className="md:hidden">
      {activeLeaderIds.length > 0 && (
        <>{activeLeaderIds.length} leaders responding</>
      )}
      {usageData && usageData.totalCostUsd > 0 && (
        <span className="text-neutral-400">
          {activeLeaderIds.length > 0 && " \u00b7 "}
          ~${usageData.totalCostUsd.toFixed(4)} est.
        </span>
      )}
    </span>
-   <span className="ml-auto hidden md:inline">Type @ to switch leader</span>
  </div>
```

**Note:** After removing the desktop hint, evaluate whether the outer `<div>` wrapper is still needed. It contains only the mobile usage-data span. If there are no active leaders and no usage data, the div renders empty content (which is fine -- no visual impact). Keep the wrapper for the mobile cost display.

### File 3: `apps/web-platform/test/chat-input.test.tsx`

**Change:** Update the existing placeholder test (line 24-27) to reflect the new default placeholder, if the test asserts on the default value. The current default in the component is "Ask your team anything... or @mention a leader" -- this is NOT the placeholder shown on the chat page (the page overrides it). The test may not need changes since the component's default placeholder is separate from the page-level placeholder. Verify during implementation.

## Acceptance Criteria

- [ ] The attachment button, text input, and send button are vertically centered (not bottom-aligned) in the chat input bar
- [ ] The placeholder text reads "Follow up or ask another question... Type @ to switch leader" when connected
- [ ] The "Type @ to switch leader" text no longer appears as a separate element below the input bar
- [ ] Mobile layout still shows usage data below the input bar (the mobile `<span>` is preserved)
- [ ] The "Reconnecting..." placeholder does not include the `@` hint text
- [ ] Existing tests pass without modification (or are updated if they assert on the affected text)

## Test Scenarios

- Given the chat page is loaded and connected, when inspecting the input bar, then all three elements (paperclip, textarea, send button) are vertically aligned to center
- Given the chat page is loaded and connected, when the textarea is empty, then the placeholder reads "Follow up or ask another question... Type @ to switch leader"
- Given the chat page is reconnecting, when the textarea is empty, then the placeholder reads "Reconnecting..."
- Given the chat page is loaded on mobile, when there are active leaders, then the usage data still appears below the input bar
- Given the chat page is loaded on desktop, when inspecting below the input bar, then no "Type @ to switch leader" text is present as a separate element

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- UI alignment bug fix with no business logic changes.

## References

- `apps/web-platform/components/chat/chat-input.tsx` -- ChatInput component with flex layout
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- Chat page with placeholder and hint text
- `apps/web-platform/test/chat-input.test.tsx` -- Existing ChatInput tests
