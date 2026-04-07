# Tasks: Parallelize KB Reader I/O

Ref: `knowledge-base/project/plans/2026-04-07-perf-parallelize-kb-reader-io-plan.md`

## Phase 1: Core Implementation

- [ ] 1.1 Parallelize `collectMdFiles` in `apps/web-platform/server/kb-reader.ts`
  - [ ] 1.1.1 Split entries into directory promises and file paths
  - [ ] 1.1.2 Use `Promise.all` for recursive directory calls
  - [ ] 1.1.3 Concatenate results

- [ ] 1.2 Parallelize `buildTree` in `apps/web-platform/server/kb-reader.ts`
  - [ ] 1.2.1 Separate directory and file entry processing into promise arrays
  - [ ] 1.2.2 Directory promises: recursive call + empty-dir filter (return null)
  - [ ] 1.2.3 File promises: stat with catch for graceful modifiedAt omission
  - [ ] 1.2.4 Await both arrays with `Promise.all`, filter nulls, sort, merge

- [ ] 1.3 Parallelize `searchKb` in `apps/web-platform/server/kb-reader.ts`
  - [ ] 1.3.1 Map file paths to parallel stat+read+match promises
  - [ ] 1.3.2 Create per-callback `RegExp` instances (avoid shared `lastIndex` state)
  - [ ] 1.3.3 Filter null results, sort by match count, apply limit

## Phase 2: Testing

- [ ] 2.1 Run existing test suite: `cd apps/web-platform && npx vitest run test/kb-reader.test.ts`
- [ ] 2.2 Run security tests: `cd apps/web-platform && npx vitest run test/kb-security.test.ts`
- [ ] 2.3 Verify all 17 kb-reader tests pass unchanged
- [ ] 2.4 Verify all 4 kb-security tests pass unchanged
