---
title: "fix: PDF viewer truncation and KB sidebar collapse icon misalignment"
type: fix
date: 2026-04-16
deepened: 2026-04-16
---

# fix: PDF viewer truncation and KB sidebar collapse icon misalignment

## Enhancement Summary

**Deepened on:** 2026-04-16
**Sections enhanced:** 3 (Proposed Solution, Alternative Approaches, Context)
**Research sources:** react-pdf v10 docs (Context7), CSS flexbox spec, project learnings

### Key Improvements

1. **Corrected the CSS canvas constraint approach** -- react-pdf docs explicitly warn against resizing `<canvas>` via CSS (`[&_canvas]:max-h-full` would cause layer misalignment). Replaced with proper `min-h-0` flex containment that lets the existing `overflow-auto` handle scrollable PDF content.
2. **Added height-based width calculation as the recommended approach** -- When the PDF page is taller than the container, compute a `maxWidth` from the container height and the PDF aspect ratio, then pass `Math.min(containerWidth, maxWidth)` as the `width` prop. This ensures the canvas fits without scrolling.
3. **Documented react-pdf v10 constraint** -- `height` prop is ignored when `width` is set; sizing must go through `width` or `scale` only.

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

Replace the `h-full` approach with a proper height containment strategy using `min-h-0` on flex items to fix the height chain, combined with container-height-aware width calculation to ensure the PDF fits without scrolling.

### Research Insights -- react-pdf canvas sizing

**Critical constraint from react-pdf v10 docs:**

> "Avoid resizing the `<canvas>` element using CSS alone. Resizing the canvas with CSS affects only that layer, leaving other layers like the text and annotation layers out of sync. React-PDF requires precise knowledge of the rendering dimensions."

This means the originally proposed `[&_canvas]:max-h-full [&_canvas]:w-auto` CSS approach is **incorrect** -- it would resize the canvas visually but leave react-pdf's internal rendering dimensions unchanged, causing layer misalignment.

**react-pdf v10 `<Page>` sizing rules:**

- If `width` is set, `height` is ignored (react-pdf calculates height from aspect ratio)
- If only `height` is set, width is calculated from aspect ratio
- If neither is set, the page renders at its intrinsic size
- Sizing must go through the `width`, `height`, or `scale` props -- not CSS on the canvas

**Recommended approach: height-aware width calculation**

Since the component already uses a ResizeObserver to track `containerWidth`, extend it to also track `containerHeight`. Then compute the maximum width that would produce a page fitting within the container height:

```text
maxWidthFromHeight = containerHeight * (pageOriginalWidth / pageOriginalHeight)
effectiveWidth = Math.min(containerWidth, maxWidthFromHeight)
```

Pass `effectiveWidth` as the `width` prop to `<Page>`. This ensures react-pdf renders the canvas at exactly the right dimensions to fit the container -- no CSS resizing, no scrolling.

**Specific changes:**

1. In `components/kb/pdf-preview.tsx`:
   - Change the outer wrapper from `h-full` to `min-h-0 h-full` (flex item height containment)
   - Add `min-h-0` to the `flex-1` container div that wraps `<Document>` -- this ensures the flex item can shrink below its content size
   - Extend the existing ResizeObserver to also capture `containerHeight` (`entry.contentRect.height`)
   - Store the PDF page's original dimensions from `onLoadSuccess` callback on `<Page>` (provides `originalWidth` and `originalHeight`)
   - Compute `effectiveWidth = Math.min(containerWidth, containerHeight * (originalWidth / originalHeight))` when both container dimensions and page dimensions are available
   - Pass `effectiveWidth` (instead of raw `containerWidth`) as the `width` prop to `<Page>`
   - Account for padding: subtract the `p-4` padding (32px total vertical, 32px total horizontal) from container dimensions before calculation
   - Remove `gap-3` from the outer flex column and account for the pagination controls height (~40px) in the available height calculation

2. In `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:
   - Add `min-h-0` to the file preview wrapper `<div class="flex-1 overflow-y-auto">` so the flex height containment is unbroken

**Fallback behavior:** If the page dimensions are not yet known (before `onLoadSuccess` fires), use `containerWidth` as before -- the page may initially render taller than the container, but once dimensions are known, the next render will fit. This avoids a blank frame on initial load.

**Simpler alternative (if height-aware calculation is too complex):** Just ensure the `min-h-0` chain is unbroken and rely on the existing `overflow-auto` on the container div. This means the PDF page may be taller than the visible area and require scrolling within the viewer pane, but it would never be truncated/clipped. This is acceptable UX and significantly simpler to implement. The height-aware width calculation is the premium approach that eliminates scrolling entirely.

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

### Research Insights -- CSS flexbox height containment

**The `min-h-0` pattern:** In CSS flexbox, flex items have `min-height: auto` by default, which prevents them from shrinking below their content size. When a flex column has `flex: 1` items containing content taller than the container, the item refuses to shrink, pushing content outside the container (the "truncation" visible in the screenshots). Adding `min-h-0` (Tailwind: `min-h-0`) overrides this default, allowing the flex item to shrink to fit its allocated space. This is the canonical fix for "flex item won't shrink in column direction."

**Height chain verification for this bug:**

```text
h-dvh (dashboard layout)
  -> flex-1 overflow-y-auto (main)         <- scroll container, provides height context
    -> h-full flex (kb layout)             <- needs parent height (gets it from flex-1)
      -> flex-1 overflow-y-auto (content)  <- MISSING min-h-0 -- won't shrink below content
        -> h-full flex-col (kb page)       <- MISSING min-h-0
          -> flex-1 overflow-y-auto (preview wrapper) <- MISSING min-h-0
            -> h-full flex-col (PdfPreview)  <- MISSING min-h-0
              -> flex-1 overflow-auto (container) <- MISSING min-h-0
                -> canvas (intrinsic height from react-pdf)
