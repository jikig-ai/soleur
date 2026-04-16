---
title: "feat: Collapsible Sidebars (Main Nav, KB, Team Settings)"
type: feat
date: 2026-04-16
issue: 2342
pr: 2415
---

# Collapsible Sidebars

## Overview

Make all three dashboard sidebar surfaces collapsible on desktop to give users more
screen real estate for content. Each sidebar persists its collapse state in
`localStorage` so it survives page refreshes. A single `Cmd/Ctrl+B` shortcut toggles
the contextually-relevant sidebar based on the current route. Mobile behavior is
unchanged — the existing drawer (main), class-swap (KB), and bottom tabs (settings)
patterns stay as-is.

## Problem Statement

On typical ~1280px laptop screens the fixed sidebars consume 192–256px of horizontal
space that cannot be reclaimed. Users working in KB file content or settings forms
lose meaningful editing width to navigation they only need intermittently.

## Proposed Solution

| Surface | Expanded | Collapsed | Toggle Location |
|---------|----------|-----------|-----------------|
| Main dashboard | `w-56` (224px) with icons + labels | `w-14` (56px) icon-only with tooltips | Bottom of sidebar, chevron icon |
| KB file tree | `w-64` (256px) with tree + search | `w-0` fully hidden | Content area top-left, chevron icon |
| Settings nav | `w-48` (192px) with text links | `w-0` fully hidden | Content area top-left, chevron icon |

**Shared infrastructure:**

- `useSidebarCollapse(key)` hook: `useState` + `useEffect` hydration from
  `localStorage`, matches the `PaymentWarningBanner` sessionStorage pattern
  already in `layout.tsx` (NOT `useSyncExternalStore` — unused in codebase)
- `Cmd/Ctrl+B` keyboard shortcut: pathname-based routing to toggle the
  innermost sidebar. Uses raw `document.addEventListener("keydown")` matching
  the existing `Cmd+Shift+L` pattern in `selection-toolbar.tsx`
- CSS `transition-[width] duration-200 ease-out` on all sidebars. Per
  documented learning: always-render the sidebar element and toggle width,
  never use conditional rendering (`{!collapsed && <Sidebar/>}`) which
  breaks CSS transitions

## Technical Considerations

**Architecture:** Each sidebar owns its own collapse state via the shared hook.
No global context needed — the hook reads/writes `localStorage` directly.

**Keyboard shortcut coordination:** Each sidebar layout registers its own
`Cmd/Ctrl+B` listener with a pathname guard. When the pathname matches, that
listener calls `toggle()` and `e.preventDefault()`. Since each listener checks a
disjoint pathname prefix, exactly one handler fires per keypress:

- KB layout (`kb/layout.tsx`): fires when `pathname.startsWith("/dashboard/kb")`
- Settings shell (`settings-shell.tsx`): fires when `pathname.startsWith("/dashboard/settings")`
- Main layout (`layout.tsx`): fires when pathname is NOT KB or Settings

This avoids cross-component state coordination — no context, refs, or custom
events needed. Each sidebar toggles itself.

**SSR safety:** The hook initializes collapsed to `false` (expanded). A
post-hydration `useEffect` reads `localStorage` and may flip to `true`. This
matches the existing `PaymentWarningBanner` pattern — the initial render matches
the server and React reconciles the client-only update cleanly.

**Main sidebar CSS transition conflict:** The existing `<aside>` uses
`transition-transform duration-200 ease-out` for the mobile drawer slide and
`md:transition-none` to disable it on desktop. For desktop collapse, replace
`md:transition-none` with `md:transition-[width] md:duration-200 md:ease-out`.
This gives mobile its translate animation and desktop its width animation on the
same element without conflict. Desktop always has `md:translate-x-0` so the
translate transition is a no-op there.

**Main sidebar icon-only mode:** The nav items already have SVG icons
(`GridIcon`, `BookIcon`, `SettingsIcon`, etc.). When collapsed, labels are hidden
via `overflow-hidden` on the text span, and a `title` attribute on the `<Link>`
provides a native tooltip. The sidebar header hides the "Soleur" text and shows
only the toggle chevron.

**KB sidebar full collapse:** The aside transitions to `w-0 overflow-hidden`.
A small toggle button (`ChevronRight` icon) appears on the left edge of the
content area when collapsed. When expanded, a `ChevronLeft` icon sits in the
sidebar header. **Mobile coexistence:** The mobile class-swap
(`hidden`/`block` based on `isContentView`) and the desktop width transition
(`md:w-64`/`md:w-0`) operate on independent CSS properties at different
breakpoints — mobile toggles `display`, desktop transitions `width`. No conflict.

