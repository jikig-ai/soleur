# Tasks: fix create project setup failure

Source: `knowledge-base/project/plans/2026-04-06-fix-create-project-setup-failure-plan.md`

## Phase 1: Fix organization repo creation

- [ ] 1.1 Add installation account type detection to `createRepo` in `apps/web-platform/server/github-app.ts`
  - Query `GET /app/installations/{id}` to get account type (User vs Organization)
  - Use `POST /orgs/{org}/repos` for organizations, `POST /user/repos` for users
  - Update error messages to include GitHub API response details
- [ ] 1.2 Write tests for org vs user repo creation in `apps/web-platform/test/github-app-create-repo.test.ts`
  - Test org installation routes to `/orgs/{org}/repos`
  - Test user installation routes to `/user/repos`
  - Test error propagation from GitHub API

## Phase 2: Improve error propagation

- [ ] 2.1 Add Sentry capture and specific error return to `POST /api/repo/create` in `apps/web-platform/app/api/repo/create/route.ts`
  - Import and call `Sentry.captureException(err)` in catch handler
  - Return the actual error message from the GitHub API (not generic "Failed to create repository")
- [ ] 2.2 Surface create-repo errors in client at `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - Read error from `POST /api/repo/create` response body
  - Pass error message to `setSetupError()` before setting state to "failed"
- [ ] 2.3 Surface setup POST errors in client at `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - Read error from `POST /api/repo/setup` response body in `startSetup`
  - Pass error message to `setSetupError()` before setting state to "failed"
- [ ] 2.4 Write tests for error propagation in `apps/web-platform/test/create-route-error.test.ts`
  - Test that create route returns GitHub error message in response
  - Test that create route calls `Sentry.captureException`

## Phase 3: Post-deploy verification

- [ ] 3.1 Verify ca-certificates fix deployed (v0.14.3+ on health endpoint)
- [ ] 3.2 E2E flow test via Playwright: "Connect Existing" flow
- [ ] 3.3 E2E flow test via Playwright: "Start Fresh" (Create Project) flow
- [ ] 3.4 Resolve stale Sentry issues (workspace cleanup, git clone cert failure)
- [ ] 3.5 Verify no users stuck in `repo_status: "error"` via Supabase REST API
