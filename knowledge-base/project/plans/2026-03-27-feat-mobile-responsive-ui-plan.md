---
title: "feat: mobile-first responsive UI (sidebar to hamburger menu, touch nav)"
type: feat
date: 2026-03-27
issue: "#1041"
milestone: "Phase 1: Close the Loop (Mobile-First, PWA)"
semver: minor
---

# feat: mobile-first responsive UI (sidebar to hamburger menu, touch nav)

## Overview

The current dashboard layout uses a fixed 224px sidebar (`w-56` in `apps/web-platform/app/(dashboard)/layout.tsx`) that consumes approximately 40% of the viewport on a 375px mobile screen. This makes the dashboard unusable on mobile devices -- the primary content area gets only ~151px of width, text wraps awkwardly, and the domain leader grid becomes unreadable.

This plan replaces the fixed sidebar with a collapsible hamburger menu on mobile breakpoints while preserving the desktop sidebar experience. The domain leader selector grid and chat interface are made touch-friendly with appropriately sized tap targets.

**Related issue:** [#1041](https://github.com/jikig-ai/soleur/issues/1041)
**CTO assessment:** Layout architecture change, 2-3 days.

## Problem Statement / Motivation

The Phase 1 milestone ("Close the Loop") requires that a new user can complete the full journey (signup, BYOK, connect repo, multi-turn conversation) on mobile. The current `flex h-screen` + `w-56` sidebar layout makes this impossible:

1. **Sidebar steals 40% of mobile viewport:** At 375px (iPhone SE), the sidebar is 224px, leaving 151px for content. The "Start a conversation" CTA and domain leader cards cannot render legibly.
2. **No responsive breakpoints exist:** The dashboard layout has zero media queries or responsive utility classes. It is purely desktop.
3. **Domain leader grid assumes width:** The `md:grid-cols-2` grid works on tablet+ but the cards need sufficient width to display the leader name, title, and description.
4. **Chat input bar needs touch optimization:** The text input and send button need minimum 44px touch targets per WCAG 2.5.5.
5. **Lighthouse mobile score:** Without mobile optimization, the dashboard will fail the >80 threshold due to layout shift and viewport issues.

## Proposed Solution

A mobile-first responsive approach using Tailwind CSS v4 utility classes (the project already uses `@tailwindcss/postcss` v4.2.1). No new dependencies needed.

### Architecture

**Pattern: Sidebar-to-drawer with CSS-only mobile detection + minimal React state**

1. **Mobile breakpoint:** `max-width: 768px` (Tailwind `md:` prefix threshold). Below this, sidebar becomes an overlay drawer triggered by a hamburger button.
2. **Desktop behavior unchanged:** Above 768px, the sidebar renders as-is with `w-56 flex flex-col`.
3. **Drawer state:** A single `useState<boolean>` in the dashboard layout controls open/close. Closed by default. Auto-closes on route change.
4. **Overlay backdrop:** Semi-transparent backdrop behind the drawer, clickable to dismiss. Use `fixed inset-0` with `bg-black/50`. Per the `backdrop-filter` learning, avoid `backdrop-filter: blur()` on parent elements as it breaks `position: fixed` descendant sizing.
5. **Touch targets:** All interactive elements (nav links, hamburger button, sign-out) get minimum `min-h-[44px] min-w-[44px]` on mobile per WCAG 2.5.5.

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/layout.tsx` | Add hamburger button, mobile drawer state, responsive classes, overlay backdrop, auto-close on navigation |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Make domain leader grid single-column on mobile, increase tap target sizes |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | Touch-optimize input bar, ensure message bubbles do not overflow at 375px |
| `apps/web-platform/app/globals.css` | Add any custom utility classes or transitions not covered by Tailwind utilities |

### No Changes Needed

| File | Reason |
|------|--------|
| Auth pages (`login`, `signup`, `accept-terms`, `setup-key`) | Already mobile-friendly: centered layout with `max-w-sm`, `p-4` padding, no fixed-width elements |
| `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx` | Simple centered placeholder, already responsive |
| `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx` | Already uses `max-w-md`, `p-4`, centered layout -- works at 375px |

## Technical Considerations

### CSS / Tailwind v4

- **Tailwind v4 uses CSS-based config** -- no `tailwind.config.js`. Custom theme values go in `globals.css` via `@theme`.
- The project uses `@import "tailwindcss"` in `globals.css`. Tailwind v4's default breakpoints: `sm: 640px`, `md: 768px`, `lg: 1024px`.
- Constitution mandates CSS in `@layer` cascade layers. The current `globals.css` is minimal (just the import). Custom styles should use `@layer components` or `@layer utilities`.

### State Management

- The layout is already `"use client"` -- adding `useState` for drawer toggle has no SSR impact.
- Route change detection via `usePathname()` (already imported) to auto-close drawer on navigation.

### Known Gotchas (from learnings)

1. **backdrop-filter breaks fixed positioning** (learning: `2026-02-17-backdrop-filter-breaks-fixed-positioning`): Do NOT use `backdrop-filter: blur()` on the overlay. Use `bg-black/50` opacity only. If blur is needed later, use explicit `height: calc(100vh - offset)` instead of `top/bottom` pairs.
2. **Grid divisibility rule** (learning: `2026-02-22-landing-page-grid-orphan-regression`): The domain leader grid has 8 cards. Single column (8/1=8, clean) and two columns (8/2=4, clean) are both safe. Do not use 3-column layout unless the card count changes.
3. **auto-fill grid semantic grouping** (learning: `2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile`): The leader grid uses explicit `grid-cols-1 md:grid-cols-2` (not auto-fill), which is correct and should be preserved.

### Performance

- No new JS libraries. The hamburger toggle is ~10 lines of React state.
- CSS transitions for the drawer slide-in add no bundle weight.
- Eliminating horizontal overflow improves CLS (Cumulative Layout Shift), helping Lighthouse score.

### Accessibility

- Hamburger button must have `aria-label="Toggle navigation"` and `aria-expanded={isOpen}`.
- Drawer must trap focus when open (use `inert` attribute on main content, or a focus-trap utility).
- ESC key closes the drawer.
- Overlay backdrop must be `aria-hidden="true"` with `tabIndex={-1}`.

### Non-goals

- **PWA / service worker** -- separate issue, Phase 1 scope.
- **Dark/light theme toggle** -- not in scope.
- **Tablet-specific breakpoint** -- the `md:` breakpoint covers tablet adequately. The sidebar shows at 768px+.
- **Animated page transitions** -- unnecessary complexity.
- **CSS-only drawer** (checkbox hack) -- React state is simpler and more accessible than the `:checked` pseudo-class pattern.

## Acceptance Criteria

### Functional Requirements

- [ ] At viewport widths below 768px, sidebar is hidden and a hamburger button appears in a top bar
- [ ] Tapping the hamburger button opens a full-height drawer overlay with navigation items and sign-out
- [ ] Tapping the backdrop or a nav link closes the drawer
- [ ] Pressing ESC closes the drawer
- [ ] At viewport widths 768px and above, sidebar renders as the current fixed layout (no regression)
- [ ] Domain leader grid displays as single column on mobile, two columns on desktop
- [ ] All domain leader cards are tappable and link correctly on touch devices
- [ ] Chat input bar and send button have minimum 44px touch targets on mobile
- [ ] Message bubbles do not overflow or cause horizontal scroll at 375px
- [ ] No horizontal scroll on any screen at any viewport width (375px through 1920px+)
- [ ] Dashboard is fully usable on 375px viewport (iPhone SE)

### Non-Functional Requirements

- [ ] Lighthouse mobile score > 80 on the dashboard page
- [ ] No new JS dependencies added
- [ ] Drawer open/close transition completes in < 300ms
- [ ] All interactive elements meet WCAG 2.5.5 touch target size (44x44px minimum)

### Quality Gates

- [ ] Visual verification at 375px, 768px, 1024px, and 1440px viewports
- [ ] Test on iOS Safari (via Playwright WebKit), Android Chrome (via Playwright Chromium), desktop Chrome/Edge
- [ ] No TypeScript errors (`npx tsc --noEmit`)
- [ ] markdownlint passes on all changed markdown files

## Domain Review

**Domains relevant:** Product, Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO flagged this as a layout architecture change. The core risk is in the sidebar-to-drawer transition: React state management for the drawer must properly handle route changes, keyboard events, and focus trapping. The approach of using Tailwind responsive utilities with minimal state is architecturally sound -- no new abstractions or component libraries are introduced. The `"use client"` boundary is already established in the layout, so no SSR implications. The main technical risks are: (1) ensuring the drawer does not cause layout shift during open/close animations, (2) handling the `fixed` positioning correctly per the documented backdrop-filter learning, and (3) verifying that the chat WebSocket connection is not disrupted by layout changes.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

This is a modification to an existing page layout, not creation of new user-facing pages. The changes follow standard mobile-responsive patterns (hamburger drawer, single-column grid). Interactive wireframing is not warranted for well-established responsive patterns.

## Test Scenarios

### Acceptance Tests

- Given a 375px viewport, when the dashboard loads, then the sidebar is hidden and a hamburger button is visible in the top bar
- Given a 375px viewport, when the user taps the hamburger button, then a drawer overlay slides in from the left showing all navigation items
- Given the drawer is open, when the user taps the overlay backdrop, then the drawer closes
- Given the drawer is open, when the user taps a navigation link, then the drawer closes and navigation occurs
- Given the drawer is open, when the user presses ESC, then the drawer closes
- Given a 1024px viewport, when the dashboard loads, then the sidebar renders in its fixed 224px layout with no hamburger button
- Given a 375px viewport, when viewing the dashboard, then domain leader cards display in a single column with no horizontal overflow
- Given a 375px viewport, when in the chat view, then the input field and send button each have at least 44px touch targets
- Given any viewport width between 375px and 1920px, when viewing any dashboard page, then there is no horizontal scrollbar

### Edge Cases

- Given a 768px viewport (exact breakpoint), when the dashboard loads, then the desktop sidebar is visible (not the hamburger menu)
- Given the drawer is open and the user rotates from portrait to landscape (crossing 768px), then the drawer closes and sidebar appears
- Given a narrow viewport with a long domain leader description, then text wraps cleanly without overflow

### Browser Verification

- **Playwright WebKit** (iOS Safari proxy): Navigate to `/dashboard` at 375px viewport, verify hamburger menu, tap through domain leaders
- **Playwright Chromium** (Android Chrome proxy): Navigate to `/dashboard` at 375px viewport, verify touch targets, no horizontal scroll
- **Playwright Chromium** (desktop Chrome/Edge): Navigate to `/dashboard` at 1440px viewport, verify desktop sidebar unchanged

### Lighthouse Verification

- Run `npx lighthouse https://localhost:3000/dashboard --only-categories=performance,accessibility --emulated-form-factor=mobile --output=json` and verify performance score > 80

## Success Metrics

- Lighthouse mobile score > 80 on dashboard page
- Zero horizontal scroll at 375px viewport
- All acceptance criteria pass in Playwright tests
- No regressions on desktop layout

## Dependencies and Risks

**Dependencies:**

- None. Tailwind v4 and React are already available. No new packages needed.

**Risks:**

- **Low:** Chat WebSocket connection may need testing during drawer open/close to ensure no disruption
- **Low:** Focus trapping in the drawer may need the native `inert` attribute (supported in all modern browsers) rather than a library
- **Medium:** Lighthouse >80 may require additional performance work beyond layout (e.g., image optimization, code splitting) -- but the layout changes should meaningfully improve CLS

## References and Research

### Internal References

- Dashboard layout: `apps/web-platform/app/(dashboard)/layout.tsx` -- current sidebar implementation
- Dashboard page: `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- domain leader grid
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- message list and input bar
- Domain leaders data: `apps/web-platform/server/domain-leaders.ts` -- 8 leaders
- Learning: `knowledge-base/project/learnings/2026-02-17-backdrop-filter-breaks-fixed-positioning.md`
- Learning: `knowledge-base/project/learnings/2026-02-22-landing-page-grid-orphan-regression.md`
- Learning: `knowledge-base/project/learnings/ui-bugs/2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile.md`

### External References

- [WCAG 2.5.5 Target Size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html) -- 44x44px minimum touch targets
- [Tailwind CSS v4 Responsive Design](https://tailwindcss.com/docs/responsive-design) -- mobile-first breakpoint utilities
- [MDN inert attribute](https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/inert) -- focus trapping without JS libraries
