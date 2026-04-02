# Tasks: GitHub App Installation ID Verification

## Phase 1: Core Implementation

### 1.1 Add `verifyInstallationOwnership()` to `server/github-app.ts`

- [ ] 1.1.1 Export `verifyInstallationOwnership(installationId: number, expectedLogin: string)` function
- [ ] 1.1.2 Call `GET /app/installations/{installationId}` using `createAppJwt()` and `githubFetch()`
- [ ] 1.1.3 Return `{ verified: boolean; error?: string }` -- handle 404, non-OK, and missing account
- [ ] 1.1.4 Compare `account.login` against `expectedLogin` (case-insensitive)

### 1.2 Update `POST /api/repo/install` route

- [ ] 1.2.1 Extract GitHub username from `user.user_metadata?.user_name` with identity fallback
- [ ] 1.2.2 Return 403 if no GitHub identity found on the authenticated user
- [ ] 1.2.3 Call `verifyInstallationOwnership()` before storing
- [ ] 1.2.4 Return 403 on ownership mismatch, 404 on missing installation
- [ ] 1.2.5 Log verification failures with structured context (userId, installationId)

## Phase 2: Testing

### 2.1 Write unit tests for installation ID verification

- [ ] 2.1.1 Create `apps/web-platform/test/install-route.test.ts`
- [ ] 2.1.2 Test: happy path -- installation matches user, returns 200
- [ ] 2.1.3 Test: ownership mismatch -- installation belongs to different user, returns 403
- [ ] 2.1.4 Test: non-existent installation (GitHub 404), returns 404
- [ ] 2.1.5 Test: user has no GitHub identity, returns 403
- [ ] 2.1.6 Test: unauthenticated request returns 401 (regression)
