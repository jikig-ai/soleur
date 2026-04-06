# Tasks: fix workspace cleanup root-owned files

## Phase 1: Setup and TDD Red Phase

### 1.1 Write failing tests for Phase 3 mv-aside behavior

- [ ] Add test: `removeWorkspaceDir` renames workspace to `*.orphaned-<timestamp>` when rm and find-delete fail but mv succeeds
- [ ] Add test: `removeWorkspaceDir` throws user-friendly error (no `sudo`) when rm, find-delete, AND mv all fail
- [ ] Add test: orphaned path is within workspace root (path validation)
- **File:** `apps/web-platform/test/workspace-cleanup.test.ts`

### 1.2 Write failing tests for orphan cleanup function

- [ ] Add test: `cleanupOrphanedWorkspaces` deletes deletable orphaned directories
- [ ] Add test: `cleanupOrphanedWorkspaces` skips undeletable orphaned directories without throwing
- [ ] Add test: `cleanupOrphanedWorkspaces` logs warning for orphans older than 7 days
- [ ] Add test: `cleanupOrphanedWorkspaces` ignores non-orphaned directories (UUID-named workspaces)
- **File:** `apps/web-platform/test/workspace-cleanup.test.ts`

### 1.3 Verify existing tests still pass

- [ ] Run `./node_modules/.bin/vitest run test/workspace-cleanup.test.ts` -- confirm existing tests pass, new tests fail
- **File:** `apps/web-platform/test/workspace-cleanup.test.ts`

## Phase 2: Core Implementation (Green Phase)

### 2.1 Add Phase 3 (mv-aside) to `removeWorkspaceDir`

- [ ] After Phase 2 find-delete, attempt `rmdir` to check if directory is empty
- [ ] If `rmdir` fails, rename workspace to `<path>.orphaned-<timestamp>`
- [ ] Log warning with both original and orphaned paths
- [ ] If `mv` also fails, throw user-friendly error: "please try again or contact support"
- [ ] Remove the `sudo rm -rf` error message from the function
- **File:** `apps/web-platform/server/workspace.ts`

### 2.2 Add `cleanupOrphanedWorkspaces` function

- [ ] Scan workspace root for entries matching `.orphaned-`
- [ ] Attempt `rm -rf` on each
- [ ] Log info on success, debug on skip (still undeletable)
- [ ] Log Sentry warning for orphans older than 7 days (parse timestamp from suffix)
- [ ] Export function for use in server startup
- **File:** `apps/web-platform/server/workspace.ts`

### 2.3 Wire orphan cleanup to server lifecycle

- [ ] Call `cleanupOrphanedWorkspaces` on server startup
- [ ] Set interval for periodic cleanup (every 6 hours)
- [ ] Clear interval on SIGTERM
- **File:** `apps/web-platform/server/index.ts` (or wherever the server entry point is)

### 2.4 Run tests -- all should pass

- [ ] Run `./node_modules/.bin/vitest run test/workspace-cleanup.test.ts`
- [ ] Verify all new and existing tests pass

## Phase 3: Refactor and Polish

### 3.1 Review error message sanitization

- [ ] Grep codebase for `sudo rm -rf` -- verify it no longer appears in any user-facing code path
- [ ] Verify server-side logs retain full diagnostic detail (paths, stderr)

### 3.2 Verify integration points

- [ ] Confirm `provisionWorkspaceWithRepo` (line 152) correctly uses the updated `removeWorkspaceDir`
- [ ] Confirm `deleteWorkspace` (line 251) correctly uses the updated `removeWorkspaceDir`
- [ ] Confirm `DELETE /api/repo/disconnect` best-effort handler still works with new behavior

### 3.3 Run full test suite

- [ ] Run workspace-cleanup tests
- [ ] Run disconnect-route tests
- [ ] Run account-delete tests
