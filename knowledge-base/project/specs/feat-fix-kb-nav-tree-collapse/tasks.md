# Tasks: fix KB navigation tree collapse on file select

## Phase 1: Core Fix

- [ ] 1.1 Modify `layout.tsx` to render `FileTree` and `SearchOverlay` directly in the sidebar `<aside>` element instead of relying on `children`
  - Import `FileTree` and `SearchOverlay` into `layout.tsx`
  - Replace `{!isContentView && children}` with the tree header, search overlay, and file tree components
  - Keep responsive classes: sidebar hidden on mobile when viewing content, visible on desktop always
- [ ] 1.2 Simplify `page.tsx` at `/dashboard/kb` -- remove tree rendering code since the layout now handles it
  - The page should return `null` or a minimal fragment (layout renders everything needed)
- [ ] 1.3 Add auto-expand logic: when pathname changes, compute ancestor directory paths for the selected file and add them to `expanded` set
  - Add a `useEffect` in `layout.tsx` that watches `pathname`
  - Extract file path from pathname (strip `/dashboard/kb/` prefix)
  - Build ancestor paths (e.g., `engineering`, `engineering/specs`) and merge into `expanded`
  - Only add ancestors, never remove existing expanded entries (preserve manual expand/collapse)

## Phase 2: Testing

- [ ] 2.1 Write test: sidebar tree remains visible after navigating to a file (desktop)
- [ ] 2.2 Write test: selected file is highlighted in tree with `isActive` styling
- [ ] 2.3 Write test: parent directories auto-expand when navigating to a nested file
- [ ] 2.4 Write test: mobile responsive behavior -- tree hidden when viewing content, visible at root
- [ ] 2.5 Verify search overlay remains functional in sidebar during content view
- [ ] 2.6 Run existing KB tests to ensure no regressions: `bun test apps/web-platform/test/kb-reader.test.ts`

## Phase 3: QA Verification

- [ ] 3.1 Visual QA: navigate to KB page, expand folders, click a file, verify tree stays visible
- [ ] 3.2 Visual QA: navigate between multiple files, verify tree state persists
- [ ] 3.3 Visual QA: verify mobile responsive behavior with narrow viewport
