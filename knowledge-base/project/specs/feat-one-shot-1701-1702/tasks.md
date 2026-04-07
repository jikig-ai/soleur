# Tasks: pre-merge-rebase precondition guards and remote isolation

## Phase 1: Precondition Guards (#1701)

- [ ] 1.1 Add `expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("")` before `JSON.parse` at line 195 ("no review evidence blocks merge with deny")
- [ ] 1.2 Add precondition guard before `JSON.parse` at line 287 ("branch behind main triggers merge and push")
- [ ] 1.3 Add precondition guard before `JSON.parse` at line 302 ("uncommitted changes blocks merge with deny")
- [ ] 1.4 Add precondition guard before `JSON.parse` at line 322 ("staged uncommitted changes blocks merge with deny")
- [ ] 1.5 Add precondition guard before `JSON.parse` at line 352 ("merge conflict aborts and blocks with file list")
- [ ] 1.6 Add precondition guard before `JSON.parse` at line 493 ("push failure after merge blocks with deny")
- [ ] 1.7 Add precondition guard before `JSON.parse(first.stdout)` at line 529 ("hook is idempotent -- second run after merge shows up-to-date")

## Phase 2: Remote Ref Reset (#1702)

- [ ] 2.1 Add `let initialMainSha: string;` declaration alongside `repoDir` and `remoteDir`
- [ ] 2.2 Capture initial SHA in `beforeAll` after first push to origin/main
- [ ] 2.3 Restructure `beforeEach` to: checkout main, reset remote ref, fetch origin, reset local, git clean -fd, branch cleanup

## Phase 3: Verification

- [ ] 3.1 Run full test suite (`bun test test/pre-merge-rebase.test.ts`) -- all 21 tests pass
- [ ] 3.2 Run test suite 3+ times to verify no flakiness
