# KB REST API Specification

**Issue:** #1688
**Branch:** feat-kb-rest-api
**Brainstorm:** [2026-04-07-kb-rest-api-brainstorm.md](../../brainstorms/2026-04-07-kb-rest-api-brainstorm.md)

## Problem Statement

Founders cannot see what their AI agents produced. The knowledge base (branded "Organization Memory") contains brainstorms, plans, specs, learnings, and domain artifacts, but there is no programmatic way to access them from the web platform. The KB viewer UI (#1689) needs a REST API to browse, read, and search these artifacts.

## Goals

- Expose KB file tree, content, and search via REST API
- Enable the KB viewer UI to render the user's Organization Memory
- Maintain the security posture established in Phase 2

## Non-Goals

- Organization-scoped access (user-scoped only, matching current schema)
- Server-side markdown rendering (client renders)
- Write/edit operations (read-only API)
- External API access (private, same-origin only)
- Search indexing or infrastructure (in-process grep)
- Rate limiting (no existing pattern; deferred)

## Functional Requirements

### FR1: File Tree Endpoint

`GET /api/kb/tree`

Returns the full recursive directory structure of the user's KB.

**Response shape:**

```json
{
  "tree": {
    "name": "knowledge-base",
    "type": "directory",
    "children": [
      {
        "name": "project",
        "type": "directory",
        "children": [
          {
            "name": "learnings",
            "type": "directory",
            "children": [
              { "name": "2026-03-20-cwe22-path-traversal.md", "type": "file", "path": "project/learnings/2026-03-20-cwe22-path-traversal.md" }
            ]
          }
        ]
      }
    ]
  }
}
```

- Only `.md` files are included
- Paths are relative to the KB root (no absolute paths exposed)
- Empty directories are excluded
- Sorted: directories first, then files, alphabetically within each group

### FR2: Content Endpoint

`GET /api/kb/content/:path`

Returns the raw markdown content and parsed YAML frontmatter for a single file.

**Response shape:**

```json
{
  "path": "project/learnings/2026-03-20-cwe22-path-traversal.md",
  "frontmatter": {
    "category": "security",
    "module": "web-platform/server",
    "tags": ["path-traversal", "CWE-22"]
  },
  "content": "# CWE-22 Path Traversal\n\nNever use string.startsWith()..."
}
```

- `:path` is a catch-all parameter (e.g., `project/learnings/foo.md`)
- Frontmatter is parsed to JSON via `gray-matter`; content is raw markdown (no frontmatter delimiters)
- Files without frontmatter return `frontmatter: {}`
- Only `.md` files are served; other file types return 404
- Non-existent paths return 404
- Path traversal attempts return 403

### FR3: Search Endpoint

`GET /api/kb/search?q=<query>`

Full-text search across all `.md` files in the user's KB.

**Response shape:**

```json
{
  "query": "path traversal",
  "results": [
    {
      "path": "project/learnings/2026-03-20-cwe22-path-traversal.md",
      "frontmatter": { "category": "security" },
      "matches": [
        {
          "line": 5,
          "text": "Never use **string.startsWith()** for **path traversal** checks.",
          "highlight": [42, 56]
        }
      ]
    }
  ],
  "total": 1
}
```

- `q` parameter is required; empty query returns 400
- Search is case-insensitive
- Results include frontmatter for filtering in the UI
- Each match includes line number, full line text, and highlight position (start, end offsets)
- Results sorted by number of matches (descending)
- Maximum 100 results per query

## Technical Requirements

### TR1: Authentication

- All endpoints require Supabase cookie session auth
- Route handlers call `createClient()` + `supabase.auth.getUser()` and return 401 on failure
- Middleware already protects `/api/kb/*` paths (not in PUBLIC_PATHS)
- No CSRF validation needed (GET-only endpoints)

### TR2: Path Traversal Protection

- All user-supplied paths validated via `isPathInWorkspace()` from `server/sandbox.ts`
- Symlink resolution via `fs.realpathSync()` (CWE-59 protection)
- Trailing-separator guard to prevent prefix collisions
- Failed validation returns 403, not 404 (do not reveal directory structure)

### TR3: Error Handling

- Error responses sanitized via `error-sanitizer.ts` pattern
- No filesystem paths, workspace structure, or internal errors leaked to client
- Supabase errors: always destructure `{ data, error }`, fail-closed for auth

### TR4: Architecture

- Business logic extracted to `server/kb-reader.ts`
- Route handlers are thin (auth + delegation)
- Three route files:
  - `app/api/kb/tree/route.ts`
  - `app/api/kb/content/[...path]/route.ts`
  - `app/api/kb/search/route.ts`
- New dependency: `gray-matter` for frontmatter parsing
- Both `bun.lock` and `package-lock.json` must be regenerated

### TR5: Testing

- Unit tests for `server/kb-reader.ts` (tree building, content parsing, search, path validation)
- Negative-space security test: scan all KB route files and assert path parameters are validated
- Integration with existing `csrf-coverage.test.ts` (GET routes are exempt, but if POST routes are added later, they must be covered)
- Test framework: Vitest (existing config)

## Dependencies

- Phase 2 security audit (#674): CLOSED -- security patterns reviewed
- Consumed by: KB viewer UI (#1689)
- YAML frontmatter parsing: `gray-matter` package (new dependency)
