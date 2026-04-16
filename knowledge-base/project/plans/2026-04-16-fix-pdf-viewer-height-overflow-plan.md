---
title: "fix: PDF viewer height overflow hides pagination controls"
type: fix
date: 2026-04-16
---

# fix: PDF viewer height overflow hides pagination controls

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

## Context

### Relevant learnings

- `knowledge-base/project/learnings/ui-bugs/2026-04-15-flex-column-width-and-markdown-overflow-2229.md`: Documents the `min-w-0` / `min-h-0` pattern for flex containers. Key insight: flex items default to `min-height: auto` (or `min-width: auto`), preventing shrinking below content size. Adding `min-h-0` at each flex level is required to propagate height constraints.

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
