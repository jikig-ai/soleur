---
title: "fix: chat input bar vertical alignment"
type: fix
date: 2026-04-12
deepened: 2026-04-12
---

# fix: Chat input bar vertical alignment

## Enhancement Summary

**Deepened on:** 2026-04-12
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Test Scenarios, Context)
**Research sources used:** Tailwind CSS v4 docs (Context7), project learnings (flex layout, footer redesign), codebase analysis

### Key Improvements

1. Corrected height calculation analysis -- textarea with `text-sm` + `py-3` + `rows={1}` computes to ~46px (not ~38px), meaning the buttons (44px) are the shorter elements
2. Added `box-sizing: border-box` verification confirming all elements include border in their height calculation
3. Added Tailwind v4 `field-sizing-content` as a consideration for future auto-sizing behavior
4. Added visual verification step using Playwright at multiple breakpoints (institutional learning from footer layout redesign)

### New Considerations Discovered

- The height mismatch may be ~2px (46px textarea vs 44px buttons), not the large gap initially assumed -- visual verification before and after is critical
- Tailwind v4 provides `field-sizing-content` utility for content-based textarea sizing, which could interact with `min-h-[44px]`
- The mobile @ button uses `absolute bottom-2.5` positioning which remains stable regardless of textarea height changes

## Overview

The chat input footer area has a vertical alignment bug. The attachment (paperclip) button, text input field (textarea), and send button are not properly aligned vertically. The root cause is a mismatch between the fixed-height buttons (44px) and the textarea's computed height, combined with the use of `items-end` flex alignment which anchors everything to the bottom edge rather than centering elements vertically.

## Problem Statement

In `apps/web-platform/components/chat/chat-input.tsx`, the input bar container (line 389) uses:

```tsx
<div className="flex items-end gap-2">
```

The three children have different intrinsic heights:

- **Attachment button:** Fixed `h-[44px] w-[44px]` (44px outer, includes 1px border via `box-sizing: border-box`)
- **Textarea:** `rows={1}` with `py-3` (12px top + 12px bottom) + `text-sm` (14px font / 20px line-height) + 1px border top + 1px border bottom = ~46px computed height, but varies with content and browser rendering
- **Send button:** Fixed `h-[44px] w-[44px]` (44px outer, no border -- solid bg)

With `items-end`, all three are pushed to the bottom of the flex container. Since the textarea (~46px) is slightly taller than the buttons (44px), a small gap appears above the buttons -- creating a visually misaligned row. The exact pixel difference depends on the browser's textarea line-height computation for `text-sm` with `rows={1}`.

### Research Insights

**Height calculation detail (Tailwind v4 + border-box):**

Tailwind v4 applies `box-sizing: border-box` globally via its reset layer. This means:

- Attachment button: `h-[44px]` = 44px total including 1px border = 42px content + 2px border
- Send button: `h-[44px]` = 44px total (no border, solid background)
- Textarea: `py-3` (24px) + content-height (`rows=1` * `line-height: 1.25rem` = 20px) + border (2px) = 46px total

The `items-end` choice was likely intentional for when the textarea grows to multiple lines (the buttons should stay at the bottom). However, with `rows={1}` (the default single-line state), the visual result is misalignment because the three elements have different total heights.

**Institutional learning applied:** The project has a documented learning (`footer-layout-redesign-flex-children-visual-verification-20260402.md`) that warns: "Always verify flex layout changes at desktop, tablet, AND mobile breakpoints with screenshots before committing." This applies directly -- the fix must be visually verified at multiple breakpoints.

## Proposed Solution

Apply a single change to `apps/web-platform/components/chat/chat-input.tsx`:

### 1. Match textarea height to button height

Set a minimum height on the textarea that matches the buttons' 44px, ensuring consistent alignment in the default single-line state:

```tsx
// Before (line 425)
className="w-full resize-none rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 pr-12 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50"

// After
className="w-full resize-none rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 pr-12 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50 min-h-[44px]"
```

### 2. Keep `items-end` for multi-line behavior

The `items-end` alignment is correct for the multi-line textarea case (buttons stay anchored to the bottom when the textarea expands). With the `min-h-[44px]` fix, the single-line case will have all three elements at the same baseline height, eliminating or minimizing the visual gap while preserving correct behavior when the textarea grows.

### Research Insights

**Why `min-h-[44px]` is safe with `box-sizing: border-box`:**

Tailwind v4's reset sets `box-sizing: border-box` globally. The `min-h-[44px]` arbitrary value utility compiles to `min-height: 44px`, which in border-box mode includes padding and border. If the textarea's natural height (46px with current padding) exceeds this minimum, the `min-h` is a no-op for the single-line case -- but it prevents the textarea from ever being shorter than the buttons if padding or font-size changes in the future.

**Browser-specific textarea rendering:**

Different browsers compute `rows={1}` textarea height slightly differently. Some browsers may render the textarea at exactly 44px, others at 46px. The `min-h-[44px]` ensures a floor that matches the button height regardless of browser rendering.

**Tailwind v4 `field-sizing-content` consideration:**

