---
title: "feat: mobile-first responsive UI (sidebar to hamburger menu, touch nav)"
type: feat
date: 2026-03-27
issue: "#1041"
milestone: "Phase 1: Close the Loop (Mobile-First, PWA)"
semver: minor
---

# feat: mobile-first responsive UI (sidebar to hamburger menu, touch nav)

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 8
**Research sources:** Context7 (Next.js, tailwindcss-safe-area), project learnings (3), constitution conventions, codebase analysis (12 files)

### Key Improvements

1. **iOS safe area handling** -- added `env(safe-area-inset-*)` padding for notched devices and home indicator, critical for PWA milestone
2. **Concrete implementation snippets** -- full code examples for layout.tsx drawer, mobile top bar, and CSS transitions ready for copy-paste implementation
3. **`useMediaQuery` hook for orientation change** -- handles the edge case where device rotation crosses the 768px breakpoint while drawer is open
4. **`dvh` viewport units** -- use `100dvh` instead of `100vh` to handle iOS Safari's dynamic toolbar correctly
5. **Scroll lock on body** -- prevent background content from scrolling when drawer overlay is open

### New Considerations Discovered

- iOS Safari 100vh bug: `100vh` does not account for the dynamic URL bar; use `100dvh` (dynamic viewport height) which Tailwind v4 supports via `h-dvh`
- Safe area insets are required for the Phase 1 PWA milestone (installable app with `viewport-fit=cover`)
- The `inert` attribute is the correct approach for focus trapping -- no library needed, browser support is universal in 2026
- Body scroll lock requires `overflow: hidden` on the `<body>` element when the drawer is open to prevent background content scrolling on iOS

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

#### Research Insights: Drawer Implementation

**Best Practices for mobile drawers:**

- Use `transform: translateX(-100%)` for the hidden state and `transform: translateX(0)` for visible -- GPU-accelerated, no layout reflow
- Apply `will-change: transform` on the drawer element to hint at GPU compositing (remove after transition completes if using `transitionend` listener)
- Transition duration of 200-250ms feels snappy; 300ms+ feels sluggish on mobile. Use `transition-duration: 200ms` with `ease-out` for opening and `ease-in` for closing
- The drawer should be rendered in the DOM at all times (not conditionally mounted) to enable CSS transitions. Use `visibility: hidden` + `pointer-events: none` when closed, paired with the transform

**Concrete implementation pattern for `layout.tsx`:**

```tsx
// Mobile top bar -- only visible below md breakpoint
<div className="flex h-14 items-center border-b border-neutral-800 bg-neutral-900 px-4 md:hidden">
  <button
    onClick={() => setDrawerOpen(true)}
    aria-label="Open navigation"
    aria-expanded={drawerOpen}
    className="flex h-10 w-10 items-center justify-center rounded-lg text-neutral-400 hover:bg-neutral-800 hover:text-white"
  >
    <MenuIcon className="h-5 w-5" />
  </button>
  <span className="ml-3 text-lg font-semibold tracking-tight text-white">
    Soleur
  </span>
</div>

// Overlay backdrop
{drawerOpen && (
  <div
    className="fixed inset-0 z-40 bg-black/50 md:hidden"
    aria-hidden="true"
    onClick={() => setDrawerOpen(false)}
  />
)}

// Sidebar/drawer -- always rendered, conditionally positioned
<aside
  className={`
    fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-neutral-800 bg-neutral-900
    transition-transform duration-200 ease-out
    ${drawerOpen ? "translate-x-0" : "-translate-x-full"}
    md:relative md:z-auto md:w-56 md:translate-x-0 md:transition-none
  `}
>
  {/* Close button inside drawer -- mobile only */}
  <div className="flex items-center justify-between px-5 py-5">
    <span className="text-lg font-semibold tracking-tight text-white">
      Soleur
    </span>
    <button
      onClick={() => setDrawerOpen(false)}
      aria-label="Close navigation"
      className="flex h-10 w-10 items-center justify-center rounded-lg text-neutral-400 hover:bg-neutral-800 hover:text-white md:hidden"
    >
      <XIcon className="h-5 w-5" />
    </button>
  </div>
  {/* ...nav items and sign-out unchanged... */}
</aside>

// Main content with inert when drawer is open
<main
  className="flex-1 overflow-y-auto bg-neutral-950"
  {...(drawerOpen ? { inert: "" } : {})}
>
  {children}
</main>
```

