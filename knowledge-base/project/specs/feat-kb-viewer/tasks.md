# KB Viewer UI — Tasks

**Issue:** #1689
**Branch:** kb-viewer
**Plan:** `knowledge-base/project/plans/2026-04-07-feat-kb-viewer-ui-plan.md`

## Phase 0: Prerequisites

- [ ] 0.1 Extract shared markdown renderer
  - [ ] 0.1.1 Create `components/ui/markdown-renderer.tsx` with `MARKDOWN_COMPONENTS`, `REMARK_PLUGINS`, `DISALLOWED_ELEMENTS`, `MarkdownRenderer` component
  - [ ] 0.1.2 Update chat page to import from shared component
  - [ ] 0.1.3 Verify chat page renders identically
- [ ] 0.2 Install rehype-highlight
  - [ ] 0.2.1 `cd apps/web-platform && bun add rehype-highlight` (default import, no selective language registration)
  - [ ] 0.2.2 Regenerate lockfiles: `bun install` then `npm install` in `apps/web-platform/`
- [ ] 0.3 Extend tree API with timestamps
  - [ ] 0.3.1 Add `modifiedAt?: string` to `TreeNode` interface in `server/kb-reader.ts`
  - [ ] 0.3.2 Update `buildTree()` to include `fs.stat().mtime` as ISO 8601 for file nodes
  - [ ] 0.3.3 Update `kb-reader.test.ts` — verify `modifiedAt` present on file nodes

## Phase 1: KB Layout + Route Structure

- [ ] 1.1 Create KB layout (`app/(dashboard)/dashboard/kb/layout.tsx`) — `"use client"`
  - [ ] 1.1.1 Fetch tree data from `/api/kb/tree` on mount, store in state
  - [ ] 1.1.2 Desktop: two-panel layout (w-64 sidebar + content area)
  - [ ] 1.1.3 Mobile: single panel — tree OR content based on `usePathname()`
  - [ ] 1.1.4 React context for tree data, expansion state, loading/error (required — App Router `{children}` boundary prevents props)
  - [ ] 1.1.5 Handle workspace-not-ready (503 → "Setting up your workspace" state)
  - [ ] 1.1.6 Handle unauthorized (401) → redirect to login
  - [ ] 1.1.7 React error boundary wrapping content area (not tree) to contain fetch failures
  - [ ] 1.1.8 Loading skeleton while tree fetches

## Phase 2: File Tree Component + Tree View Page

- [ ] 2.1 Create file tree (`components/kb/file-tree.tsx`)
  - [ ] 2.1.1 Accepts `TreeNode`, renders recursive tree with node rendering inline (no separate component)
  - [ ] 2.1.2 Expand/collapse via `Set<string>` from layout context
  - [ ] 2.1.3 File nodes: `<Link>` to `/dashboard/kb/<path>` + relative time
  - [ ] 2.1.4 Directory nodes: click toggles expand state
  - [ ] 2.1.5 Relative time formatter utility (no external dep)
  - [ ] 2.1.6 Cap visual indent at 3 levels — deeper items render without further indent
- [ ] 2.2 Rewrite tree view page (`app/(dashboard)/dashboard/kb/page.tsx`)
  - [ ] 2.2.1 Show file tree when KB has content
  - [ ] 2.2.2 Empty state: "Nothing Here Yet. One Message Changes That." / subtext / "Open a Chat" CTA → `/dashboard/chat/new`
  - [ ] 2.2.3 Empty state styling: Cormorant Garamond 500 headline, Inter 400 subtext, gold gradient CTA, "KNOWLEDGE BASE" section label

## Phase 3: Content View + Markdown Rendering

- [ ] 3.1 Create content page (`app/(dashboard)/dashboard/kb/[...path]/page.tsx`) — `"use client"`
  - [ ] 3.1.1 Extract path from `params.path`, join with `/`, fetch from `/api/kb/content/`
  - [ ] 3.1.2 Render with shared `MarkdownRenderer` + rehype-highlight
  - [ ] 3.1.3 Brand typography: Cormorant Garamond h1/h2, Inter body, JetBrains Mono code
  - [ ] 3.1.4 Handle 404 — "File not found. This file may have been renamed or removed." + link to tree
  - [ ] 3.1.5 Handle directory deep links → plain redirect to `/dashboard/kb`
  - [ ] 3.1.6 Loading skeleton placeholder
  - [ ] 3.1.7 Mobile back arrow in content header (not just breadcrumb)
  - [ ] 3.1.8 "Chat about this" — inline `<Link>` to `/dashboard/chat/new?msg=...&leader=cto` (no separate component)
- [ ] 3.2 Create breadcrumb (`components/kb/kb-breadcrumb.tsx`)
  - [ ] 3.2.1 Render path segments as clickable links
  - [ ] 3.2.2 Last segment is current file (non-clickable)

## Phase 4: Search

- [ ] 4.1 Create search overlay (`components/kb/search-overlay.tsx`)
  - [ ] 4.1.1 Search input with 300ms debounce
  - [ ] 4.1.2 Results as cards: file path + up to 3 matching snippets
  - [ ] 4.1.3 Highlight search term using API `highlight` offsets
  - [ ] 4.1.4 Click result navigates directly to content view
  - [ ] 4.1.5 Empty results message
  - [ ] 4.1.6 Search operates independently of tree loading state
- [ ] 4.2 Integrate search into KB layout
  - [ ] 4.2.1 Search bar above file tree (desktop)
  - [ ] 4.2.2 Search bar at top of tree view (mobile)

## Deferred (tracking issues created)

- #1716 — Keyboard navigation for tree and search
- #1714 — Inline conversations on KB artifacts
- #1715 — KB search indexing for large knowledge bases
