---
title: "fix: KB navigation tree disappears when selecting a file"
type: fix
date: 2026-04-10
---

# fix: KB navigation tree disappears when selecting a file

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 5
**Research sources used:** Context7 Next.js docs, project learnings, source code analysis

### Key Improvements

1. Confirmed root cause via Next.js App Router documentation: layouts persist across navigation but `children` swaps to the matched page -- the sidebar must render tree components directly, not via `children`
2. Added concrete implementation code for the auto-expand `useEffect` with proper merge semantics (additive-only to preserve manual collapse state)
3. Added edge case handling for `page.tsx` simplification -- must still return a valid React node for the route to exist
4. Identified testing gap: no existing component tests for KB layout or file tree; added test strategy using stable `useRouter` mock pattern from project learning
5. Added performance consideration: `useMemo` the auto-expand path computation to avoid unnecessary set operations on every render

### New Considerations Discovered

- The `useEffect` dependency on `router` in the existing layout causes re-fetches when the router reference changes (documented in learning `2026-04-07-userouter-mock-instability-causes-useeffect-refire.md`) -- the fix should also stabilize this dependency
- `page.tsx` cannot return `null` directly in Next.js App Router (the route segment would not render) -- it should return a fragment or empty div
- The `SearchOverlay` component uses `Link` to navigate to files from search results -- this path also triggers the content view and must keep the sidebar visible

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

### Research Insights

**Next.js App Router Layout Behavior (from Context7 docs):**

> "A layout is UI that is **shared** between multiple pages. On navigation, layouts preserve state, remain interactive, and do not rerender."

This confirms the correct pattern: render persistent navigation components (like the file tree) directly in the layout, not via `children`. The layout persists across page navigations, so any component rendered directly in the layout will stay visible. The `children` prop swaps to whatever page matches the current route.

**Alternative Approach Considered: Parallel Routes**

Next.js supports `@slot` parallel routes where a layout receives multiple named slots as props. This would allow `@sidebar` and `children` to be separate page components. However, this is over-engineered for this bug -- the tree is already a reusable component (`FileTree`) that can be imported directly into the layout. Parallel routes add directory structure complexity for no benefit here.

## Proposed Solution

Render the `FileTree` and `SearchOverlay` directly in the layout's sidebar instead of relying on `children` for tree rendering. The sidebar should always show the tree when content is loaded, regardless of the current route. The `page.tsx` at `/dashboard/kb` becomes simplified since the layout handles tree rendering.

### Changes Required

**1. `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`**

In the two-panel layout branch (lines 91-116), render the tree directly in the `<aside>` instead of conditionally rendering `children`:

- Import `FileTree` and `SearchOverlay` components directly
- Always render the tree sidebar content (header + search + file tree) in the `<aside>` element
- Render `children` only in the content area `<div>` on the right
- Keep the mobile responsive behavior: on mobile, show sidebar when at root (`!isContentView`), show content when viewing a file (`isContentView`)

Current problematic pattern (lines 91-116):

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
import { FileTree } from "@/components/kb/file-tree";
import { SearchOverlay } from "@/components/kb/search-overlay";

// In the two-panel layout return:
<aside
  className={`w-full shrink-0 overflow-y-auto border-r border-neutral-800 md:block md:w-64 ${
    isContentView ? "hidden" : "block"
  }`}
>
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

<div
  className={`min-w-0 flex-1 overflow-y-auto md:block ${
    isContentView ? "block" : "hidden"
  }`}
>
  <KbErrorBoundary>
    {isContentView ? children : <DesktopPlaceholder />}
  </KbErrorBoundary>
</div>
```

### Research Insights

**Performance Consideration:** The `FileTree` and `SearchOverlay` components already consume context via `useKb()`. Since the layout provides the `KbContext` and does not re-render on navigation (App Router layout behavior), these components will correctly react to context changes (expand/collapse) without unnecessary re-renders of the layout itself.

**Edge Case -- Double Rendering:** When at `/dashboard/kb` (root), the layout renders `FileTree` in the sidebar AND `children` (which is `page.tsx`). If `page.tsx` still renders `FileTree`, the tree appears twice. This is why `page.tsx` must be simplified (see change 2 below).

**2. `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`**

This page currently renders the tree header, search, and `FileTree`. After the fix, the layout handles tree rendering directly. The page must be simplified to avoid duplicate rendering.

The page should return an empty fragment. It must still export a default component for the route segment to exist in Next.js App Router (a missing `page.tsx` means the route `/dashboard/kb` would not be routable):

```tsx
"use client";

