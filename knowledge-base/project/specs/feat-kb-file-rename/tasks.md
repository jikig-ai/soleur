# Tasks: feat-kb-file-rename

## Phase 1: Setup

- [x] 1.1 Extract `sanitizeFilename` and constants (`WINDOWS_RESERVED`, `MAX_FILENAME_BYTES`) from `apps/web-platform/app/api/kb/upload/route.ts` into `apps/web-platform/server/kb-validation.ts`
- [x] 1.2 Update `apps/web-platform/app/api/kb/upload/route.ts` to import `sanitizeFilename` from the shared module
- [x] 1.3 Verify existing upload tests still pass after extraction

## Phase 2: Core Implementation -- API

- [x] 2.1 Write failing tests for PATCH `/api/kb/file/[...path]` in `apps/web-platform/test/kb-rename.test.ts`
  - [x] 2.1.1 Auth tests (unauthenticated, workspace not ready, no repo connected)
  - [x] 2.1.2 Validation tests (null bytes, `.md` rejection, path traversal, symlinks, empty newName, invalid newName, directory path, extension change, same name)
  - [x] 2.1.3 Conflict tests (newName already exists at destination)
  - [x] 2.1.4 Happy path test (atomic Git Trees API flow: GET blob SHA, POST tree, POST commit, PATCH ref, sync)
  - [x] 2.1.5 Error recovery tests (GitHub API errors at each step, sync failures)
  - [x] 2.1.6 Edge case tests (Unicode filenames, MAX_FILENAME_BYTES boundary)
- [x] 2.2 Implement PATCH handler in `apps/web-platform/app/api/kb/file/[...path]/route.ts`
  - [x] 2.2.1 CSRF + auth + workspace validation (same pattern as DELETE)
  - [x] 2.2.2 Path extraction and validation (null bytes, `.md`, path traversal, symlinks)
  - [x] 2.2.3 Parse and validate newName from JSON body (sanitizeFilename, extension preservation, same-name check)
  - [x] 2.2.4 GET file blob SHA from Contents API at old path
  - [x] 2.2.5 Check if destination path already exists via Contents API GET (409 if so)
  - [x] 2.2.6 GET current branch ref and commit tree SHA
  - [x] 2.2.7 POST `/git/trees` with base_tree, old path `sha: null`, new path with blob SHA
  - [x] 2.2.8 POST `/git/commits` with new tree SHA and parent commit
  - [x] 2.2.9 PATCH `/git/refs/heads/{branch}` to update branch pointer
  - [x] 2.2.10 Workspace sync (git pull --ff-only)
  - [x] 2.2.11 Error handling, logging, and Sentry capture
- [x] 2.3 Run tests -- all should pass (GREEN)

## Phase 3: Core Implementation -- UI

- [x] 3.1 Write failing component tests in `apps/web-platform/test/file-tree-rename.test.tsx`
  - [x] 3.1.1 Pencil icon visibility (attachment files only, not .md)
  - [x] 3.1.2 Edit mode entry (click pencil, input appears with basename without extension)
  - [x] 3.1.3 Extension displayed as static suffix after input
  - [x] 3.1.4 Confirm rename (Enter key triggers PATCH call with extension appended)
  - [x] 3.1.5 Confirm rename on blur
  - [x] 3.1.6 Cancel rename (Escape key, no API call)
  - [x] 3.1.7 Error display (inline error on API failure)
  - [x] 3.1.8 Loading state ("Renaming..." shown during API call)
- [x] 3.2 Add RenameState type and rename UI to `apps/web-platform/components/kb/file-tree.tsx`
  - [x] 3.2.1 Add PencilIcon SVG component
  - [x] 3.2.2 Add RenameState type
  - [x] 3.2.3 Add pencil button (hover, attachment files only, left of delete icon)
  - [x] 3.2.4 Add inline input for edit mode (pre-filled with basename, static extension suffix)
  - [x] 3.2.5 Add auto-focus and select-all on input mount
  - [x] 3.2.6 Add keyboard handlers (Enter to confirm, Escape to cancel, blur to confirm)
  - [x] 3.2.7 Add rename fetch call (PATCH) with extension auto-append, tree refresh on success
  - [x] 3.2.8 Add error display (inline, dismissable, same pattern as delete)
  - [x] 3.2.9 Add "Renaming..." loading state with opacity reduction
- [x] 3.3 Run component tests -- all should pass (GREEN)

## Phase 4: Testing and Polish

- [x] 4.1 Run full test suite to verify no regressions
- [x] 4.2 Run markdownlint on changed `.md` files
- [x] 4.3 Verify TypeScript compilation passes
