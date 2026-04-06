# Tasks: fix create project setup failure

Source: `knowledge-base/project/plans/2026-04-06-fix-create-project-setup-failure-plan.md`

## Phase 0: Add `administration:write` permission to GitHub App (prerequisite)

- [ ] 0.1 Add `administration:write` repository permission to the Soleur AI GitHub App via Playwright
  - Navigate to `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/permissions`
  - Add `Repository permissions > Administration: Read and write`
  - Approve the new permission for the `jikig-ai` org installation
- [ ] 0.2 Verify permission via API: `GET /app/installations/121112974` should show `permissions.administration: "write"`

## Phase 1: Fix organization repo creation

- [ ] 1.1 Extract `getInstallationAccount` helper from `verifyInstallationOwnership` in `apps/web-platform/server/github-app.ts`
  - New function returns `InstallationAccount` (login, id, type)
  - Refactor `verifyInstallationOwnership` to call the new helper
  - Existing install route tests must continue to pass
- [ ] 1.2 Route `createRepo` to the correct endpoint using `getInstallationAccount`
  - Organization: `POST /orgs/{account.login}/repos`
  - User: `POST /user/repos` (existing behavior)
  - Extract GitHub error message from response body (match `createPullRequest` pattern)
- [ ] 1.3 Write tests for org vs user repo creation in `apps/web-platform/test/github-app-create-repo.test.ts`
  - Follow `github-app-pr.test.ts` pattern (RSA key gen, globalThis.fetch mock, uniqueInstallationId)
  - Use installationId range starting at 8000 to avoid cache collision
  - Test org installation routes to `/orgs/{org}/repos`
  - Test user installation routes to `/user/repos`
  - Test 422 error propagation includes GitHub error message
  - Test 404 installation throws "Installation not found"

## Phase 2: Improve error propagation

- [ ] 2.1 Add Sentry capture and specific error return to `POST /api/repo/create` in `apps/web-platform/app/api/repo/create/route.ts`
  - Import `* as Sentry from "@sentry/nextjs"`
  - Call `Sentry.captureException(err)` in catch handler
  - Return the actual error message (not generic "Failed to create repository")
- [ ] 2.2 Surface create-repo errors in client at `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - Read error from `POST /api/repo/create` response body via `.json().catch(() => null)`
  - Pass `data?.error` to `setSetupError()` before setting state to "failed"
- [ ] 2.3 Surface setup POST errors in client at `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - Read error from `POST /api/repo/setup` response body in `startSetup`
  - Pass `data?.error` to `setSetupError()` before setting state to "failed"
- [ ] 2.4 Write tests for error propagation in `apps/web-platform/test/create-route-error.test.ts`
  - Follow `install-route-handler.test.ts` mock pattern
  - Mock `@sentry/nextjs` to verify `captureException` is called
  - Test that create route returns GitHub error message in response body

## Phase 3: Post-deploy verification

- [ ] 3.1 Verify ca-certificates fix deployed: `curl -s https://app.soleur.ai/health | jq '.version'` expects v0.14.3+
- [ ] 3.2 E2E flow test via Playwright: "Connect Existing" flow (clone succeeds after cert fix)
- [ ] 3.3 E2E flow test via Playwright: "Start Fresh" (Create Project) flow (org repo creation succeeds)
- [ ] 3.4 Resolve stale Sentry issues (workspace cleanup, git clone cert failure)
- [ ] 3.5 Verify no users stuck in `repo_status: "error"` via Supabase REST API query