export default function KnowledgeBasePage() {
  // Tree rendering is handled by layout.tsx sidebar
  // This page exists only to make /dashboard/kb a valid route
  return <></>;
}
```

The loading, error, empty, and no-project states are already handled by the layout's conditional rendering (lines 82-88 in `layout.tsx`), so `page.tsx` does not need to duplicate those checks.

### Research Insights

**Why not delete `page.tsx`?** In Next.js App Router, a route segment requires a `page.tsx` to be routable. Without it, `/dashboard/kb` would return a 404. The page must exist even if it renders nothing visible, because the layout's two-panel branch only activates when `!loading && !error && hasTreeContent` -- those early-return states still need a routable page.

**Why not return `null`?** React components can return `null`, but this is valid. An empty fragment `<></>` is more explicit and conventional for "intentionally renders nothing."

**3. Auto-expand tree to show selected file**

When navigating to a file, the tree should auto-expand the parent directories of the selected file so the user can see where they are. Add a `useEffect` in `layout.tsx` that watches `pathname` and expands ancestor directories.

```tsx
// In layout.tsx, after the existing useEffect for fetchTree:

useEffect(() => {
  if (!pathname.startsWith("/dashboard/kb/") || pathname === "/dashboard/kb") {
    return;
  }
  // Extract relative file path: "engineering/specs/some-file.md"
  const relativePath = pathname.slice("/dashboard/kb/".length);
  const segments = relativePath.split("/");

  // Build ancestor directory paths: ["engineering", "engineering/specs"]
  // Skip the last segment (the file itself)
  const ancestors: string[] = [];
  for (let i = 0; i < segments.length - 1; i++) {
    ancestors.push(segments.slice(0, i + 1).join("/"));
  }

  if (ancestors.length === 0) return;

  // Additive merge: add ancestors without removing existing expanded dirs
  setExpanded((prev) => {
    const next = new Set(prev);
    let changed = false;
    for (const dir of ancestors) {
      if (!next.has(dir)) {
        next.add(dir);
        changed = true;
      }
    }
    return changed ? next : prev;
  });
}, [pathname]);
```

### Research Insights

**Additive-only merge is critical.** The `setExpanded` call must only ADD ancestors, never remove existing entries. If a user manually expanded `marketing/` and then navigates to `engineering/specs/file.md`, the `marketing/` folder must stay expanded. The `changed` flag avoids creating a new Set reference when nothing was added, preventing unnecessary re-renders.

**Dependency array:** Only `pathname` is needed. `setExpanded` is a React state setter (stable reference). Do NOT include `expanded` in the dependency array -- that would create an infinite loop (effect modifies expanded, which triggers the effect again).

**Edge case -- URL-encoded paths:** If file paths contain spaces or special characters, `pathname` will be URL-encoded. The `split("/")` approach works correctly because the encoding preserves `/` as the separator. The tree node keys (`parentPath/name`) use unencoded names, so the ancestors must be decoded. Use `decodeURIComponent(pathname.slice("/dashboard/kb/".length))` before splitting.

**Edge case -- trailing slash:** If the URL has a trailing slash (e.g., `/dashboard/kb/engineering/`), the last segment from `split("/")` would be an empty string. The `segments.length - 1` skip handles this correctly since the empty string is the "file" that gets skipped.

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
- [ ] Search result links in sidebar correctly navigate to files while keeping sidebar visible

### Research Insights

**Edge Case -- Search Result Navigation:** The `SearchOverlay` component renders `Link` elements pointing to `/dashboard/kb/{path}`. When a user clicks a search result, the navigation triggers `isContentView = true`, which shows the content panel. The sidebar remains visible because the tree is now rendered directly in the layout. No changes needed to `SearchOverlay`, but this interaction path should be tested.

**Edge Case -- Direct URL Navigation:** When a user navigates directly to `/dashboard/kb/some-file.md` (bookmark, external link), the layout mounts fresh. The `fetchTree` effect fetches the tree, and the auto-expand effect expands ancestors. Both effects run on mount, but `fetchTree` is async while auto-expand is sync. The auto-expand effect will run before the tree data arrives (expanded set updated, but no tree nodes to display yet). This is fine -- when the tree data arrives, the nodes will render with the correct expanded state because `FileTree` reads from the `expanded` set in context.

## Test Scenarios

- Given the KB page with loaded content, when the user clicks a file in the tree, then the file content appears on the right AND the tree remains visible on the left
- Given the user is viewing a file, when they click a different file in the tree, then the content updates and the tree stays visible with the new file highlighted
- Given the user is viewing a deeply nested file, when the page loads, then all parent directories are expanded to reveal the file's position
- Given the user manually collapses a directory, when they navigate to a file in a different directory, then the manually collapsed directory stays collapsed (only ancestors of the selected file auto-expand)
- Given a mobile viewport at `/dashboard/kb`, when the user clicks a file, then only the content view shows (tree is hidden)
- Given a mobile viewport viewing a file, when the user clicks the back arrow, then the tree view shows again
- Given the user clicks a search result in the sidebar, then the file content loads and the tree remains visible with the file's parent directories expanded

### Research Insights

**Testing Strategy:** There are no existing component tests for the KB layout or file tree (verified by searching the `test/` directory). The existing `kb-reader.test.ts` only tests the server-side tree builder, not the UI components.

**When writing tests, apply the stable `useRouter` mock pattern** from learning `2026-04-07-userouter-mock-instability-causes-useeffect-refire.md`:

```typescript
// Correct -- stable reference
const mockPush = vi.fn();
const mockRouter = { push: mockPush };
vi.mock("next/navigation", () => ({
  useRouter: () => mockRouter,
  usePathname: () => "/dashboard/kb/engineering/specs/file.md",
}));
```

Do NOT create a new object per call -- this causes `useEffect` re-fires and flaky tests.

**Test the auto-expand logic with unit tests on the path computation:**

```typescript
// Extract ancestor computation into a pure function for testability
function getAncestorPaths(relativePath: string): string[] {
  const segments = relativePath.split("/");
  const ancestors: string[] = [];
  for (let i = 0; i < segments.length - 1; i++) {
    ancestors.push(segments.slice(0, i + 1).join("/"));
  }
  return ancestors;
}