**Body scroll lock pattern:**

```tsx
// Prevent background scrolling when drawer is open
useEffect(() => {
  if (drawerOpen) {
    document.body.style.overflow = "hidden";
  } else {
    document.body.style.overflow = "";
  }
  return () => {
    document.body.style.overflow = "";
  };
}, [drawerOpen]);
```

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/layout.tsx` | Add hamburger button, mobile drawer state, responsive classes, overlay backdrop, auto-close on navigation, body scroll lock, ESC handler, inert attribute |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Make domain leader grid single-column on mobile, increase tap target sizes, reduce heading sizes on mobile |
| `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | Touch-optimize input bar, ensure message bubbles do not overflow at 375px, adjust header for mobile top bar |
| `apps/web-platform/app/globals.css` | Add safe-area-inset CSS custom properties and any transitions not covered by Tailwind utilities |

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

#### Research Insights: Tailwind v4 Mobile Patterns

**Dynamic viewport units:** Tailwind v4 includes `h-dvh` (dynamic viewport height) which maps to `100dvh`. This solves the iOS Safari bug where `100vh` includes the space behind the URL bar. Use `h-dvh` instead of `h-screen` for the root layout container on mobile:

```tsx
// BEFORE: h-screen uses 100vh which is wrong on iOS Safari
<div className="flex h-screen">

// AFTER: h-dvh uses 100dvh which accounts for dynamic toolbar
<div className="flex h-dvh">
```

**Safe area insets for notched devices:** When the PWA milestone adds `viewport-fit=cover` to the viewport meta tag, content will extend behind the notch and home indicator. Prepare for this now by using `env(safe-area-inset-*)` in the mobile top bar and drawer:

```css
@layer components {
  .safe-top {
    padding-top: env(safe-area-inset-top, 0px);
  }
  .safe-bottom {
    padding-bottom: env(safe-area-inset-bottom, 0px);
  }
}
```

Apply `safe-top` to the mobile top bar and `safe-bottom` to the drawer's sign-out section. The fallback `0px` ensures no visual change until `viewport-fit=cover` is enabled.

**Tailwind v4 transition utilities:** The built-in `transition-transform`, `duration-200`, and `ease-out` classes are sufficient for the drawer animation. No custom CSS needed for the transition itself.

### State Management

- The layout is already `"use client"` -- adding `useState` for drawer toggle has no SSR impact.
- Route change detection via `usePathname()` (already imported) to auto-close drawer on navigation.

#### Research Insights: Orientation Change Handling

When a user rotates their device from portrait (e.g., 375px) to landscape (e.g., 812px on iPhone), the viewport may cross the 768px breakpoint. If the drawer is open, it should auto-close because the desktop sidebar takes over. Use a `matchMedia` listener:

```tsx
// Auto-close drawer when viewport crosses md breakpoint
useEffect(() => {
  const mediaQuery = window.matchMedia("(min-width: 768px)");
  const handler = () => {
    if (mediaQuery.matches) setDrawerOpen(false);
  };
  mediaQuery.addEventListener("change", handler);
  return () => mediaQuery.removeEventListener("change", handler);
}, []);
```

This is more reliable than a `resize` event listener because `matchMedia` fires once per transition, not continuously during resize.

### Known Gotchas (from learnings)

