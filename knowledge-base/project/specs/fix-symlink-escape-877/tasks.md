# Tasks: fix symlink escape defense-in-depth (#877)

## Phase 1: Core Implementation

- [ ] 1.1 Refactor `isPathInWorkspace` in `apps/web-platform/server/sandbox.ts`
  - [ ] 1.1.1 Add `import fs from "fs"` to sandbox.ts
  - [ ] 1.1.2 Implement `resolveRealPath(filePath: string): string | null` -- resolves symlinks via `fs.realpathSync`, falls back to ancestor walk for ENOENT, returns null for ELOOP/EACCES/ENOTDIR
  - [ ] 1.1.3 Implement `resolveParentRealPath(filePath: string): string | null` -- walks up directory tree to find deepest existing ancestor, resolves it, re-appends remaining segments; returns null on non-ENOENT errors at any ancestor level (prevents skipping malicious symlinks)
  - [ ] 1.1.4 Implement `resolveWorkspacePath(workspacePath: string): string` -- resolves workspace root with `realpathSync`, falls back to `path.resolve` for test environments where workspace does not exist on disk
  - [ ] 1.1.5 Update `isPathInWorkspace` to call `resolveRealPath` for filePath and `resolveWorkspacePath` for workspacePath
  - [ ] 1.1.6 Add CWE-59, CVE-2025-55130, and TOCTOU documentation comments

## Phase 2: Testing

- [ ] 2.1 Add symlink defense tests to `apps/web-platform/test/canusertool-sandbox.test.ts`
  - [ ] 2.1.1 Set up temp directory fixtures with `beforeEach`/`afterEach` for real filesystem symlink tests
  - [ ] 2.1.2 Test: denies absolute symlink pointing outside workspace (symlink to /etc)
  - [ ] 2.1.3 Test: denies relative symlink pointing outside workspace (symlink to ../../../etc)
  - [ ] 2.1.4 Test: allows symlink pointing inside workspace (internal symlink)
  - [ ] 2.1.5 Test: denies write through symlinked parent directory
  - [ ] 2.1.6 Test: denies circular symlinks (ELOOP)
  - [ ] 2.1.7 Test: denies chained symlinks that ultimately escape workspace
  - [ ] 2.1.8 Test: handles non-existent file in real directory (Write/Edit path)
  - [ ] 2.1.9 Test: handles deeply nested non-existent path (ancestor walk)
  - [ ] 2.1.10 Verify all 11 existing `isPathInWorkspace` tests still pass

## Phase 3: Validation

- [ ] 3.1 Run full test suite (`./node_modules/.bin/vitest run` in `apps/web-platform/`)
- [ ] 3.2 Verify plugin symlink (`plugins/soleur -> /app/shared/plugins/soleur`) behavior -- document in code comment if agents cannot read plugin files through file tools
