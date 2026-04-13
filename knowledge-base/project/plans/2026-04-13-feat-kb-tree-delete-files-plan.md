---
title: "feat: Add file deletion to KB Tree"
type: feat
date: 2026-04-13
---

# feat: Add file deletion to KB Tree

## Overview

Users need to delete uploaded files/attachments from the KB Tree that are no longer relevant or were uploaded by mistake. Currently the KB Tree supports uploading files but provides no way to remove them -- the only recourse is manual git operations on the repository.

## Problem Statement / Motivation

When users upload files to the knowledge base (images, PDFs, CSVs, etc.), mistakes happen: wrong files get uploaded, outdated attachments linger, or test uploads clutter the tree. Without a delete action, users must leave the Soleur dashboard and manually interact with their GitHub repository to remove files. This breaks the self-contained KB management experience.

## Proposed Solution

Add a DELETE operation to the KB Tree following the same architectural pattern as the existing upload flow:

1. **New API route**: `DELETE /api/kb/file/[...path]` -- validates the path, deletes via GitHub Contents API, syncs the local workspace
2. **UI delete action**: Add a delete button (trash icon) to file items in `file-tree.tsx` with a confirmation dialog
3. **Tree refresh**: Call `refreshTree()` after successful deletion to update the sidebar

## Technical Considerations

### Architecture

The delete flow mirrors the upload flow (`POST /api/kb/upload`) with these key differences:

- **`githubApiPost` blocks DELETE**: The existing `githubApiPost` function in `server/github-api.ts` rejects DELETE methods as a safety guard for cloud agents (line 79-80). The delete route must call the GitHub API directly using `fetch` with a scoped installation token, or a new `githubApiDelete` function must be added. **Decision**: Add a new `githubApiDelete` function to `server/github-api.ts` -- this keeps the safety guard for cloud agents intact while allowing first-party API routes to delete files. The function is server-only and not exposed to agent sessions.
- **SHA required**: The GitHub Contents API DELETE requires the file's current SHA. The route must first GET the file metadata to obtain the SHA, then DELETE with it.
- **Catch-all route**: Uses `[...path]` segments (like `api/kb/content/[...path]`) instead of FormData (like upload).

### Security

All security patterns from the upload and content routes apply:

| Check | Implementation | Source Pattern |
|-------|---------------|----------------|
| CSRF validation | `validateOrigin()` + `rejectCsrf()` | `upload/route.ts:67-68` |
| Authentication | Supabase `getUser()` | `upload/route.ts:71-76` |
| Path traversal | `isPathInWorkspace(fullPath, kbRoot)` | `upload/route.ts:162` |
| Null byte injection | Reject `\0` in path | `upload/route.ts:152-156` |
| Symlink escape | `fs.lstatSync()` + `isSymbolicLink()` check | `content/[...path]/route.ts:101-109`, learning `2026-04-07-symlink-escape-recursive-directory-traversal.md` |
| Workspace status | Verify `workspace_status === "ready"` | `upload/route.ts:87-89` |
| Repository connected | Verify `repo_url` and `github_installation_id` | `upload/route.ts:91-93` |

### Workspace Sync

After deleting via the GitHub Contents API, the local workspace must sync using the credential helper pattern (learning: `kb-upload-missing-credential-helper-20260413.md`):

```text
1. generateInstallationToken(installationId)
2. Write temporary credential helper script
3. git -c credential.helper=!<helper-path> pull --ff-only
4. Clean up credential helper in finally block
```

### Scope Restriction

Only files within the `knowledge-base/` directory can be deleted. The `isPathInWorkspace()` check uses `kbRoot` (not `workspace_path`) as the boundary, matching the upload route's behavior.

### Files That Will Not Be Deletable

Markdown files (`.md`) are the core knowledge base content and are created/managed by agents. This plan restricts deletion to attachment files only (the same `ALLOWED_EXTENSIONS` set used by upload: `png, jpg, jpeg, gif, webp, pdf, csv, txt, docx`). Markdown file management is a separate concern with different UX implications (content loss vs attachment removal).

## Acceptance Criteria

- [ ] `DELETE /api/kb/file/[...path]` route exists and validates auth, CSRF, path traversal, symlinks, and workspace status
- [ ] Route rejects paths outside `knowledge-base/` via `isPathInWorkspace()`
- [ ] Route rejects null bytes in path segments
- [ ] Route rejects symlink targets via `lstat().isSymbolicLink()` check
- [ ] Route deletes the file via GitHub Contents API (GET sha, then DELETE)
- [ ] Route syncs workspace after deletion using credential helper pattern
- [ ] Route returns 200 on success, 401/403/404/400/502 for error cases
- [ ] File items in `file-tree.tsx` show a delete button (trash icon) on hover
- [ ] Delete button is only shown for attachment files (non-`.md`)
- [ ] Clicking delete shows a confirmation dialog before proceeding
- [ ] Successful deletion calls `refreshTree()` to update the tree
- [ ] Delete state (deleting/error) is shown inline like upload state
- [ ] `githubApiDelete` function exists in `server/github-api.ts` for first-party DELETE calls
- [ ] Unit tests cover: happy path, path traversal rejection, symlink rejection, 404 handling, workspace sync failure

