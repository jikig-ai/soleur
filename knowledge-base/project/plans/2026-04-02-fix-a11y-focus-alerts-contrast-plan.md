# fix: a11y focus indicators, screen reader announcements, and contrast across Phase 1 screens

**Issue:** #1382 | **Type:** bug fix | **Effort:** Medium | **Milestone:** Phase 2: Secure for Beta

## Problem

Cross-cutting accessibility issues across all 9 Phase 1 screens (27 P1 items from UX audit):

1. **No visible focus indicators** — `focus:outline-none` used in 7 files without adequate replacement. Keyboard users cannot see which element is focused.
2. **Error messages lack `role="alert"`** — Zero `role="alert"` usage anywhere in the codebase. Screen readers cannot announce errors.
3. **`text-neutral-600` fails WCAG AA** — ~3.8:1 contrast ratio on dark backgrounds (needs 4.5:1 for normal text, 3:1 for large).
4. **Chat messages overflow** — Long unbroken strings (URLs) cause horizontal scroll.

## Approach

Three global fixes plus one component fix, all independent:

### Fix 1: Focus indicators via Tailwind base layer

Add a `@layer base` rule in `apps/web-platform/app/globals.css` that applies `focus-visible:ring-2 ring-amber-500 ring-offset-2 ring-offset-neutral-950` to all interactive elements. Uses `:focus-visible` (not `:focus`) so mouse clicks don't trigger rings.

**Files:**

- `apps/web-platform/app/globals.css` — Add `@layer base` focus rule

**Note:** Two components (`key-rotation-form.tsx`, `delete-account-dialog.tsx`) already have custom `focus:ring` styles. In Tailwind v4, `@layer base` rules have lower specificity than utility classes, so the existing component-level `focus:ring-red-700` and `focus:ring-amber-600` utilities will naturally win. No `:where()` wrapper needed. The existing `focus:outline-none` declarations can stay — they suppress the browser's default outline, not box-shadow rings.

### Fix 2: Screen reader announcements

Add `role="alert"` to all error message `<p>` elements and the `ErrorCard` container.

**Files (11 locations):**

- `apps/web-platform/app/(auth)/setup-key/page.tsx` — error `<p>`
- `apps/web-platform/app/(auth)/signup/page.tsx` — 2 error `<p>` elements
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` — error `<p>`
- `apps/web-platform/app/(auth)/accept-terms/page.tsx` — error `<p>`
- `apps/web-platform/app/(auth)/login/page.tsx` — 2 error `<p>` elements
- `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx` — error `<p>`
- `apps/web-platform/components/auth/oauth-buttons.tsx` — error `<p>`
- `apps/web-platform/components/settings/key-rotation-form.tsx` — error `<p>`
- `apps/web-platform/components/settings/delete-account-dialog.tsx` — error `<p>`
- `apps/web-platform/components/ui/error-card.tsx` — container `<div>`

### Fix 3: Contrast ratio

Replace `text-neutral-600` with `text-neutral-400` in hint/secondary text. On neutral-950 background (#0a0a0a):

- neutral-600 (#525252): 2.53:1 — fails WCAG AA (normal and large)
- neutral-500 (#737373): 4.18:1 — fails WCAG AA normal (passes large only)
- neutral-400 (#a3a3a3): 7.85:1 — passes WCAG AA comfortably

**Files (6):**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — lines 174, 265
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — lines 132, 165
- `apps/web-platform/components/chat/at-mention-dropdown.tsx` — line 117
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` — lines 641, 800
- `apps/web-platform/components/settings/key-rotation-form.tsx` — `placeholder:text-neutral-400`
- `apps/web-platform/components/settings/delete-account-dialog.tsx` — `placeholder:text-neutral-400`

### Fix 4: Chat message overflow

Add `overflow-wrap: anywhere` to message bubble `<p>` in the chat conversation page.

**Files:**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — MessageBubble `<p>` element (~line 326)

## Acceptance Criteria

- [ ] All interactive elements have visible focus indicators (amber ring on focus-visible)
- [ ] Custom focus rings on key-rotation-form and delete-account-dialog are preserved
- [ ] Mouse clicks do not trigger focus rings (focus-visible, not focus)
- [ ] All error messages have `role="alert"` for screen reader announcement
- [ ] All text meets WCAG AA contrast ratios (4.5:1 normal, 3:1 large)
- [ ] Chat messages with long unbroken strings wrap without horizontal overflow

## Test Scenarios

### Browser QA

1. Tab through login/signup pages — verify visible amber focus ring
2. Verify delete dialog shows red focus ring (not overridden by global amber)
3. Verify mouse clicks do not trigger focus rings
4. Paste a long unbroken URL in chat — verify it wraps
5. Verify hint text is readable against dark background (neutral-400 on neutral-950)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — accessibility bug fix on existing screens.

## Implementation Notes

- **Tailwind v4**: Uses `@import "tailwindcss"` (not v3 config). `@layer base` works the same.
- **No existing a11y patterns**: This is the first accessibility work in the codebase. Patterns established here set the precedent.
- **All fixes are independent**: Can be implemented in any order. No dependencies between them.
