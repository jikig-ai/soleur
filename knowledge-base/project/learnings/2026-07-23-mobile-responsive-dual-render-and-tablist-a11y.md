---
title: "Responsive dual-render (breakpoint-gated siblings), sessionStorage-in-useState SSR-safety, swipe axis guard, and complete tablist a11y"
date: 2026-07-23
branch: feat-mobile-kanban-board-layout
category: ui-bugs
tags: [nextjs, ssr, hydration, tailwind, sessionstorage, touch-swipe, wai-aria, tablist, mobile]
---

# Learning: four reusable frontend patterns from the mobile kanban board

## Problem

Building a mobile-only layout (a single-column status-selector board) for the Workstream kanban that must NOT touch the desktop 7-column board, while preserving all shared state (SWR fetch, optimistic writes, URL↔drawer sync, filters). Four patterns emerged, two of them non-obvious SSR/hydration traps.

## Solution / Key Insights

### 1. Choosing between a CSS dual-render and a `useMediaQuery` gate depends on whether the subtree is server-rendered — and on whether both trees render the SAME queryable content

Two ways to ship a mobile-specific layout beside a desktop one:

**(a) CSS dual-render** — render BOTH as siblings, gate with pure Tailwind:
```tsx
<div className="hidden … md:flex">{/* desktop */}</div>
<MobileBoard className="md:hidden" … />
```
Both subtrees render identically on server + client (CSS hides one) → no hydration mismatch, no resize flash. This is the right choice when the subtree **is server-rendered** and the two trees don't duplicate the same test-queried content. It's the codebase idiom for small/distinct content (chat-surface, chat-input, nav-count-badge).

**(b) `useMediaQuery` JS gate** — render EXACTLY ONE tree:
```tsx
const isDesktop = useMediaQuery("(min-width: 768px)");
… isDesktop ? <DesktopBoard/> : <MobileBoard/>
```

**The trap that decided it here:** the desktop and mobile trees both render the SAME list of `IssueCard`s. Under CSS dual-render, BOTH trees mount, so the DOM contains every card **twice**. happy-dom/jsdom do NOT apply CSS media queries, so the sibling `WorkstreamBoard` test suite — which queries the global `screen` (`screen.getByText("Card one")`) — broke with `Found multiple elements` on 12 tests. This is a **real regression the CSS approach caused**, not just a test artifact: on desktop the hidden `MobileBoard` still mounts and runs its `sessionStorage` write effect for a surface the user never sees.

`useMediaQuery` was the correct gate here **specifically because the board is client-only**: `WorkstreamBoard` returns `<BoardSkeleton/>` until the client SWR fetch resolves (no `fallbackData`/SSR provider), so the gated board render never executes during SSR or first client paint. That means (1) no hydration mismatch (server + first-paint both emit the skeleton regardless of the hook's value — the hook is called unconditionally at the top, but its differing server/client value doesn't reach the output while `!data`), and (2) no flash — by the time the board renders, `useMediaQuery`'s `useState(() => window.matchMedia(q).matches)` initializer reads the REAL viewport on its first board render. **Decision rule:** prefer (b) when the subtree is client-only-mounted AND the two trees duplicate queryable content or effects; prefer (a) when the subtree is genuinely server-rendered and its trees are cheap + distinct. Either way the mobile component **consumes the parent's already-computed `filtered` array + `openIssue`** so filters/search, URL sync, and write orchestration stay single-sourced.

### 2. `sessionStorage` inside a `useState(() => …)` initializer is hydration-safe ONLY when the component is never server-rendered

`useState(() => initialStatus())` where `initialStatus()` reads `window.sessionStorage` is dangerous: React re-runs the initializer on the client at hydration, and if the client value (from storage) differs from the server value (storage unavailable → derived default), you get a **hydration mismatch**. A try/catch around the storage read prevents the *crash* but NOT the *mismatch*.

