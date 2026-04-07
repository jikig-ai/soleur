---
title: "feat: KB Viewer UI"
type: feat
date: 2026-04-07
---

# KB Viewer UI

## Overview

Build the knowledge-base viewer at `/dashboard/kb` — the primary surface where founders review what agents produced. Renders a file tree sidebar, markdown content with syntax highlighting, and search with snippet results. Deep-linkable via catch-all route, mobile-responsive with separate tree/content views.

**Issue:** #1689 | **Branch:** kb-viewer | **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-07-kb-viewer-brainstorm.md`

## Problem Statement

Founders cannot see what their AI organization produced. Plans, brainstorms, specs, brand guides, and competitive analyses exist in the knowledge-base directory but are invisible through the web platform. Without a viewer, the compounding knowledge advantage is hidden and the review loop is broken.

The roadmap (Theme T3: "Make the Moat Visible") states: "If users cannot see what agents produced, the value is invisible." The KB viewer closes this loop.

## Proposed Solution

A route-segment layout using Next.js App Router:

- **KB layout** (`layout.tsx`) persists the file tree sidebar on desktop, hides it on mobile when viewing content
- **Tree view page** (`page.tsx`) shows the file tree root with search bar and empty state
- **Content view page** (`[...path]/page.tsx`) renders markdown files via catch-all route, enabling deep links

API integration consumes three existing endpoints: `/api/kb/tree`, `/api/kb/content/[...path]`, `/api/kb/search?q=`.

## Technical Approach

### Architecture

```text
app/(dashboard)/dashboard/kb/
  layout.tsx              -- KB layout: tree sidebar (desktop), responsive shell ("use client")
  page.tsx                -- Tree view: file listing, search, empty state
  [...path]/
    page.tsx              -- Content view: markdown rendering, chat-about link ("use client")

components/
  kb/
    file-tree.tsx         -- Recursive collapsible tree with timestamps (nodes inline)
    search-overlay.tsx    -- Search input + snippet results
    kb-breadcrumb.tsx     -- Path breadcrumb for content view
  ui/
    markdown-renderer.tsx -- Shared renderer (extracted from chat page)
```

**Data flow:**

1. `layout.tsx` fetches tree data from `/api/kb/tree` on mount (client-side, auth-gated)
2. Tree state (expanded nodes) stored in React state, persisted across navigation on desktop
3. `[...path]/page.tsx` fetches file content from `/api/kb/content/[...path]` using the URL path segments
4. Search component calls `/api/kb/search?q=` with debounced input

**Key patterns:**

- `usePathname()` in layout to detect whether a file is selected (show/hide tree on mobile)
- Tree expansion state in `useState` with `Set<string>` for expanded paths
- Responsive breakpoint detection via CSS media queries + `matchMedia` listener (matching existing dashboard pattern at 768px)

### Implementation Phases

#### Phase 0: Prerequisites

Extract shared markdown renderer and install new dependency. This phase unblocks all subsequent phases.

**Tasks:**

- [ ] Extract `MARKDOWN_COMPONENTS`, `REMARK_PLUGINS`, `DISALLOWED_ELEMENTS`, and `MarkdownContent` from `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:319-394` into `apps/web-platform/components/ui/markdown-renderer.tsx`
- [ ] Update chat page to import from the new shared component
- [ ] Install `rehype-highlight` at app level: `cd apps/web-platform && bun add rehype-highlight` (use default import — 45KB total, selective registration not worth the config complexity)
- [ ] Regenerate both lockfiles: `bun install` then `npm install` in `apps/web-platform/`
- [ ] Extend `buildTree()` in `apps/web-platform/server/kb-reader.ts` to include `modifiedAt` (file stat `mtime`) in `TreeNode` for files
- [ ] Add `modifiedAt?: string` (ISO 8601) to the `TreeNode` interface
- [ ] Verify chat page still renders markdown correctly after extraction

**Files modified:**

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — remove inline markdown components, import from shared
- `apps/web-platform/components/ui/markdown-renderer.tsx` — new shared component
- `apps/web-platform/server/kb-reader.ts` — add `modifiedAt` to `TreeNode`
- `apps/web-platform/package.json` — add `rehype-highlight`
- `apps/web-platform/bun.lock` — regenerated
- `apps/web-platform/package-lock.json` — regenerated

