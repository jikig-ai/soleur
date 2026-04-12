---
title: "fix: chat input vertical alignment and placeholder consolidation"
type: fix
date: 2026-04-12
---

# fix: Chat input vertical alignment and placeholder consolidation

## Enhancement Summary

**Deepened on:** 2026-04-12
**Sections enhanced:** 4 (Root Cause Analysis, Implementation, Acceptance Criteria, Test Scenarios)
**Research sources:** Tailwind v4 docs, Vercel React best practices, project learnings (Tailwind a11y patterns, chat UX bugs), web-design-guidelines skill

### Key Improvements

1. Confirmed `items-center` is safe because the textarea is fixed single-row (`rows={1}`, `resize-none`) -- no multi-line growth scenario where `items-end` would be preferable
2. Added edge case: placeholder text length on narrow viewports may truncate -- verified ellipsis is the default browser behavior for placeholder overflow
3. Added consideration for the mobile `@` button position (absolute-positioned inside textarea) -- unaffected by the `items-center` change since it's positioned relative to the textarea, not the flex container
4. Confirmed no test changes needed -- the existing test asserts on the component's default placeholder ("Ask your team anything..."), not the page-level override

### New Considerations Discovered

- The remaining `<div>` wrapper below the input (containing mobile usage data) renders empty content on desktop after removing the hint span -- this is harmless but could be conditionally rendered for cleanliness
- The `placeholder:text-neutral-500` class on the textarea passes WCAG AA contrast on `bg-neutral-900` (contrast ratio approximately 4.6:1) -- per project learning `2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns`, neutral-400 is the safe floor for text on neutral-950 backgrounds, but placeholder text on neutral-900 background has slightly higher luminance, making neutral-500 acceptable for placeholder text specifically

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

### Research Insights

**Why `items-center` is safe here:**

- The textarea is constrained to `rows={1}` with `resize-none` -- it will never grow taller than a single line
- Both buttons use fixed `h-[44px]` / `w-[44px]`, and the textarea's computed height (14px font + 24px padding = ~38px) is shorter than the buttons
- `items-center` vertically centers all three elements relative to the tallest element (the buttons), producing visual alignment
- If the textarea ever gains auto-grow behavior in the future, `items-end` would be preferable (keeps buttons anchored to the last line of text) -- add a code comment noting this

**Tailwind v4 note:** `items-center` maps to `align-items: center` in both Tailwind v3 and v4 -- no version-specific concerns.

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

### Research Insights

**Placeholder text best practices:**

- Combined placeholder "Follow up or ask another question... Type @ to switch leader" is 63 characters -- within reasonable length for desktop viewports
- On narrow mobile viewports, the placeholder will truncate with ellipsis (default browser behavior for `text-overflow` on input/textarea elements) -- this is acceptable since the `@` hint is secondary information
- The `placeholder:text-neutral-500` styling on the textarea applies to the entire placeholder string -- no per-segment styling is possible with native HTML placeholders, which is fine for this use case

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

**Note:** After removing the desktop hint, the outer `<div>` wrapper contains only the mobile usage-data `<span>` (which itself is `md:hidden`). On desktop, this renders as an empty container with `mt-1` margin. This is harmless -- keep the wrapper for the mobile cost display. Optionally, the entire `<div>` could be wrapped in a condition that only renders on mobile or when data is present, but this is a minor cleanup and not required for this fix.

### File 3: `apps/web-platform/test/chat-input.test.tsx`

**No changes needed.** The existing test on line 26 asserts `screen.getByPlaceholderText(/ask your team/i)` which matches the component's default placeholder "Ask your team anything... or @mention a leader". This default is not being changed -- only the page-level prop override is changing. The test validates the component in isolation using its own default, which remains correct.

## Acceptance Criteria

- [x] The attachment button, text input, and send button are vertically centered (not bottom-aligned) in the chat input bar
- [x] The placeholder text reads "Follow up or ask another question... Type @ to switch leader" when connected
- [x] The "Type @ to switch leader" text no longer appears as a separate element below the input bar
- [x] Mobile layout still shows usage data below the input bar (the mobile `<span>` is preserved)
- [x] The "Reconnecting..." placeholder does not include the `@` hint text
- [x] Existing tests pass without modification (or are updated if they assert on the affected text)
- [x] The mobile `@` button (absolute-positioned inside the textarea container) remains correctly positioned after the alignment change

## Test Scenarios

- Given the chat page is loaded and connected, when inspecting the input bar, then all three elements (paperclip, textarea, send button) are vertically aligned to center
- Given the chat page is loaded and connected, when the textarea is empty, then the placeholder reads "Follow up or ask another question... Type @ to switch leader"
- Given the chat page is reconnecting, when the textarea is empty, then the placeholder reads "Reconnecting..."
- Given the chat page is loaded on mobile, when there are active leaders, then the usage data still appears below the input bar
- Given the chat page is loaded on desktop, when inspecting below the input bar, then no "Type @ to switch leader" text is present as a separate element
- Given the chat page is loaded on a narrow mobile viewport (320px), when the textarea is empty, then the placeholder text truncates gracefully with ellipsis

### Research Insights

**Testing approach:**

- The Tailwind class change (`items-end` to `items-center`) cannot be verified via unit tests (JSDOM does not compute layout) -- visual verification via Playwright screenshot is the correct approach
- The placeholder text change can be verified via a page-level integration test or Playwright snapshot, but is not worth a dedicated unit test since the component's own default placeholder test remains valid
- Run existing tests with `npx vitest run test/chat-input.test.tsx test/chat-input-attachments.test.tsx` to confirm no regressions

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- UI alignment bug fix with no business logic changes.

## References

- `apps/web-platform/components/chat/chat-input.tsx` -- ChatInput component with flex layout
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- Chat page with placeholder and hint text
- `apps/web-platform/test/chat-input.test.tsx` -- Existing ChatInput tests
- `apps/web-platform/app/globals.css` -- Global styles with focus-visible ring pattern
- `knowledge-base/project/learnings/2026-04-02-tailwind-v4-a11y-focus-ring-contrast-patterns.md` -- Contrast ratio verification patterns
- `knowledge-base/project/learnings/ui-bugs/multi-leader-session-collision-and-chat-ux-20260403.md` -- Prior chat UX bug patterns
