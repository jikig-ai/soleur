---
title: "feat: KB REST API (file tree, content, search endpoints)"
type: feat
date: 2026-04-07
---

# KB REST API (file tree, content, search endpoints)

## Overview

Build three read-only REST API endpoints that expose a user's knowledge base ("Organization Memory") from the web platform. The endpoints serve the KB viewer UI (#1689) and are private (same-origin, cookie auth only). Data source is the user's workspace filesystem at `/workspaces/<userId>/knowledge-base/`.

**Issue:** #1688 | **Spec:** `knowledge-base/project/specs/feat-kb-rest-api/spec.md`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-07-kb-rest-api-brainstorm.md`

## Problem Statement

Founders cannot see what their AI agents produced. The knowledge base contains brainstorms, plans, specs, learnings, and domain artifacts, but there is no programmatic way to access them from the web platform. Strategic Theme T3 ("Make the Moat Visible") depends on this API.

## Proposed Solution

Three GET endpoints following existing codebase conventions:

| Endpoint | Purpose | Response |
|----------|---------|----------|
| `GET /api/kb/tree` | Full recursive directory tree | Nested JSON tree of `.md` files |
| `GET /api/kb/content/[...path]` | Single file content | Raw markdown + parsed frontmatter JSON |
| `GET /api/kb/search?q=` | Full-text search | Matching files with line-level highlighted snippets |

Architecture: thin route handlers + extracted `server/kb-reader.ts` module (matches `sandbox.ts`, `error-sanitizer.ts`, `tool-path-checker.ts` extraction pattern).

## Technical Considerations

### Architecture

All business logic extracted to `server/kb-reader.ts`. Route handlers are 15-20 lines each: auth check, workspace lookup, delegate to kb-reader, return JSON.

**Files to create:**

| File | Purpose |
|------|---------|
| `apps/web-platform/server/kb-reader.ts` | Tree builder, content reader, search engine |
| `apps/web-platform/app/api/kb/tree/route.ts` | Tree endpoint handler |
| `apps/web-platform/app/api/kb/content/[...path]/route.ts` | Content endpoint handler |
| `apps/web-platform/app/api/kb/search/route.ts` | Search endpoint handler |
| `apps/web-platform/test/kb-reader.test.ts` | Unit tests for kb-reader module |
| `apps/web-platform/test/kb-security.test.ts` | Negative-space security tests |

**Files to modify:**

| File | Change |
|------|--------|
| `apps/web-platform/package.json` | Add `gray-matter` dependency |
| `apps/web-platform/bun.lock` | Regenerated |
| `apps/web-platform/package-lock.json` | Regenerated (required for Dockerfile `npm ci`) |

### Auth Pattern (from `app/api/repo/status/route.ts`)

```typescript
const supabase = await createClient();
const { data: { user } } = await supabase.auth.getUser();
if (!user) {
  return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
}
```

GET routes skip CSRF (`validateOrigin`/`rejectCsrf`) — only POST routes use it.

### Workspace Path Lookup

```typescript
const serviceClient = createServiceClient();
const { data: userData, error: fetchError } = await serviceClient
  .from("users")
  .select("workspace_path, workspace_status")
  .eq("id", user.id)
  .single();

if (fetchError || !userData?.workspace_path) {
  return NextResponse.json({ error: "Workspace not found" }, { status: 404 });
}
if (userData.workspace_status !== "ready") {
  return NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
}
```

Must check `workspace_status === "ready"` before filesystem access. User type: `{ workspace_path: string; workspace_status: "provisioning" | "ready" }`.

### Security (Critical)

**Path traversal protection:** Use `isPathInWorkspace(filePath, kbRoot)` from `@/server/sandbox` where `kbRoot = path.join(workspacePath, "knowledge-base")`. The boundary MUST be the KB root, not the workspace root — otherwise `../../../.claude/settings.json` resolves inside the workspace and passes validation, exposing non-KB files. This handles:

- Symlink resolution via `fs.realpathSync()` (CWE-59)
- Trailing-separator guard against prefix collisions (CWE-22)
- Fail-closed on ELOOP, EACCES, dangling symlinks

**Input sanitization:**

- Reject path segments containing null bytes (`\0`) before joining — `path.join` does not strip them, and `fs.readFile` truncates at null bytes on some platforms (CWE-158)
- Cap search query `q` at 200 characters — unbounded regex compilation on arbitrary-length input is a DoS vector
- Escape special regex characters in search queries before compilation

**gray-matter code execution prevention:** Pass `{ engines: {} }` to `matter()` to disable JavaScript/CoffeeScript evaluation in frontmatter. Without this, a malicious `.md` file with `---js` frontmatter could execute arbitrary server-side code. Pin `gray-matter >= 4.0.3`.