**Success criteria:** Chat page renders identically. `rehype-highlight` importable. Tree API returns `modifiedAt` for files.

#### Phase 1: KB Layout + Route Structure

Create the route-segment layout that handles desktop sidebar vs mobile separate views.

**Tasks:**

- [ ] Create `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — `"use client"` KB-specific layout wrapping tree + content
- [ ] Layout fetches tree from `/api/kb/tree` on mount, stores in state
- [ ] Desktop (>= 768px): renders tree sidebar (w-64) + content area side by side
- [ ] Mobile (< 768px): conditionally shows tree OR content based on `usePathname()` (if path segments exist beyond `/dashboard/kb`, hide tree)
- [ ] Pass tree data, expansion state, and loading/error states to children via React context (required — App Router injects children via `{children}`, cannot pass props through that boundary)
- [ ] Handle workspace-not-ready (503) — show "Setting up your workspace" provisioning state, distinct from empty KB
- [ ] Handle unauthorized (401) — redirect to login
- [ ] React error boundary wrapping the content area (not the tree) to contain fetch failures without unmounting the sidebar
- [ ] Loading skeleton while tree fetches

**Files created:**

- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx`

**Success criteria:** Desktop shows two-panel layout. Mobile shows single panel. URL navigation works between tree and content. Workspace-provisioning state distinct from empty state. Tree expansion state preserved across page navigations. Content errors contained by error boundary.

**Note:** Both `layout.tsx` and `[...path]/page.tsx` are Client Components (`"use client"`). Future optimization: content page could be a Server Component using `params` directly if switching to server-side fetching.

#### Phase 2: File Tree Component + Tree View Page

Build the recursive file tree and the root page that displays it.

**Tasks:**

- [ ] Create `apps/web-platform/components/kb/file-tree.tsx` — accepts `TreeNode`, renders recursive collapsible tree with node rendering inline (no separate file-tree-node component — a tree node is a `<li>` with conditional rendering, not a reusable abstraction)
- [ ] Implement expand/collapse with `Set<string>` tracking expanded directory paths (consumed from layout context)
- [ ] File nodes are `<Link>` elements to `/dashboard/kb/<file.path>`
- [ ] Directory nodes toggle expand state on click
- [ ] Format `modifiedAt` as relative time ("2d ago", "5h ago", "just now") using lightweight formatter (no external dep — simple utility function)
- [ ] Cap visual indent at 3 levels deep — deeper items still render but don't indent further (prevents off-screen names on mobile)
- [ ] Replace `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx` — show file tree when KB has content, branded empty state when tree is empty
- [ ] Empty state: Variant 2 copy — "Nothing Here Yet. One Message Changes That." / subtext / "Open a Chat" CTA linking to `/dashboard/chat/new`. Cormorant Garamond 500 headline, Inter 400 subtext, gold gradient CTA. Section label "KNOWLEDGE BASE" in Inter 600 12px gold all-caps.

**Files created/modified:**

- `apps/web-platform/components/kb/file-tree.tsx` — new
- `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx` — rewritten from stub

**Success criteria:** Tree renders correct hierarchy. Directories expand/collapse. Files link to content. Timestamps display. Empty state shows branded copy with CTA.

#### Phase 3: Content View + Markdown Rendering

Build the content page that renders markdown files with syntax highlighting.

**Tasks:**

