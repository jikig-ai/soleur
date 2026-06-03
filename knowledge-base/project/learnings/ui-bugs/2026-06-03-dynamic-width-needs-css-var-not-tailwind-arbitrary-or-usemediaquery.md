---
title: "Dynamic responsive width: use a deterministic CSS-var @media rule, not a Tailwind v4 arbitrary class or useMediaQuery"
date: 2026-06-03
category: ui-bugs
module: apps/web-platform
tags: [tailwind-v4, css, ssr-hydration, useMediaQuery, playwright, adr-049, nav-rail]
related_prs: [4871]
related_adrs: [ADR-047, ADR-049]
---

# Learning: applying a JS-driven responsive width to an element

## Problem

The widenable KB nav rail needed to apply a persisted pixel width (224–480px,
from a `useRailWidth` localStorage hook) to the dashboard `aside` **only at the
md+ breakpoint** (the mobile `<md` drawer must keep its `w-64`). Two intuitive
approaches both shipped green through the entire 8,233-test vitest suite **and
both silently did nothing in a real browser** — the rail stayed pinned at the
224px default. The bug was invisible to jsdom (no CSS) and surfaced only in the
ADR-049 `nav-states` Playwright visual gate (`/soleur:qa`).

### Approach 1 — Tailwind v4 arbitrary value (FAILED)
```tsx
// className branch:
collapsed ? "md:w-14" : kbExpanded ? "md:w-[var(--kb-rail-w)]" : "md:w-56"
// + style={{ "--kb-rail-w": `${railWidth}px` }}
```
Tailwind **v4.2.1 did not generate the `md:w-[var(--kb-rail-w)]` utility** even
though the literal string is present in source. DOM probe: the class was absent,
the element fell back to `md:w-56` → `clientWidth` stuck at 223 (224 − 1px
border, border-box). No build error, no warning.

### Approach 2 — useMediaQuery-gated inline style (FAILED)
```tsx
const isDesktop = useMediaQuery("(min-width: 768px)");
const applyRailWidth = kbExpanded && isDesktop;
style={applyRailWidth ? { width: railWidth } : undefined}
```
A DOM probe (data-attribute dump) proved `window.matchMedia("(min-width:768px)")
.matches === true` at 1280px, the handle rendered (so `kbExpanded === true`),
**yet `isDesktop === false`** after 4s. The project's `useMediaQuery`
(`useState(() => window.matchMedia(q).matches)` + a `useEffect` `setMatches`)
did not flip to `true` under Next 15 / React 19 SSR hydration in this layout —
so `applyRailWidth` stayed false and `style` stayed `null`. (Collapse, which
uses an analogous `useSidebarCollapse` localStorage effect, *did* hydrate — so
"effects run" was true generally but `useMediaQuery`'s value was still wrong.)

## Solution (deterministic, no JS state, no Tailwind arbitrary class)

Carry the width on a CSS custom property + a data-attribute the element always
sets when active, consumed by an **unlayered** `@media` rule in `globals.css`:

```css
/* globals.css — unlayered, so it wins over Tailwind's layered md:w-56 */
@media (min-width: 768px) {
  aside[data-kb-rail-width] { width: var(--kb-rail-w, 14rem); }
}
```
```tsx
// layout.tsx
<aside
  data-kb-rail-width={kbExpanded ? "" : undefined}
  style={kbExpanded ? ({ "--kb-rail-w": `${railWidth}px` } as React.CSSProperties) : undefined}
  className={`... w-64 ... ${collapsed ? "md:w-14" : "md:w-56"}`}
>
```
- Mobile (`<md`): the rule is inside the md media query → never applies → base
  `w-64` drawer untouched.
- Collapsed: `kbExpanded` false → no attr/var → `md:w-14` wins.
- Setting a React inline custom property (`"--kb-rail-w"`) works reliably (unlike
  the arbitrary Tailwind class); the **CSS file** owns the breakpoint logic, so
  there is no JS-media-query state to mis-hydrate.

DOM probe confirmed: seeded 400 → `clientWidth` 399; drag 223 → 361.

## Key Insight

For a JS-driven width that must be **responsive (breakpoint-scoped)**, prefer an
explicit CSS rule consuming a custom property over either (a) a Tailwind v4
arbitrary `w-[var(...)]` class (generation is not guaranteed for CSS-var
arbitrary values) or (b) a `useMediaQuery`/`matchMedia` JS gate (SSR-hydration
timing can leave the boolean stale). Set the **value** in JS (a CSS custom
property — always renders), keep the **breakpoint decision** in CSS. Unlayered
rules beat Tailwind's layered utilities regardless of source order.

Corollary: this class of CSS-layout bug is structurally invisible to jsdom/vitest
(no CSS engine). The ADR-049 headless-Chromium `nav-states` gate is the only
thing that catches it — run `/soleur:qa` whenever a diff touches
`app/(dashboard)/**`, `components/dashboard/**`, or any `layout.tsx`.

## Playwright e2e for animated / hydration-dependent layout

Three e2e traps hit while verifying the fix:

1. **Transition race.** The rail has `md:transition-[width]` (200ms). A single
   synchronous `clientWidth` read immediately after an action catches a
   mid-animation frame (observed 326 while heading to 360; 223 at frame 0). Fix:
   `await expect.poll(() => asideWidth(page), { timeout }).toBeGreaterThan(X)`.
2. **Hydration-before-interaction.** The resize handle's SSR markup is *visible*
   before React attaches its `onPointerDown`; a `page.mouse` drag right after
   `toBeVisible()` fires DOM pointer events at an element with no listeners → no
   effect. Fix: a short settle (`await page.waitForTimeout(1500)`) before the
   drag. (A DOM probe instrumenting pointer events proved the drag itself works
   once hydrated: 11 events, 223→361.)
3. **Flaky realtime route.** `/dashboard/chat` intermittently threw
   `net::ERR_NETWORK_IO_SUSPENDED` / "context closed" from the dev server's
   `@supabase/auth-js: Expected parameter to be UUID` founder-JWT WebSocket
   error. Added `ERR_NETWORK_IO_SUSPENDED` to `gotoOrSkip`'s retry regex (same
   transient family as `ERR_ABORTED`); CI's `retries: 1` covers the rest.

