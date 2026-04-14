---
title: "feat: add file rename to KB Tree"
type: feat
date: 2026-04-14
---

# feat: Add File Rename to KB Tree

## Overview

Add the ability to rename files and folders in the knowledge base tree UI. The KB Tree already supports file deletion (merged in #2143) and file upload. This adds an inline rename interaction that lets users rename attachment files and folders directly from the sidebar tree.

## Problem Statement / Motivation

Users who upload files to the KB cannot rename them without deleting and re-uploading. Folder names cannot be changed at all through the UI. This forces users to either use git directly or live with the original names, which degrades the KB as an organizational tool.

## Proposed Solution

Add a PATCH endpoint at `/api/kb/file/[...path]` that performs a rename via the GitHub Contents API (get content at old path, create at new path, delete old). Add an inline rename UI in the file tree triggered by a pencil/edit icon button (similar to the existing delete trash icon).

### Approach: GitHub Contents API (Two-Step)

The GitHub Contents API has no native rename endpoint. A rename is implemented as:

1. **GET** the file content and SHA from the old path
2. **PUT** (create) the file at the new path with the base64 content
3. **DELETE** the old file using its SHA

This is the same API surface already used by upload (PUT) and delete (DELETE). For folders, each file in the folder must be moved individually (recursive rename).

**Why not the Git Trees API?** The Git Trees API can move files in a single commit, but it requires a more complex flow (create tree, create commit, update ref) and the existing codebase uses the Contents API exclusively. Consistency with existing patterns is preferred.

## Technical Approach

### API Route: PATCH `/api/kb/file/[...path]`

Add a PATCH handler to the existing `apps/web-platform/app/api/kb/file/[...path]/route.ts`. This file already exports DELETE.

**Request body:**

```json
{
  "newName": "renamed-file.png"
}
```

**Validation (security parity with DELETE route):**

- CSRF validation (validateOrigin/rejectCsrf)
- Authentication (supabase auth.getUser)
- Workspace status check (workspace_path, workspace_status === "ready")
- Path segment extraction and validation
- Null byte check on both old path and new name
- Extension check: `.md` files cannot be renamed through this endpoint (consistency with delete)
- Path traversal check on both old and new resolved paths (isPathInWorkspace)
- Symlink check on old path (skip on ENOENT like delete does)
- Filename sanitization on newName (reuse sanitizeFilename from upload route -- extract to shared utility)

**Rename logic:**

1. Parse `newName` from request body (JSON, not FormData)
2. Validate newName (sanitizeFilename, extension check, not `.md`)
3. Compute old GitHub path and new GitHub path (same directory, different filename)
4. GET file from GitHub Contents API at old path (get SHA + content)
5. PUT file at new path with the base64 content
6. DELETE old file using its SHA
7. Workspace sync (git pull --ff-only, same pattern as delete)
8. Return `{ oldPath, newPath, commitSha }`

**Error handling:**

- 404: Old file not found
- 409: Old file was modified since last read (SHA mismatch on delete step)
- 400: Invalid newName, empty name, `.md` file, path traversal, null bytes
- 409: New path already exists (check before PUT)
- 502: GitHub API errors
- 500: Unexpected errors, sync failures

**Folder rename:**

For the initial implementation, restrict rename to files only. Folder rename requires recursively moving all files, which involves multiple GitHub API calls per file and complex error recovery (partial rename if one file fails). Folder rename can be added as a follow-up.

### Shared Utility: `sanitizeFilename`

Extract `sanitizeFilename` from `apps/web-platform/app/api/kb/upload/route.ts` into a shared module (e.g., `apps/web-platform/server/kb-validation.ts`). Both upload and rename need the same validation. The constants `WINDOWS_RESERVED` and `MAX_FILENAME_BYTES` move with it.

### UI: Inline Rename in FileTree

Add a rename interaction to `apps/web-platform/components/kb/file-tree.tsx`:

**New state type:**

```typescript
type RenameState =
  | { status: "idle" }
  | { status: "editing"; currentName: string }
  | { status: "renaming" }
  | { status: "error"; message: string };
```

**Interaction flow:**

1. Pencil icon appears on hover next to the delete (trash) icon for attachment files (non-`.md`)
2. Clicking the pencil icon enters edit mode: the filename text becomes an inline `<input>` pre-filled with the current name (without extension)
3. User edits the name. Press Enter or blur to confirm. Press Escape to cancel.
4. On confirm: call `PATCH /api/kb/file/{path}` with `{ newName: "edited-name.ext" }`
5. On success: refresh tree, return to idle
6. On error: show inline error message (same pattern as delete error)

**Keyboard accessibility:**

- Enter: confirm rename
- Escape: cancel rename
- The input should auto-focus and select the filename (without extension) on enter

**Icon:** Use a pencil/edit SVG icon (PencilIcon component) matching the existing icon style (14x14, stroke-based).

### Files to Create

- `apps/web-platform/server/kb-validation.ts` -- shared sanitizeFilename + constants

### Files to Modify

- `apps/web-platform/app/api/kb/file/[...path]/route.ts` -- add PATCH handler
- `apps/web-platform/app/api/kb/upload/route.ts` -- import sanitizeFilename from shared module (remove local copy)
- `apps/web-platform/components/kb/file-tree.tsx` -- add rename UI, PencilIcon, RenameState
- `apps/web-platform/server/github-api.ts` -- no changes needed (uses existing githubApiGet, githubApiPost with PUT, githubApiDelete)

### Files to Create (Tests)

- `apps/web-platform/test/kb-rename.test.ts` -- API route unit tests
- `apps/web-platform/test/file-tree-rename.test.tsx` -- component tests

## Non-Goals

- Folder rename (recursive multi-file move) -- deferred to follow-up issue
- Renaming `.md` files (consistency with delete restriction)
- Drag-and-drop to move files between folders
- Batch rename (multiple files at once)

## Acceptance Criteria

- [ ] PATCH `/api/kb/file/[...path]` renames a file on GitHub and syncs workspace
- [ ] Security validations match DELETE route parity (CSRF, auth, path traversal, null bytes, symlinks, .md rejection)
- [ ] Rename button (pencil icon) appears on hover for attachment files only
- [ ] Clicking pencil enters inline edit mode with input pre-filled with current name
- [ ] Enter confirms rename, Escape cancels, blur confirms
- [ ] Duplicate filename at destination returns 409
- [ ] Error states display inline (same pattern as delete errors)
- [ ] Tree refreshes after successful rename
- [ ] `sanitizeFilename` extracted to shared module, upload route updated to import from it

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

The rename interaction follows established UI patterns (inline editing on hover, confirmation via Enter/Escape, error display). No new pages or flows are introduced.

## Test Scenarios

### API Route Tests (kb-rename.test.ts)

- Given an unauthenticated request, when PATCH is called, then return 401
- Given a valid user with workspace not ready, when PATCH is called, then return 503
- Given a path with null bytes, when PATCH is called, then return 400
- Given a `.md` file path, when PATCH is called, then return 400 "Markdown files cannot be renamed"
- Given a path traversal attempt (e.g., `../../etc/passwd`), when PATCH is called, then return 400
- Given a symlink path, when PATCH is called, then return 403
- Given a valid path but file not found on GitHub, when PATCH is called, then return 404
- Given a valid file but newName already exists at destination, when PATCH is called, then return 409
- Given an empty newName, when PATCH is called, then return 400
- Given a newName with invalid characters, when PATCH is called, then return 400
- Given a newName that is a `.md` extension, when PATCH is called, then return 400
- Given a valid file and valid newName, when PATCH is called, then file is created at new path, old file is deleted, workspace syncs, and return 200 with paths
- Given a successful GitHub create but failed delete, when PATCH is called, then return 500 with rollback info
- Given a workspace sync failure after successful rename, when PATCH is called, then return 500 with SYNC_FAILED code
- Given a directory path (GitHub returns array), when PATCH is called, then return 400 "Cannot rename a directory"

### Component Tests (file-tree-rename.test.tsx)

- Given a file tree with an attachment file, when hovering, then pencil icon is visible
- Given a `.md` file, when hovering, then no pencil icon is shown
- Given idle state, when pencil icon is clicked, then input appears with current filename
- Given edit mode, when Enter is pressed with a new name, then PATCH is called and tree refreshes
- Given edit mode, when Escape is pressed, then edit mode is cancelled without API call
- Given a rename API error, when rename fails, then error message displays inline

## References

- File deletion PR: #2143 (pattern reference for API route structure, security checks, and UI)
- Upload route: `apps/web-platform/app/api/kb/upload/route.ts` (sanitizeFilename source, GitHub Contents API PUT pattern)
- Delete route: `apps/web-platform/app/api/kb/file/[...path]/route.ts` (security validation pattern, workspace sync pattern)
- GitHub Contents API: `GET /repos/{owner}/{repo}/contents/{path}`, `PUT` (create/update), `DELETE`
- Issue: #2152
- Semver: `semver:patch` (enhancement to existing KB feature)
