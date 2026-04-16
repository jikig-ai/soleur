---
title: "fix: PDF viewer height overflow hides pagination controls"
type: fix
date: 2026-04-16
deepened: 2026-04-16
---

# fix: PDF viewer height overflow hides pagination controls

## Enhancement Summary

**Deepened on:** 2026-04-16
**Sections enhanced:** 4 (Root Cause, Phase 1, Phase 2, Phase 3)
**Research sources:** Context7 (react-pdf, Tailwind CSS), project learnings (3 relevant)

### Key Improvements

1. Added precise CSS spec citation for `min-height: auto` behavior in flex containers
2. Confirmed react-pdf `width` prop approach is correct; added `devicePixelRatio` performance note
3. Added `overflow-hidden` as alternative to `min-h-0` with tradeoff analysis
4. Added edge case: the `overflow-y-auto` on the markdown content wrapper must NOT be changed (only the file preview wrapper)

### New Considerations Discovered

- The `min-h-0` fix must be applied ONLY to the file preview wrapper (line 145), not the markdown content wrapper (line 178) which correctly uses `overflow-y-auto` for long documents
- react-pdf renders at native `devicePixelRatio` by default, which can cause performance issues on 3x displays; a `devicePixelRatio={Math.min(2, window.devicePixelRatio)}` cap on the `Page` component would improve mobile performance (out of scope but noted)

The PDF viewer's page navigation controls (Previous/Next buttons and page counter) are cut off below the viewport. Users must scroll down past the PDF content area to reach them, making multi-page PDF navigation difficult to discover and use.

## Root Cause

The `PdfPreview` component uses `h-full` on its root div and relies on its parent providing a bounded height. The height chain breaks in two contexts:

### Dashboard context (`app/(dashboard)/dashboard/kb/[...path]/page.tsx`)

The file preview content area (line 145) uses `className="flex-1 overflow-y-auto"`. Inside this, `FilePreview` renders `PdfPreview` which uses `h-full` -- but `h-full` resolves to 100% of the parent's content height, not its constrained height. The `overflow-y-auto` on the content wrapper means the PDF document expands to its natural height, pushing the pagination `div` below the viewport fold.

The height chain:

1. `main.flex-1.overflow-y-auto` (dashboard layout -- the scrolling container)
2. `div.flex.h-full.flex-col` (kb content page wrapper)
3. `div.flex-1.overflow-y-auto` (content area for FilePreview)
4. `PdfPreview` root: `div.flex.h-full.flex-col.gap-3.p-4`
5. PDF document container: `div.flex-1.overflow-auto`
6. Pagination: `div.flex.items-center.justify-center.gap-3` -- pushed below fold

The problem is at level 3: `flex-1 overflow-y-auto` creates a scrollable container whose children can grow beyond the viewport. The `h-full` on `PdfPreview` does not constrain because the parent has no explicit height -- it grows with content.

### Research Insights: CSS Spec Behavior

Per CSS Flexible Box Layout Module Level 1 (Section 4.5), the default `min-height` for flex items in a column flex container is `auto`, which resolves to the content's intrinsic minimum height. This prevents flex items from shrinking below their content size, even when `flex: 1` (i.e., `flex-shrink: 1`) is set. Setting `min-height: 0` (`min-h-0` in Tailwind) overrides this default and allows the item to shrink to zero, enabling the flex container to constrain its children to the available space.

This is the same pattern documented in the project learning `2026-04-15-flex-column-width-and-markdown-overflow-2229.md` (horizontal axis: `min-w-0`) and `2026-02-17-backdrop-filter-breaks-fixed-positioning.md` (height calculation gotchas in nested containers). The key principle: **`min-h-0` must be applied at every flex-item level between the viewport-height ancestor (`h-dvh`) and the component that needs bounded height (`h-full`)**.

### Shared page context (`app/shared/[token]/page.tsx`)

The PDF is wrapped in `<div className="h-[80vh]">` (line 147). This provides a bounded height, so the issue is less severe here. However, 80vh plus the page header (~49px) plus `pt-6 pb-20` padding on `<main>` can still push the pagination controls below the fold on shorter viewports (under ~900px).

## Implementation Plan

### Phase 1: Fix dashboard PDF viewer height containment

**File:** `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`

Change the content area wrapper for file previews from `flex-1 overflow-y-auto` to `flex-1 overflow-hidden` (or remove the `overflow-y-auto`). The `PdfPreview` component already manages its own internal scrolling via `overflow-auto` on the document container (line 71 of `pdf-preview.tsx`). The outer wrapper's `overflow-y-auto` is redundant and breaks height containment.

Specifically, change line 145:

```tsx
// Before
<div className="flex-1 overflow-y-auto">

// After
<div className="min-h-0 flex-1">
```

The `min-h-0` is critical: in a flex column, flex items default to `min-height: auto`, which prevents them from shrinking below their content size. Adding `min-h-0` allows the flex item to shrink, giving `h-full` on `PdfPreview` a bounded reference height. This follows the same pattern documented in the `2026-04-15-flex-column-width-and-markdown-overflow-2229.md` learning (the `min-w-0` pattern but for the vertical axis).

