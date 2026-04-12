# Tasks: KB File Upload

**Plan:** `knowledge-base/project/plans/2026-04-12-feat-kb-file-upload-plan.md`
**Issue:** [#1974](https://github.com/jikig-ai/soleur/issues/1974)
**Branch:** feat-kb-file-upload

## Phase 1: Backend — Upload Route

### 1.1 Create `app/api/kb/upload/route.ts`

GitHub API calls inlined directly using `githubApiPost`/`githubApiGet` from `server/github-api.ts` — no wrapper module.

- [ ] CSRF: `validateOrigin`/`rejectCsrf` as first lines
- [ ] Auth: `createClient()` + `supabase.auth.getUser()`
- [ ] Parse FormData: `file` (File) + `targetDir` (string) + `sha` (string, optional — presence signals overwrite)
- [ ] **Filename sanitization:** Strip control characters, reject leading dots, enforce max 255-byte length, reject Windows reserved names
- [ ] Server-side type validation (allowlist: png, jpeg, gif, webp, pdf, csv, txt, docx)
- [ ] Server-side size validation (reject > 20MB before any processing)
- [ ] Path traversal defense: `isPathInWorkspace(resolvedPath, kbRoot)` from `server/sandbox.ts`
- [ ] Null byte rejection, empty path rejection
- [ ] Parse `owner/repo` from user's `repo_url` column
- [ ] `generateInstallationToken(installationId)` from `server/github-app.ts`
- [ ] Base64-encode file content
- [ ] Check if file exists via `githubApiGet` → return 409 with `{ error, sha, path }` if exists and no `sha` in request
- [ ] If `sha` provided: include it in GitHub PUT (overwrite)
- [ ] `githubApiPost` PUT to `/repos/{owner}/{repo}/contents/{path}` with `{ content: base64, message: "Upload {filename} via Soleur", sha? }`
- [ ] Surface actual GitHub API errors (status + message), add `Sentry.captureException()`
- [ ] **Workspace sync:** After successful GitHub PUT, async `execFile("git", ["pull", "--ff-only"])` with 30s timeout. On failure, return `SYNC_FAILED` error (not success).
- [ ] Return `{ path, sha, commitSha }` on success (201)
- [ ] Return specific error codes: 400 (bad path/filename), 409 (duplicate with SHA), 413 (too large), 415 (bad type), 502 (GitHub error)

## Phase 2: Backend — Expand kb-reader.ts + Content Route

### 2.1 Expand `buildTree` to include all file types

- [ ] Remove `.md` filter at line 144 — include all files (or allowlist matching upload types)
- [ ] Add `extension` field to `TreeNode` type (for type-specific icons and client routing)
- [ ] Keep symlink skip (`!entry.isSymbolicLink()`)
- [ ] Update `test/kb-reader.test.ts:47` — "excludes non-.md files" test: full rewrite
- [ ] Update test at ~line 167 — "throws KbNotFoundError for non-.md file"

### 2.2 Extend content route for binary files

Extend `app/api/kb/content/[...path]/route.ts` — no new route file:

- [ ] Auth only (NO CSRF on GET — would break `<img src>` and `<embed src>`)
- [ ] If `.md`: existing `readContent` path (frontmatter + text, 1MB limit)
- [ ] If non-`.md`: read as Buffer via `fs.readFile`, path validation via `isPathInWorkspace`
- [ ] Content-Type lookup from extension
- [ ] `Content-Disposition: inline` for images/PDFs/text, `attachment` for DOCX
- [ ] Symlink check on binary path
- [ ] **Middleware bypass test:** Static-asset matcher excludes `*.png` etc. — add test that unauthenticated GET to `/api/kb/content/secret.png` returns 401

### 2.3 Keep search `.md`-only

- [ ] Verify `searchKb`/`collectMdFiles` still filters to `.md` — binary files aren't searchable
- [ ] Add comment explaining the intentional `.md`-only scope for search

### 2.4 Restrict KB sharing to `.md` files

- [ ] In `app/api/kb/share/route.ts` (share **creation** POST): add extension validation
- [ ] Reject share creation for non-`.md` files with 400 error
- [ ] Note: share consumption at `app/api/shared/[token]/route.ts` already safe — `readContent` enforces `.md`

## Phase 3: Frontend — FileTree Upload Button

### 3.1 Add `refreshTree()` to KB context

- [ ] Add `refreshTree` function to `KbContextValue` type in `kb-context.tsx`
- [ ] Implementation in `app/(dashboard)/dashboard/kb/layout.tsx` where `setTree` is available
- [ ] Re-fetches `/api/kb/tree` and calls `setTree`
- [ ] Wrap in `useMemo` to prevent unnecessary re-renders
- [ ] Preserve expanded directory state across refresh

### 3.2 Add upload button to FileTree directory items

- [ ] In `file-tree.tsx` TreeItem directory branch (line 49): add upload button
- [ ] Button visible on hover (CSS `:hover` on directory row)
- [ ] Upload icon (e.g., `PlusIcon` or `UploadIcon` from lucide)
- [ ] Click opens hidden `<input type="file">` with `accept` filter for allowed types
- [ ] Client-side validation: type allowlist + 20MB size check
- [ ] On valid file: POST to `/api/kb/upload` with FormData (file + targetDir)

### 3.3 Upload state and progress

- [ ] Loading indicator on the directory row during upload (indeterminate spinner, yellow/amber per wireframes)
- [ ] Success: call `refreshTree()`, brief success toast
- [ ] Error: display error message (surface server error text). Red for hard errors, yellow for warnings.
- [ ] Duplicate (409): simple confirm dialog — "{filename} already exists. Replace?" (not side-by-side comparison)
- [ ] On confirm: re-POST with `sha` from 409 response
- [ ] SYNC_FAILED: show "File uploaded but may not appear immediately. Try refreshing." with refresh button
- [ ] All toasts dismissible with X button

### 3.4 Add type-specific file icons

- [ ] Image files: image icon
- [ ] PDF files: PDF icon
- [ ] CSV/TXT: text/data icon
- [ ] DOCX: document icon
- [ ] Default: generic file icon (existing behavior)

## Phase 4: Frontend — File Preview Component

### 4.1 Create `components/kb/file-preview.tsx`

- [ ] Image preview: `<img>` loading from `/api/kb/content/{path}` with lightbox on click
- [ ] PDF preview: `<embed>` with fallback download link
- [ ] Text preview (TXT): `<pre>` block loading content from `/api/kb/content/{path}`
- [ ] CSV/DOCX: download link with file info (name, size)
- [ ] Loading state while fetching file

### 4.2 Route non-markdown files to file-preview

- [ ] In `app/(dashboard)/dashboard/kb/[...path]/page.tsx:25`: **remove the redirect guard** that sends non-`.md` paths to `/dashboard/kb`
- [ ] Replace with extension-based fork: `.md` → existing markdown rendering, non-`.md` → `<FilePreview>`
- [ ] Use `TreeNode.extension` from context or parse from path params
- [ ] Breadcrumb should still work for non-markdown files

## Phase 5: Testing

### 5.1 Unit tests

- [ ] Upload route: test validation (type, size, path traversal, CSRF, filename sanitization), mock GitHub API, test workspace sync success and failure
- [ ] Extended content route: test binary path validation, correct Content-Type headers, Content-Disposition, symlink rejection, auth without middleware
- [ ] `kb-reader.ts`: test expanded `buildTree` includes all types (rewrite line 47 test, update line 167 test)
- [ ] Share route: test `.md`-only restriction for share creation

### 5.2 Integration tests

- [ ] `csrf-coverage.test.ts`: verify new POST route is covered (should auto-detect)
- [ ] Upload → tree refresh → file visible flow
- [ ] Duplicate detection → confirm → overwrite flow
- [ ] Error surfacing from GitHub API
- [ ] Unauthenticated GET to `/api/kb/content/file.png` returns 401 (middleware bypass)

### 5.3 Browser QA

- [ ] Upload PNG → appears in tree → click → image preview with lightbox
- [ ] Upload PDF → appears in tree → click → embedded viewer or download
- [ ] Upload > 20MB → rejection message
- [ ] Upload .exe → rejection message
- [ ] Path traversal attempt → rejection
- [ ] Overwrite existing file → confirm → replaced
- [ ] Non-`.md` file in tree → click → FilePreview (not redirect)
- [ ] Search → only `.md` results appear
- [ ] Share button on non-`.md` file → rejected or hidden
