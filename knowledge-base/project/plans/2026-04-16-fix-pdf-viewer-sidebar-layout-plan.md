---
title: "fix: PDF viewer truncation and KB sidebar collapse icon misalignment"
type: fix
date: 2026-04-16
---

# fix: PDF viewer truncation and KB sidebar collapse icon misalignment

## Overview

Two related layout bugs in the dashboard KB viewer:

1. **PDF rendering truncation** -- The PDF viewer is clipped at the bottom depending on sidebar collapse state. Only when both sidebars are collapsed AND the chat panel is open does the PDF render fully with correct aspect ratio. The PDF should render fully regardless of sidebar state.
2. **KB sidebar collapse icon misalignment** -- When both sidebars are collapsed, the KB sidebar expand button is not vertically aligned with the main sidebar collapse icon, creating a visually inconsistent UX.

## Problem Statement

### Bug 1: PDF truncation

The height chain from the viewport to the PDF canvas has a break in CSS height propagation:

1. **Dashboard layout** (`app/(dashboard)/layout.tsx`): `<div class="flex h-dvh">` -> `<main class="flex-1 overflow-y-auto">` -- the main content area uses `overflow-y-auto` and `flex-1`, which establishes a scroll container but does NOT propagate a fixed height to children.
2. **KB layout** (`app/(dashboard)/dashboard/kb/layout.tsx`): `<div class="flex h-full">` -> content area `<div class="min-w-0 flex-1 overflow-y-auto">` -- this uses `h-full` which depends on the parent having a defined height. Since `<main>` is an `overflow-y-auto` scroll container with `flex-1`, `h-full` resolves correctly when the flex container provides the constraint.
3. **KB content page** (`app/(dashboard)/dashboard/kb/[...path]/page.tsx`): For non-markdown files, renders `<div class="flex h-full flex-col">` -> `<div class="flex-1 overflow-y-auto">` -> `<FilePreview>` -> `<PdfPreview>`.
4. **PdfPreview** (`components/kb/pdf-preview.tsx`): `<div class="flex h-full flex-col gap-3 p-4">` -> container div `<div class="flex-1 overflow-auto">` -> `<Document>` -> `<Page width={containerWidth}>`.

The issue is that `react-pdf`'s `<Page>` component renders an intrinsic-height canvas. When given only `width`, it computes height from the PDF page's aspect ratio. If the containing chain does not constrain height, the canvas grows to its natural height, which may exceed the available viewport space. The `overflow-auto` on the container div allows scrolling within it, but the outer `h-full` on PdfPreview depends on the entire height chain being unbroken.

The real problem: when sidebars change width, the content area's width changes, but the height constraint chain may break because `overflow-y-auto` on `<main>` creates a new scroll context. The PDF's natural height (computed from width via aspect ratio) is then too tall, and the bottom is clipped because the parent `flex-1` div does not constrain its height properly when `h-full` cannot resolve.

When the chat sidebar opens, it takes horizontal space, narrowing the PDF container width. A narrower width means a proportionally shorter page height (maintaining aspect ratio), which happens to fit within the viewport -- making the PDF appear "fixed" when the chat panel is open.

### Bug 2: Collapse icon misalignment

The main sidebar collapse toggle is positioned in the brand header area using `flex items-center justify-between` layout. When collapsed, the main sidebar shows a `ChevronRight` icon.

The KB sidebar expand button (shown when KB sidebar is collapsed) is rendered inside the content area (`kb/layout.tsx` line 281-292) with `m-2 h-8 w-8` styling -- a floating button with absolute margin positioning. The main sidebar's collapse toggle in the header uses `h-6 w-6` and is positioned via flexbox `justify-between` within the header row. These two icons have different sizes, different vertical positions (one is in the header flow, one is offset by `m-2` from the content area top), and are not aligned.

## Proposed Solution

### Fix 1: PDF height constraint

Replace the `h-full` approach with a proper height containment strategy. The PdfPreview component should use `min-h-0` + `flex-1` in its ancestor chain to allow the flexbox layout to properly constrain the height, and the PDF container should use `object-contain`-style rendering with `max-h` constraints rather than relying on an unbroken `h-full` chain.

**Specific changes:**

1. In `components/kb/pdf-preview.tsx`:
   - Change the outer wrapper from `h-full` to `min-h-0 h-full` (flex item height containment)
   - Add `min-h-0` to the `flex-1` container div that wraps the `<Document>` -- this ensures the flex item can shrink below its content size
   - Add `[&_canvas]:max-h-full [&_canvas]:w-auto [&_canvas]:mx-auto` to the container to constrain the rendered canvas to fit within the available space while maintaining aspect ratio
   - OR: Instead of constraining canvas via CSS, track container height with ResizeObserver (already tracking width) and pass the `height` prop to `<Page>` when the computed height (from width + aspect ratio) exceeds the container height