**Settings sidebar full collapse:** Same pattern as KB. The existing
`hidden md:block` stays as-is — `hidden` controls mobile display (none), while
`md:block` ensures the element is always rendered on desktop where the width
transition operates. The bottom tab bar on mobile is unaffected since it uses
`md:hidden` independently.

**`Cmd+B` vs KB chat sidebar:** On `/dashboard/kb*` routes, `Cmd+B` always
toggles the file tree sidebar (left panel, primary navigation). The chat sidebar
(right panel, supplementary) has its own dedicated toggle button. No conflict.

**Keyboard shortcut guards:**

- `e.preventDefault()` to suppress browser bold formatting
- Skip when `e.target` is `input`, `textarea`, or `contenteditable`

### Files to Create

- `apps/web-platform/hooks/use-sidebar-collapse.ts` — shared hook

### Files to Modify

- `apps/web-platform/app/(dashboard)/layout.tsx` — main sidebar collapse + keyboard shortcut
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — KB sidebar collapse
- `apps/web-platform/components/settings/settings-shell.tsx` — settings sidebar collapse

## Acceptance Criteria

- [ ] Main sidebar collapses to icon-only (56px) on desktop when toggle clicked
- [ ] KB file tree collapses to hidden (0px) on desktop when toggle clicked
- [ ] Settings nav collapses to hidden (0px) on desktop when toggle clicked
- [ ] Each sidebar's collapse state persists in `localStorage` across page refreshes
- [ ] `Cmd/Ctrl+B` toggles the contextually-relevant sidebar
- [ ] Collapse animation is smooth (200ms width transition)
- [ ] Mobile behavior unchanged for all three surfaces
- [ ] Keyboard shortcut does nothing when focus is in input/textarea/contenteditable
- [ ] Sidebars default to expanded on first visit (no localStorage entry)
- [ ] Private browsing mode (localStorage unavailable) degrades gracefully — sidebars work but don't persist

## Test Scenarios

- Given a user on desktop at `/dashboard`, when they click the main sidebar toggle, then the sidebar collapses to icon-only width
- Given a collapsed main sidebar, when the user hovers an icon, then a tooltip shows the nav label
- Given a user on `/dashboard/kb/some-file`, when they press `Cmd+B`, then the KB file tree sidebar collapses (not the main sidebar)
- Given a user on `/dashboard/settings/team`, when they press `Cmd+B`, then the settings sidebar collapses
- Given a collapsed sidebar, when the user refreshes the page, then the sidebar remains collapsed
- Given a user typing in a textarea, when they press `Cmd+B`, then the shortcut is ignored (no sidebar toggle)
- Given a mobile viewport (< 768px), when the user interacts with navigation, then existing mobile patterns (drawer/class-swap/tabs) are unchanged
- Given localStorage is unavailable (private mode), when the user clicks a toggle, then the sidebar collapses for the current session but does not persist
- Given the main sidebar has desktop collapse changes, when viewed on mobile (< 768px), then the slide-in drawer still works correctly (translate-x animation, backdrop overlay, ESC close)
- Given the KB sidebar is collapsed on desktop, when on `/dashboard/kb` and the KB chat sidebar is open, then `Cmd+B` toggles the file tree (left) not the chat panel (right)

### Browser Verification

- **Desktop (1280px):** Navigate each of `/dashboard`, `/dashboard/kb`, `/dashboard/settings`. Click toggle on each sidebar. Verify width transition, persistence after refresh, `Cmd+B` shortcut.
- **Mobile (375px):** Navigate same routes. Verify drawer/class-swap/tabs unchanged.
- **Tablet (768px):** Verify breakpoint boundary — sidebar should be in desktop mode.

## Domain Review

**Domains relevant:** Product, Marketing, Engineering, Operations

Carried forward from brainstorm (2026-04-15). All 8 domains assessed.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** High user value — every user on ~1280px laptops benefits. Phase 3 fit.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Collapsible sidebars serve as first proof-of-loop artifact for ux-audit narrative.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Low-risk, 1-2 day implementation. No new dependencies, follows existing patterns.

### Operations (COO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No operational impact — pure client-side feature.

### Product/UX Gate