**Alternative considered: `overflow-hidden` instead of `min-h-0`**

Changing from `overflow-y-auto` to `overflow-hidden` would also contain the height, because `overflow: hidden` establishes a block formatting context that constrains children. However, `overflow-hidden` clips any content that overflows, which could hide content if a non-PDF file type (e.g., a tall image or long download UI) rendered inside this wrapper. `min-h-0` is the more surgical fix: it addresses the flex minimum size constraint directly without changing overflow behavior.

### Research Insights: Height Chain Verification

The full height chain from viewport to PdfPreview pagination must propagate bounded height at every level:

```text
div.flex.h-dvh.flex-col.md:flex-row     (dashboard layout -- viewport height)
  main.flex-1.overflow-y-auto            (main content -- scrolls, BUT kb layout is nested inside)
    div.flex.h-full                       (kb layout -- fills main)
      div.min-w-0.flex-1.overflow-y-auto  (kb content area -- scrolls on content pages)
        div.flex.h-full.flex-col          (file page wrapper -- fills content area)
          header.shrink-0                 (page header -- fixed height)
          div.min-h-0.flex-1             ** FIX: was flex-1.overflow-y-auto **
            PdfPreview (h-full flex-col)
              div.flex-1.overflow-auto    (PDF canvas -- scrolls internally)
              div (pagination -- stays visible)
```

The `overflow-y-auto` on the kb content area (`min-w-0 flex-1 overflow-y-auto` in `kb/layout.tsx` line 277) is correct and must remain -- it handles scrolling for markdown content pages. The fix targets only the file preview content wrapper INSIDE the file page, not the layout-level scroller.

**Critical: do NOT change the markdown content wrapper** on line 178 of the same file (`className="flex-1 overflow-y-auto px-4 py-6 md:px-8"`). That wrapper correctly scrolls long markdown documents. Only the file preview wrapper on line 145 needs the fix.

### Phase 2: Fix shared page PDF viewer height

**File:** `apps/web-platform/app/shared/[token]/page.tsx`

Replace the fixed `h-[80vh]` wrapper with a calculation that accounts for the header and main padding. Use `calc()` via a Tailwind arbitrary value:

```tsx
// Before
<div className="h-[80vh]">

// After
<div className="h-[calc(100vh-theme(spacing.20)-theme(spacing.6)-49px)]">
```

However, this is fragile and couples to header height. A cleaner approach: make the shared page use a flex column layout similar to the dashboard, so the PDF viewer fills the remaining space naturally:

```tsx
// Better approach: restructure shared page main to use flex
<main className="flex min-h-0 flex-1 flex-col px-4 pb-20 pt-6">
  <div className="mx-auto w-full max-w-3xl flex-1">
    {/* ... */}
    {data?.kind === "pdf" && (
      <div className="flex h-full flex-col">
        <PdfPreview src={data.src} filename={data.filename} />
      </div>
    )}
```

But note: the shared page uses `min-h-screen` on the outer wrapper (not `h-screen`), meaning it is a document-flow page, not a viewport-constrained app shell. The `h-[80vh]` approach is actually the right pattern for a document-flow page -- just needs a slightly smaller value to account for chrome.

**Decision:** Keep the `h-[80vh]` pattern but reduce to `h-[70vh]` to provide more breathing room for the header + padding, ensuring pagination is visible on viewports as small as 768px. This is the minimal change with no structural risk.

### Phase 3: Ensure PdfPreview internal layout is correct

**File:** `apps/web-platform/components/kb/pdf-preview.tsx`

The `PdfPreview` component's internal layout is already correct:

- Root: `flex h-full flex-col gap-3 p-4` -- flex column filling parent
- Document container: `flex-1 overflow-auto` -- takes available space, scrolls internally
- Pagination: `flex items-center justify-center gap-3` -- fixed at bottom (not flex-1)

No changes needed to this file. The pagination controls will naturally stay visible when the parent provides a bounded height.

### Research Insights: react-pdf Container Sizing

Per react-pdf documentation (Context7, wojtekmaj/react-pdf v10):

- The `Page` component's `width` prop controls rendering size. The component already uses `ResizeObserver` to track `containerWidth` and passes it as `width={containerWidth}` -- this is the recommended pattern.
- **Do not resize the `<canvas>` element using CSS.** Resizing with CSS affects only the canvas layer, leaving text and annotation layers misaligned. Size must be controlled via `width`/`height`/`scale` props.
- **Performance note (out of scope):** react-pdf renders at native `devicePixelRatio` by default. On 3x displays, this means 9x the pixel count. Adding `devicePixelRatio={Math.min(2, window.devicePixelRatio)}` to the `Page` component would cap rendering density and improve mobile performance. This is a separate enhancement, not part of this fix.

### Phase 4: Update tests

**File:** `apps/web-platform/test/file-preview.test.tsx`

Existing tests verify PDF rendering and pagination button behavior. No new tests are needed for the height fix because:

- jsdom/happy-dom do not perform layout (per learning `2026-04-15-flex-column-width-and-markdown-overflow-2229.md`, insight 5)
- The fix is a CSS class change, not a logic change
- Visual verification requires Playwright (QA phase)

Optionally, add a snapshot or class-assertion test to guard against regression:

```tsx
it("dashboard file preview wraps PDF in height-constrained container", () => {
  // Verify the className on the wrapper includes min-h-0
  // This guards against reverting the fix
});
```

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` | Change content wrapper from `flex-1 overflow-y-auto` to `min-h-0 flex-1` |
| `apps/web-platform/app/shared/[token]/page.tsx` | Change `h-[80vh]` to `h-[70vh]` on PDF container |

## Files NOT Modified (and why)

| File | Reason |
|------|--------|
| `apps/web-platform/components/kb/pdf-preview.tsx` | Internal layout is correct; fix is in parent containers |
| `apps/web-platform/components/kb/file-preview.tsx` | Pass-through component; no layout responsibility |

## Acceptance Criteria

- [ ] PDF page navigation controls (Previous, page counter, Next) are visible without scrolling when viewing a multi-page PDF in the dashboard KB viewer
- [ ] PDF page navigation controls are visible without scrolling when viewing a multi-page PDF via a shared link (`/shared/[token]`)
- [ ] The PDF document content area scrolls internally when the PDF page is taller than the available space
- [ ] Single-page PDFs (no pagination controls) still render correctly with no blank space where controls would be
- [ ] Image preview, text preview, and download preview in the dashboard are unaffected
- [ ] The fix works on viewports as small as 768px height

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CSS bug fix in existing UI components.

## Test Scenarios

- Given a multi-page PDF open in the dashboard KB viewer, when the page loads, then the Previous/Next buttons and page counter are visible without scrolling
- Given a multi-page PDF open via a shared link, when the page loads, then the Previous/Next buttons and page counter are visible without scrolling
- Given a tall single-page PDF in the dashboard, when the page loads, then the PDF content scrolls within its container and no pagination controls appear
- Given an image file in the dashboard KB viewer, when the page loads, then the image preview renders correctly (regression check)
- Given a .txt file in the dashboard KB viewer, when the page loads, then the text preview renders correctly (regression check)
- Given a multi-page PDF in the dashboard with the KB file tree sidebar collapsed (Cmd+B), when the viewport is narrow (768px width), then the pagination controls are still visible
- Given a multi-page PDF in the dashboard with the chat sidebar open, when the viewport is standard width (1280px), then the pagination controls are still visible despite reduced content area width
- Given the shared page viewed on a short viewport (768px height), when a multi-page PDF loads, then the pagination controls are visible within the `h-[70vh]` container without scrolling the outer page

## Context

### Relevant learnings

- `knowledge-base/project/learnings/ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`: Documents the `min-w-0` / `min-h-0` pattern for flex containers. Key insight: flex items default to `min-height: auto` (or `min-width: auto`), preventing shrinking below content size. Adding `min-h-0` at each flex level is required to propagate height constraints.
- `knowledge-base/project/learnings/2026-04-07-kb-viewer-react-context-layout-patterns.md`: Documents KB two-panel layout patterns, including the App Router layout persistence model and context-driven sidebar state.
- `knowledge-base/project/learnings/ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md`: Documents the fix for sidebar disappearing on navigation -- the same layout file we are modifying. Confirms `FileTree` is rendered directly in layout, not via children.
- `knowledge-base/project/learnings/2026-04-15-kb-share-binary-files-lifecycle.md`: Documents the shared page binary file viewer implementation, including the `PdfPreview` reuse pattern and CSP configuration. Confirms the shared page's `h-[80vh]` wrapper was an MVP choice.
- `knowledge-base/project/learnings/2026-02-17-backdrop-filter-breaks-fixed-positioning.md`: Documents height calculation gotchas in CSS when containing blocks are established by unexpected properties. Same class of issue: viewport-relative sizing assumptions broken by intermediate containers.

### Key file paths

- `apps/web-platform/components/kb/pdf-preview.tsx` -- the PDF viewer component
- `apps/web-platform/components/kb/file-preview.tsx` -- file type router component
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` -- dashboard KB content page
- `apps/web-platform/app/shared/[token]/page.tsx` -- shared document page
- `apps/web-platform/app/(dashboard)/layout.tsx` -- dashboard shell layout (defines `h-dvh` and `flex-1`)
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` -- KB two-panel layout

## MVP

Two class changes: `min-h-0 flex-1` on the dashboard content wrapper, `h-[70vh]` on the shared page PDF container.

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| Add `max-h-[80vh]` to PdfPreview root | Couples viewport constraint to the component instead of the layout; breaks reusability in contexts with different available heights |
| Use `position: sticky` on pagination | Over-engineering for a layout containment issue; sticky positioning interacts poorly with nested scroll containers |
| Restructure shared page to flex app shell | The shared page is a document-flow page by design (with `min-h-screen`); converting it to an app shell changes its scrolling model unnecessarily |
