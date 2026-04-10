---
title: "fix: KB navigation tree disappears when selecting a file"
type: fix
date: 2026-04-10
---

# fix: KB navigation tree disappears when selecting a file

## Overview

When a user clicks a file in the Knowledge Base navigation tree, the sidebar tree disappears entirely. The tree should remain visible and expanded in the sidebar while the selected file's content renders in the main content area.

## Problem Statement

The KB page uses a two-panel layout (`layout.tsx`) with a sidebar for the file tree and a main area for content. The layout relies on Next.js App Router's `children` prop to render both the tree and content views, but `children` can only be one page at a time:

- At `/dashboard/kb`, `children` is `page.tsx` (renders `FileTree`)
- At `/dashboard/kb/some-file.md`, `children` is `[...path]/page.tsx` (renders file content)

The layout conditionally renders `children` inside the sidebar only when `!isContentView` (line 101 of `layout.tsx`):

```tsx
{!isContentView && children}
```

When navigating to a file, `isContentView` becomes `true`, so the sidebar `<aside>` renders empty -- the `FileTree` component is never placed there because `children` is now the content page, not the tree page.

## Proposed Solution

Render the `FileTree` and `SearchOverlay` directly in the layout's sidebar instead of relying on `children` for tree rendering. The sidebar should always show the tree when content is loaded, regardless of the current route. The `page.tsx` at `/dashboard/kb` becomes either redundant (removed) or simplified to only handle the mobile full-screen tree view.

### Changes Required

**1. `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`**

In the two-panel layout branch (lines 91-116), render the tree directly in the `<aside>` instead of conditionally rendering `children`:

- Import `FileTree` and `SearchOverlay` components directly
- Always render the tree sidebar content (header + search + file tree) in the `<aside>` element
- Render `children` only in the content area `<div>` on the right
- Keep the mobile responsive behavior: on mobile, show sidebar when at root (`!isContentView`), show content when viewing a file (`isContentView`)

Current problematic pattern:

```tsx
<aside className={`... ${isContentView ? "hidden" : "block"}`}>
  {!isContentView && children}  {/* BUG: empty when viewing content */}
</aside>
<div className={`... ${isContentView ? "block" : "hidden"}`}>
  {isContentView ? children : <DesktopPlaceholder />}
</div>
```

Fixed pattern:

```tsx
<aside className={`... ${isContentView ? "hidden" : "block"}`}>
  {/* Always render tree in sidebar */}
  <div className="flex h-full flex-col">
    <header className="shrink-0 px-4 pb-3 pt-4">
      <h1 className="font-serif text-lg font-medium tracking-tight text-white">
        Knowledge Base
      </h1>
    </header>
    <div className="shrink-0 px-3 pb-3">
      <SearchOverlay />
    </div>
    <div className="flex-1 overflow-y-auto px-2 pb-4">
      <FileTree />
    </div>
  </div>
</aside>
<div className={`... ${isContentView ? "block" : "hidden"}`}>
  {isContentView ? children : <DesktopPlaceholder />}
</div>
```

**2. `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`**

This page currently renders the tree header, search, and `FileTree`. After the fix, the layout handles tree rendering directly. The `page.tsx` should either:

- **Option A (preferred):** Keep `page.tsx` but make it render a simple redirect or the `DesktopPlaceholder` -- it only serves as the mobile landing for `/dashboard/kb`
- **Option B:** Remove the tree-rendering code from `page.tsx` entirely and let the layout handle all tree rendering. The page becomes minimal (possibly just a fragment or placeholder)

Since `page.tsx` is what `children` resolves to when at `/dashboard/kb`, and the layout already shows `DesktopPlaceholder` when `!isContentView`, the page only needs to exist for Next.js routing. It can be simplified to return `null` or a fragment since the layout handles everything.

**3. Auto-expand tree to show selected file**

When navigating to a file, the tree should auto-expand the parent directories of the selected file so the user can see where they are. Add a `useEffect` in `layout.tsx` that:

- Extracts the file path from `pathname` (strip `/dashboard/kb/` prefix)
- Computes all ancestor directory paths
- Adds them to the `expanded` set

This ensures the tree shows the active file's location highlighted.

## Acceptance Criteria

- [ ] Desktop: sidebar tree remains visible when clicking a file link
- [ ] Desktop: selected file is highlighted in the tree (existing `isActive` styling)
- [ ] Desktop: parent directories of the selected file auto-expand in the tree
- [ ] Desktop: "Select a file to view" placeholder shows on the right when no file is selected
- [ ] Mobile: tree view shows at `/dashboard/kb`, content shows at `/dashboard/kb/[...path]`
- [ ] Mobile: back arrow on content view returns to tree
- [ ] Folder expand/collapse state persists across file navigation
- [ ] Search overlay remains functional in the sidebar
- [ ] No duplicate tree rendering (tree renders once in sidebar, not in both sidebar and content area)

## Test Scenarios

- Given the KB page with loaded content, when the user clicks a file in the tree, then the file content appears on the right AND the tree remains visible on the left
- Given the user is viewing a file, when they click a different file in the tree, then the content updates and the tree stays visible with the new file highlighted
- Given the user is viewing a deeply nested file, when the page loads, then all parent directories are expanded to reveal the file's position
- Given the user manually collapses a directory, when they navigate to a file in a different directory, then the manually collapsed directory stays collapsed (only ancestors of the selected file auto-expand)
- Given a mobile viewport at `/dashboard/kb`, when the user clicks a file, then only the content view shows (tree is hidden)
- Given a mobile viewport viewing a file, when the user clicks the back arrow, then the tree view shows again

## Context

### Files to Modify

- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` -- primary fix location
- `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx` -- simplify (tree rendering moved to layout)

### Files for Reference (read-only)

- `apps/web-platform/components/kb/file-tree.tsx` -- tree component
- `apps/web-platform/components/kb/kb-context.tsx` -- context definition
- `apps/web-platform/components/kb/search-overlay.tsx` -- search component
- `apps/web-platform/components/kb/kb-breadcrumb.tsx` -- breadcrumb component
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` -- content page

### Related Learning

- `knowledge-base/project/learnings/2026-04-07-kb-viewer-react-context-layout-patterns.md` -- documents the initial KB viewer implementation patterns and context-driven layout decisions

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a frontend bug fix in an existing UI component.

## References

- Next.js App Router layouts documentation: layouts wrap pages and persist across navigation, but `children` changes to the matched page component
- The `expanded` state in `KbContext` already supports path-based keys (learning finding #2)