**Tier:** advisory
**Decision:** skipped (user declined — standard UX pattern, brainstorm validated approach)
**Agents invoked:** none
**Skipped specialists:** none

## Implementation Phases

### Phase 1: Main Sidebar + Shared Hook + Keyboard Shortcut

Create `apps/web-platform/hooks/use-sidebar-collapse.ts`:

- `useSidebarCollapse(storageKey: string): [collapsed: boolean, toggle: () => void]`
- `useState(false)` + `useEffect` hydration from `localStorage`
- try/catch for private browsing
- Follows `PaymentWarningBanner` pattern exactly

Modify `apps/web-platform/app/(dashboard)/layout.tsx`:

- Import `useSidebarCollapse` with key `"soleur:sidebar.main.collapsed"`
- Replace `md:transition-none` with `md:transition-[width] md:duration-200 md:ease-out`
- Toggle between `md:w-56` (expanded) and `md:w-14` (collapsed)
- When collapsed: hide label text (`overflow-hidden whitespace-nowrap`), keep icons, add `title` attribute
- Add chevron toggle button at bottom of sidebar nav
- Add inline `ChevronLeftIcon` / `ChevronRightIcon` SVG (matches existing inline icon pattern)
- Add `Cmd/Ctrl+B` keyboard handler guarded to non-KB/non-Settings routes
- Verify mobile drawer still works (the `transition-transform` for mobile is preserved,
  only the `md:` override changes)

### Phase 2: KB Sidebar + Settings Sidebar

Modify `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`:

- Import `useSidebarCollapse` with key `"soleur:sidebar.kb.collapsed"`
- Add `transition-[width] duration-200 ease-out` to the `<aside>` at `md:` breakpoint
- Toggle between `md:w-64` (expanded) and `md:w-0 md:overflow-hidden md:border-r-0` (collapsed)
- Preserve mobile class-swap logic (`hidden`/`block` from `isContentView`) — it operates on
  `display` independently of the desktop `width` transition
- Add chevron toggle button in sidebar header (expanded) and content area left edge (collapsed)
- Always render the sidebar element (never conditional render)
- Add `Cmd/Ctrl+B` handler guarded to `/dashboard/kb*` routes

Modify `apps/web-platform/components/settings/settings-shell.tsx`:

- Import `useSidebarCollapse` with key `"soleur:sidebar.settings.collapsed"`
- Add `transition-[width] duration-200 ease-out` to the `<nav>` at `md:` breakpoint
- Keep existing `hidden md:block` — `hidden` handles mobile, `md:block` ensures desktop rendering
- Toggle between `md:w-48` (expanded) and `md:w-0 md:overflow-hidden md:border-r-0` (collapsed)
- Add chevron toggle button in sidebar header (expanded) and content area left edge (collapsed)
- Mobile bottom tab bar unaffected
- Add `Cmd/Ctrl+B` handler guarded to `/dashboard/settings*` routes

## Alternative Approaches Considered

| Approach | Why Not |
|----------|---------|
| `useSyncExternalStore` for cross-tab sync | Not used anywhere in codebase. Cross-tab sidebar sync is not a user need. |
| Shared React context for all sidebar states | Unnecessary coupling — each sidebar is independent. |
| Framer Motion for animations | No animation library in codebase. Tailwind `transition-[width]` is sufficient. |
| Resizable sidebars (drag to resize) | Scope creep. Collapse/expand covers the user need without drag complexity. |
| Icon-only collapse for all sidebars | KB file tree and settings text links have no meaningful icon representation. |

## References

### Internal

- Main sidebar: `apps/web-platform/app/(dashboard)/layout.tsx`
- KB sidebar: `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`
- Settings shell: `apps/web-platform/components/settings/settings-shell.tsx`
- PaymentWarningBanner pattern: `apps/web-platform/app/(dashboard)/layout.tsx:23-80`
- Keyboard shortcut pattern: `apps/web-platform/components/kb/selection-toolbar.tsx:32-36` (`isShortcutKey`)
- useMediaQuery hook: `apps/web-platform/hooks/use-media-query.ts`
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-15-collapsible-navs-ux-review-brainstorm.md`

### Learnings Applied

- Always-render sidebar elements for CSS transitions: `knowledge-base/project/learnings/2026-03-27-react-inert-attribute-typing.md`
- Render sidebar directly in layout.tsx: `knowledge-base/project/learnings/ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md`
- Use `inert={boolean || undefined}`: `knowledge-base/project/learnings/2026-03-27-react-inert-attribute-typing.md`
