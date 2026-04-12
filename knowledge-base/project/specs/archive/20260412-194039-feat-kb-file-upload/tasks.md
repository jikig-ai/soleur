# Tasks: KB File Upload

**Plan:** `knowledge-base/project/plans/2026-04-12-feat-kb-file-upload-plan.md`
**Issue:** [#1974](https://github.com/jikig-ai/soleur/issues/1974)
**Branch:** feat-kb-file-upload

## Phase 1: Backend — Upload Route

### 1.1 Create `app/api/kb/upload/route.ts`

GitHub API calls inlined directly using `githubApiPost`/`githubApiGet` from `server/github-api.ts` — no wrapper module.

- [x] CSRF: `validateOrigin`/`rejectCsrf` as first lines
- [x] Auth: `createClient()` + `supabase.auth.getUser()`
- [x] Parse FormData: `file` (File) + `targetDir` (string) + `sha` (string, optional — presence signals overwrite)
- [x] **Filename sanitization:** Strip control characters, reject leading dots, enforce max 255-byte length, reject Windows reserved names
- [x] Server-side type validation (allowlist: png, jpeg, gif, webp, pdf, csv, txt, docx)
- [x] Server-side size validation (reject > 20MB before any processing)
- [x] Path traversal defense: `isPathInWorkspace(resolvedPath, kbRoot)` from `server/sandbox.ts`
- [x] Null byte rejection, empty path rejection
- [x] Parse `owner/repo` from user's `repo_url` column
- [x] `generateInstallationToken(installationId)` from `server/github-app.ts`
- [x] Base64-encode file content
- [x] Check if file exists via `githubApiGet` → return 409 with `{ error, sha, path }` if exists and no `sha` in request
- [x] If `sha` provided: include it in GitHub PUT (overwrite)
- [x] `githubApiPost` PUT to `/repos/{owner}/{repo}/contents/{path}` with `{ content: base64, message: "Upload {filename} via Soleur", sha? }`
- [x] Surface actual GitHub API errors (status + message), add `Sentry.captureException()`
- [x] **Workspace sync:** After successful GitHub PUT, async `execFile("git", ["pull", "--ff-only"])` with 30s timeout. On failure, return `SYNC_FAILED` error (not success).
- [x] Return `{ path, sha, commitSha }` on success (201)
- [x] Return specific error codes: 400 (bad path/filename), 409 (duplicate with SHA), 413 (too large), 415 (bad type), 502 (GitHub error)

## Phase 2: Backend — Expand kb-reader.ts + Content Route

### 2.1 Expand `buildTree` to include all file types

- [x] Remove `.md` filter at line 144 — include all files (or allowlist matching upload types)
- [x] Add `extension` field to `TreeNode` type (for type-specific icons and client routing)
- [x] Keep symlink skip (`!entry.isSymbolicLink()`)
- [x] Update `test/kb-reader.test.ts:47` — "excludes non-.md files" test: full rewrite
- [x] Update test at ~line 167 — "throws KbNotFoundError for non-.md file"

### 2.2 Extend content route for binary files

Extend `app/api/kb/content/[...path]/route.ts` — no new route file:

- [x] Auth only (NO CSRF on GET — would break `<img src>` and `<embed src>`)
- [x] If `.md`: existing `readContent` path (frontmatter + text, 1MB limit)
- [x] If non-`.md`: read as Buffer via `fs.readFile`, path validation via `isPathInWorkspace`
- [x] Content-Type lookup from extension
- [x] `Content-Disposition: inline` for images/PDFs/text, `attachment` for DOCX
- [x] Symlink check on binary path
- [x] **Middleware bypass test:** Static-asset matcher excludes `*.png` etc. — add test that unauthenticated GET to `/api/kb/content/secret.png` returns 401

### 2.3 Keep search `.md`-only

- [x] Verify `searchKb`/`collectMdFiles` still filters to `.md` — binary files aren't searchable
- [x] Add comment explaining the intentional `.md`-only scope for search

### 2.4 Restrict KB sharing to `.md` files

- [x] In `app/api/kb/share/route.ts` (share **creation** POST): add extension validation
- [x] Reject share creation for non-`.md` files with 400 error
- [x] Note: share consumption at `app/api/shared/[token]/route.ts` already safe — `readContent` enforces `.md`

## Phase 3: Frontend — FileTree Upload Button

### 3.1 Add `refreshTree()` to KB context

- [x] Add `refreshTree` function to `KbContextValue` type in `kb-context.tsx`
- [x] Implementation in `app/(dashboard)/dashboard/kb/layout.tsx` where `setTree` is available
- [x] Re-fetches `/api/kb/tree` and calls `setTree`
- [x] Wrap in `useMemo` to prevent unnecessary re-renders
- [x] Preserve expanded directory state across refresh

### 3.2 Add upload button to FileTree directory items

- [x] In `file-tree.tsx` TreeItem directory branch (line 49): add upload button
- [x] Button visible on hover (CSS `:hover` on directory row)
- [x] Upload icon (e.g., `PlusIcon` or `UploadIcon` from lucide)
- [x] Click opens hidden `<input type="file">` with `accept` filter for allowed types
- [x] Client-side validation: type allowlist + 20MB size check
- [x] On valid file: POST to `/api/kb/upload` with FormData (file + targetDir)

### 3.3 Upload state and progress

- [x] Loading indicator on the directory row during upload (indeterminate spinner, yellow/amber per wireframes)
- [x] Success: call `refreshTree()`, brief success toast
- [x] Error: display error message (surface server error text). Red for hard errors, yellow for warnings.
- [x] Duplicate (409): simple confirm dialog — "{filename} already exists. Replace?" (not side-by-side comparison)
- [x] On confirm: re-POST with `sha` from 409 response
- [x] SYNC_FAILED: show "File uploaded but may not appear immediately. Try refreshing." with refresh button
- [x] All toasts dismissible with X button

### 3.4 Add type-specific file icons

- [x] Image files: image icon
- [x] PDF files: PDF icon
- [x] CSV/TXT: text/data icon
- [x] DOCX: document icon
- [x] Default: generic file icon (existing behavior)

## Phase 4: Frontend — File Preview Component

### 4.1 Create `components/kb/file-preview.tsx`

- [x] Image preview: `<img>` loading from `/api/kb/content/{path}` with lightbox on click
- [x] PDF preview: `<embed>` with fallback download link
- [x] Text preview (TXT): `<pre>` block loading content from `/api/kb/content/{path}`
- [x] CSV/DOCX: download link with file info (name, size)
- [x] Loading state while fetching file

### 4.2 Route non-markdown files to file-preview

- [x] In `app/(dashboard)/dashboard/kb/[...path]/page.tsx:25`: **remove the redirect guard** that sends non-`.md` paths to `/dashboard/kb`
- [x] Replace with extension-based fork: `.md` → existing markdown rendering, non-`.md` → `<FilePreview>`
- [x] Use `TreeNode.extension` from context or parse from path params
- [x] Breadcrumb should still work for non-markdown files

## Phase 5: Testing

### 5.1 Unit tests

- [x] Upload route: test validation (type, size, path traversal, CSRF, filename sanitization), mock GitHub API, test workspace sync success and failure
- [x] Extended content route: test binary path validation, correct Content-Type headers, Content-Disposition, symlink rejection, auth without middleware
- [x] `kb-reader.ts`: test expanded `buildTree` includes all types (rewrite line 47 test, update line 167 test)
- [x] Share route: test `.md`-only restriction for share creation

### 5.2 Integration tests

- [x] `csrf-coverage.test.ts`: verify new POST route is covered (should auto-detect)
- [x] Upload → tree refresh → file visible flow
- [x] Duplicate detection → confirm → overwrite flow
- [x] Error surfacing from GitHub API
- [x] Unauthenticated GET to `/api/kb/content/file.png` returns 401 (middleware bypass)

### 5.3 Browser QA

- [x] Upload PNG → appears in tree → click → image preview with lightbox
- [x] Upload PDF → appears in tree → click → embedded viewer or download
- [x] Upload > 20MB → rejection message
- [x] Upload .exe → rejection message
- [x] Path traversal attempt → rejection
- [x] Overwrite existing file → confirm → replaced
- [x] Non-`.md` file in tree → click → FilePreview (not redirect)
- [x] Search → only `.md` results appear
- [x] Share button on non-`.md` file → rejected or hidden
