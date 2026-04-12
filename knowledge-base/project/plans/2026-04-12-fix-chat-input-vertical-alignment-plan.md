---
title: "fix: chat input bar vertical alignment"
type: fix
date: 2026-04-12
---

# fix: Chat input bar vertical alignment

## Overview

The chat input footer area has a vertical alignment bug. The attachment (paperclip) button, text input field (textarea), and send button are not properly aligned vertically. The root cause is a mismatch between the fixed-height buttons (44px) and the textarea's computed height, combined with the use of `items-end` flex alignment which anchors everything to the bottom edge rather than centering elements vertically.

## Problem Statement

In `apps/web-platform/components/chat/chat-input.tsx`, the input bar container (line 389) uses:

```tsx
<div className="flex items-end gap-2">
```

The three children have different intrinsic heights:

- **Attachment button:** Fixed `h-[44px] w-[44px]` (44px)
- **Textarea:** `rows={1}` with `py-3` (12px top + 12px bottom) + `text-sm` (14px line-height) = ~38px computed height, but varies with content
- **Send button:** Fixed `h-[44px] w-[44px]` (44px)

With `items-end`, all three are pushed to the bottom of the flex container. When the textarea is shorter than the buttons, a visible gap appears above the textarea while the buttons sit flush at the bottom -- creating a visually misaligned row.

The `items-end` choice was likely intentional for when the textarea grows to multiple lines (the buttons should stay at the bottom). However, with `rows={1}` (the default single-line state), the visual result is misalignment.

## Proposed Solution

Apply two changes to `apps/web-platform/components/chat/chat-input.tsx`:

### 1. Match textarea height to button height

Set a minimum height on the textarea that matches the buttons' 44px, ensuring consistent alignment in the default single-line state:

```tsx
// Before
className="w-full resize-none rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 pr-12 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50"

// After
className="w-full resize-none rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 pr-12 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50 min-h-[44px]"
```

### 2. Keep `items-end` for multi-line behavior

The `items-end` alignment is correct for the multi-line textarea case (buttons stay anchored to the bottom when the textarea expands). With the `min-h-[44px]` fix, the single-line case will have all three elements at the same 44px height, eliminating the visual gap while preserving correct behavior when the textarea grows.

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/components/chat/chat-input.tsx:425` | Add `min-h-[44px]` to textarea className |

### Why not `items-center`?

Changing `items-end` to `items-center` would fix single-line alignment but break the multi-line case. When a user types several lines and the textarea expands, `items-center` would push the buttons to the vertical middle of the expanded textarea rather than keeping them at the bottom alongside the last line. `items-end` is the correct behavior; the real fix is ensuring consistent element heights.

## Acceptance Criteria

- [ ] Attachment button, textarea, and send button are vertically aligned in the default single-line state
- [ ] When the textarea expands to multiple lines, the buttons remain anchored at the bottom
- [ ] The fix applies to both the chat page (`/dashboard/chat/[conversationId]`) and any other consumer of the ChatInput component
- [ ] No visual regression in mobile view (the mobile @ button inside the textarea remains correctly positioned)
- [ ] Existing tests in `apps/web-platform/test/chat-input.test.tsx` continue to pass

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

## Context

The chat input component was recently updated in PR #1975 (feat: chat file attachments) which added the attachment button. The original textarea + send button layout used `items-center` before the attachment button was added. The attachment button introduction changed the flex alignment to `items-end` without adjusting the textarea height to match the 44px buttons.

### Related files

- `apps/web-platform/components/chat/chat-input.tsx` -- primary fix target
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- consumer
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- has a similar pattern on the first-run input (not affected, uses a standard `<input>` that matches button height)
- `apps/web-platform/test/chat-input.test.tsx` -- existing tests to verify
- `apps/web-platform/test/chat-input-attachments.test.tsx` -- attachment-specific tests

## References

- Related PR: #1975 (chat file attachments)
- Tailwind v4 docs: `min-h-[44px]` arbitrary value utility
