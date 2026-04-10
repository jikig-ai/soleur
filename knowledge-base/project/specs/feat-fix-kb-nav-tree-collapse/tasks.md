# Tasks: fix KB navigation tree collapse on file select

## Phase 1: Core Fix

- [x] 1.1 Modify `layout.tsx` to render `FileTree` and `SearchOverlay` directly in the sidebar `<aside>` element
  - Add imports: `import { FileTree } from "@/components/kb/file-tree"` and `import { SearchOverlay } from "@/components/kb/search-overlay"`
  - Replace `{!isContentView && children}` with the tree header, search overlay, and file tree components rendered directly
  - Keep responsive classes: sidebar hidden on mobile when viewing content (`isContentView ? "hidden" : "block"`), visible on desktop always (`md:block`)
  - Ensure `children` is rendered ONLY in the content area div (right panel), not in the sidebar
- [x] 1.2 Simplify `page.tsx` at `/dashboard/kb` to avoid duplicate tree rendering
  - Remove `FileTree`, `SearchOverlay` imports and rendering
  - Remove loading, error, empty, and no-project state handlers (layout already handles these)
  - Return an empty fragment `<></>` -- the page must still exist for the route to be valid in App Router
  - Keep the `"use client"` directive
- [x] 1.3 Add auto-expand `useEffect` in `layout.tsx`
  - Watch `pathname` for changes
  - Guard: skip if not under `/dashboard/kb/` or exactly `/dashboard/kb`
  - Decode pathname with `decodeURIComponent` before splitting (handles URL-encoded special characters)
  - Compute ancestor directory paths from the file path segments (skip the last segment which is the file)
  - Merge ancestors into `expanded` set additively (never remove existing entries to preserve manual expand/collapse)
  - Use `changed` flag to avoid creating a new Set reference when nothing was added (prevents unnecessary re-renders)
  - Dependency array: only `[pathname]` -- do NOT include `expanded` (infinite loop) or `setExpanded` (stable ref)

## Phase 2: Testing

- [x] 2.1 Extract `getAncestorPaths(relativePath: string): string[]` as a pure utility function for testability
  - Place in `apps/web-platform/components/kb/` or alongside layout
  - Unit test edge cases: root file (`"file.md"` returns `[]`), single nesting, deep nesting, trailing slash
- [x] 2.2 Write component test: sidebar tree remains visible after navigating to a file (desktop)
  - Use stable `useRouter` mock pattern (module-level constant, not per-call object creation)
  - Mock `usePathname` to return `/dashboard/kb/engineering/file.md`
  - Mock `fetch` for `/api/kb/tree` to return a tree with the `engineering` directory
  - Assert: `FileTree` component is rendered in the sidebar
- [ ] 2.3 Write component test: selected file is highlighted in tree with `isActive` styling
- [ ] 2.4 Write component test: parent directories auto-expand when navigating to a nested file
  - Mock pathname to a deeply nested path
  - Assert: the `expanded` set includes all ancestor directories
- [ ] 2.5 Write component test: mobile responsive behavior -- tree hidden when viewing content, visible at root
- [x] 2.6 Run existing KB tests to ensure no regressions (full suite: 662 passed)

## Phase 3: QA Verification

- [ ] 3.1 Visual QA: navigate to KB page, expand folders, click a file, verify tree stays visible on the left
- [ ] 3.2 Visual QA: navigate between multiple files, verify tree state persists and active file highlighting updates
- [ ] 3.3 Visual QA: use search overlay to find a file, click result, verify tree stays visible with file's parent dirs expanded
- [ ] 3.4 Visual QA: verify mobile responsive behavior with narrow viewport (tree hidden on content view, back arrow returns to tree)
- [ ] 3.5 Visual QA: direct URL navigation to a file (simulate bookmark) -- tree loads and auto-expands correctly