Tailwind v4 introduces `field-sizing-content` which makes textareas auto-size to their content. If this utility is applied in the future, `min-h-[44px]` would still serve as the floor height, preventing the textarea from collapsing below button height when empty. No action needed now, but noted for future awareness.

**Alternative considered -- `self-end` on buttons:**

Adding `self-end` to both buttons would be redundant with the container's `items-end` but would make the intent explicit. Not recommended -- it adds noise without changing behavior.

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/components/chat/chat-input.tsx:425` | Add `min-h-[44px]` to textarea className |

### Why not `items-center`?

Changing `items-end` to `items-center` would fix single-line alignment but break the multi-line case. When a user types several lines and the textarea expands, `items-center` would push the buttons to the vertical middle of the expanded textarea rather than keeping them at the bottom alongside the last line. `items-end` is the correct behavior; the real fix is ensuring consistent element heights.

## Acceptance Criteria

- [x] Attachment button, textarea, and send button are vertically aligned in the default single-line state
- [x] When the textarea expands to multiple lines, the buttons remain anchored at the bottom
- [x] The fix applies to both the chat page (`/dashboard/chat/[conversationId]`) and any other consumer of the ChatInput component
- [x] No visual regression in mobile view (the mobile @ button inside the textarea remains correctly positioned)
- [x] Existing tests in `apps/web-platform/test/chat-input.test.tsx` continue to pass

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

This is a CSS-only fix to an existing component. No new pages, no new flows. The existing UI is being corrected to match its intended design.

## Test Scenarios

- Given a fresh chat page load, when the input bar is visible with a single-line textarea, then the attachment button, textarea, and send button tops and bottoms are visually aligned at 44px height
- Given a chat session, when the user types multiple lines causing the textarea to expand, then the attachment and send buttons remain at the bottom of the input row
- Given a mobile viewport, when the input bar is visible, then the mobile @ mention button remains correctly positioned inside the textarea
- Given the input is disabled, when viewing the input bar, then alignment is unchanged (no shift or jump)
- Given attachment previews are shown above the input bar, when the preview strip is visible, then the input bar alignment below it is unaffected

### Research Insights

**Visual verification protocol (from institutional learning):**

Take Playwright screenshots at 3 breakpoints before and after the fix:

1. **Desktop (1280px):** Full input bar visible with attachment button, textarea, and send button
2. **Tablet (768px):** Input bar at medium width, verify no wrapping or overflow
3. **Mobile (375px):** Input bar with mobile @ button visible, verify `md:hidden` @ button positioning

Compare before/after screenshots to confirm the alignment improvement and detect any regressions. This follows the project's documented learning from the footer layout redesign: "Always verify flex layout changes at desktop, tablet, AND mobile breakpoints with screenshots before committing."

**Edge case -- attachment preview strip interaction:**

When attachments are added (preview strip appears above the input bar with `mb-2`), the flex container layout should be unaffected since the preview strip is a sibling, not a flex child of the `items-end` container.

## Context

The chat input component was recently updated in PR #1975 (feat: chat file attachments) which added the attachment button. The original textarea + send button layout used `items-center` before the attachment button was added. The attachment button introduction changed the flex alignment to `items-end` without adjusting the textarea height to match the 44px buttons.

### Research Insights

**Dashboard page consistency check:**

The dashboard page (`apps/web-platform/app/(dashboard)/dashboard/page.tsx`, lines 264-282) has a similar input bar pattern in the first-run state:

```tsx
<div className="flex items-end gap-2">
  <input ... className="flex-1 rounded-xl border ... px-4 py-3 text-sm ..." />
  <button ... className="flex h-[44px] w-[44px] shrink-0 ..." />
</div>
```

This uses a standard `<input>` (single-line by nature) which has more predictable height behavior than a `<textarea>`. It does NOT have an attachment button (only send). The same `items-end` + mismatched heights pattern could theoretically cause a minor misalignment here too, but `<input>` elements typically render closer to the specified padding + line-height than textareas. No fix needed for the dashboard page at this time, but worth visual verification.

### Related files

- `apps/web-platform/components/chat/chat-input.tsx` -- primary fix target
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- consumer
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- has a similar pattern on the first-run input (not affected, uses a standard `<input>` that matches button height)
- `apps/web-platform/test/chat-input.test.tsx` -- existing tests to verify
- `apps/web-platform/test/chat-input-attachments.test.tsx` -- attachment-specific tests
- `apps/web-platform/app/globals.css` -- Tailwind v4 base styles with `safe-bottom` utility used by the input bar container

## References

- Related PR: #1975 (chat file attachments)
- Tailwind v4 docs: `min-h-[44px]` arbitrary value utility ([min-height documentation](https://tailwindcss.com/docs/min-height))
- Tailwind v4 docs: `field-sizing-content` utility for content-based textarea sizing ([field-sizing documentation](https://tailwindcss.com/docs/field-sizing))
- Tailwind v4 docs: `items-end` / `items-center` align-items utilities ([align-items documentation](https://tailwindcss.com/docs/align-items))
- Institutional learning: `knowledge-base/project/learnings/docs-site/footer-layout-redesign-flex-children-visual-verification-20260402.md` -- flex layout changes require multi-breakpoint visual verification
