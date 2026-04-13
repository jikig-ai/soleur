# Tasks: fix KB upload workspace sync auth

Plan: `knowledge-base/project/plans/2026-04-13-fix-kb-upload-workspace-sync-auth-plan.md`

## Phase 1: Setup

- [x] 1.1 Read `apps/web-platform/app/api/kb/upload/route.ts`
- [x] 1.2 Read `apps/web-platform/test/kb-upload.test.ts`
- [x] 1.3 Verify existing tests pass: `cd apps/web-platform && bun test test/kb-upload.test.ts`

## Phase 2: Write Failing Tests (RED)

- [x] 2.1 Add test: "git pull is called with credential helper argument"
  - Assert `mockExecFile` is called with args containing `-c` and `credential.helper=!`
- [x] 2.2 Add test: "credential helper file is cleaned up after successful pull"
  - Assert `unlinkSync` is called with the helper path
- [x] 2.3 Add test: "credential helper file is cleaned up after failed pull"
  - Mock `execFile` to reject, assert `unlinkSync` is still called
- [x] 2.4 Add test: "returns SYNC_FAILED when token generation fails"
  - Mock `generateInstallationToken` to reject, assert 500 with SYNC_FAILED code
- [x] 2.5 Verify tests fail: `cd apps/web-platform && bun test test/kb-upload.test.ts`

## Phase 3: Implementation (GREEN)

- [x] 3.1 Add imports to `route.ts`: `generateInstallationToken`, `randomCredentialPath` from `@/server/github-app`, `writeFileSync`/`unlinkSync` from `node:fs`
- [x] 3.2 Replace bare `git pull --ff-only` (lines 226-244) with authenticated pull using credential helper pattern
- [x] 3.3 Add `finally` block to clean up credential helper file
- [x] 3.4 Verify tests pass: `cd apps/web-platform && bun test test/kb-upload.test.ts`

## Phase 4: Verification

- [x] 4.1 Run full test suite: `cd apps/web-platform && bun test`
- [x] 4.2 Run markdownlint on changed .md files: `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-13-fix-kb-upload-workspace-sync-auth-plan.md`