// Test cases:
expect(getAncestorPaths("file.md")).toEqual([]);
expect(getAncestorPaths("engineering/file.md")).toEqual(["engineering"]);
expect(getAncestorPaths("engineering/specs/file.md")).toEqual(["engineering", "engineering/specs"]);
```

## Context

### Files to Modify

- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` -- primary fix location (import FileTree/SearchOverlay, render in sidebar, add auto-expand useEffect)
- `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx` -- simplify to empty fragment (tree rendering moved to layout)

### Files for Reference (read-only)

- `apps/web-platform/components/kb/file-tree.tsx` -- tree component (uses `useKb()` for expanded state, `usePathname()` for active file highlighting)
- `apps/web-platform/components/kb/kb-context.tsx` -- context definition (KbContextValue interface with `expanded: Set<string>`, `toggleExpanded`)
- `apps/web-platform/components/kb/search-overlay.tsx` -- search component (uses `Link` to navigate to `/dashboard/kb/{path}`)
- `apps/web-platform/components/kb/kb-breadcrumb.tsx` -- breadcrumb component (non-clickable directory segments per learning)
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` -- content page (fetches and renders markdown, independent of sidebar)

### Related Learnings

- `knowledge-base/project/learnings/2026-04-07-kb-viewer-react-context-layout-patterns.md` -- documents the initial KB viewer implementation patterns including:
  - Directory expand keys must include full path, not just name (finding #2) -- the auto-expand logic must use the same path format
  - `useMemo` for context value objects (finding #4) -- already implemented in `layout.tsx`
  - Breadcrumb links to directories cause silent redirects (finding #5) -- directory segments are non-clickable spans
- `knowledge-base/project/learnings/test-failures/2026-04-07-userouter-mock-instability-causes-useeffect-refire.md` -- stable mock reference pattern required for testing `useRouter`/`usePathname` dependent effects

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- this is a frontend bug fix in an existing UI component.

## References

- [Next.js App Router Layouts](https://nextjs.org/docs/app/building-your-application/routing/layouts-and-templates): layouts wrap pages and persist across navigation, but `children` changes to the matched page component
- [Next.js Parallel Routes](https://nextjs.org/docs/app/building-your-application/routing/parallel-routes): alternative pattern using `@slot` naming (not recommended for this fix -- adds complexity for no benefit)
- The `expanded` state in `KbContext` already supports path-based keys (learning finding #2)
- Context7 Next.js docs confirm: "layouts preserve state, remain interactive, and do not rerender" on navigation
