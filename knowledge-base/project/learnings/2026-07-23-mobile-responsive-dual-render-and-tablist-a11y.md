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

### 1. Breakpoint-gated sibling dual-render is the SSR-safe way to ship a mobile-specific layout

To add a mobile layout without a rewrite of the desktop one, render BOTH as siblings and gate with **pure Tailwind**, no `useMediaQuery`:
```tsx
<div className="hidden gap-3 overflow-x-auto pb-4 md:flex">{/* desktop 7 columns */}</div>
<MobileBoard issues={filtered} onOpen={openIssue} className="md:hidden" />
```
Both subtrees render identically on server and client (CSS hides one) → **no hydration mismatch, no JS layout flash**. A `useMediaQuery`/`matchMedia` gate would render different trees on server vs. first client paint → hydration mismatch + flash. This matches the codebase's existing `hidden … md:flex` / `md:hidden` idiom (chat-surface, chat-input, nav-count-badge). The mobile component **consumes the parent's already-computed derived state** (the `filtered` array + the `openIssue` callback) rather than re-deriving — so filters/search, URL sync, and write orchestration stay single-sourced with zero duplication and no drift.

Bounded cost: the mobile sibling renders ONLY the selected status's cards (capped), so the always-mounted hidden subtree is a small, effect-free addition.

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

## Tags
category: ui-bugs
module: apps/web-platform/components/workstream (mobile-board, mobile-status-selector, workstream-board)