2. In `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:
   - Ensure the file preview wrapper `<div class="flex-1 overflow-y-auto">` also has `min-h-0` so the flex height containment is unbroken

The preferred approach is **option 1** (CSS containment via `min-h-0` + canvas `max-h-full`), because it avoids adding JS complexity and works naturally with flexbox.

### Fix 2: KB sidebar collapse icon alignment

Move the KB sidebar expand button (when collapsed) from its current floating position in the content area to the header row of the content area, aligned with the main sidebar's collapse toggle position.

**Specific changes:**

1. In `app/(dashboard)/dashboard/kb/layout.tsx`:
   - Remove the floating expand button from the content area (lines 281-292)
   - Add the expand button to the KB content header area, positioned consistently with the main sidebar's collapse toggle -- same size (`h-6 w-6`), same vertical alignment (in the header `flex items-center justify-between` row)
   - When KB sidebar is collapsed, show the expand icon in the header area of the content pane, at the same vertical position as the main sidebar's collapse toggle

## Acceptance Criteria

- [ ] PDF renders fully (no bottom truncation) when both sidebars are expanded
- [ ] PDF renders fully when main sidebar is collapsed and KB sidebar is expanded
- [ ] PDF renders fully when both sidebars are collapsed
- [ ] PDF renders fully when both sidebars are collapsed and chat panel is open
- [ ] PDF maintains correct aspect ratio in all sidebar states
- [ ] PDF page navigation controls remain visible and functional in all states
- [ ] KB sidebar expand icon (when collapsed) is vertically aligned with the main sidebar collapse icon
- [ ] KB sidebar expand icon uses the same size (`h-6 w-6`) as the main sidebar collapse toggle for visual consistency
- [ ] Cmd+B shortcut still toggles the appropriate sidebar
- [ ] No layout shift or content jump when toggling sidebars
- [ ] Mobile layout (below md breakpoint) is unaffected

## Test Scenarios

- Given both sidebars expanded, when viewing a PDF file in the KB, then the entire PDF page is visible without bottom truncation
- Given main sidebar collapsed and KB sidebar expanded, when viewing a PDF file, then the PDF page is fully visible
- Given both sidebars collapsed, when viewing a PDF file, then the PDF page is fully visible and the KB expand icon aligns vertically with the main sidebar collapse icon
- Given both sidebars collapsed and chat panel open, when viewing a PDF file, then the PDF still renders fully (regression guard)
- Given a multi-page PDF, when navigating between pages in any sidebar state, then pagination controls remain visible and functional
- Given the browser window is resized, when sidebars change state, then the PDF re-renders to fit the new container width without truncation
- **Browser:** Navigate to `/dashboard/kb/<path-to-pdf>`, toggle sidebar states via Cmd+B, verify PDF rendering in each state

## Context

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/components/kb/pdf-preview.tsx` | Add `min-h-0` to flex containers, constrain canvas height |
| `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` | Add `min-h-0` to file preview wrapper |
| `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` | Move KB expand button to header-aligned position |

### Related code

- `apps/web-platform/app/(dashboard)/layout.tsx` -- Main dashboard layout with sidebar collapse (lines 192-344)
- `apps/web-platform/hooks/use-sidebar-collapse.ts` -- Collapse state persistence hook
- `apps/web-platform/components/kb/file-preview.tsx` -- FilePreview wrapper that renders PdfPreview for `.pdf` files
- PR #2423: `fix(dashboard): unify sidebar collapse toggle position to header top-right` -- Recent related fix
- PR #2415: `feat(dashboard): collapsible sidebars with Cmd+B shortcut` -- Introduced collapsible sidebars

### Root cause analysis

The CSS `h-full` chain from `h-dvh` on the outermost div down to PdfPreview's container is fragile. It works when the total content height fits the viewport but breaks when sidebar width changes cause the PDF to compute a taller intrinsic height. The `overflow-y-auto` on intermediate containers creates scroll contexts that mask the overflow rather than constraining children. Adding `min-h-0` to flex items in the chain allows flexbox to properly distribute space and constrain the PDF canvas height.

## Alternative Approaches Considered

| Approach | Reason Not Chosen |
|----------|-------------------|
| Use `height` prop on `<Page>` with JS calculation | Adds unnecessary JS complexity; CSS containment is sufficient |
| Use `object-fit: contain` on canvas directly | `react-pdf` renders a `<canvas>` element whose dimensions are set programmatically; CSS `object-fit` does not affect canvas rendering |
| Set fixed `max-height` (e.g., `calc(100vh - 120px)`) | Fragile -- depends on header heights staying fixed; breaks with payment banners or variable-height headers |

## Domain Review

**Domains relevant:** Product (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

This is a bug fix restoring correct rendering behavior, not a new UI feature. No UX design review needed.

## References

- Learning: [KB viewer layout patterns](../../learnings/2026-04-07-kb-viewer-react-context-layout-patterns.md)
- PR #2423: Sidebar collapse toggle unification
- PR #2415: Collapsible sidebars with Cmd+B shortcut
- PR #2412: KB chat sidebar inline rendering on desktop
- [react-pdf docs](https://www.npmjs.com/package/react-pdf) -- `<Page>` component accepts `width` and `height` props
