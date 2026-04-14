# Tasks: feat-kb-file-rename

## Phase 1: Setup

- [ ] 1.1 Extract `sanitizeFilename` and constants (`WINDOWS_RESERVED`, `MAX_FILENAME_BYTES`) from `apps/web-platform/app/api/kb/upload/route.ts` into `apps/web-platform/server/kb-validation.ts`
- [ ] 1.2 Update `apps/web-platform/app/api/kb/upload/route.ts` to import `sanitizeFilename` from the shared module
- [ ] 1.3 Verify existing upload tests still pass after extraction

## Phase 2: Core Implementation -- API

- [ ] 2.1 Write failing tests for PATCH `/api/kb/file/[...path]` in `apps/web-platform/test/kb-rename.test.ts`
  - [ ] 2.1.1 Auth tests (unauthenticated, workspace not ready, no repo connected)
  - [ ] 2.1.2 Validation tests (null bytes, `.md` rejection, path traversal, symlinks, empty newName, invalid newName, directory path, extension change, same name)
  - [ ] 2.1.3 Conflict tests (newName already exists at destination)
  - [ ] 2.1.4 Happy path test (atomic Git Trees API flow: GET blob SHA, POST tree, POST commit, PATCH ref, sync)
  - [ ] 2.1.5 Error recovery tests (GitHub API errors at each step, sync failures)
  - [ ] 2.1.6 Edge case tests (Unicode filenames, MAX_FILENAME_BYTES boundary)
- [ ] 2.2 Implement PATCH handler in `apps/web-platform/app/api/kb/file/[...path]/route.ts`
  - [ ] 2.2.1 CSRF + auth + workspace validation (same pattern as DELETE)
  - [ ] 2.2.2 Path extraction and validation (null bytes, `.md`, path traversal, symlinks)
  - [ ] 2.2.3 Parse and validate newName from JSON body (sanitizeFilename, extension preservation, same-name check)
  - [ ] 2.2.4 GET file blob SHA from Contents API at old path
  - [ ] 2.2.5 Check if destination path already exists via Contents API GET (409 if so)
  - [ ] 2.2.6 GET current branch ref and commit tree SHA
  - [ ] 2.2.7 POST `/git/trees` with base_tree, old path `sha: null`, new path with blob SHA
  - [ ] 2.2.8 POST `/git/commits` with new tree SHA and parent commit
  - [ ] 2.2.9 PATCH `/git/refs/heads/{branch}` to update branch pointer
  - [ ] 2.2.10 Workspace sync (git pull --ff-only)
  - [ ] 2.2.11 Error handling, logging, and Sentry capture
- [ ] 2.3 Run tests -- all should pass (GREEN)

## Phase 3: Core Implementation -- UI

- [ ] 3.1 Write failing component tests in `apps/web-platform/test/file-tree-rename.test.tsx`
  - [ ] 3.1.1 Pencil icon visibility (attachment files only, not .md)
  - [ ] 3.1.2 Edit mode entry (click pencil, input appears with basename without extension)
  - [ ] 3.1.3 Extension displayed as static suffix after input
  - [ ] 3.1.4 Confirm rename (Enter key triggers PATCH call with extension appended)
  - [ ] 3.1.5 Confirm rename on blur
  - [ ] 3.1.6 Cancel rename (Escape key, no API call)
  - [ ] 3.1.7 Error display (inline error on API failure)
  - [ ] 3.1.8 Loading state ("Renaming..." shown during API call)
- [ ] 3.2 Add RenameState type and rename UI to `apps/web-platform/components/kb/file-tree.tsx`
  - [ ] 3.2.1 Add PencilIcon SVG component
  - [ ] 3.2.2 Add RenameState type
  - [ ] 3.2.3 Add pencil button (hover, attachment files only, left of delete icon)
  - [ ] 3.2.4 Add inline input for edit mode (pre-filled with basename, static extension suffix)
  - [ ] 3.2.5 Add auto-focus and select-all on input mount
  - [ ] 3.2.6 Add keyboard handlers (Enter to confirm, Escape to cancel, blur to confirm)
  - [ ] 3.2.7 Add rename fetch call (PATCH) with extension auto-append, tree refresh on success
  - [ ] 3.2.8 Add error display (inline, dismissable, same pattern as delete)
  - [ ] 3.2.9 Add "Renaming..." loading state with opacity reduction
- [ ] 3.3 Run component tests -- all should pass (GREEN)

## Phase 4: Testing and Polish

- [ ] 4.1 Run full test suite to verify no regressions
- [ ] 4.2 Run markdownlint on changed `.md` files
- [ ] 4.3 Verify TypeScript compilation passes