1. **backdrop-filter breaks fixed positioning** (learning: `2026-02-17-backdrop-filter-breaks-fixed-positioning`): Do NOT use `backdrop-filter: blur()` on the overlay. Use `bg-black/50` opacity only. If blur is needed later, use explicit `height: calc(100vh - offset)` instead of `top/bottom` pairs.
2. **Grid divisibility rule** (learning: `2026-02-22-landing-page-grid-orphan-regression`): The domain leader grid has 8 cards. Single column (8/1=8, clean) and two columns (8/2=4, clean) are both safe. Do not use 3-column layout unless the card count changes.
3. **auto-fill grid semantic grouping** (learning: `2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile`): The leader grid uses explicit `grid-cols-1 md:grid-cols-2` (not auto-fill), which is correct and should be preserved.

### Performance

- No new JS libraries. The hamburger toggle is ~10 lines of React state.
- CSS transitions for the drawer slide-in add no bundle weight.
- Eliminating horizontal overflow improves CLS (Cumulative Layout Shift), helping Lighthouse score.

#### Research Insights: Lighthouse Mobile Score

**Key factors for Lighthouse mobile > 80:**

- **Layout stability (CLS):** The current sidebar-always-visible layout causes massive layout shift on mobile because the browser renders 224px of sidebar + content, then discovers it overflows. Replacing with a hidden-by-default drawer eliminates this entirely.
- **`h-dvh` vs `h-screen`:** Using `100dvh` prevents the iOS Safari toolbar from causing a layout recalculation on scroll, which Lighthouse penalizes as CLS.
- **Font display:** The dashboard uses no custom fonts (system font stack via Tailwind defaults), so no FOIT/FOUT penalty.
- **Largest Contentful Paint (LCP):** The dashboard's LCP element is likely the "Start a conversation" CTA or the heading text. Neither requires optimization beyond what is already present.
- **Total Blocking Time (TBI):** The drawer toggle adds negligible JS (~200 bytes minified). No impact on TBI.

