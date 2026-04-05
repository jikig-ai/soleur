# Tasks: fix workspace permission denied during re-setup

Issue: #1534

## Phase 1: Setup

- [ ] 1.1 Read and understand `apps/web-platform/server/workspace.ts` (focus on `provisionWorkspaceWithRepo` lines 117-238 and `deleteWorkspace` lines 246-256)
- [ ] 1.2 Read existing tests in `apps/web-platform/test/workspace-error-handling.test.ts`
- [ ] 1.3 Run existing tests to confirm they pass: `cd apps/web-platform && npx vitest run test/workspace-error-handling.test.ts test/workspace.test.ts`

## Phase 2: Write Failing Tests (TDD Gate)

- [ ] 2.1 Add test: `removeWorkspaceDir handles files not owned by current user`
  - Create a workspace directory with a file that has restrictive permissions (mode 000)
  - Call `provisionWorkspaceWithRepo` or the extracted `removeWorkspaceDir`
  - Assert the workspace is cleaned up and re-provisioned successfully
- [ ] 2.2 Add test: `removeWorkspaceDir is a no-op when workspace does not exist`
  - Call with a non-existent path
  - Assert no error is thrown
- [ ] 2.3 Add test: `deleteWorkspace handles permission-denied files`
  - Create a workspace with restrictive-permission files
  - Call `deleteWorkspace`
  - Assert the directory is removed
- [ ] 2.4 Run tests and confirm they FAIL (red phase): `cd apps/web-platform && npx vitest run test/workspace-error-handling.test.ts`

## Phase 3: Implementation

- [ ] 3.1 Extract `removeWorkspaceDir(workspacePath: string): void` helper in `apps/web-platform/server/workspace.ts`
  - Phase 1: Direct `rm -rf` (existing behavior)
  - Phase 2: `chmod -R u+rwX` then retry `rm -rf`
  - Phase 3: `find -mindepth 1 -delete` then `rmdir`
  - Throw descriptive error if all phases fail
- [ ] 3.2 Update `provisionWorkspaceWithRepo` (line 152-154) to call `removeWorkspaceDir`
- [ ] 3.3 Update `deleteWorkspace` (line 252-254) to call `removeWorkspaceDir`

## Phase 4: Verify (Green Phase)

- [ ] 4.1 Run all workspace tests: `cd apps/web-platform && npx vitest run test/workspace-error-handling.test.ts test/workspace.test.ts`
- [ ] 4.2 Confirm all tests pass (green phase)
- [ ] 4.3 Run full test suite to check for regressions: `cd apps/web-platform && npx vitest run`

## Phase 5: Ship

- [ ] 5.1 Run `soleur:compound`
- [ ] 5.2 Run `soleur:ship`
