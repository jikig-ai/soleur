# Tasks: feat-kb-file-rename

## Phase 1: Setup

- [ ] 1.1 Extract `sanitizeFilename` and constants (`WINDOWS_RESERVED`, `MAX_FILENAME_BYTES`) from `apps/web-platform/app/api/kb/upload/route.ts` into `apps/web-platform/server/kb-validation.ts`
- [ ] 1.2 Update `apps/web-platform/app/api/kb/upload/route.ts` to import `sanitizeFilename` from the shared module
- [ ] 1.3 Verify existing upload tests still pass after extraction

## Phase 2: Core Implementation -- API

- [ ] 2.1 Write failing tests for PATCH `/api/kb/file/[...path]` in `apps/web-platform/test/kb-rename.test.ts`
  - [ ] 2.1.1 Auth tests (unauthenticated, workspace not ready, no repo connected)
  - [ ] 2.1.2 Validation tests (null bytes, `.md` rejection, path traversal, symlinks, empty newName, invalid newName, directory path)
  - [ ] 2.1.3 Conflict tests (newName already exists at destination)
  - [ ] 2.1.4 Happy path test (GET content + PUT at new path + DELETE old path + sync)
  - [ ] 2.1.5 Error recovery tests (GitHub API errors, sync failures)
- [ ] 2.2 Implement PATCH handler in `apps/web-platform/app/api/kb/file/[...path]/route.ts`
  - [ ] 2.2.1 CSRF + auth + workspace validation (same pattern as DELETE)
  - [ ] 2.2.2 Path extraction and validation (null bytes, `.md`, path traversal, symlinks)
  - [ ] 2.2.3 Parse and validate newName from JSON body
  - [ ] 2.2.4 Check if destination path already exists (409 if so)
  - [ ] 2.2.5 GET file content from old path (SHA + base64)
  - [ ] 2.2.6 PUT file at new path
  - [ ] 2.2.7 DELETE old file
  - [ ] 2.2.8 Workspace sync (git pull --ff-only)
  - [ ] 2.2.9 Error handling and logging
- [ ] 2.3 Run tests -- all should pass (GREEN)

## Phase 3: Core Implementation -- UI

- [ ] 3.1 Write failing component tests in `apps/web-platform/test/file-tree-rename.test.tsx`
  - [ ] 3.1.1 Pencil icon visibility (attachment files only, not .md)
  - [ ] 3.1.2 Edit mode entry (click pencil, input appears)
  - [ ] 3.1.3 Confirm rename (Enter key triggers PATCH call)
  - [ ] 3.1.4 Cancel rename (Escape key, no API call)
  - [ ] 3.1.5 Error display (inline error on API failure)
- [ ] 3.2 Add RenameState type and rename UI to `apps/web-platform/components/kb/file-tree.tsx`
  - [ ] 3.2.1 Add PencilIcon SVG component
  - [ ] 3.2.2 Add RenameState type
  - [ ] 3.2.3 Add pencil button (hover, attachment files only, next to delete icon)
  - [ ] 3.2.4 Add inline input for edit mode (pre-filled with current name, auto-focus, select text)
  - [ ] 3.2.5 Add keyboard handlers (Enter to confirm, Escape to cancel)
  - [ ] 3.2.6 Add rename fetch call (PATCH) and tree refresh on success
  - [ ] 3.2.7 Add error display (inline, dismissable)
  - [ ] 3.2.8 Add "Renaming..." loading state
- [ ] 3.3 Run component tests -- all should pass (GREEN)

## Phase 4: Testing and Polish

- [ ] 4.1 Run full test suite to verify no regressions
- [ ] 4.2 Run markdownlint on changed `.md` files
- [ ] 4.3 Verify TypeScript compilation passes