It is safe here only because **MobileBoard is never server-rendered**: the board is gated on `!swrData → <Skeleton>` and the SWR fetch has no `fallbackData`/SSR provider, so on the server (and the first client paint) the board is a skeleton; MobileBoard mounts only after the client fetch resolves, client-side, once. **Always verify the render gate before trusting a storage-reading `useState` initializer.** If a component CAN be SSR'd, read storage in a `useEffect` after mount instead (initialize state to a deterministic default first) — the pattern used by `components/pwa/pwa-controls.tsx`.

### 3. A hand-rolled touch-swipe on a vertical scroll region must guard on dominant axis

A swipe handler on a vertically-scrolling panel that measures only horizontal delta mis-fires: a thumb scroll that drifts sideways >threshold triggers the swipe action. Record BOTH axes and require horizontal dominance:
```ts
if (Math.abs(dx) < 48 || Math.abs(dx) <= Math.abs(dy)) return; // ignore vertical/diagonal
```

### 4. A complete WAI-ARIA tablist is more than roving tabIndex + arrows

Beyond `role=tablist/tab`, `aria-selected`, roving `tabIndex`, ArrowLeft/Right, and a dynamic `aria-labelledby` on the `role=tabpanel`, a conformant tablist also needs:
- **Home/End** keys → first/last tab.
- **`tabIndex=0` on an EMPTY tabpanel** (no focusable child) so keyboard users can focus its content; omit it when the panel holds focusable children (they are the tab stops).
- **An explicit `aria-label`** when the visible tab label is a bare "Label 5" count pill — otherwise the accessible name is a context-free trailing number. Use `aria-label={\`${label}, ${count} issues\`}`.
- Keep the selected tab **scrolled into view** on every selection change (incl. non-keyboard swipe), via a `useEffect` on the selected value.

## Session Errors

1. **The plan prescribed a non-existent Tailwind token `ring-soleur-gold`.** — Recovery: verified against `globals.css` + existing `ring-soleur-*` usage; the real token is `ring-soleur-accent-gold-fg`. **Prevention:** a plan is authoritative for intent, never for exact class tokens — grep the theme/globals.css (or existing usages) for any plan-quoted Tailwind color before using it; a wrong `ring-/bg-/text-soleur-*` is a SILENT no-op (no tsc/test failure).
2. **A test asserted `getByText("#100")` but `IssueCard` renders the raw id `100` (no `#`).** — Recovery: asserted the card title instead. **Prevention:** when asserting on a reused presentational component's output, read that component's JSX for the exact rendered text rather than assuming a format.
3. **The planning subagent left the plan file uncommitted and wrote no `specs/feat-<branch>/tasks.md`.** — Recovery: committed the plan + hand-wrote session-state.md. **Prevention:** after a plan+deepen subagent returns, `git status` for the plan artifact and commit it before `/work` (the work skill reads the plan path directly, so a missing tasks.md is non-fatal).
4. **Review AND compound both asserted "no desktop regression" + "full test-all.sh green", but the CSS dual-render had actually broken 12 tests in the sibling `workstream-board.test.tsx` (duplicate `IssueCard` text → `getByText` "Found multiple elements").** Escaped review + compound; caught only at `/ship` Phase 4 when the full suite reported `217/218` and the one failing suite was `[FAIL] apps/web-platform (0ms)`. — Recovery: switched the component from the CSS dual-render to a `useMediaQuery` gate (renders one tree; happy-dom defaults to a 1024px viewport so the desktop tests pass unchanged), added a narrow-viewport integration test, corrected this learning's Pattern #1. **Prevention:** (a) NEVER assert "test-all green" from a summary count — a `N-1/N` line means one suite failed; grep the log for the non-`[ok]` suite. (b) A dual-render that duplicates queryable content MUST be run against the EXISTING sibling-component test that queries global `screen`, not just its own new test — the new test renders the mobile component in isolation and cannot surface the duplication. (c) `[FAIL] <suite> (0ms)` = a whole sub-suite crashed/failed, not a 0-cost pass.

## Tags
category: ui-bugs
module: apps/web-platform/components/workstream (mobile-board, mobile-status-selector, workstream-board)