- [ ] Create `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — catch-all route
- [ ] Page extracts path from `params.path` (string array), joins with `/`, fetches from `/api/kb/content/<joined-path>`
- [ ] Render content using shared `MarkdownRenderer` with rehype-highlight plugin added
- [ ] Create `apps/web-platform/components/kb/kb-breadcrumb.tsx` — renders path segments as clickable links (each segment links to its parent directory or root)
- [ ] Handle 404 (file not found) — display "File not found. This file may have been renamed or removed." with link back to tree
- [ ] Handle directory deep links (e.g., `/dashboard/kb/product/`) — plain redirect to `/dashboard/kb`
- [ ] Handle loading state — skeleton placeholder while content loads
- [ ] Apply brand typography: Cormorant Garamond for rendered h1/h2, Inter for body, JetBrains Mono for code
- [ ] Syntax highlighting theme: dark theme matching neutral-950 code blocks with amber-300 strings
- [ ] Mobile back button — visible back arrow in content header (not just breadcrumb). Design in this phase, not deferred to polish
- [ ] "Chat about this" — inline `<Link>` in content header navigating to `/dashboard/chat/new?msg=Tell me about the file at <kb-path>&leader=cto` (uses existing `?msg=` param from chat page). No separate component file — it's one link element

**Files created:**

- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — new (`"use client"`)
- `apps/web-platform/components/kb/kb-breadcrumb.tsx` — new

**Success criteria:** Deep links work (`/dashboard/kb/product/roadmap.md` renders the file). Breadcrumb navigates. Code blocks highlighted. 404 handled gracefully. Mobile back arrow visible. "Chat about this" opens chat with file context.

#### Phase 4: Search

Build the search overlay with snippet results.

**Tasks:**

- [ ] Create `apps/web-platform/components/kb/search-overlay.tsx` — search input + results panel
- [ ] Debounce input (300ms) before calling `/api/kb/search?q=`
- [ ] Render results as cards: file path + up to 3 matching line snippets per file
- [ ] Highlight search term within snippet text using the `highlight` offsets from the API
- [ ] Click result navigates to `/dashboard/kb/<result.path>`
- [ ] Empty results: "No results for '<query>'" message
- [ ] Integrate search into KB layout — search bar above file tree on desktop, top of tree view on mobile
- [ ] Search operates independently of tree state — clicking a result navigates directly to content view

**Files created:**

- `apps/web-platform/components/kb/search-overlay.tsx` — new

**Success criteria:** Search returns highlighted snippets. Click navigates to file. Empty results handled. Debounce prevents excessive API calls.

### QA Verification (post-implementation, not a build phase)

- [ ] Mobile (< 768px): verify separate views, back navigation with back arrow
- [ ] Tablet (768-1024px): verify sidebar doesn't crowd content
- [ ] Desktop (> 1024px): verify two-panel layout
- [ ] No `backdrop-filter` on containers with fixed-position children (known learning)
- [ ] Separate grid containers for semantically distinct groups (known learning)
- [ ] Dynamic import for rehype-highlight confirmed working
- [ ] Lighthouse audit — target > 80 mobile (Performance, Accessibility, Best Practices)
- [ ] PWA safe-area insets verified
- [ ] Browser back/forward navigation between tree and content views

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Client-state routing (single page, no URL) | Loses deep linking, bookmarks, agent-to-KB links. Fights App Router model. |
| Bottom sheet for mobile file tree | Higher implementation complexity with no UX benefit over separate views. |
| shiki for syntax highlighting | ~1.7MB bundle vs ~45KB for rehype-highlight. Lighthouse risk too high for v1. |
| Domain badges in tree (colored tags per domain) | Requires frontmatter parsing for every file on tree load. Too heavy for tree endpoint. |
| Read-only without "Chat about this" | Misses closing the review loop. The button is small scope with high value. |

## Acceptance Criteria

### Functional Requirements

- [ ] Sidebar displays KB file tree with collapsible directories
- [ ] File tree shows file name + relative last-modified date
- [ ] Clicking a file renders markdown with proper formatting and syntax highlighting
- [ ] Search bar returns results with file path and matching line snippets
- [ ] Empty state displays when KB has no artifacts
- [ ] Mobile: file tree and content are separate views with back navigation
- [ ] Deep links work: `/dashboard/kb/product/roadmap.md` renders directly
- [ ] "Chat about this" button opens chat with file context
- [ ] Breadcrumb navigation shows current file path

### Non-Functional Requirements

- [ ] Lighthouse mobile score > 80 (Performance, Accessibility, Best Practices)
- [ ] Solar Forge brand compliance (Cormorant Garamond headings, dark + gold theme)
- [ ] Works in PWA standalone mode with safe-area insets
- [ ] No markdown component duplication between chat and KB

### Quality Gates

- [ ] TDD: failing tests before implementation for each phase
- [ ] Shared markdown renderer extracted and chat page verified
- [ ] Both lockfiles (bun.lock + package-lock.json) regenerated after dependency changes
- [ ] Markdownlint clean on all changed .md files

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a populated KB, when loading `/dashboard/kb`, then file tree renders with correct hierarchy (directories first, alpha sorted)
- Given a file in the tree, when clicking it, then URL updates to `/dashboard/kb/<path>` and content renders with formatted markdown
- Given a content view, when clicking browser back, then returns to tree view with expansion state preserved
- Given a search query matching KB content, when submitting search, then results show with file path and highlighted snippets
- Given a search query matching nothing, when submitting search, then "No results" message displays
- Given an empty KB (no artifacts), when loading `/dashboard/kb`, then empty state with CTA displays
- Given a deep link `/dashboard/kb/product/roadmap.md`, when loading directly, then content renders without tree interaction
- Given a content view, when clicking "Chat about this", then navigates to `/dashboard/chat/new?msg=...`
- Given a mobile viewport (< 768px), when viewing KB, then tree and content are separate full-screen views

### Edge Cases

- Given a deep link to a non-existent file, when loading, then 404 message with link back to tree
- Given a workspace that is not ready (status !== "ready"), when loading KB, then appropriate error message
- Given a code block with TypeScript in a KB file, when rendering, then syntax highlighting applied
- Given a file tree with 5+ nesting levels, when viewing on mobile, then tree scrolls correctly without layout overflow
- Given a search with special regex characters, when submitting, then characters are escaped and search works (API already handles this)

### Integration Verification

- **Browser:** Navigate to `/dashboard/kb`, verify tree loads, click a file, verify content renders, click "Chat about this", verify chat opens
- **API verify:** `curl -s /api/kb/tree` returns `{ tree: { name, type, children, modifiedAt } }` with `modifiedAt` on file nodes

## Domain Review

**Domains relevant:** Marketing, Product, Engineering

### Marketing (CMO) — carried from brainstorm

**Status:** reviewed
**Assessment:** KB viewer is the most marketing-critical screen after the landing page. Three priorities: (1) visual design must match Solar Forge brand system, (2) empty state must convert new users, (3) implementation must produce screenshot-ready output from day one. Recommended copywriter for empty state and conversion-optimizer for layout.

### Engineering (CTO) — carried from brainstorm

**Status:** reviewed
**Assessment:** Strong existing foundation. Key concerns: extract shared markdown renderer before building (prevents divergence), rehype-highlight adds new dependency class (both lockfiles), nested sidebar needs careful mobile handling. Estimated 3-5 days.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo (from brainstorm), copywriter, ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

**CPO (from brainstorm):** Feature strategically well-placed (Phase 3, item 3.2). No wireframes or spec existed prior to this session — brainstorm and spec now created. Seven UX questions resolved during brainstorm. Mobile-first design essential. UX gate (#671) enforces wireframes before implementation.

**Spec-flow-analyzer — 10 gaps identified (4 critical):**

1. **404 for non-existent file** (critical) — deep links to deleted/renamed files need a 404 UI with "Return to file tree" link. → Addressed in Phase 3.
2. **Workspace provisioning state** (critical) — new users hit 503 before workspace is ready. Need "Setting up your workspace" state distinct from empty KB. → Add to Phase 1 layout.
3. **Empty→populated transition** — no auto-refresh after first conversation populates KB. → Fetch-on-mount acceptable for v1; note in tasks.
4. **Tree state lost on mobile back** — expand/collapse state resets on back navigation. → Store in layout context (persists across page navigations).
5. **Directory deep link** — `/dashboard/kb/product/` hits 404 since API only serves `.md` files. → Redirect to tree root with directory auto-expanded.
6. **"Chat about this" exit** — no return path from chat to KB. → Browser back sufficient for v1.
7. **Search during tree loading** — search should operate independently of tree state. → Search results navigate directly to content view.
8. **Deep nesting (5+ levels)** — tree indentation pushes names off-screen on mobile. → Cap indent at level 3, horizontal scroll for deeper content, breadcrumb truncation with ellipsis.
9. **No loading states** — need loading skeletons for tree, content, and search. → Add to each phase.
10. **Timestamps missing from API** — already addressed in Phase 0 (`modifiedAt` extension).

**Copywriter — empty state copy (3 variants, recommends Variant 2):**

- **Variant 1 (Bold):** "Your AI Organization Awaits Orders" / "Every plan, brainstorm, spec, and analysis your agents produce lives here..."
- **Variant 2 (Action-oriented, RECOMMENDED):** "Nothing Here Yet. One Message Changes That." / "Start a conversation and your AI organization gets to work — producing plans, specs, brand guides, and competitive analyses that appear here automatically." / CTA: "Open a Chat"
- **Variant 3 (Value-focused):** "Where Your Knowledge Base Compounds" / artifact list + CTA "Begin Building"

Implementation: Cormorant Garamond 500 headline, Inter 400 subtext, gold gradient CTA button. Section label "KNOWLEDGE BASE" in Inter 600 12px gold all-caps above headline.

## Dependencies & Prerequisites

| Dependency | Status | Impact |
|------------|--------|--------|
| KB REST API (#1688) | Merged (01f69dd9) | All three endpoints live and tested |
| UX gate (#671) | Closed | Process gate — wireframes should precede implementation |
| react-markdown v10.1.0 | Installed | Already used in chat page |
| remark-gfm v4.0.1 | Installed | Already used in chat page |
| rehype-highlight | Not installed | Must add in Phase 0 |
| Chat page `?msg=` param | Exists (line 22, 61-69) | "Chat about this" can use existing mechanism |

## Risk Analysis & Mitigation

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Lighthouse regression from rehype-highlight | Medium | Low | Dynamic import (~45KB total). Measure before/after. |
| Tree API missing `modifiedAt` | Low | Certain | Phase 0 extends `buildTree()` to include `fs.stat().mtime`. Small change. |
| Markdown component divergence | Medium | Medium | Phase 0 extracts shared renderer as hard prerequisite before any KB work. |
| "Chat about this" chat context not rendering | Low | Medium | Uses existing `?msg=` param pattern. If chat doesn't support context injection, button still works as a navigation link. |
| Mobile layout fighting dashboard drawer | Low | Low | KB layout uses same 768px breakpoint and `usePathname()` pattern as dashboard. |
| Docker build failure from missing lockfile sync | High | Medium | AGENTS.md rule: regenerate both `bun.lock` and `package-lock.json` after any dependency change. Phase 0 explicitly includes this. |

## References & Research

### Internal References

- KB REST API implementation: `apps/web-platform/server/kb-reader.ts`
- API route handlers: `apps/web-platform/app/api/kb/{tree,content,search}/`
- Existing markdown components: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:319-394`
- Dashboard layout pattern: `apps/web-platform/app/(dashboard)/layout.tsx`
- KB page stub: `apps/web-platform/app/(dashboard)/dashboard/kb/page.tsx`
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-07-kb-viewer-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-kb-viewer/spec.md`

### Learnings Applied

- `NEXT_PUBLIC_` env vars require Docker build args: `knowledge-base/project/learnings/2026-03-17-nextjs-docker-public-env-vars.md`
- CSP nonces in middleware: `knowledge-base/project/learnings/2026-03-20-nonce-based-csp-nextjs-middleware.md`
- `auto-fill` grid loses semantic grouping on mobile: `knowledge-base/project/learnings/ui-bugs/2026-02-19-auto-fill-grid-loses-semantic-grouping-on-mobile.md`
- `backdrop-filter` breaks fixed positioning: `knowledge-base/project/learnings/2026-02-17-backdrop-filter-breaks-fixed-positioning.md`
- Grid orphan regression at tablet: `knowledge-base/project/learnings/2026-02-22-landing-page-grid-orphan-regression.md`

### Related Issues

- #1689 — KB viewer UI (this feature)
- #1688 — KB REST API (dependency, merged)
- #672 — Phase 3 epic (parent)
- #671 — UX gate (process dependency)
- #1714 — Inline conversations on KB artifacts (deferred to L4)
- #1715 — KB search indexing for large knowledge bases (deferred)
