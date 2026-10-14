---
feature: feat-mobile-responsive-ui
issue: "#1041"
created: 2026-03-27
deepened: 2026-03-27
---

# Tasks: Mobile-First Responsive UI

## Phase 1: Setup and Foundation

- [x] 1.1 Add `MenuIcon` (hamburger) and `XIcon` (close) inline SVG components to `apps/web-platform/app/(dashboard)/layout.tsx`
- [x] 1.2 Add `useState<boolean>` for drawer open/close state in `DashboardLayout`
- [x] 1.3 Add `useEffect` to auto-close drawer on pathname change (via existing `usePathname()`)
- [x] 1.4 Add `useEffect` for ESC key handler to close drawer
- [x] 1.5 Add `useEffect` for body scroll lock (`document.body.style.overflow`) when drawer is open
- [x] 1.6 Add `useEffect` with `matchMedia("(min-width: 768px)")` listener to auto-close drawer on orientation change crossing the md breakpoint

## Phase 2: Core Implementation -- Dashboard Layout

- [x] 2.1 Change root container from `h-screen` to `h-dvh` in `apps/web-platform/app/(dashboard)/layout.tsx` for correct iOS Safari dynamic toolbar behavior
- [x] 2.2 Add mobile top bar with hamburger button (`md:hidden` class) containing brand name and hamburger icon, with `aria-label="Open navigation"` and `aria-expanded`
- [x] 2.3 Add overlay backdrop (`fixed inset-0 bg-black/50 z-40 md:hidden`) that appears when drawer is open, with `aria-hidden="true"` and click-to-dismiss
- [x] 2.4 Convert existing `<aside>` to always-rendered mobile drawer: `fixed inset-y-0 left-0 z-50 w-64 transition-transform duration-200 ease-out` with `-translate-x-full` when closed, `translate-x-0` when open. Do NOT use `backdrop-filter` on any parent element (per learning: backdrop-filter breaks fixed positioning)
- [x] 2.5 Add `md:relative md:z-auto md:w-56 md:translate-x-0 md:transition-none` classes to preserve desktop sidebar behavior
- [x] 2.6 Add `inert` attribute to `<main>` content when drawer is open (native focus trapping, zero bundle cost)
- [x] 2.7 Increase touch targets on nav links and sign-out button: `min-h-[44px]` on mobile per WCAG 2.5.5
- [x] 2.8 Add close button (XIcon) with `aria-label="Close navigation"` inside the drawer header, visible only on mobile (`md:hidden`)
- [x] 2.9 Add safe-area-inset CSS custom properties to `apps/web-platform/app/globals.css` using `@layer components` for future PWA notch handling

## Phase 3: Core Implementation -- Dashboard Page

- [x] 3.1 Verify domain leader grid in `apps/web-platform/app/(dashboard)/dashboard/page.tsx` uses `grid-cols-1 md:grid-cols-2` (already correct -- confirm no auto-fill). Grid divisibility check: 8 cards / 1 col = 8 rows (clean), 8 cards / 2 cols = 4 rows (clean)
- [x] 3.2 Increase touch target size on domain leader cards: `p-4` minimum, `gap-3` between cards, ensure tappable area covers the full card
- [x] 3.3 Adjust "Start a conversation" CTA: reduce horizontal padding on mobile (`px-4 md:px-6`), ensure text does not overflow
- [x] 3.4 Reduce heading sizes on mobile: `text-xl md:text-2xl` for the Command Center heading
- [x] 3.5 Adjust page container padding: `px-4 md:px-6` for mobile breathing room

## Phase 4: Core Implementation -- Chat Page

- [x] 4.1 Ensure chat header in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` does not overlap with mobile top bar -- adjust `px-4 md:px-6` padding
- [x] 4.2 Increase input field and send button to minimum 44px height on mobile: existing `py-3` on input (~44px) is sufficient, added `min-h-[44px]` to send button
- [x] 4.3 Constrain message bubble max-width on mobile: `max-w-[90%] md:max-w-[80%]` to prevent overflow at 375px
- [x] 4.4 Ensure ReviewGateCard buttons wrap correctly on narrow viewports (already uses `flex-wrap` -- verified)
- [x] 4.5 Verify the WebSocket connection (`useWebSocket`) is not disrupted by layout changes -- the hook lives in the chat page, not the layout, so it is unaffected

## Phase 5: CSS and Globals

- [x] 5.1 Add safe-area-inset utility classes in `apps/web-platform/app/globals.css` using `@layer components`
- [x] 5.2 Verify Tailwind v4 `transition-transform`, `duration-200`, `ease-out` classes are sufficient for the drawer animation (no custom CSS needed -- verified)
- [ ] 5.3 Verify no horizontal overflow on any page at 375px -- diagnose and fix overflow sources rather than applying `overflow-x-hidden`

## Phase 6: Testing and Verification

- [ ] 6.1 Visual verification at 375px (iPhone SE), 768px (iPad), 1024px (desktop), 1440px (large desktop) using Playwright screenshots
- [ ] 6.2 Test hamburger menu open/close cycle on Playwright WebKit (iOS Safari proxy) at 375px
- [ ] 6.3 Test hamburger menu open/close cycle on Playwright Chromium (Android Chrome proxy) at 375px
- [ ] 6.4 Test desktop sidebar unchanged on Playwright Chromium at 1440px -- pixel comparison with baseline
- [ ] 6.5 Verify no horizontal scrollbar at 375px on all dashboard pages (dashboard, chat, kb, billing)
- [ ] 6.6 Verify touch targets are 44px+ on all interactive elements at 375px
- [x] 6.7 Run `next build` -- zero TypeScript errors (inert uses boolean typing, build passes)
- [ ] 6.8 Run Lighthouse mobile audit on dashboard page -- score > 80
- [ ] 6.9 Verify ESC key closes drawer
- [ ] 6.10 Verify drawer auto-closes on navigation to a different page
- [ ] 6.11 Verify drawer auto-closes on device rotation crossing 768px breakpoint (matchMedia handler)
- [ ] 6.12 Verify body scroll lock -- background content does not scroll when drawer overlay is open
- [ ] 6.13 Verify grid divisibility at all breakpoints: `card_count % column_count == 0`