## Session Errors

1. **Tailwind v4 arbitrary CSS-var width class never generated.** — Recovery: switched to an explicit unlayered `@media` rule consuming `var(--kb-rail-w)`. — Prevention: don't use `w-[var(--x)]` for layout-critical responsive widths in Tailwind v4; write the CSS rule. Captured in this learning.
2. **`useMediaQuery` stayed false under SSR hydration despite `matchMedia` true.** — Recovery: removed the JS media-query gate; moved the breakpoint decision into CSS. — Prevention: avoid `useMediaQuery` for layout-critical render decisions that must be correct on first interactive frame; use CSS media queries.
3. **e2e width reads raced the 200ms width transition + hydration.** — Recovery: `expect.poll` retrying assertions. — Prevention: poll, never single-read, any animated/async-hydrated dimension. (Routed to the qa skill below.)
4. **Pointer-drag fired before React hydration attached handlers.** — Recovery: settle wait before the drag. — Prevention: wait for interactivity (not just visibility) before `page.mouse` interactions on hydrated client components.
5. **Chat-route e2e flake (`ERR_NETWORK_IO_SUSPENDED` / context closed).** — Recovery: added the error to the goto retry regex. — Prevention: the dev server's synthetic-session realtime founder-JWT mint fails; treat chat-route nav as retryable.
6. **`tsc --noEmit | head` reported EXIT=0 while tsc exited 1.** — Recovery: re-ran capturing `$?` to a file, then grepped non-`.next/` errors. — Prevention: known pipefail trap (`hr`/test-all-tail-masking) — capture `rc=$?` before piping; the real error was a pre-existing `.next/types` artifact (`PaymentWarningBanner` named export in a layout file), not my diff.
7. **heredoc probe file didn't persist; playwright exited 144 (port collision).** — Recovery: wrote the probe with the Write tool and freed port 3100. — Prevention: use the Write tool for multi-line test files, not `cat <<EOF` chained with a long-running command.
8. **`SendMessage` tool unavailable to continue the planning agent for the mid-session scope addition.** — Recovery: spawned a fresh general-purpose agent that read + amended the existing plan in place. — Prevention: in this harness, continue agent context only when SendMessage is present; otherwise spawn a fresh agent pointed at the on-disk artifacts.
