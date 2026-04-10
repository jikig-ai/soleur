---
module: KB Viewer
date: 2026-04-10
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Navigation tree disappears when clicking a file in Knowledge Base"
  - "Sidebar renders empty when navigating to /dashboard/kb/[...path]"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [nextjs-app-router, layout-children, sidebar-persistence, file-tree]
---

# KB Navigation Tree Disappears on File Select

## Problem

When a user clicks a file in the Knowledge Base navigation tree, the sidebar tree
completely disappears. The tree should remain visible in the sidebar while the file
content renders in the main content area.

## Symptoms

- Sidebar renders empty when viewing any file at `/dashboard/kb/[...path]`
- Tree only visible at the root `/dashboard/kb` route
- No errors in console -- the UI simply goes blank in the sidebar

## Root Cause

The KB layout (`layout.tsx`) used the Next.js App Router `children` prop to render
the file tree in the sidebar. In App Router, `children` swaps to whatever page matches
the current route:

- At `/dashboard/kb`: `children` = `page.tsx` (renders FileTree)
- At `/dashboard/kb/some-file.md`: `children` = `[...path]/page.tsx` (renders content)

The layout conditionally rendered `children` in the sidebar only when `!isContentView`:

```tsx
// BUG: empty when viewing content because children is the content page
<aside>{!isContentView && children}</aside>
```

When navigating to a file, `isContentView` becomes true, and `children` is the content
page -- so the sidebar renders nothing.

## Solution

Import `FileTree` and `SearchOverlay` directly in `layout.tsx` instead of relying on
`children` for tree rendering. The layout persists across navigation (App Router
guarantee), so components rendered directly in it stay visible.

**Key changes:**

1. **layout.tsx:** Import and render FileTree/SearchOverlay directly in the `<aside>`
2. **page.tsx:** Simplified to empty fragment `<></>` (must exist for route to be valid)
3. **Auto-expand:** Added useEffect watching `pathname` to expand ancestor directories
4. **State UI:** Moved loading/error/empty state components from page.tsx into layout.tsx

```tsx
// BEFORE (broken): tree rendered via children
<aside>{!isContentView && children}</aside>

// AFTER (fixed): tree rendered directly in layout
<aside>
  <SearchOverlay />
  <FileTree />
</aside>
<div>{isContentView ? children : <DesktopPlaceholder />}</div>
```

## Key Insight

In Next.js App Router, persistent UI elements (navigation trees, sidebars, toolbars)
must be rendered directly in layouts, not via the `children` prop. The `children` prop
swaps to the matched page component on every navigation. Layouts persist across sibling
route navigations -- any component imported directly into a layout will stay visible.

## Prevention

- When building two-panel layouts in App Router, always render the persistent panel's
  content directly in the layout. Only use `children` for the swappable content area.
- When moving JSX components between files, check for import-dependent components
  (`Link`, `Image`, etc.) that need corresponding import statements in the target file.

## Session Errors

1. **`setup-ralph-loop.sh` not found at wrong path** -- Recovery: found correct path via
   glob search. **Prevention:** one-shot skill should reference `plugins/soleur/scripts/`
   not `plugins/soleur/skills/one-shot/scripts/`.

2. **Plain `<a>` tags used instead of `next/link` Link** -- When moving EmptyState and
   NoProjectState from page.tsx to layout.tsx, `Link` imports were dropped. Architecture
   reviewer caught this. **Prevention:** When moving JSX between files, audit all
   import-dependent components and add missing imports to the target file.

3. **QA browser testing blocked by ENOSPC** -- Dev server started but Watchpack file
   watcher limit prevented route discovery. All routes returned 404.
   **Prevention:** Increase `fs.inotify.max_user_watches` sysctl, or use `next build &&
   next start` instead of `next dev` for QA in worktree-heavy repos.

4. **`git add` with escaped parentheses failed** -- Path `app/(dashboard)/` required
   single quotes, not backslash escaping. **Prevention:** Always use single quotes for
   git paths containing parentheses: `git add 'path/(group)/file'`.

## Tags

category: ui-bug
module: kb-viewer