```

Every flex item in the chain from `<main>` to the canvas container needs `min-h-0` to allow proper height constraint propagation. Missing it at any level breaks the chain.

### Research Insights -- Learning: KB viewer action-button consolidation

From `knowledge-base/project/learnings/2026-04-15-kb-viewer-consolidate-action-buttons.md`:

- The `showDownload` prop on `PdfPreview` defaults to `true` for the shared viewer (`/shared/[token]/page.tsx`) which renders `PdfPreview` directly (not via `FilePreview`). Changes to `PdfPreview`'s layout structure must preserve this default behavior.
- The `safeDecode` helper in `kb-breadcrumb.tsx` is used in the KB content page for filename derivation. Changes to the page layout must not break this import.
- When adding exports to modified modules, check for `vi.mock` factories in tests that need updating.
- Port collisions are a known issue when running dev servers across worktrees. QA should use `PORT=3001` fallback.

### Edge Cases

- **Payment banner visible:** When `subscriptionStatus === "past_due"` or `"unpaid"`, the dashboard layout renders a banner above `{children}` that consumes ~44px of vertical space. The height-aware width calculation must account for this by using the actual measured container height (via ResizeObserver), not a computed value.
- **Multi-page PDF with pagination controls:** The pagination bar consumes ~40px below the PDF canvas. The available height for the canvas must subtract this when computing `effectiveWidth`.
- **Single-page PDF:** No pagination controls rendered, so full container height is available for the canvas.
- **Zero-width container during sidebar animation:** The `md:transition-[width] md:duration-200` on sidebars means the container width changes gradually. The ResizeObserver fires multiple times during animation. The current implementation handles this correctly (each resize triggers a state update), but rapid state updates may cause visible re-rendering. Consider using `requestAnimationFrame` debouncing if flicker is observed.
- **Shared viewer at `/shared/[token]/page.tsx`:** Renders `PdfPreview` directly without the dashboard/KB layout wrapper. Changes to `PdfPreview`'s height calculation must work both with and without the flex containment chain. The `h-full` + `min-h-0` approach is safe because `min-h-0` has no effect when not inside a flex container.

## Alternative Approaches Considered

| Approach | Reason Not Chosen |
|----------|-------------------|
| CSS `[&_canvas]:max-h-full` on container | react-pdf docs explicitly warn: "avoid resizing the canvas element using CSS alone" -- causes layer misalignment between canvas, text layer, and annotation layer |
| Use `height` prop on `<Page>` instead of `width` | When `width` is set, `height` is ignored (react-pdf v10 behavior). Using only `height` would lose responsive width-to-container behavior |
| Use `object-fit: contain` on canvas directly | Same as CSS resize -- react-pdf manages canvas dimensions programmatically; CSS overrides desync layers |
| Set fixed `max-height` (e.g., `calc(100vh - 120px)`) | Fragile -- depends on header heights staying fixed; breaks with payment banners or variable-height headers |
| `min-h-0` only (no width calculation) | Viable as simpler alternative. Fixes truncation by allowing proper flex shrinking, but page may still be taller than viewport requiring in-pane scrolling. Acceptable UX but not optimal |

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
- Learning: [KB viewer action-button consolidation](../../learnings/2026-04-15-kb-viewer-consolidate-action-buttons.md)
- PR #2423: Sidebar collapse toggle unification
- PR #2415: Collapsible sidebars with Cmd+B shortcut
- PR #2412: KB chat sidebar inline rendering on desktop
- [react-pdf v10 README](https://github.com/wojtekmaj/react-pdf/blob/v10.1.0/README.md) -- `<Page>` props: `width` takes precedence over `height`; avoid CSS canvas resizing
- [react-pdf FAQ: layer misalignment](https://github.com/wojtekmaj/react-pdf/wiki/Frequently-Asked-Questions) -- "avoid resizing the canvas element using CSS alone"
- [CSS flexbox `min-height: auto`](https://www.w3.org/TR/css-flexbox-1/#min-size-auto) -- W3C spec: flex items default to `min-height: auto`, which prevents shrinking below content size
