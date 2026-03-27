---
feature: feat-mobile-responsive-ui
issue: "#1041"
created: 2026-03-27
---

# Tasks: Mobile-First Responsive UI

## Phase 1: Setup and Foundation

- [ ] 1.1 Add `MenuIcon` (hamburger) and `XIcon` (close) inline SVG components to `apps/web-platform/app/(dashboard)/layout.tsx`
- [ ] 1.2 Add `useState<boolean>` for drawer open/close state in `DashboardLayout`
- [ ] 1.3 Add `useEffect` to auto-close drawer on pathname change (via existing `usePathname()`)
- [ ] 1.4 Add `useEffect` for ESC key handler to close drawer

## Phase 2: Core Implementation -- Dashboard Layout

- [ ] 2.1 Add mobile top bar with hamburger button (`md:hidden` class) containing brand name and hamburger icon in `apps/web-platform/app/(dashboard)/layout.tsx`
- [ ] 2.2 Add overlay backdrop (`fixed inset-0 bg-black/50 z-40`) that appears when drawer is open, with click-to-dismiss
- [ ] 2.3 Convert existing `<aside>` to mobile drawer: `fixed inset-y-0 left-0 z-50 w-64 transform transition-transform` with `-translate-x-full` when closed, `translate-x-0` when open
- [ ] 2.4 Add `md:relative md:translate-x-0 md:w-56` classes to preserve desktop sidebar behavior
- [ ] 2.5 Add `inert` attribute to main content when drawer is open (focus trapping)
- [ ] 2.6 Increase touch targets on nav links and sign-out button: `min-h-[44px]` on mobile
- [ ] 2.7 Add close button (XIcon) inside the drawer header for mobile

## Phase 3: Core Implementation -- Dashboard Page

- [ ] 3.1 Adjust domain leader grid in `apps/web-platform/app/(dashboard)/dashboard/page.tsx`: ensure single column on mobile with adequate card padding
- [ ] 3.2 Increase touch target size on domain leader cards: `p-4` minimum, adequate gap between cards
- [ ] 3.3 Adjust "Start a conversation" CTA padding for mobile readability
- [ ] 3.4 Reduce heading sizes on mobile: `text-xl md:text-2xl` for the Command Center heading

## Phase 4: Core Implementation -- Chat Page

- [ ] 4.1 Ensure chat header in `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` does not overlap with mobile top bar
- [ ] 4.2 Increase input field and send button to minimum 44px height on mobile: `py-3` or `min-h-[44px]`
- [ ] 4.3 Constrain message bubble max-width on mobile: `max-w-[90%] md:max-w-[80%]` to prevent overflow
- [ ] 4.4 Ensure ReviewGateCard buttons wrap correctly on narrow viewports (already uses `flex-wrap`, verify at 375px)

## Phase 5: CSS and Transitions

- [ ] 5.1 Add drawer slide transition in `apps/web-platform/app/globals.css` if Tailwind transition utilities are insufficient
- [ ] 5.2 Verify no horizontal overflow on any page at 375px by adding `overflow-x-hidden` to the root layout if needed (prefer fixing overflow source over hiding it)

## Phase 6: Testing and Verification

- [ ] 6.1 Visual verification at 375px (iPhone SE), 768px (iPad), 1024px (desktop), 1440px (large desktop) using Playwright screenshots
- [ ] 6.2 Test hamburger menu open/close cycle on Playwright WebKit (iOS Safari proxy)
- [ ] 6.3 Test hamburger menu open/close cycle on Playwright Chromium (Android Chrome proxy)
- [ ] 6.4 Test desktop sidebar unchanged on Playwright Chromium at 1440px
- [ ] 6.5 Verify no horizontal scrollbar at 375px on all dashboard pages
- [ ] 6.6 Verify touch targets are 44px+ on all interactive elements at 375px
- [ ] 6.7 Run `npx tsc --noEmit` -- zero TypeScript errors
- [ ] 6.8 Run Lighthouse mobile audit on dashboard page -- score > 80
- [ ] 6.9 Verify ESC key closes drawer
- [ ] 6.10 Verify drawer auto-closes on navigation to a different page
