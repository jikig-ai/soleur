---
title: "fix: a11y focus indicators, screen reader announcements, and contrast across Phase 1 screens"
type: fix
date: 2026-04-02
---

# fix: a11y focus indicators, screen reader announcements, and contrast across Phase 1 screens

## Overview

Cross-cutting accessibility issues across all 9 Phase 1 screens identified by UX audit. Three systemic problems affect 27 P1 items total but are resolvable with 3 global fixes plus 1 targeted CSS addition for chat message overflow.

Closes #1382

## Problem Statement

1. **No visible focus indicators** -- Every interactive element uses `focus:outline-none` without an adequate replacement. Keyboard users cannot see which element is focused.
2. **Error messages lack `role="alert"`** -- Across all screens, error `<p>` tags are invisible to screen readers. Error announcements are not programmatically conveyed.
3. **`text-neutral-600` fails WCAG AA** -- ~3.8:1 contrast ratio on `bg-neutral-950` background, used in dashboard hints and chat UI. WCAG AA requires 4.5:1 for normal text, 3:1 for large text.
4. **Chat messages lack `overflow-wrap: anywhere`** -- Long unbroken strings (URLs, code) can cause horizontal overflow in message bubbles.

## Proposed Solution

### Fix 1: Global focus-visible ring via CSS base layer

Add a global `focus-visible` ring style in `apps/web-platform/app/globals.css` using `@layer base`. This provides visible focus indicators without removing `focus:outline-none` from individual components (the outline-none suppresses the browser default; the new ring replaces it).

**Target file:** `apps/web-platform/app/globals.css`

```css
@layer base {
  :where(a, button, input, textarea, select, [tabindex]:not([tabindex="-1"])) {
    @apply focus-visible:ring-2 focus-visible:ring-amber-500 focus-visible:ring-offset-2 focus-visible:ring-offset-neutral-950 focus-visible:outline-none;
  }
}
```