**Performance gotcha:** Avoid `transition: all` on the drawer -- it animates properties like `width` and `opacity` that trigger layout reflow. Use `transition-property: transform` explicitly (Tailwind's `transition-transform` class does this correctly).

### Accessibility

- Hamburger button must have `aria-label="Open navigation"` and `aria-expanded={isOpen}`.
- Close button inside drawer must have `aria-label="Close navigation"`.
- Drawer must trap focus when open (use `inert` attribute on main content).
- ESC key closes the drawer.
- Overlay backdrop must be `aria-hidden="true"`.

#### Research Insights: Accessibility Deep Dive

**The `inert` attribute is the correct approach:**

The HTML `inert` attribute (globally supported since 2023) makes an element and all its descendants non-interactive and invisible to assistive technology. Applying `inert` to the `<main>` element when the drawer is open achieves:

- Focus trapping in the drawer (Tab/Shift+Tab cycle stays in drawer)
- Screen reader exclusion of background content
- Click/tap blocking on background content

This is superior to JavaScript focus-trap libraries because:

- Zero bundle size (native browser feature)
- Handles all interaction modes (keyboard, touch, pointer, assistive tech)
- No edge cases with shadow DOM or iframes

**Implementation:**

```tsx
<main
  className="flex-1 overflow-y-auto bg-neutral-950"
  {...(drawerOpen ? { inert: "" } : {})}
>
```

Note: React requires `inert=""` (string attribute) rather than `inert={true}` (boolean) because `inert` is a non-standard HTML attribute in React's type system as of React 19. The empty string is equivalent to the boolean attribute per HTML spec.

**ESC key handler:**

```tsx
useEffect(() => {
  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape" && drawerOpen) {
      setDrawerOpen(false);
    }
  }
  document.addEventListener("keydown", handleKeyDown);
  return () => document.removeEventListener("keydown", handleKeyDown);
}, [drawerOpen]);
```

**ARIA landmarks:** The `<aside>` element already provides a `complementary` landmark role. Add `role="navigation"` to the `<nav>` inside the drawer for screen reader navigation shortcuts. The mobile top bar header should use `role="banner"` (implied by `<header>` but explicit is better for the mobile-only bar using `<div>`).

### Non-goals

- **PWA / service worker** -- separate issue, Phase 1 scope.
- **Dark/light theme toggle** -- not in scope.
- **Tablet-specific breakpoint** -- the `md:` breakpoint covers tablet adequately. The sidebar shows at 768px+.
- **Animated page transitions** -- unnecessary complexity.
- **CSS-only drawer** (checkbox hack) -- React state is simpler and more accessible than the `:checked` pseudo-class pattern.
- **Safe area plugin installation** -- `tailwindcss-safe-area` provides utility classes like `pt-safe` and `pb-safe`, but for 2 CSS rules, raw `env(safe-area-inset-*)` in `globals.css` is simpler than adding a dependency. Revisit if the PWA milestone needs extensive safe-area handling.

## Acceptance Criteria

### Functional Requirements

- [x] At viewport widths below 768px, sidebar is hidden and a hamburger button appears in a top bar
- [x] Tapping the hamburger button opens a full-height drawer overlay with navigation items and sign-out
- [x] Tapping the backdrop or a nav link closes the drawer
- [x] Pressing ESC closes the drawer
- [x] At viewport widths 768px and above, sidebar renders as the current fixed layout (no regression)
- [x] Domain leader grid displays as single column on mobile, two columns on desktop
- [x] All domain leader cards are tappable and link correctly on touch devices
- [x] Chat input bar and send button have minimum 44px touch targets on mobile
- [x] Message bubbles do not overflow or cause horizontal scroll at 375px
- [ ] No horizontal scroll on any screen at any viewport width (375px through 1920px+)
- [ ] Dashboard is fully usable on 375px viewport (iPhone SE)
- [x] Body content does not scroll when drawer overlay is open

### Non-Functional Requirements

- [ ] Lighthouse mobile score > 80 on the dashboard page
- [x] No new JS dependencies added
- [x] Drawer open/close transition completes in < 300ms (target: 200ms)
- [x] All interactive elements meet WCAG 2.5.5 touch target size (44x44px minimum)
- [x] Root container uses `100dvh` (not `100vh`) for correct iOS Safari behavior

### Quality Gates

- [ ] Visual verification at 375px, 768px, 1024px, and 1440px viewports
- [ ] Test on iOS Safari (via Playwright WebKit), Android Chrome (via Playwright Chromium), desktop Chrome/Edge
- [x] No TypeScript errors (`npx tsc --noEmit`)
- [ ] markdownlint passes on all changed markdown files
- [x] Breakpoint audit: verify `card_count % column_count == 0` at every responsive breakpoint for the domain leader grid

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
- Given the drawer is open, when the user scrolls on the background content area, then the background does not scroll (scroll lock active)
- Given an iPhone with a notch (safe-area-inset-top > 0), when viewing the mobile top bar, then the bar content is not obscured by the notch

#### Research Insights: Additional Test Scenarios

**iOS Safari-specific tests:**

- Given an iPhone in Safari, when the URL bar collapses during scroll, then the layout does not jump (verified by `100dvh` usage)
- Given an iPhone 14 Pro (Dynamic Island), when the drawer is open, then the drawer content starts below the Dynamic Island area

**Touch interaction tests:**

- Given a 375px viewport, when the user swipe-scrolls on the domain leader grid, then scrolling is smooth with no jank
- Given the chat input is focused on mobile, when the virtual keyboard appears, then the input remains visible above the keyboard (the `interactiveWidget: "resizes-visual"` viewport setting may help here -- test without it first)

**Regression tests:**

- Given a 1440px desktop viewport, when comparing the dashboard before and after changes, then the sidebar layout, spacing, and colors are pixel-identical
- Given a 1024px viewport, when the window is resized below 768px, then the sidebar transitions to the hamburger pattern without page reload

### Browser Verification

- **Playwright WebKit** (iOS Safari proxy): Navigate to `/dashboard` at 375px viewport, verify hamburger menu, tap through domain leaders
- **Playwright Chromium** (Android Chrome proxy): Navigate to `/dashboard` at 375px viewport, verify touch targets, no horizontal scroll
- **Playwright Chromium** (desktop Chrome/Edge): Navigate to `/dashboard` at 1440px viewport, verify desktop sidebar unchanged

### Lighthouse Verification

- Run Lighthouse via Playwright: navigate to the dashboard, then use `page.evaluate` to run the Lighthouse audit programmatically or use the `lighthouse` CLI:

```bash
npx lighthouse http://localhost:3000/dashboard \
  --only-categories=performance,accessibility \
  --form-factor=mobile \
  --chrome-flags="--headless=new" \
  --output=json --output-path=./lighthouse-report.json
```

Verify: `jq '.categories.performance.score' lighthouse-report.json` returns >= 0.80

## Success Metrics

- Lighthouse mobile score > 80 on dashboard page
- Zero horizontal scroll at 375px viewport
- All acceptance criteria pass in Playwright tests
- No regressions on desktop layout

## Dependencies and Risks

**Dependencies:**

- None. Tailwind v4 and React are already available. No new packages needed.

**Risks:**

- **Low:** Chat WebSocket connection may need testing during drawer open/close to ensure no disruption. The WebSocket is managed by `useWebSocket` in the chat page, not in the layout -- layout re-renders should not affect it.
- **Low:** Focus trapping in the drawer uses the native `inert` attribute -- universal browser support in 2026, no library needed.
- **Medium:** Lighthouse >80 may require additional performance work beyond layout (e.g., image optimization, code splitting) -- but the layout changes should meaningfully improve CLS. The switch from `h-screen` to `h-dvh` alone eliminates a major CLS source on iOS.
- **Low:** The `inert` attribute typing in React 19 -- React 19 added `inert` to its type definitions, so `inert=""` should work without `@ts-ignore`. Verify with `npx tsc --noEmit`.

## References and Research

### Internal References

- Dashboard layout: `apps/web-platform/app/(dashboard)/layout.tsx` -- current sidebar implementation (135 lines, inline SVG icons, `"use client"`)
- Dashboard page: `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- domain leader grid (`grid-cols-1 md:grid-cols-2`, 8 cards)
- Chat page: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` -- message list, input bar, review gate cards (247 lines)
- Domain leaders data: `apps/web-platform/server/domain-leaders.ts` -- 8 leaders (CMO, CTO, CFO, CPO, CRO, COO, CLO, CCO)
- Global CSS: `apps/web-platform/app/globals.css` -- minimal, just `@import "tailwindcss"`
- Root layout: `apps/web-platform/app/layout.tsx` -- `bg-neutral-950 text-neutral-100 antialiased` body classes, viewport handled by Next.js automatically
- Learning: `knowledge-base/project/learnings/2026-02-17-backdrop-filter-breaks-fixed-positioning.md` -- avoid `backdrop-filter` on parents of fixed-position elements
- Learning: `knowledge-base/project/learnings/2026-02-22-landing-page-grid-orphan-regression.md` -- grid divisibility rule: `card_count % column_count == 0` at every breakpoint
- Learning: `knowledge-base/project/learnings/ui-bugs/2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile.md` -- use explicit grid columns, not auto-fill

### External References

- [WCAG 2.5.5 Target Size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html) -- 44x44px minimum touch targets
- [Tailwind CSS v4 Responsive Design](https://tailwindcss.com/docs/responsive-design) -- mobile-first breakpoint utilities
- [MDN inert attribute](https://developer.mozilla.org/en-US/docs/Web/API/HTMLElement/inert) -- focus trapping without JS libraries
- [MDN Dynamic viewport units](https://developer.mozilla.org/en-US/docs/Web/CSS/length#dynamic) -- `dvh`, `dvw` units for mobile Safari dynamic toolbar
- [Next.js Viewport API](https://nextjs.org/docs/app/api-reference/functions/generate-viewport) -- `generateViewport` for viewport meta configuration (Next.js auto-includes `width=device-width, initial-scale=1`)
- [tailwindcss-safe-area](https://github.com/mvllow/tailwindcss-safe-area) -- reference for safe area patterns (not installing, using raw `env()` instead)
