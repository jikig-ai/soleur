# Tasks: Parallelize KB Reader I/O

Ref: `knowledge-base/project/plans/2026-04-07-perf-parallelize-kb-reader-io-plan.md`

## Phase 1: Core Implementation

- [x] 1.1 Parallelize `collectMdFiles` in `apps/web-platform/server/kb-reader.ts`
  - [x] 1.1.1 Split entries into directory promises and file paths
  - [x] 1.1.2 Use `Promise.all` for recursive directory calls
  - [x] 1.1.3 Concatenate results

- [x] 1.2 Parallelize `buildTree` in `apps/web-platform/server/kb-reader.ts`
  - [x] 1.2.1 Separate directory and file entry processing into promise arrays
  - [x] 1.2.2 Directory promises: recursive call + empty-dir filter (return null)
  - [x] 1.2.3 File promises: stat with catch for graceful modifiedAt omission
  - [x] 1.2.4 Await both arrays with `Promise.all`, filter nulls, sort, merge

- [x] 1.3 Parallelize `searchKb` in `apps/web-platform/server/kb-reader.ts`
  - [x] 1.3.1 Map file paths to parallel stat+read+match promises
  - [x] 1.3.2 Create per-callback `RegExp` instances (avoid shared `lastIndex` state)
  - [x] 1.3.3 Filter null results, sort by match count, apply limit

## Phase 2: Testing

- [x] 2.1 Run existing test suite: `cd apps/web-platform && npx vitest run test/kb-reader.test.ts`
- [x] 2.2 Run security tests: `cd apps/web-platform && npx vitest run test/kb-security.test.ts`
- [x] 2.3 Verify all 17 kb-reader tests pass unchanged
- [x] 2.4 Verify all 4 kb-security tests pass unchanged