## Test Scenarios

- Given a valid file path within knowledge-base, when DELETE is called with valid auth, then the file is removed from GitHub and workspace syncs
- Given a path containing `../` traversal, when DELETE is called, then 400 is returned
- Given a path targeting a symlink, when DELETE is called, then 403 is returned
- Given a non-existent file path, when DELETE is called, then 404 is returned
- Given a valid delete where workspace sync fails, when DELETE is called, then the file is deleted from GitHub but 500 is returned with `SYNC_FAILED` code
- Given an unauthenticated request, when DELETE is called, then 401 is returned
- Given a path with null bytes, when DELETE is called, then 400 is returned
- Given a file item in the tree, when hovering over it, then a delete button (trash icon) appears
- Given the delete button is clicked, when confirmation dialog appears, then "Delete" and "Cancel" buttons are shown
- Given the user confirms deletion, when the API returns success, then the tree refreshes and the file disappears

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** The key architectural decision is adding `githubApiDelete` to `server/github-api.ts` rather than bypassing the safety guard. This preserves the DELETE-blocking invariant for cloud agents while enabling first-party routes. The credential helper pattern is well-documented and should be copied from the upload route verbatim. No new dependencies required.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

The change adds a hover-revealed trash icon to existing file items and a simple confirmation dialog. This follows the established pattern of the upload button (hover-revealed on directory items). No new pages or flows are created.

## Implementation Guide

### Files to Create

- `apps/web-platform/app/api/kb/file/[...path]/route.ts` -- DELETE handler
- `apps/web-platform/test/kb-delete.test.ts` -- API route unit tests
- `apps/web-platform/test/file-tree-delete.test.tsx` -- Component tests for delete UI

### Files to Modify

- `apps/web-platform/server/github-api.ts` -- Add `githubApiDelete` function
- `apps/web-platform/components/kb/file-tree.tsx` -- Add delete button, confirmation dialog, delete state

### `githubApiDelete` in `server/github-api.ts`

```typescript
/**
 * Make an authenticated DELETE request to the GitHub API.
 * Restricted to first-party API routes — NOT exposed to cloud agent sessions.
 * The githubApiPost DELETE guard remains in place for agent safety.
 */
export async function githubApiDelete<T = unknown>(
  installationId: number,
  path: string,
  body: Record<string, unknown>,
): Promise<T | null> {
  const token = await generateInstallationToken(installationId);

  const response = await fetch(`${GITHUB_API}${path}`, {
    method: "DELETE",
    headers: {
      Authorization: `token ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    await handleErrorResponse(response, path);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json() as Promise<T>;
}
```

### DELETE Route Pattern (`api/kb/file/[...path]/route.ts`)

The route follows this sequence:

1. CSRF validation (`validateOrigin` + `rejectCsrf`)
2. Auth check (Supabase `getUser()`)
3. Fetch workspace data (service client)
4. Extract and validate path from URL segments
5. Null byte check on path
6. Path traversal check via `isPathInWorkspace(fullPath, kbRoot)`
7. Symlink check via `lstat().isSymbolicLink()`
8. Extension check -- only allow deleting attachment files (non-`.md`)
9. Parse owner/repo from `repo_url`
10. GET file SHA from GitHub Contents API (`githubApiGet`)
11. DELETE file via GitHub Contents API (`githubApiDelete`)
12. Workspace sync via credential helper + `git pull --ff-only`
13. Return success response

### UI Changes in `file-tree.tsx`

Add to the file node render (the `return` block starting at line 280):

1. A `deleteState` state variable (similar to `uploadState`)
2. A trash icon button revealed on hover (same pattern as upload button on directories)
3. A confirmation dialog below the file item when `deleteState.status === "confirming"`
4. A deleting indicator when `deleteState.status === "deleting"`
5. An error display when `deleteState.status === "error"`
6. Only show the delete button for non-`.md` files (check `node.extension !== ".md"`)

## References

- Upload route pattern: `apps/web-platform/app/api/kb/upload/route.ts`
- Content route with catch-all path: `apps/web-platform/app/api/kb/content/[...path]/route.ts`
- Sandbox validation: `apps/web-platform/server/sandbox.ts`
- GitHub API wrapper: `apps/web-platform/server/github-api.ts`
- Credential helper learning: `knowledge-base/project/learnings/integration-issues/kb-upload-missing-credential-helper-20260413.md`
- Symlink escape learning: `knowledge-base/project/learnings/2026-04-07-symlink-escape-recursive-directory-traversal.md`
- GitHub Contents API DELETE: `DELETE /repos/{owner}/{repo}/contents/{path}` requires `{ message, sha }` body
