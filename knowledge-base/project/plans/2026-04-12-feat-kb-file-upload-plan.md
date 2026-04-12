---
title: "feat: KB file upload — images, PDFs, and documents via GitHub Contents API"
type: feat
date: 2026-04-12
---

# feat: KB file upload

## Overview

Enable users to upload files (images, PDFs, CSV, TXT, DOCX) to any knowledge-base directory via the web UI. Uploaded files are committed to the user's git repo through the GitHub Contents API, giving agents native discoverability and users full data portability (`git clone` exports everything).

**Issue:** [#1974](https://github.com/jikig-ai/soleur/issues/1974)
**Spec:** `knowledge-base/project/specs/feat-kb-file-upload/spec.md`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-12-kb-file-upload-brainstorm.md`
**PR:** [#2002](https://github.com/jikig-ai/soleur/pull/2002) (draft)

## Problem Statement

The KB viewer is read-only for non-markdown content. Users who want to store reference materials (brand assets, financial PDFs, data CSVs) must commit them via git CLI, breaking the "no-code" promise. The FileTree only shows `.md` files — binary content is invisible even if already committed.

## Proposed Solution

Three coordinated changes:

1. **Upload API** — `POST /api/kb/upload` accepts a file + target directory, commits via GitHub Contents API using the GitHub App installation token (server-side proxy, no GitHub credentials in browser)
2. **Expanded kb-reader.ts** — `buildTree` includes all file types (not just `.md`), existing content route extended to serve binary files with correct Content-Type
3. **FileTree upload button** — Per-directory upload button appears on hover, opens native file picker filtered to allowed types

## Technical Approach

### Files to Create

| File | Purpose |
|------|---------|
| `app/api/kb/upload/route.ts` | POST endpoint — auth, validate, proxy to GitHub Contents API. Calls `githubApiPost` / `githubApiGet` directly (no wrapper module). |
| `components/kb/file-preview.tsx` | Render non-markdown files: image preview, embedded PDF viewer, download link |

### Files to Modify

| File | Change |
|------|--------|
| `server/kb-reader.ts:144` | Remove `.md` filter in `buildTree` — include all file types (or allowlist) |
| `server/kb-reader.ts:104` | `collectMdFiles` — keep `.md`-only for search (binary files aren't searchable) |
| `app/api/kb/content/[...path]/route.ts` | **Extend** to serve binary files: if non-`.md`, read as Buffer, return with correct `Content-Type` + `Content-Disposition` header. Auth-only (no CSRF on GET). |
| `components/kb/file-tree.tsx:49` | Add upload button to directory items (visible on hover) |
| `components/kb/kb-context.tsx` | Add `refreshTree()` method to context — called after upload completes |
| `test/kb-reader.test.ts:47` | Update "excludes non-.md files" test → now includes all file types. Also update test at ~line 167 ("throws KbNotFoundError for non-.md file") |
| `app/(dashboard)/dashboard/kb/[...path]/page.tsx:25` | **Remove redirect guard** that sends non-.md paths to `/dashboard/kb`. Replace with fork: `.md` → markdown render, non-`.md` → `<FilePreview>` component |
| `app/api/kb/share/route.ts:45` | **Restrict share creation to `.md` files** — add extension validation. Currently only validates `isPathInWorkspace`, so users could create share links for binary files that 404 on access |
| `server/kb-reader.ts` (TreeNode type) | Add `extension` field to `TreeNode` for type-specific icons and client-side routing (avoids parsing filename on every render) |

### Upload Flow

```
User clicks upload button on directory
  → Native file picker (filtered to allowed types)
  → Client validates type + size (< 20MB)
  → POST /api/kb/upload { file (FormData), targetDir }
  → Server validates: auth, CSRF, type allowlist, size, path traversal, filename sanitization
  → Parse owner/repo from user's repo_url
  → generateInstallationToken(installationId)
  → Check if file exists (GET /repos/{owner}/{repo}/contents/{path})
     → If exists AND no sha in request: return 409 with { error, sha, path }
     → Client shows simple confirm: "logo.png already exists. Replace?"
     → If confirm: client re-POSTs with sha from 409 response
  → PUT /repos/{owner}/{repo}/contents/{path} { content: base64, message, sha? }
  → Workspace sync: async git pull on user's workspace
  → Return { path, sha, commitSha }
  → Client calls refreshTree() → FileTree updates
```

### Workspace Sync (Critical — identified by SpecFlow)

**Problem:** The upload commits to GitHub via Contents API, but `buildTree` reads from the local filesystem. Without a sync step, the uploaded file is invisible in the tree after `refreshTree()`.

**Solution:** After a successful GitHub Contents API PUT, the upload route triggers a `git pull` on the user's workspace directory before returning. This ensures the local filesystem has the committed file when the client calls `refreshTree()`.

```typescript
// In upload route, after successful GitHub PUT:
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const execFileAsync = promisify(execFile);
await execFileAsync("git", ["pull", "--ff-only"], { cwd: workspacePath, timeout: 30000 });
```

**Considerations:**

- Use async `execFile` (not `execFileSync`) to avoid blocking the Node.js event loop. Sync would freeze all concurrent requests during git pull.
- Use `execFile` (not `exec`) to prevent shell injection — no user input in args
- Use `--ff-only` to avoid merge conflicts (we just pushed, so fast-forward is guaranteed)
- Set a 30-second timeout to prevent hangs
- If `git pull` fails (network, `.git/index.lock` contention), return a clear error: `{ error: "File committed to GitHub but workspace sync failed. Try refreshing.", code: "SYNC_FAILED" }`. Do NOT return `success: true` — the file is invisible.
- The workspace git credentials come from the GitHub App installation token (set as `GIT_ASKPASS` or credential helper)

### API Contracts

**POST /api/kb/upload — Request:**

FormData fields:

- `file` (File) — the file to upload (filename derived from `file.name`, sanitized server-side)
- `targetDir` (string) — relative path within knowledge-base (e.g., `assets/images`)
- `sha` (string, optional) — SHA of existing file; presence signals overwrite intent (no separate boolean)

**POST /api/kb/upload — Response:**

Success (201):

```json
{ "path": "assets/images/logo.png", "sha": "abc123", "commitSha": "def456" }
```

Duplicate (409):

```json
{ "error": "File already exists", "sha": "abc123", "path": "assets/images/logo.png" }
```

Validation errors: 400 (bad path), 413 (too large), 415 (unsupported type)

```json
{ "error": "File exceeds 20MB limit", "code": "FILE_TOO_LARGE" }
```

Auth/CSRF errors: 401, 403
GitHub API errors: 502 with upstream message

```json
{ "error": "GitHub API error: Not Found", "code": "GITHUB_API_ERROR", "status": 404 }
```

### Binary File Serving (extended content route)

No new route — extend `app/api/kb/content/[...path]/route.ts`:

```
GET /api/kb/content/path/to/image.png
  → Auth (supabase.auth.getUser) — NO CSRF on GET (would break <img src> and <embed src>)
  → Resolve workspace_path from user record
  → isPathInWorkspace(fullPath, kbRoot) — path traversal defense
  → If .md: existing readContent path (frontmatter + text)
  → If non-.md: fs.readFile(fullPath) as Buffer
  → Content-Type from extension lookup
  → Content-Disposition: inline (images, PDFs, text) or attachment (DOCX)
  → Return raw bytes with correct headers
```

**Middleware note:** The middleware matcher excludes `*.png`, `*.jpg`, etc. by extension regex. This means `/api/kb/content/photo.png` bypasses middleware entirely — auth relies solely on in-route validation. This is acceptable but must be tested: "unauthenticated request to `/api/kb/content/secret.png` returns 401."

### Content-Type Map

| Extension | Content-Type | Preview Component |
|-----------|-------------|-------------------|
| `.png` | `image/png` | `<img>` with lightbox |
| `.jpg`, `.jpeg` | `image/jpeg` | `<img>` with lightbox |
| `.gif` | `image/gif` | `<img>` with lightbox |
| `.webp` | `image/webp` | `<img>` with lightbox |
| `.pdf` | `application/pdf` | `<iframe>` or `<embed>` (browser native) |
| `.csv` | `text/csv` | Download link |
| `.txt` | `text/plain` | `<pre>` block |
| `.docx` | `application/vnd.openxmlformats...` | Download link |

## Technical Considerations

### Security (Critical)

- **CSRF protection** on `POST /api/kb/upload`: `validateOrigin`/`rejectCsrf` as first lines. The `csrf-coverage.test.ts` negative-space test will catch omissions at CI time. (Learning: `2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md`)
- **Path traversal**: Use `isPathInWorkspace(fullPath, kbRoot)` from `server/sandbox.ts:110-126` — resolves symlinks via `realpathSync`, uses trailing `/` guard. Never use bare `startsWith()`. Reject null bytes, `..` segments, empty paths. (Learning: `2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`)
- **Symlink escape**: Skip symlinks in enumeration (`!entry.isSymbolicLink()`). The binary serving route must validate against symlink-based escapes. (Learning: `2026-04-07-symlink-escape-recursive-directory-traversal.md`)
- **File type validation**: Allowlist on both client and server. Never use blocklist. Validate by extension AND Content-Type header.
- **Size validation**: Reject > 20MB server-side before attempting GitHub API call. Client validates too.
- **Filename sanitization**: Strip control characters, reject leading dots (hidden files), enforce max 255-byte filename length, reject Windows reserved names (`CON`, `NUL`, etc.). `isPathInWorkspace` catches traversal but not these cases.
- **Middleware exclusion awareness**: The middleware matcher excludes static asset extensions (`.png`, `.jpg`, etc.). Requests to `/api/kb/content/secret.png` bypass middleware — auth must be enforced in-route. Add a test: "unauthenticated GET to binary content returns 401."

### GitHub API

- **Auth**: Reuse `generateInstallationToken(installationId)` from `server/github-app.ts:423`. No new auth flow needed. (Learning: `2026-03-29-repo-connection-implementation.md`)
- **Contents API format**: `PUT /repos/{owner}/{repo}/contents/{path}` with `{ message, content: base64, sha? }`. The `sha` field is required for updates (overwrite), omitted for creates.
- **Error surfacing**: Return actual GitHub API error messages to client (status + message), not generic strings. Add `Sentry.captureException()`. (Learning: `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`)
- **Base64 encoding**: Transit-only. Do not persist base64 in database columns (especially not `bytea` — PostgREST corrupts it). (Learning: `2026-03-17-postgrest-bytea-base64-mismatch.md`)
- **Rate limits**: GitHub Contents API has a 100MB repo size soft limit and per-file 100MB limit. Our 20MB cap is well within bounds.
- **Permissions**: The GitHub App must have `contents: write` scope on the installation. If missing, the PUT will fail with a non-obvious 403. Verify scope during upload or surface the specific permission error. Check the App's current permission configuration.
- **Error response parsing**: GitHub returns `{ message: string, documentation_url: string, errors?: [...] }`. Parse and surface the `message` field.

### Frontend Architecture

- **Upload button placement**: Goes in `layout.tsx` sidebar (not page component) because the FileTree is rendered in layout. (Learning: `2026-04-10-kb-nav-tree-disappears-on-file-select.md`)
- **Expanded directory keys**: Use full path keys (not just name) for expanded state. (Learning: `2026-04-07-kb-viewer-react-context-layout-patterns.md`)
- **refreshTree**: Add to `KbContextValue`. After upload, re-fetch `/api/kb/tree` and update context. Wrap in `useMemo` to avoid re-renders.
- **Progress UX**: GitHub Contents API is synchronous (base64 in request body) so XHR progress is less meaningful than streaming. Show indeterminate spinner during commit, then success state.
- **File icons**: Add type-specific icons in FileTree (image icon, PDF icon, etc.) — currently only generic `FileIcon`.
- **Reusable patterns from chat attachments**: `PendingAttachment` type (`components/chat/chat-input.tsx:17-24`), `validateAndAddFiles` pattern, error toast auto-dismiss.
- **File routing via extension**: All non-`.md` files (including `.txt`, `.csv`) route through the extended content route's binary branch, NOT through `readContent`. The `readContent` function has a 1MB `MAX_FILE_SIZE` limit that would reject uploaded text files > 1MB. Only `.md` files use the markdown parsing path.
- **Page redirect removal**: The `[...path]/page.tsx` at line 25 currently redirects non-`.md` paths to `/dashboard/kb`. This MUST be replaced with a fork: check `TreeNode.extension` → `.md` renders markdown, everything else renders `<FilePreview>`. (Kieran: actual file is `app/(dashboard)/dashboard/kb/[...path]/page.tsx`, not `(app)`).
- **Expanded state after refresh**: When `refreshTree()` replaces the tree, ensure the `expanded` Set includes any new parent directories created by GitHub Contents API for nested uploads. Otherwise the uploaded file could be hidden inside a collapsed directory.

### Performance

- **kb-reader.ts `buildTree`**: Currently parallelized with `Promise.all`. Expanding to all file types will increase tree size. Keep symlink skip. No regex with shared `g` flag under concurrency. (Learning: `2026-04-07-promise-all-parallel-fs-io-patterns.md`)
- **Search stays `.md`-only**: `searchKb`/`collectMdFiles` should keep the `.md` filter — binary files aren't text-searchable. Expanding search scope would add no value and slow it down.

## Acceptance Criteria

### Functional

- [x] Per-directory upload button visible on hover in FileTree sidebar
- [x] Clicking upload opens native file picker filtered to: PNG, JPEG, GIF, WebP, PDF, CSV, TXT, DOCX
- [x] Uploaded file is committed to the correct directory in the user's git repo
- [x] Commit message format: `Upload {filename} via Soleur` (clear provenance)
- [x] After upload, FileTree refreshes to show the new file without page reload
- [x] Non-markdown files visible in FileTree with type-appropriate icons
- [x] Clicking an image shows preview with lightbox
- [x] Clicking a PDF shows embedded viewer (browser native)
- [x] Clicking CSV/TXT shows content or download link
- [x] Clicking DOCX shows download link
- [x] Duplicate filename returns 409, client prompts overwrite or cancel
- [x] Overwrite re-commits with correct SHA (no force push)
- [x] Upload shows loading indicator during commit
- [x] Error messages surface actual GitHub API errors, not generic strings

### Non-Functional

- [x] Files > 20MB rejected client-side AND server-side with clear message
- [x] Unsupported file types rejected client-side AND server-side
- [x] Path traversal attempts (../../, null bytes, symlinks) rejected server-side
- [x] CSRF protection on POST route (validated by csrf-coverage.test.ts)
- [x] Binary file serving route validates path within workspace boundary
- [x] No base64 content persisted in database

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a user with a connected repo, when they click the upload button on a directory and select a PNG, then the file appears in the FileTree and clicking it shows an image preview
- Given a user uploads a PDF, when they click it in the FileTree, then a PDF viewer or download link is displayed
- Given a user uploads a file with the same name as an existing file, when the server returns 409, then the client prompts to overwrite or cancel
- Given a user confirms overwrite, when the upload succeeds, then the file is updated in git with a new commit (SHA included in PUT)

### Security Tests

- Given a path traversal attempt (`../../etc/passwd`), when POST /api/kb/upload is called, then the server returns 400
- Given a null byte in the path (`file%00.md`), when POST /api/kb/upload is called, then the server returns 400
- Given a symlink in the KB directory, when GET /api/kb/file/[...path] follows the symlink, then `isPathInWorkspace` rejects it
- Given a file > 20MB, when POST /api/kb/upload is called, then the server returns 413 before reaching GitHub API
- Given a `.exe` file, when POST /api/kb/upload is called, then the server returns 415 (unsupported type)
- Given a missing CSRF token, when POST /api/kb/upload is called, then the server returns 403
- Given an unauthenticated request to GET /api/kb/content/secret.png (middleware bypass via extension), then the route returns 401
- Given a filename with control characters or leading dot, when POST /api/kb/upload is called, then the filename is sanitized or rejected

### Edge Cases

- Given a deeply nested directory (3+ levels), when uploading a file, then the file is committed to the correct path
- Given a filename with special characters (spaces, unicode), when uploading, then the file is committed with the correct name
- Given a user with no connected repo, when they attempt upload, then a clear error explains repo connection is required
- Given GitHub API returns a rate limit error, when the upload fails, then the actual error message is surfaced
- Given the file already exists and user cancels overwrite, then no commit is made
- Given workspace sync fails after GitHub commit, when the upload returns, then a clear error is returned (`SYNC_FAILED`) with message "File committed to GitHub but workspace sync failed. Try refreshing."
- Given a zero-byte file, when POST /api/kb/upload is called, then the upload succeeds (GitHub accepts empty content)
- Given GitHub App installation lacks `contents: write` permission, when upload fails with 403, then the error message identifies the missing permission
- Given a user creates a share link for a non-.md file, when the share POST is called, then the server returns 400 ("Only markdown files can be shared")
- Given two concurrent uploads to the same directory with different filenames, when both succeed, then both files are committed (no SHA conflict)

### Cross-Feature Regression

- Given the tree now shows all file types, when KB search is performed, then only `.md` files appear in results (search stays markdown-only)
- Given a binary file exists in the tree, when the user clicks it, then the page renders `<FilePreview>` (not redirect to `/dashboard/kb`)
- Given KB sharing, when a user attempts to share a non-`.md` file, then share creation is rejected

### Integration Verification (for `/soleur:qa`)

- **Browser:** Navigate to /dashboard/kb, hover over a directory, click upload, select a test PNG, verify it appears in tree, click to preview
- **Browser:** Upload a test PDF, verify embedded viewer or download link
- **Browser:** Upload a file with same name, verify overwrite prompt appears

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| Workspace sync lag — file committed to GitHub but not visible locally | Async `git pull --ff-only` after PUT. On failure, return clear `SYNC_FAILED` error (not success). Client can retry or prompt refresh. |
| GitHub Contents API rate limits (5000/hr for installation tokens) | 20MB cap keeps payload small; typical usage is well under limits |
| Large file base64 encoding doubles memory | 20MB file → ~27MB base64. Server-side validation rejects before encoding if possible |
| `buildTree` performance with many non-.md files | Tree already parallelized; monitor for repos with 1000+ files |
| GDPR deletion — git history persistence | Accept git history persistence; "delete" removes from HEAD. Tracked in #1976. Document in spec Non-Goals. |
| Browser PDF viewer inconsistency | Use `<embed>` with fallback download link |
| KB sharing breaks for non-.md files | Restrict share creation to `.md` files at the API level |
| GitHub App missing `contents: write` scope | Verify permission during upload, surface specific error |
| Installation token expiry mid-large-upload | Token cached with 5-min safety margin; 20MB uploads complete well within that window |

## Open Decisions

### 1. Agent discoverability (Spec Goal 3 / Test T7)

The spec says "Agents can discover and reference uploaded files natively" and T7 tests "agent can reference the file in conversation." The plan expands `buildTree` so agents see file names in the tree, but agents operating server-side cannot call the browser endpoint (`GET /api/kb/file/[...path]`). Binary file content is not accessible to agents through the current architecture.

**Decision needed:** Either (a) descope T7 from this PR and track agent-side binary file access as a follow-up issue, or (b) add a server-side file access path for agents (e.g., agents call `readBinaryContent` directly, which returns a Buffer + Content-Type). Option (a) is recommended for V1 — agent discoverability of file *names* is sufficient; *reading* binary content is a separate capability.

### 2. Roadmap row

Issue #1974 is milestoned to Phase 3 but has no numbered row in the Phase 3 table. Add row 3.20 before implementation begins (AGENTS.md workflow gate).

## Domain Review

**Domains relevant:** Product, Marketing, Engineering

### Engineering (CTO) — carried from brainstorm

**Status:** reviewed
**Assessment:** Chat attachment infrastructure partially reusable for validation patterns. Core risk is kb-reader.ts expansion (currently filesystem/.md only). Medium-high complexity (3-5 days). GitHub Contents API is new to the codebase — no existing usage. Recommends architecture decision record for storage strategy (already documented in brainstorm decisions table).

### Marketing (CMO) — carried from brainstorm

**Status:** reviewed
**Assessment:** Reinforces compounding moat messaging ("your KB gets richer with every upload"). Table-stakes for knowledge management competitors. Recommends conversion-optimizer for upload flow layout review. Needs clear file type list and storage limit communication for pricing page.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead
**Skipped specialists:** none
**Pencil available:** yes

#### CPO Findings

- **Roadmap gap:** #1974 needs row 3.20 in Phase 3 table
- **Agent discoverability gap:** T7 has no implementation path for server-side agent access — recommend descoping from V1
- **Brand alignment:** PASS — git-committed storage aligns with "full data portability" and "accessible anywhere"
- **Priority:** P3-low, non-blocking for Phase 3 closure
- **GitHub App permissions:** Verify `contents: write` scope on installation

#### SpecFlow Findings (Critical Gaps Resolved)

- **Workspace sync:** Upload commits to GitHub but `buildTree` reads local disk. Added `git pull --ff-only` step to upload route.
- **Page redirect:** `[...path]/page.tsx:25` actively rejects non-.md paths. Must be replaced with extension-based fork.
- **409 response body:** Unspecified. Added API contract with SHA in 409 response.
- **KB sharing breaks:** Share creation validates only `isPathInWorkspace`. Added `.md`-only restriction to share POST route.
- **1MB vs 20MB limit:** `readContent` has 1MB limit. All non-.md files route through binary endpoint.
- **TreeNode extension field:** Added for client-side routing and type-specific icons.
- **Additional test cases:** Workspace sync failure, zero-byte files, permissions, concurrent uploads, cross-feature regressions.

#### UX Design Lead Findings

Wireframes delivered: `knowledge-base/product/design/kb-file-upload/kb-file-upload-flows.pen`

7 frames covering all flows:

| Frame | Flow | Key Decision |
|-------|------|-------------|
| 01 | Default sidebar state | All file types visible with type-specific icons |
| 02 | Upload hover button | Per-directory button revealed on hover (yellow callout) |
| 03 | Upload loading state | Yellow highlight on tree item + toast with commit progress |
| 04 | Image preview | Inline preview with metadata, dimensions, lightbox hint |
| 05 | PDF preview | Embedded viewer with page counter |
| 06 | Duplicate overwrite dialog | Side-by-side comparison (existing vs new) with Cancel/Replace |
| 07 | Error states | 4 toast patterns: 413, 415, GitHub API (with retry), no-repo (with settings link) |

**Design decisions to implement:**

- Loading state uses yellow/amber (differentiates from error=red, success=blue)
- Overwrite dialog shows file comparison with metadata for informed decisions
- Error toasts differentiate hard errors (red) from soft warnings (yellow)
- All toasts are dismissible with X button

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Supabase Storage (presigned URLs) | No data portability — user can't `git clone` and get their files. Breaks standing requirement (AGENTS.md). |
| Client-side GitHub API calls | Requires GitHub credentials in browser. Inconsistent with CI/CD proxy architecture (constitution 3.10). |
| Drag-and-drop onto FileTree | Deferred to post-V1. Per-directory button is simpler and sufficient. |
| Git LFS for large files | Per-user repos are small enough without it. Adds complexity. |

## References & Research

### Internal References

- kb-reader.ts: `apps/web-platform/server/kb-reader.ts` (buildTree:117, readContent:173, MAX_FILE_SIZE:6)
- Path validation: `apps/web-platform/server/sandbox.ts:110-126` (isPathInWorkspace)
- GitHub auth: `apps/web-platform/server/github-app.ts:423` (generateInstallationToken)
- GitHub API wrapper: `apps/web-platform/server/github-api.ts:23-106`
- Chat attachment patterns: `apps/web-platform/app/api/attachments/presign/route.ts`, `components/chat/chat-input.tsx:17-24`
- FileTree: `apps/web-platform/components/kb/file-tree.tsx` (TreeItem:31, directories:49)
- KB context: `apps/web-platform/components/kb/kb-context.tsx`

### Learnings Applied

- CSRF three-layer defense: `2026-03-20-csrf-three-layer-defense-nextjs-api-routes.md`
- Path traversal (CWE-22): `2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- Symlink escape: `2026-04-07-symlink-escape-recursive-directory-traversal.md`
- KB nav tree layout fix: `2026-04-10-kb-nav-tree-disappears-on-file-select.md`
- KB context patterns: `2026-04-07-kb-viewer-react-context-layout-patterns.md`
- Promise.all fs patterns: `2026-04-07-promise-all-parallel-fs-io-patterns.md`
- GitHub App auth: `2026-03-29-repo-connection-implementation.md`
- GitHub API error surfacing: `2026-04-06-github-app-org-repo-creation-endpoint-routing.md`
- PostgREST bytea corruption: `2026-03-17-postgrest-bytea-base64-mismatch.md`
- Middleware prefix matching: `2026-03-20-middleware-prefix-matching-bypass.md`
- CSRF structural enforcement: `2026-03-20-csrf-prevention-structural-enforcement-via-negative-space-tests.md`

### Related Issues

- #1974 — KB file upload (this feature)
- #1961 — Chat file attachments (shipped — patterns reused)
- #1976 — GDPR deletion scope (Supabase Storage purge, related)
- #2002 — Draft PR