The `:where()` selector keeps specificity at 0 so component-level overrides (e.g., the delete dialog's `focus:ring-red-700`) still win. The `focus-visible` pseudo-class only fires on keyboard navigation, not mouse clicks.

**Affected files (10 instances of `focus:outline-none`):**

- `apps/web-platform/app/(auth)/setup-key/page.tsx` (1)
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` (2)
- `apps/web-platform/app/(auth)/signup/page.tsx` (2)
- `apps/web-platform/app/(auth)/login/page.tsx` (2)
- `apps/web-platform/components/chat/chat-input.tsx` (1)
- `apps/web-platform/components/settings/key-rotation-form.tsx` (1)
- `apps/web-platform/components/settings/delete-account-dialog.tsx` (1)

After adding the global base layer rule, the per-component `focus:outline-none` classes become redundant for outline suppression (the global rule handles it). However, two settings components (`key-rotation-form.tsx`, `delete-account-dialog.tsx`) have intentional custom focus rings (`focus:ring-1 focus:ring-amber-600` and `focus:ring-1 focus:ring-red-700`). These should be preserved and converted to `focus-visible:` variants to match the global pattern.

### Fix 2: Add `role="alert"` to all error message elements

Add `role="alert"` to every conditional error `<p>` element so screen readers announce errors immediately when they appear.

**Affected files (11 instances):**

- `apps/web-platform/app/(auth)/setup-key/page.tsx:84`
- `apps/web-platform/app/(auth)/signup/page.tsx:84,130`
- `apps/web-platform/app/(auth)/connect-repo/page.tsx:444`
- `apps/web-platform/app/(auth)/accept-terms/page.tsx:76`
- `apps/web-platform/app/(auth)/login/page.tsx:111,157`
- `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx:95`
- `apps/web-platform/components/auth/oauth-buttons.tsx:99`
- `apps/web-platform/components/settings/key-rotation-form.tsx:74`
- `apps/web-platform/components/settings/delete-account-dialog.tsx:85`

Each follows the same pattern:

```tsx
// Before
{error && <p className="text-sm text-red-400">{error}</p>}

// After
{error && <p className="text-sm text-red-400" role="alert">{error}</p>}
```

### Fix 3: Replace `text-neutral-600` with `text-neutral-500` in hint/helper text

`text-neutral-600` on `bg-neutral-950` yields ~3.8:1 contrast. `text-neutral-500` yields ~5.6:1, comfortably above WCAG AA 4.5:1.

**Affected files (text content instances only -- excluding icons and placeholder text):**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:174` -- "Send a message to get started"
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:265` -- input hint bar
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx:132` -- dashboard hint
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx:165` -- section label
- `apps/web-platform/components/chat/at-mention-dropdown.tsx:117` -- keyboard hint
- `apps/web-platform/app/(auth)/connect-repo/page.tsx:641` -- provider hint
- `apps/web-platform/app/(auth)/connect-repo/page.tsx:800` -- conditional text class

**Note:** `placeholder:text-neutral-600` in `key-rotation-form.tsx:68` and `delete-account-dialog.tsx:79` also uses `text-neutral-600` but for placeholder text, which is exempt from WCAG contrast requirements since it is not "real" content. Change these to `placeholder:text-neutral-500` anyway for consistency.

### Fix 4: Add `overflow-wrap: anywhere` to chat message bubbles

Add `break-anywhere` (Tailwind's `overflow-wrap: anywhere` utility, or a custom class if the version does not include it) to the `<p>` element inside `MessageBubble`.

**Affected file:**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:326`

```tsx
// Before
<p className="whitespace-pre-wrap">{content}</p>

// After
<p className="whitespace-pre-wrap break-all">{content}</p>
```

Note: Tailwind v4 may use `overflow-wrap-anywhere` or `break-all` -- verify the correct utility class. `break-all` (`word-break: break-all`) is the most broadly supported fallback.

## Technical Considerations

- **CSS layer ordering**: The project constitution specifies `@layer` ordering as `reset, tokens, base, layout, components, utilities`. The new focus rule goes in `base`, which is correct. Verify `globals.css` imports Tailwind before the `@layer components` block (it does -- line 1 is `@import "tailwindcss"`).
- **No Tailwind config file**: The project uses Tailwind v4 CSS-first configuration (`@import "tailwindcss"` in globals.css). No `tailwind.config.ts` exists. Custom utilities are added directly in CSS.
- **`:where()` specificity**: Using `:where()` ensures the global focus ring has zero specificity, so any component-level `focus-visible:ring-*` class wins without `!important`.
- **`focus-visible` vs `focus`**: `focus-visible` only triggers on keyboard navigation (Tab, Shift+Tab), not mouse clicks. This is the correct behavior -- users clicking an input do not need a focus ring, but keyboard users do.

## Acceptance Criteria

- [ ] All interactive elements have visible focus indicators on keyboard Tab navigation
- [ ] All error messages are announced by screen readers (`role="alert"` present)
- [ ] All text meets WCAG AA contrast ratios (4.5:1 normal text, 3:1 large text)
- [ ] Chat messages with long unbroken strings do not cause horizontal overflow
- [ ] Existing custom focus rings on settings forms (amber, red) are preserved
- [ ] No visual regressions on mouse-click interactions (focus rings should not appear on click)

## Test Scenarios

- Given a user tabs through the login page, when focus lands on the email input, then a visible amber ring appears around the input
- Given a user submits the signup form with invalid data, when the error message appears, then a screen reader announces the error text immediately
- Given the dashboard page loads, when examining hint text elements, then all have a contrast ratio of at least 4.5:1 against the background
- Given a chat message contains a 200-character unbroken URL, when rendered in the message bubble, then the text wraps without horizontal overflow
- Given a user clicks a button with a mouse, when the click completes, then no focus ring is visible (focus-visible only fires on keyboard)
- Given the delete account dialog input, when tabbed into, then the red focus ring appears (not the global amber ring)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a CSS/HTML accessibility bug fix with no marketing, legal, operations, product strategy, sales, finance, or support impact. Product/UX gate: NONE (modifies existing UI classes, not page structure or user flows).

## Implementation Notes

### Phase 1: Global focus-visible ring + overflow-wrap

1. Edit `apps/web-platform/app/globals.css` to add the `@layer base` focus-visible rule
2. Edit `MessageBubble` in chat page to add `break-all` to the message `<p>` element

### Phase 2: Error message `role="alert"`

3. Add `role="alert"` to all 11 error `<p>` elements across 8 files

### Phase 3: Contrast fix

4. Replace `text-neutral-600` with `text-neutral-500` across 7 files (text content instances)
5. Replace `placeholder:text-neutral-600` with `placeholder:text-neutral-500` in 2 settings files

### Phase 4: Cleanup (optional)

6. Convert per-component `focus:outline-none` to `focus-visible:outline-none` for consistency (the global rule makes these redundant, but explicit is better)
7. Convert `focus:border-neutral-500` to `focus-visible:border-neutral-500` on input elements for consistency

## References

- Related issue: [#1382](https://github.com/jikig-ai/soleur/issues/1382)
- WCAG 2.1 AA Success Criterion 1.4.3 (Contrast Minimum)
- WCAG 2.1 AA Success Criterion 2.4.7 (Focus Visible)
- WCAG 2.1 AA Success Criterion 4.1.3 (Status Messages)
- Tailwind CSS `focus-visible` docs
