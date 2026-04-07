# KB Viewer UI Specification

**Issue:** #1689
**Branch:** kb-viewer
**Status:** Draft
**Last Updated:** 2026-04-07

## Problem Statement

Founders cannot see what their AI organization produced. Plans, brainstorms, specs, brand guides, and competitive analyses exist in the knowledge-base directory but are invisible through the web platform. Without a viewer, the compounding knowledge advantage is hidden and the review loop is broken.

## Goals

- G1: Founders can browse their knowledge-base file tree with collapsible directories
- G2: Founders can read rendered markdown files with syntax highlighting
- G3: Founders can search across all KB content and navigate to results
- G4: Works on mobile (PWA-installable, Lighthouse > 80)
- G5: Files are deep-linkable via URL for agent-to-KB references
- G6: Founders can initiate a chat about any KB file ("Ask about this")

## Non-Goals

- Editing KB files through the UI (read-only surface)
- Inline conversations on artifacts (deferred to L4 roadmap vision)
- Non-markdown file rendering (API only returns .md files)
- Full-text search indexing or ranking (v1 uses grep-like content search)
- Agent output quality linting or brand compliance checking
- Domain badge metadata in file tree (requires per-file frontmatter parsing)
- Storybook or visual regression testing (deferred)

## Functional Requirements

| ID | Requirement | Acceptance Criteria |
|----|-------------|-------------------|
| FR1 | File tree sidebar | Displays KB directory structure with collapsible folders. Shows file name + relative last-modified date. Sorted: directories first (alpha), then files (alpha). |
| FR2 | Markdown rendering | Clicking a file renders content with proper formatting: headings, lists, tables, code blocks, links, images. Uses Solar Forge brand typography (Cormorant Garamond headings, Inter body, JetBrains Mono code). |
| FR3 | Syntax highlighting | Code blocks render with language-specific highlighting via rehype-highlight. Languages: markdown, yaml, json, typescript, bash. |
| FR4 | Search | Search bar accepts text query, returns results with file path and matching line snippets with highlighted terms. Clicking a result navigates to the file. |
| FR5 | Empty state | When KB has no artifacts, displays conversion-oriented messaging encouraging the user to start a conversation. Copy to be reviewed by copywriter. |
| FR6 | Mobile responsive | Separate views on mobile: file tree is one screen, tapping a file navigates to content view with back button. Desktop shows side-by-side layout. |
| FR7 | Deep linking | Files accessible via `/dashboard/kb/[...path]`. Supports bookmarks, browser back/forward, and agent-generated links. |
| FR8 | Ask about this | Button on content view opens a new chat conversation with the current file as context. |

## Technical Requirements

| ID | Requirement | Detail |
|----|-------------|--------|
| TR1 | Route structure | Next.js App Router catch-all: `app/(dashboard)/dashboard/kb/[...path]/page.tsx` nested in KB layout |
| TR2 | Shared markdown | Extract `MARKDOWN_COMPONENTS` from chat page to `components/ui/markdown-renderer.tsx` before building |
| TR3 | API integration | Consume three endpoints: `/api/kb/tree`, `/api/kb/content/[...path]`, `/api/kb/search?q=` |
| TR4 | Syntax highlighter | rehype-highlight with selective language registration. Install at app level, regenerate both lockfiles (bun.lock + package-lock.json) |
| TR5 | Performance | Lighthouse mobile score > 80. Dynamic import for rehype-highlight. No backdrop-filter on containers with fixed-position children. |
| TR6 | Responsive breakpoints | Test at mobile (< 768px), tablet (768-1024px), desktop (> 1024px). Separate grid containers for semantically distinct groups. |
| TR7 | Brand compliance | Solar Forge design system: dark background, gold/amber accents, Cormorant Garamond headings, Inter body text, JetBrains Mono code blocks. |

## Component Architecture

```text
app/(dashboard)/dashboard/kb/
  layout.tsx              -- KB layout: fetches tree, renders sidebar on desktop
  page.tsx                -- Root view: file tree listing + empty state
  [...path]/
    page.tsx              -- Content view: renders markdown + ask-about button

components/
  kb/
    file-tree.tsx         -- Recursive collapsible tree with timestamps
    search-overlay.tsx    -- Search input + snippet results list
    kb-breadcrumb.tsx     -- Breadcrumb navigation for content view
    ask-about-button.tsx  -- Opens chat with file context
  ui/
    markdown-renderer.tsx -- Shared markdown renderer (extracted from chat)
```

## API Contract

### GET /api/kb/tree

```typescript
type TreeNode = {
  name: string;
  type: "file" | "directory";
  path?: string;       // only for files
  children?: TreeNode[]; // only for directories
};
// Response: { tree: TreeNode }
```

### GET /api/kb/content/[...path]

```typescript
type ContentResult = {
  path: string;
  frontmatter: Record<string, unknown>;
  content: string; // raw markdown (frontmatter stripped)
};
```

### GET /api/kb/search?q=

```typescript
type SearchMatch = {
  line: number;
  text: string;
  highlight: [number, number]; // start, end offsets
};
type SearchResult = {
  path: string;
  frontmatter: Record<string, unknown>;
  matches: SearchMatch[];
};
// Response: { query: string, results: SearchResult[], total: number }
```

## Test Scenarios

| ID | Scenario | Expected |
|----|----------|----------|
| TS1 | Load KB with populated directory | File tree renders with correct hierarchy |
| TS2 | Click a file in tree | URL updates to `/dashboard/kb/<path>`, content renders |
| TS3 | Navigate back from content | Returns to tree view, tree state preserved |
| TS4 | Search for existing term | Results show with snippets and highlighted matches |
| TS5 | Search for non-existent term | Empty results message displayed |
| TS6 | Load empty KB | Empty state with CTA displayed |
| TS7 | Deep link to specific file | Content renders directly without tree interaction |
| TS8 | Click "Ask about this" | Navigates to chat with file context |
| TS9 | Mobile viewport | Tree and content are separate views |
| TS10 | Code block in markdown | Syntax highlighting applied |

## Dependencies

- KB REST API (#1688) -- merged, endpoints live
- UX gate (#671) -- closed (process gate). Wireframes required before implementation.
- react-markdown v10.1.0 + remark-gfm v4.0.1 -- already installed
- rehype-highlight -- new dependency, must be added

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Lighthouse score regression from syntax highlighter | Medium | Dynamic import, selective language registration, measure before/after |
| Markdown component divergence between chat and KB | Medium | Extract shared renderer as prerequisite task |
| Last-modified timestamps not in current API | Low | Extend tree endpoint to include file stat mtime, or derive from git |
| "Ask about this" requires chat integration that may not exist | Low | Button can create new conversation with file path as initial context |
