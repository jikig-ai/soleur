---
title: "feat: add file rename to KB Tree"
type: feat
date: 2026-04-14
---

# feat: Add File Rename to KB Tree

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** 5 (Technical Approach, API Route, UI, Error Handling, Test Scenarios)
**Research sources:** GitHub REST API docs (Context7), existing codebase patterns (#2143), institutional learnings

### Key Improvements

1. Atomic rename via Git Trees API instead of two-step Contents API -- single commit, no orphaned files on failure
2. Extension preservation enforcement -- prevent users from changing file extensions during rename (security: blocks `.png` to `.md` bypass)
3. Optimistic UI update pattern -- show renamed file immediately, revert on error for responsive UX

### New Considerations Discovered

- GitHub Contents API docs explicitly warn: PUT and DELETE "must use these endpoints serially" and "concurrent requests will conflict" -- validates the need for careful ordering if using Contents API
- Git Trees API enables single-commit atomic rename (create tree with old path `sha: null` + new path with blob SHA, create commit, update ref) -- eliminates the partial-failure window entirely
- Extension change during rename could bypass the `.md` restriction -- must validate that the new extension matches the old extension

## Overview

Add the ability to rename files and folders in the knowledge base tree UI. The KB Tree already supports file deletion (merged in #2143) and file upload. This adds an inline rename interaction that lets users rename attachment files directly from the sidebar tree.

## Problem Statement / Motivation

Users who upload files to the KB cannot rename them without deleting and re-uploading. This forces users to either use git directly or live with the original names, which degrades the KB as an organizational tool.

## Proposed Solution

Add a PATCH endpoint at `/api/kb/file/[...path]` that performs an atomic rename via the GitHub Git Trees API (single commit). Add an inline rename UI in the file tree triggered by a pencil/edit icon button (similar to the existing delete trash icon).

### Approach: Git Trees API (Atomic Single-Commit)

The GitHub Contents API has no native rename endpoint and requires two commits (PUT + DELETE) which creates a partial-failure window. Instead, use the Git Trees API for an atomic single-commit rename:

1. **GET** the file blob SHA from the old path via Contents API
2. **POST** `/git/trees` with `base_tree` set to current tree, two entries: old path with `sha: null` (delete) and new path with the existing blob SHA (create)
3. **POST** `/git/commits` with the new tree SHA and current commit as parent
4. **PATCH** `/git/refs/heads/{branch}` to update the branch ref to the new commit

This produces a single atomic commit. If any step fails, no changes are persisted.

### Research Insights

**Why Git Trees API over Contents API:**

- Contents API PUT + DELETE creates two separate commits, leaving a window where the file exists at both paths (after PUT but before DELETE)
- GitHub docs explicitly state PUT and DELETE "must use these endpoints serially" and "concurrent requests will conflict"
- If DELETE fails after PUT succeeds, the file is duplicated with no automatic rollback
- Git Trees API produces one atomic commit -- either the rename happens completely or not at all
- The existing `githubApiPost` helper already supports arbitrary methods and can be used for the Git Trees API endpoints

**Trade-off acknowledged:** The Git Trees API flow requires 4 serial API calls (GET content, POST tree, POST commit, PATCH ref) vs. Contents API's 3 (GET, PUT, DELETE). But atomicity eliminates the need for rollback logic, making the implementation simpler overall despite the extra call.

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
- **Extension preservation check:** newName must have the same extension as the original file (prevents `.png` to `.md` bypass of the markdown restriction)
- Path traversal check on both old and new resolved paths (isPathInWorkspace)
- Symlink check on old path (skip on ENOENT like delete does)
- Filename sanitization on newName (reuse sanitizeFilename from upload route -- extract to shared utility)
- **Same-name check:** if newName equals current name, return 400 "New name is the same as current name"

### Research Insights -- Validation

**Extension preservation is a security boundary.** Without it, a user could rename `exploit.png` to `exploit.md`, bypassing the `.md` restriction that both the delete and upload routes enforce. The extension check should compare `path.extname(oldName).toLowerCase()` with `path.extname(newName).toLowerCase()`.

**Rename logic (Git Trees API -- atomic):**

1. Parse `newName` from request body (JSON, not FormData)
2. Validate newName (sanitizeFilename, extension preservation, not `.md`, not same name)
3. Compute old and new GitHub paths (same directory, different filename)
4. **GET** file metadata from Contents API at old path -- extract `sha` (blob SHA)
5. **Check** if new path already exists via Contents API GET (return 409 if so)
6. **GET** the current branch ref to get the latest commit SHA
7. **GET** the commit to get the tree SHA
8. **POST** `/git/trees` with `base_tree` and two entries:
   - `{ path: oldFilePath, mode: "100644", type: "blob", sha: null }` (delete old)
   - `{ path: newFilePath, mode: "100644", type: "blob", sha: blobSha }` (create new)
9. **POST** `/git/commits` with new tree SHA, parent = current commit SHA, message = "Rename {oldName} to {newName} via Soleur"
10. **PATCH** `/git/refs/heads/{branch}` with new commit SHA
11. Workspace sync (git pull --ff-only, same pattern as delete)
12. Return `{ oldPath, newPath, commitSha }`

**Error handling:**

- 404: Old file not found
- 400: Invalid newName, empty name, `.md` file, path traversal, null bytes, extension change, same name
- 409: New path already exists (check before tree creation)
- 502: GitHub API errors (any step in the Git Trees flow)
- 500: Unexpected errors, sync failures

### Research Insights -- Error Handling

**Atomicity simplifies error handling.** With the Git Trees API, if any step fails before the ref update (step 10), no changes are persisted. The only partial-failure scenario is if the ref update succeeds but workspace sync fails -- which is the same scenario the existing delete route already handles with `SYNC_FAILED`.

**Folder rename:**

For the initial implementation, restrict rename to files only. Folder rename requires enumerating all files in the tree and creating entries for each -- add as a follow-up.

### Shared Utility: `sanitizeFilename`

Extract `sanitizeFilename` from `apps/web-platform/app/api/kb/upload/route.ts` into a shared module `apps/web-platform/server/kb-validation.ts`. Both upload and rename need the same validation. The constants `WINDOWS_RESERVED` and `MAX_FILENAME_BYTES` move with it.

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
4. On confirm: call `PATCH /api/kb/file/{path}` with `{ newName: "edited-name.ext" }` (extension appended automatically)
5. On success: refresh tree, return to idle
6. On error: show inline error message (same pattern as delete error)

### Research Insights -- UI Patterns

**Extension handling in the input field:**

- The input should show only the basename without extension (e.g., "screenshot" not "screenshot.png")
- The extension is displayed as a static suffix after the input: `[input: screenshot][.png]`
- On submit, the extension is re-appended automatically: `newName = inputValue + originalExtension`
- This prevents accidental extension changes and makes the interaction cleaner

**Optimistic UI update:**

- When the user confirms a rename, immediately update the tree node's `name` property in local state
- If the PATCH fails, revert to the old name and show the error
- This provides instant visual feedback instead of waiting for the API round-trip + tree refresh

**Keyboard accessibility:**

- Enter: confirm rename
- Escape: cancel rename
- The input should auto-focus and select all text on enter (the basename portion)
- Tab should also confirm (consistent with other inline edit patterns)

**Icon placement:** The pencil icon sits to the left of the trash icon in the hover action area. Order: `[pencil] [trash]`. Both share the same opacity/hover transition.

**Icon:** Use a pencil/edit SVG icon (PencilIcon component) matching the existing icon style (14x14, stroke-based, `currentColor`).

### Files to Create

- `apps/web-platform/server/kb-validation.ts` -- shared sanitizeFilename + constants

### Files to Modify

- `apps/web-platform/app/api/kb/file/[...path]/route.ts` -- add PATCH handler
- `apps/web-platform/app/api/kb/upload/route.ts` -- import sanitizeFilename from shared module (remove local copy)
- `apps/web-platform/components/kb/file-tree.tsx` -- add rename UI, PencilIcon, RenameState
- `apps/web-platform/server/github-api.ts` -- no changes needed (uses existing githubApiGet, githubApiPost)

### Files to Create (Tests)

- `apps/web-platform/test/kb-rename.test.ts` -- API route unit tests
- `apps/web-platform/test/file-tree-rename.test.tsx` -- component tests

## Non-Goals

- Folder rename (recursive multi-file move) -- deferred to follow-up issue
- Renaming `.md` files (consistency with delete restriction)
- Drag-and-drop to move files between folders
- Batch rename (multiple files at once)
- Changing file extensions during rename (security boundary)

## Acceptance Criteria

- [x] PATCH `/api/kb/file/[...path]` renames a file on GitHub atomically (single commit via Git Trees API) and syncs workspace
- [x] Security validations match DELETE route parity (CSRF, auth, path traversal, null bytes, symlinks, .md rejection)
- [x] Extension preservation enforced -- cannot change file extension during rename
- [x] Rename button (pencil icon) appears on hover for attachment files only
- [x] Clicking pencil enters inline edit mode with input pre-filled with current basename (without extension)
- [x] Extension displayed as static suffix next to input
- [x] Enter confirms rename, Escape cancels, blur confirms
- [x] Duplicate filename at destination returns 409
- [x] Error states display inline (same pattern as delete errors)
- [x] Tree refreshes after successful rename
- [x] `sanitizeFilename` extracted to shared module, upload route updated to import from it

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
- Given a newName that changes the extension (e.g., `.png` to `.jpg`), when PATCH is called, then return 400 "Cannot change file extension"
- Given a newName that is the same as the current name, when PATCH is called, then return 400 "New name is the same as current name"
- Given a newName that is a `.md` extension, when PATCH is called, then return 400
- Given a valid file and valid newName, when PATCH is called, then a single atomic commit is created via Git Trees API, workspace syncs, and return 200 with `{ oldPath, newPath, commitSha }`
- Given a workspace sync failure after successful rename, when PATCH is called, then return 500 with SYNC_FAILED code
- Given a directory path (GitHub returns array), when PATCH is called, then return 400 "Cannot rename a directory"
- Given a GitHub API error during tree creation, when PATCH is called, then return 502

### Component Tests (file-tree-rename.test.tsx)

- Given a file tree with an attachment file, when hovering, then pencil icon is visible
- Given a `.md` file, when hovering, then no pencil icon is shown
- Given idle state, when pencil icon is clicked, then input appears with current basename (without extension)
- Given edit mode, then extension is displayed as static text after the input
- Given edit mode, when Enter is pressed with a new name, then PATCH is called with newName including extension and tree refreshes
- Given edit mode, when Escape is pressed, then edit mode is cancelled without API call
- Given edit mode, when blur occurs, then rename is confirmed (same as Enter)
- Given a rename API error, when rename fails, then error message displays inline
- Given a rename in progress, then "Renaming..." loading state is shown

### Research Insights -- Test Edge Cases

- **Race condition test:** Given two rename requests for the same file, verify the second receives a conflict error (the ref update uses non-force mode which fails if the ref changed)
- **Large filename test:** Given a newName at MAX_FILENAME_BYTES boundary, verify it is accepted; at MAX_FILENAME_BYTES + 1, verify it is rejected
- **Unicode filename test:** Given a newName with Unicode characters (e.g., emoji, CJK), verify sanitizeFilename handles byte-length correctly (UTF-8 multi-byte)

## References

- File deletion PR: #2143 (pattern reference for API route structure, security checks, and UI)
- Upload route: `apps/web-platform/app/api/kb/upload/route.ts` (sanitizeFilename source, GitHub Contents API PUT pattern)
- Delete route: `apps/web-platform/app/api/kb/file/[...path]/route.ts` (security validation pattern, workspace sync pattern)
- GitHub Contents API docs: PUT and DELETE "must use these endpoints serially" -- validates serial approach
- GitHub Git Trees API: `POST /repos/{owner}/{repo}/git/trees` -- enables atomic rename in single commit
- GitHub Git Commits API: `POST /repos/{owner}/{repo}/git/commits` -- creates commit from tree
- GitHub Git Refs API: `PATCH /repos/{owner}/{repo}/git/refs/{ref}` -- updates branch pointer
- Issue: #2152
- Semver: `semver:patch` (enhancement to existing KB feature)
