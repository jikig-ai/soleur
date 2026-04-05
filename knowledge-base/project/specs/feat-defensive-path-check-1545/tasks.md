# Tasks: Defensive path prefix check for removeWorkspaceDir

## Phase 1: Tests (TDD RED)

- [ ] 1.1 Add test cases to `apps/web-platform/test/workspace-cleanup.test.ts`
  - [ ] 1.1.1 Test: rejects path outside workspace root (`/etc/passwd`)
  - [ ] 1.1.2 Test: rejects the workspace root itself
  - [ ] 1.1.3 Test: rejects prefix collision paths (`/tmp/soleur-test-workspaces-cleanup-evil`)
  - [ ] 1.1.4 Test: rejects `../` traversal paths that resolve outside root
  - [ ] 1.1.5 Test: accepts valid workspace subdirectory paths (existing behavior)
- [ ] 1.2 Run tests, confirm new tests fail (RED phase)

## Phase 2: Implementation (TDD GREEN)

- [ ] 2.1 Add `resolve` import from `"path"` in `apps/web-platform/server/workspace.ts`
- [ ] 2.2 Add defensive prefix check at top of `removeWorkspaceDir` (before `existsSync`)
  - Resolve both `workspacePath` and `getWorkspacesRoot()` via `path.resolve()`
  - Reject if `resolved === root` (workspace root itself)
  - Reject if `!resolved.startsWith(root + "/")` (outside workspace root)
  - Throw: `"Refusing to remove path outside workspace root"`
- [ ] 2.3 Run tests, confirm all pass (GREEN phase)

## Phase 3: Verification

- [ ] 3.1 Run full test suite: `./node_modules/.bin/vitest run` from `apps/web-platform/`
- [ ] 3.2 Run TypeScript type check: `npx tsc --noEmit` from `apps/web-platform/`
- [ ] 3.3 Run markdownlint on changed `.md` files
