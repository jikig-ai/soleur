# Tasks: fix symlink escape defense-in-depth (#877)

## Phase 1: Core Implementation

- [ ] 1.1 Refactor `isPathInWorkspace` in `apps/web-platform/server/sandbox.ts`
  - [ ] 1.1.1 Add `import fs from "fs"` to sandbox.ts
  - [ ] 1.1.2 Implement `resolveRealPath(filePath: string): string | null` -- resolves symlinks via `fs.realpathSync`, falls back to parent resolution for ENOENT, returns null for ELOOP/EACCES
  - [ ] 1.1.3 Implement `resolveParentRealPath(filePath: string): string | null` -- walks up directory tree to find deepest existing ancestor, resolves it, re-appends remaining segments
  - [ ] 1.1.4 Update `isPathInWorkspace` to call `resolveRealPath` instead of bare `path.resolve`
  - [ ] 1.1.5 Add TOCTOU documentation comment explaining the race condition and mitigations

## Phase 2: Testing

- [ ] 2.1 Add symlink defense tests to `apps/web-platform/test/canusertool-sandbox.test.ts`
  - [ ] 2.1.1 Set up temp directory fixtures with `beforeEach`/`afterEach` for real filesystem symlink tests
  - [ ] 2.1.2 Test: denies symlink pointing outside workspace (symlink to /etc)
  - [ ] 2.1.3 Test: allows symlink pointing inside workspace (internal symlink)
  - [ ] 2.1.4 Test: denies write through symlinked parent directory
  - [ ] 2.1.5 Test: denies circular symlinks (ELOOP)
  - [ ] 2.1.6 Test: handles non-existent file in real directory (Write/Edit path)
  - [ ] 2.1.7 Test: chained symlinks that ultimately escape workspace
  - [ ] 2.1.8 Verify all 11 existing `isPathInWorkspace` tests still pass

## Phase 3: Validation

- [ ] 3.1 Run full test suite (`./node_modules/.bin/vitest run` in `apps/web-platform/`)
- [ ] 3.2 Verify plugin symlink (`plugins/soleur -> /app/shared/plugins/soleur`) behavior -- document in code comment if agents cannot read plugin files through file tools
