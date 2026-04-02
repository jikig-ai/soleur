# Tasks: fix(security) remove user_metadata fallback

## Phase 1: Test (TDD - Red)

- [x] 1.1 Add structural enforcement test: `user_metadata` not referenced for `user_name` in route source
  - File: `apps/web-platform/test/install-route.test.ts`
  - Read `apps/web-platform/app/api/repo/install/route.ts` source via `readFileSync` (matches existing pattern)
  - Assert that `user_metadata` combined with `user_name` does not appear in the `githubLogin` assignment block
  - This test should FAIL against the current code (red phase)

## Phase 2: Implementation (Green)

- [x] 2.1 Remove `?? user.user_metadata?.user_name` fallback from line 50
  - File: `apps/web-platform/app/api/repo/install/route.ts`
  - Remove the `??` and `user.user_metadata?.user_name` from the `githubLogin` assignment
- [x] 2.2 Update code comment on line 43 from "identity first" to "identity only"
  - File: `apps/web-platform/app/api/repo/install/route.ts`
  - Change "Extract GitHub username from provider-controlled identity first" to "Extract GitHub username from provider-controlled identity only"

## Phase 3: Verify

- [x] 3.1 Run full test suite: `cd apps/web-platform && npx vitest run test/install-route.test.ts`
  - All existing 12 tests pass
  - New structural test passes (1 new test)
