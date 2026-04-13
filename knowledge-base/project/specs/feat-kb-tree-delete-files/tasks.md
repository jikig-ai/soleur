# Tasks: feat-kb-tree-delete-files

## Phase 1: Setup

- [x] 1.1 Create worktree at `.worktrees/feat-kb-tree-delete-files/`

## Phase 2: Core Implementation

### 2.1 Add `githubApiDelete` to `server/github-api.ts`

- [ ] 2.1.1 Add `githubApiDelete` function after `githubApiPost` -- authenticated DELETE with `generateInstallationToken`, same error handling via `handleErrorResponse`
- [ ] 2.1.2 Export the function

### 2.2 Create DELETE API route (`api/kb/file/[...path]/route.ts`)

- [ ] 2.2.1 CSRF validation (`validateOrigin` + `rejectCsrf`)
- [ ] 2.2.2 Auth check (Supabase `getUser()`)
- [ ] 2.2.3 Fetch workspace data (service client: `workspace_path`, `workspace_status`, `repo_url`, `github_installation_id`)
- [ ] 2.2.4 Extract path from URL segments, validate workspace status
- [ ] 2.2.5 Null byte check on path
- [ ] 2.2.6 Path traversal check via `isPathInWorkspace(fullPath, kbRoot)`
- [ ] 2.2.7 Symlink check via `fs.promises.lstat()` + `isSymbolicLink()`
- [ ] 2.2.8 Extension check -- reject `.md` files (only attachments are deletable)
- [ ] 2.2.9 Parse owner/repo from `repo_url`
- [ ] 2.2.10 GET file SHA from GitHub Contents API (`githubApiGet`)
- [ ] 2.2.11 DELETE file via GitHub Contents API (`githubApiDelete`) with `{ message, sha }`
- [ ] 2.2.12 Workspace sync via credential helper + `git pull --ff-only` (copy pattern from upload route lines 238-270)
- [ ] 2.2.13 Return success/error responses with appropriate status codes

### 2.3 Add delete UI to `file-tree.tsx`

- [ ] 2.3.1 Add `DeleteState` type (`idle | confirming | deleting | error`)
- [ ] 2.3.2 Add `deleteState` state to file node section
- [ ] 2.3.3 Add trash icon button (hover-revealed, same pattern as upload button on directories)
- [ ] 2.3.4 Only show delete button for non-`.md` files (`node.extension !== ".md"`)
- [ ] 2.3.5 Add confirmation dialog (inline, same style as duplicate dialog)
- [ ] 2.3.6 Add `deleteFile` callback: `fetch(`/api/kb/file/${node.path}`, { method: "DELETE" })`
- [ ] 2.3.7 Call `refreshTree()` after successful deletion
- [ ] 2.3.8 Show error state inline with dismiss button (same pattern as upload error)
- [ ] 2.3.9 Add `TrashIcon` SVG component

## Phase 3: Testing

- [ ] 3.1 Write API route tests (`test/kb-delete.test.ts`)
  - [ ] 3.1.1 Happy path: valid file path returns 200 and calls GitHub API
  - [ ] 3.1.2 Path traversal: `../` in path returns 400
  - [ ] 3.1.3 Null bytes: `\0` in path returns 400
  - [ ] 3.1.4 Symlink target: returns 403
  - [ ] 3.1.5 Non-existent file: returns 404
  - [ ] 3.1.6 Unauthenticated: returns 401
  - [ ] 3.1.7 Workspace not ready: returns 503
  - [ ] 3.1.8 `.md` file rejection: returns 400
  - [ ] 3.1.9 Workspace sync failure: returns 500 with `SYNC_FAILED` code
- [ ] 3.2 Write component tests (`test/file-tree-delete.test.tsx`)
  - [ ] 3.2.1 Delete button appears on hover for attachment files
  - [ ] 3.2.2 Delete button does NOT appear for `.md` files
  - [ ] 3.2.3 Clicking delete shows confirmation dialog
  - [ ] 3.2.4 Confirming deletion calls API and refreshes tree
  - [ ] 3.2.5 Canceling returns to idle state
  - [ ] 3.2.6 API error shows error message with dismiss button
