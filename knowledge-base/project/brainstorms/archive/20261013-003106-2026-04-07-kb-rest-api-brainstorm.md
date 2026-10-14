# KB REST API Brainstorm

**Date:** 2026-04-07
**Issue:** #1688
**Participants:** Founder, CTO, CPO, CMO

## What We're Building

REST API endpoints for the web platform that expose the user's knowledge base (internally branded "Organization Memory") for programmatic access. Three endpoints:

1. **File tree** (`GET /api/kb/tree`) -- returns the full recursive directory structure of the user's KB
2. **Content reader** (`GET /api/kb/content/:path`) -- returns a specific file's raw markdown content with parsed YAML frontmatter as structured JSON
3. **Search** (`GET /api/kb/search?q=`) -- full-text search across all `.md` files with highlighted snippets

The primary consumer is the KB viewer UI (#1689). The API is private (same-origin, cookie auth only).

## Why This Approach

The KB is the compounding moat made visible (Strategic Theme T3). Without an API to access it, the viewer UI cannot exist, and founders cannot see what their agents produced. The approach follows existing codebase conventions:

- **Thin route handlers + extracted module** -- matches the `sandbox.ts`, `error-sanitizer.ts`, `tool-path-checker.ts` pattern of extracting testable business logic from route handlers
- **Filesystem-first** -- KB files live on disk at `/workspaces/<userId>/knowledge-base/`. No database migration needed.
- **In-process grep for search** -- individual user KBs are small (hundreds of files, single-digit MB). No indexing infrastructure needed at this scale.
- **Raw markdown response** -- the client renders markdown, giving the viewer UI full control over styling and custom components.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope | User-scoped | Matches current schema (`users.workspace_path`). No org table needed. |
| Content rendering | Raw markdown + parsed frontmatter JSON | Client renders. More flexible for the viewer UI. |
| Search strategy | In-process grep | Simple. No index. Fine for <500 files per user. Optimize when measured. |
| User-facing name | "Organization Memory" | Reinforces compounding narrative. "Knowledge base" is engineering jargon. API paths stay `/api/kb/`. |
| API surface | Private (frontend only) | Same-origin cookie auth. No CORS, no API tokens. External access can be added later. |
| Tree depth | Full recursive | One call returns the entire tree. Fine for workspaces <1000 files. |
| File types | Markdown only (.md) | 99% of KB is markdown. Keep it focused. |
| Architecture | Thin routes + kb-reader module | Follows existing extraction pattern. Testable. Security composes with `isPathInWorkspace()`. |

## Open Questions

1. **Workspace stability for repo connection (#1060):** When a founder connects their GitHub repo, does the KB API read from the cloned repo's `knowledge-base/` directory? If the workspace structure changes, the API may need rework. Acceptable risk for Phase 3 -- the API reads from whatever `workspace_path` points to.

2. **Rate limiting:** No rate limiting exists in the codebase. The search endpoint does filesystem I/O per request. Worth adding basic rate limiting? Deferred -- not blocking for Phase 3 launch.

3. **Pagination for search results:** The issue doesn't specify. For small KBs, returning all results is fine. May need pagination later if KBs grow large.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The critical architectural question is data source -- confirmed as per-user workspace filesystem. Path traversal is the primary security risk; existing `sandbox.ts` provides battle-tested mitigation (CWE-22/CWE-59). Search should start simple (in-process grep). No new infrastructure needed. Recommends abstracting behind a `KBReader` interface for future storage backend flexibility.

### Product (CPO)

**Summary:** The KB API is a prerequisite feature, not premature scope -- T3 depends on it. Key product decisions resolved: raw markdown (client renders), user-scoped, private API. Flagged workspace stability risk relative to repo connection (#1060). Recommends spec-first approach (resolved via this brainstorm).

### Marketing (CMO)

**Summary:** The KB is the compounding moat made visible -- treat it as a positioning event, not just a feature. "Knowledge base" is engineering jargon; adopted "Organization Memory" as user-facing name. The viewer UI (when built on this API) will be the single most compelling proof of the CaaS thesis. Content Gap 1 ("What Is Knowledge Compounding?") becomes activatable once the viewer ships. No immediate marketing action needed for the API itself.
