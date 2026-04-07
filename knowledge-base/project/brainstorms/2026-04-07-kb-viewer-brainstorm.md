# KB Viewer UI Brainstorm

**Date:** 2026-04-07
**Issue:** #1689
**Branch:** kb-viewer
**Participants:** Founder, CPO, CMO, CTO

## What We're Building

The knowledge-base viewer -- the primary surface where founders review what agents produced (plans, brainstorms, specs, brand guides, competitive analyses). This closes the review loop: "what did agents produce?"

Scope:

- Sidebar file tree with collapsible directories and last-modified timestamps
- Markdown rendering with syntax highlighting (rehype-highlight)
- Search bar with snippet results and highlighted matches
- "Chat about this" button linking KB files to chat
- Mobile-responsive with separate tree/content views
- Deep-linkable via catch-all route `/dashboard/kb/[...path]`

## Why This Approach

The KB viewer is Soleur's most marketing-critical screen after the landing page (CMO assessment). It is where the CaaS thesis becomes visible -- if founders cannot see what agents produced, the compounding knowledge advantage is invisible.

The route-segment layout approach was chosen because:

1. **Next.js idiomatic** -- layout persists the file tree on desktop while pages swap content. No manual state management for tree persistence.
2. **URL-driven by design** -- catch-all route enables deep linking, bookmarks, and agent-to-KB links ("I updated your roadmap -> [View](/dashboard/kb/product/roadmap.md)").
3. **Mobile separation is natural** -- layout hides the tree sidebar when a `[...path]` page is active on mobile. Back button returns to tree via browser navigation.
4. **Shared markdown renderer** -- extracting from chat prevents duplication and ensures brand-consistent rendering across surfaces.

## Key Decisions

| # | Decision | Choice | Alternatives Considered | Rationale |
|---|----------|--------|------------------------|-----------|
| 1 | Mobile interaction model | Separate views (tree -> content -> back) | Collapsible panel, bottom sheet | Most mobile-native pattern (Files app). Simplest to build. Back button works naturally with URL routing. |
| 2 | URL structure | Catch-all route `/dashboard/kb/[...path]` | Client state only | Enables deep linking, bookmarks, browser back/forward, agent-to-KB links. Essential for the review loop. |
| 3 | Syntax highlighting | rehype-highlight with selective languages (md, yaml, json, ts, bash) | shiki (lazy-loaded) | ~45KB vs ~1.7MB. Lighthouse > 80 target. KB content is mostly prose with occasional code. Good enough quality. |
| 4 | Interactivity level | Read-only + "Chat about this" button | Pure read-only, full inline conversations | Button opens chat with file as context. Small scope increase that demonstrates the agent-KB loop immediately. Full inline conversations deferred to L4 roadmap vision. |
| 5 | File metadata in tree | Name + last-modified relative date | Name only, name + domain badge | Timestamps make "compounding knowledge" tangible (CMO). Domain badges require frontmatter parsing for every file -- too heavy for tree. |
| 6 | Search results UX | Snippets with highlighted matches | File list only | API already returns line-level matches with highlight offsets. Snippets make search feel intelligent. |
| 7 | Component architecture | Route-segment layout (tree in layout, content in page) | Single page with client routing | Most Next.js-idiomatic. Tree persists on desktop nav. Mobile transitions handled by framework. |

## Open Questions

- **Empty state copy:** Who writes the empty state messaging? CMO flagged this as conversion-critical. Should go through copywriter, not be a developer placeholder.
- **Tree depth on mobile:** Default collapsed past level 2? Or show all levels? UX wireframes should test this.
- **"Chat about this" chat integration:** Does `/dashboard/chat/new?context=<kb-path>` exist yet? If not, the button can be a stub that creates a new conversation with the file path as the first message.
- **Last-modified source:** Git metadata via API, file stat, or frontmatter date field? API currently returns frontmatter but not timestamps.
- **Non-markdown files:** YAML, JSON, images in KB -- render raw, show as code, or hide from tree? Current API only includes `.md` files.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** The KB viewer is the most marketing-critical screen after the landing page. It makes the CaaS thesis visible. Three priorities: (1) visual design must match Solar Forge brand system (Cormorant Garamond headings, dark + gold), not a generic docs viewer; (2) empty state must convert new users into action; (3) implementation must produce screenshot-ready output from day one for marketing collateral. Recommended delegating layout review to conversion-optimizer and empty state copy to copywriter.

### Product (CPO)

**Summary:** Feature is strategically well-placed (Phase 3, item 3.2) and correctly sequenced after KB REST API. Main risk is building without UX review -- the UX gate (#671) exists specifically because Phase 1 screens were built without design review. Seven UX questions identified covering entry point, interactivity, navigation depth, file types, stale content, search navigation, and deep linking. Recommends ux-design-lead wireframes (mobile-first) before implementation.

### Engineering (CTO)

**Summary:** Existing foundation is strong -- KB page stub, react-markdown installed, three API endpoints live, dashboard nav already routes to KB. Key technical concerns: (1) extract shared markdown renderer from chat before building; (2) nested sidebar architecture needs careful mobile handling; (3) rehype-highlight adds a new dependency class -- must install at app level and regenerate both lockfiles; (4) URL structure decision (catch-all chosen) enables SSR and deep linking. Estimated 3-5 days including UX wireframes.

## File Structure

```text
app/(dashboard)/dashboard/kb/
  layout.tsx              <- KB layout (tree sidebar on desktop)
  page.tsx                <- Tree view (root listing, empty state)
  [...path]/
    page.tsx              <- Content view (renders markdown file)

components/
  kb/
    file-tree.tsx         <- Recursive tree component
    search-overlay.tsx    <- Search with snippet results
    kb-breadcrumb.tsx     <- Breadcrumb nav for content view
        (inline in content page — no separate component)
  ui/
    markdown-renderer.tsx <- Extracted from chat (shared)
```

## Technical Constraints (from Learnings)

- `NEXT_PUBLIC_` env vars must be passed as Docker build args (not runtime env)
- CSP nonces follow `lib/csp.ts` + middleware pattern
- Avoid `backdrop-filter` on containers with fixed-position children (sidebar, floating search)
- Test responsive layouts at mobile, tablet, and desktop breakpoints
- Use separate grid containers for semantically distinct UI groups