**Error sanitization:** Never expose raw `err.message` from `fs.readFile` or `gray-matter` in responses. Implement KB-specific error mapping in `kb-reader.ts` (not reusing `sanitizeErrorForClient` which is WebSocket-oriented):

- `ENOENT` → 404 "File not found"
- `EACCES` → 403 "Access denied"
- Path validation failure → 403 "Access denied"
- YAML parse error → return `frontmatter: {}` (content is still readable markdown — don't punish the user for a parsing detail)
- Unknown → 500 "An unexpected error occurred"

**Middleware:** `/api/kb/*` paths are automatically protected by existing middleware (not in `PUBLIC_PATHS`). No middleware changes needed.

### Performance

In-process grep for search. Individual user KBs are small (hundreds of files, single-digit MB). Performance ceiling: ~500 files, ~10 MB per workspace. No indexing needed at current scale.

### Implementation Phases

#### Phase 1: Core Implementation

1. Add `gray-matter` (>= 4.0.3) to `apps/web-platform/package.json` dependencies
2. Run `bun install` then `npm install` to regenerate both lockfiles
3. Create `server/kb-reader.ts` with types (`TreeNode`, `ContentResult`, `SearchResult`, `SearchMatch`) and all three functions:
   - `buildTree(kbRoot: string): Promise<TreeNode>` — recursive scan, .md filter, empty dir exclusion, dirs-first sorting, relative paths only
   - `readContent(kbRoot: string, relativePath: string): Promise<ContentResult>` — null byte rejection, `isPathInWorkspace(filePath, kbRoot)` check, .md extension check, `fs.promises.stat` size guard (reject > 1MB), `readFile`, `gray-matter` parse with `{ engines: {} }`. On YAML parse errors: return `frontmatter: {}` (content is still readable)
   - `searchKb(kbRoot: string, query: string): Promise<{ results: SearchResult[]; total: number }>` — recursive .md file find, escape regex special chars, case-insensitive match per line, highlight offsets (character indices), parse frontmatter per match, sort by match count descending, cap at 100. Inline `const kbRoot = path.join(workspacePath, "knowledge-base")` — no wrapper function
4. Create three route handlers (each: auth + workspace lookup + `logger.error(...)` on failures + delegate):
   - `app/api/kb/tree/route.ts` — delegate to `buildTree`
   - `app/api/kb/content/[...path]/route.ts` — join `params.path`, delegate to `readContent`
   - `app/api/kb/search/route.ts` — validate `q` (required, max 200 chars), delegate to `searchKb`
5. Write `test/kb-reader.test.ts` — unit tests for all three functions:
   - `buildTree`: empty dir, nested dirs, mixed file types, sorting, missing KB dir
   - `readContent`: valid file, missing file (404), non-.md (404), path traversal (403), null bytes (403), frontmatter, no frontmatter, malformed YAML (returns `frontmatter: {}`), directory path without extension, file over 1MB
   - `searchKb`: basic match, case insensitivity, highlight offsets, max 100 cap, special regex chars escaped, no matches, query too long

#### Phase 2: Security Tests

1. Create `test/kb-security.test.ts` with negative-space tests:
   - All KB route files import and use `isPathInWorkspace`
   - Path traversal attempts (`../`, `..%2F`, symlinks) return 403
   - Error responses contain no filesystem paths
   - Non-.md file requests are rejected

## Acceptance Criteria

### Functional

- [ ] `GET /api/kb/tree` returns recursive tree of `.md` files for authenticated user
- [ ] `GET /api/kb/content/[...path]` returns raw markdown + parsed frontmatter JSON
- [ ] `GET /api/kb/search?q=` returns matching files with line-level highlighted snippets
- [ ] All endpoints return 401 for unauthenticated requests
- [ ] All endpoints return 503 when workspace is provisioning (not ready)
- [ ] Content endpoint returns 403 for path traversal attempts
- [ ] Content endpoint returns 404 for non-existent or non-.md files
- [ ] Search endpoint returns 400 for empty/missing query parameter
- [ ] Search results capped at 100 entries

### Security

- [ ] Path traversal protection via `isPathInWorkspace()` (CWE-22, CWE-59)
- [ ] Error responses sanitized — no filesystem paths leaked (CWE-209)
- [ ] No absolute paths in any response body
- [ ] Workspace status checked before filesystem access

### Quality

- [ ] Unit tests for all `kb-reader.ts` functions
- [ ] Negative-space security test for path validation coverage
- [ ] `gray-matter` added to correct `package.json` with both lockfiles updated
- [ ] No CSRF test failures (GET routes are exempt)

## Test Scenarios

### Tree Endpoint

- Given an authenticated user with a provisioned workspace, when GET /api/kb/tree, then return recursive tree of .md files
- Given an empty knowledge-base directory, when GET /api/kb/tree, then return tree with no children
- Given directories containing only non-.md files, when GET /api/kb/tree, then those directories are excluded
- Given a workspace where `knowledge-base/` directory does not exist, when GET /api/kb/tree, then return empty tree (root with no children)

### Content Endpoint

- Given a valid .md file path, when GET /api/kb/content/project/learnings/foo.md, then return `{ path, frontmatter, content }`
- Given a file without YAML frontmatter, when GET /api/kb/content/path/to/file.md, then return `frontmatter: {}`
- Given a path like `../../etc/passwd`, when GET /api/kb/content/../../etc/passwd, then return 403
- Given a path to a .json file, when GET /api/kb/content/data.json, then return 404
- Given a non-existent path, when GET /api/kb/content/missing.md, then return 404
- Given a file with malformed YAML frontmatter, when GET /api/kb/content/bad-yaml.md, then return content with `frontmatter: {}`
- Given a directory path without extension, when GET /api/kb/content/project/learnings, then return 404
- Given a path containing null bytes, when GET /api/kb/content/project%00/evil.md, then return 403

### Search Endpoint

- Given query "path traversal", when GET /api/kb/search?q=path%20traversal, then return matching files with highlight offsets
- Given query with special regex chars "file[0]", when GET /api/kb/search?q=file[0], then chars are escaped and search works
- Given no query parameter, when GET /api/kb/search, then return 400
- Given query matching >100 files, when searching, then results are capped at 100
- Given query longer than 200 characters, when GET /api/kb/search?q=..., then return 400

### Auth

- Given no session cookie, when calling any /api/kb/ endpoint, then return 401
- Given a user with workspace_status="provisioning", when calling any /api/kb/ endpoint, then return 503

## Domain Review

**Domains relevant:** Engineering, Product, Marketing (carried forward from brainstorm)

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Data source confirmed as per-user workspace filesystem. Path traversal is primary security risk — existing `sandbox.ts` mitigates CWE-22/CWE-59. Search starts simple (in-process grep). No new infrastructure needed.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** KB API is prerequisite for T3 ("Make the Moat Visible"). Key decisions resolved: raw markdown (client renders), user-scoped, private API. Workspace stability risk relative to repo connection (#1060) accepted.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Adopted "Organization Memory" as user-facing name. No immediate marketing action for API itself. Content Gap 1 activatable once viewer UI ships on top of this API.

## Dependencies and Risks

| Dependency | Status | Impact |
|------------|--------|--------|
| Phase 2 security audit (#674) | CLOSED | Security patterns reviewed — compose with existing |
| KB viewer UI (#1689) | OPEN | Primary consumer — API shapes inform viewer |
| Repo connection (#1060) | OPEN | May change workspace structure later — acceptable risk |

| Risk | Mitigation |
|------|------------|
| Path traversal vulnerability | Reuse battle-tested `isPathInWorkspace()` + negative-space tests |
| Dual lockfile drift | Regenerate both `bun.lock` and `package-lock.json` after adding `gray-matter` |
| Search performance at scale | In-process grep fine for current scale; documented ceiling of ~500 files |

## References and Research

### Internal References

- Auth pattern: `apps/web-platform/app/api/repo/status/route.ts:11-19`
- Workspace lookup: `apps/web-platform/server/workspace.ts:17-56`
- Path security: `apps/web-platform/server/sandbox.ts:110` (`isPathInWorkspace`)
- Error sanitization: `apps/web-platform/server/error-sanitizer.ts:26` (`sanitizeErrorForClient`)
- CSRF structural test: `apps/web-platform/lib/auth/csrf-coverage.test.ts`
- Test setup pattern: `apps/web-platform/test/sandbox.test.ts:74-81`
- Vitest config: `apps/web-platform/vitest.config.ts`
- User type: `apps/web-platform/lib/types.ts:51-58`

### Institutional Learnings

- CWE-22 path traversal: `knowledge-base/project/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- CWE-59 symlink escape: `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md`
- CWE-209 error sanitization: `knowledge-base/project/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`
- YAML frontmatter edge cases: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
- Directory-driven content discovery: `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
- CSRF structural enforcement: `knowledge-base/project/learnings/2026-03-20-csrf-prevention-structural-enforcement-via-negative-space-tests.md`
