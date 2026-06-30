# Learning: `components/ui/sheet.tsx` desktop branch is an inline push-column, not an overlay

## Problem

A new desktop consumer (the Workstream issue-detail drawer) used the shared
`<Sheet>` primitive expecting a right-edge slide-in **overlay** (per the approved
mock). On desktop the panel rendered instead as a 380px, content-height box
stacked **below** the kanban columns — visually broken — and `tsc` + the unit
suite were all green. The component test rendered `IssueDetailSheet` at the test
root (its own flex context), so it never reproduced the board's block layout and
never caught it. Multi-agent review (pattern-recognition) flagged it as P2.

## Root cause

`components/ui/sheet.tsx` has two breakpoint branches:

- **Mobile:** `createPortal(panel, document.body)` → a fixed bottom-sheet overlay.
- **Desktop (`min-width: 768px`):** `return panel` **inline** with
  `flex h-full w-[380px] shrink-0 ... border-l`. It is designed to be a
  **flex-row sibling inside a full-height flex container** (the content area
  shrinks to make room) — NOT a portaled overlay. It renders no backdrop and
  does no focus management.

The only other consumer (`components/chat/kb-chat-sidebar.tsx`) is explicitly
**mobile-only**; on desktop that feature renders its content directly inside a
Panel. So Workstream was the first desktop consumer of the inline branch, and it
placed the Sheet inside a plain block `<div>` (`<main className="px-6 py-8">`)
with no full-height flex parent — hence the box-below-columns render.

## Solution

When the design calls for a floating **overlay drawer** on desktop, do NOT use
the shared `Sheet`'s desktop branch. Render a self-contained portal overlay:

```tsx
return createPortal(
  <div className="fixed inset-0 z-50">
    <div className="absolute inset-0 bg-black/40" aria-hidden onClick={onClose} />
    <div role="dialog" aria-modal="true" aria-label={label}
         className="absolute right-0 top-0 flex h-full w-full max-w-[440px] flex-col border-l ... shadow-2xl">
      {children}
    </div>
  </div>,
  document.body,
);
```

This also let us add backdrop-click close + Esc + focus-return (focus the close
button on open, restore the opener on close) — which the shared `Sheet` does not
provide on desktop. If instead you genuinely want the **push-column** layout
(content shrinks beside the panel, Linear-style), use the shared `Sheet` but make
the parent a `flex h-full` row so the inline branch sits as a real right column.

## Key Insight

A breakpoint-branched UI primitive can have fundamentally different rendering
*topologies* per breakpoint (portaled-overlay vs inline-flex-child). A
component test that renders the primitive at the test root validates neither
topology against its real parent layout. When adopting such a primitive on a
**new breakpoint or a new parent layout**, verify the rendered topology in a
real-CSS context (the mock, or a headless-Chromium gate) — jsdom and a
root-rendered RTL test are both blind to it. Decide overlay-vs-push from the
design and pick the matching mechanism explicitly.

## Tags
category: ui-bugs
module: apps/web-platform/components/ui/sheet.tsx
