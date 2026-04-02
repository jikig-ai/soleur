# Tasks: feat-org-install-ownership

Source: `knowledge-base/project/plans/2026-04-02-feat-org-install-ownership-verification-plan.md`

## Phase 1: Tests (TDD)

- [ ] 1.1 Update existing org rejection test in `apps/web-platform/test/install-route.test.ts`
  - Rename "rejects organization installations with 403" to reflect new behavior
  - Change to test: org installation where user IS a member returns `verified: true`
  - Mock three sequential fetches: (1) installation lookup returns org account, (2) token exchange POST succeeds, (3) membership check returns 204
- [ ] 1.2 Add test: org installation where user is NOT a member
  - Mock: (1) installation lookup returns org account, (2) token exchange POST succeeds, (3) membership check returns 404
  - Assert: `verified: false`, `status: 403`, error message matches "not a member"
- [ ] 1.3 Add test: org membership check fails with 403 (missing Members permission)
  - Mock: (1) installation lookup returns org account, (2) token exchange POST succeeds, (3) membership check returns 403
  - Assert: `verified: false`, `status: 502`, error message matches "Failed to verify"
- [ ] 1.4 Add test: org membership check returns 500 (GitHub API error)
  - Mock: (1) installation lookup returns org account, (2) token exchange POST succeeds, (3) membership check returns 500
  - Assert: `verified: false`, `status: 502`
- [ ] 1.5 Verify all existing User-type tests still pass (no changes expected)

## Phase 2: Implementation

- [ ] 2.1 Replace org rejection block in `apps/web-platform/server/github-app.ts:156-168`
  - Import or call `generateInstallationToken(installationId)` to get an installation token
  - Call `GET /orgs/{account.login}/members/{expectedLogin}` with `Authorization: token {installationToken}`
  - Handle 204 (member) -> `{ verified: true }`
  - Handle 404 (not member) -> `{ verified: false, error: "User is not a member of the organization", status: 403 }`
  - Handle other errors -> `{ verified: false, error: "Failed to verify organization membership", status: 502 }`
- [ ] 2.2 Update log messages: replace "not yet supported" warning with appropriate info/error logging for membership check results

## Phase 3: Validation

- [ ] 3.1 Run `npx vitest run apps/web-platform/test/install-route.test.ts` -- all tests pass
- [ ] 3.2 Run full test suite to check no regressions
- [ ] 3.3 Verify no new dependencies added (uses existing `generateInstallationToken` and `githubFetch`)
