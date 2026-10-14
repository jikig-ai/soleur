# Tasks: Fix Create Project Start Fresh Flow

**Plan:** [2026-04-10-fix-create-project-start-fresh-flow-plan.md](../../plans/2026-04-10-fix-create-project-start-fresh-flow-plan.md)
**Issue:** #1872
**Branch:** `feat-fix-1872-create-project-issues`

[Updated 2026-04-10: Revised Phase 3 sentinel approach after tracing actual code paths; both Start Fresh and Connect Existing use provisionWorkspaceWithRepo]

## Phase 1: Fix Import Screen Shown After Start Fresh

- [x] 1.1 Add create-flow flag to sessionStorage in `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - [x] 1.1.1 In `handleCreateNew()`, set `sessionStorage.setItem("soleur_create_flow", "true")`
  - [x] 1.1.2 In `handleOpenDashboard()` and `handleStartOver()`, clear `sessionStorage.removeItem("soleur_create_flow")`
- [x] 1.2 Guard auto-detect effect against create flow and ready status
  - [x] 1.2.1 In the auto-detect effect (line 97-123), check `soleur_create_flow` flag and skip if set
  - [x] 1.2.2 Before auto-detect, call `GET /api/repo/status`. If `status === "ready"`, redirect to `/dashboard` and return
  - [x] 1.2.3 Clear stale `repos` and `reposLoading` state at effect top (learning: defensive-state-clear-on-useeffect-remount)
- [x] 1.3 Guard callback effect against lost sessionStorage
  - [x] 1.3.1 In the callback effect (line 125-185), when `pendingCreateData` is null, check `GET /api/repo/status`
  - [x] 1.3.2 If `status === "ready"`, redirect to `/dashboard` instead of calling `fetchRepos()`
  - [x] 1.3.3 If `status !== "ready"`, proceed to `fetchRepos()` (existing behavior for Connect Existing)
- [x] 1.4 Pass `source` parameter through startSetup
  - [x] 1.4.1 Add optional `source?: "start_fresh" | "connect_existing"` parameter to `startSetup` callback
  - [x] 1.4.2 Pass `source` in `POST /api/repo/setup` request body
  - [x] 1.4.3 Update callers: `handleCreateSubmit` passes `"start_fresh"`, `handleSelectProject` passes `"connect_existing"`, callback effect with `pendingCreateData` passes `"start_fresh"`
- [x] 1.5 Write tests for auto-detect guard in new `apps/web-platform/test/connect-repo-guards.test.tsx`
  - [x] 1.5.1 Test: auto-detect skipped when `soleur_create_flow` is in sessionStorage
  - [x] 1.5.2 Test: auto-detect redirects to `/dashboard` when repo_status is "ready"
  - [x] 1.5.3 Test: callback with no sessionStorage data and repo_status "ready" redirects to `/dashboard`
  - [x] 1.5.4 Test: callback with no sessionStorage data and repo_status "not_connected" falls through to fetchRepos
  - [x] 1.5.5 Test: "Connect Existing" flow still works with auto-detect (regression)

## Phase 2: Fix Vision.md Content Validation

- [x] 2.1 Add content validation to `tryCreateVision()` in `apps/web-platform/server/vision-helpers.ts`
  - [x] 2.1.1 Reject content shorter than 10 characters (too short to be a vision)
  - [x] 2.1.2 Reject content starting with `/` (slash command)
  - [x] 2.1.3 Reject bare leader mention (`@xxx` without content after it)
  - [x] 2.1.4 Reject content matching pattern `### Vision` followed by `/soleur:` (malformed sync output)
- [x] 2.2 Write tests for content validation in existing `apps/web-platform/test/vision-creation.test.ts`
  - [x] 2.2.1 Test: slash command `/soleur:sync --headless` is rejected (mockWriteFile not called)
  - [x] 2.2.2 Test: short content `@cpo` is rejected
  - [x] 2.2.3 Test: valid vision "I'm building a marketplace for designers" is accepted
  - [x] 2.2.4 Test: content with `### Vision /soleur:sync` pattern is rejected
  - [x] 2.2.5 Test: mention with content `@cpo I'm building a marketplace` IS accepted

## Phase 3: Suppress Welcome Hook for Start Fresh Workspaces

- [x] 3.1 Add `options` parameter to `provisionWorkspaceWithRepo()` in `apps/web-platform/server/workspace.ts`
  - [x] 3.1.1 Add optional `options?: { suppressWelcomeHook?: boolean }` as last parameter
  - [x] 3.1.2 After writing `.claude/settings.json`, conditionally write `soleur-welcomed.local` when `options?.suppressWelcomeHook` is true
- [x] 3.2 Also create sentinel in `provisionWorkspace()` (auth callback path for new users)
  - [x] 3.2.1 Add `writeFileSync(join(claudeDir, "soleur-welcomed.local"), "")` after writing settings.json
  - [x] 3.2.2 Rationale: `provisionWorkspace()` creates a blank workspace for new users who haven't connected a repo yet -- these users will go through the guided onboarding, not `/soleur:sync`
- [x] 3.3 Update `POST /api/repo/setup` in `apps/web-platform/app/api/repo/setup/route.ts`
  - [x] 3.3.1 Accept optional `source` field in request body (`"start_fresh" | "connect_existing"`)
  - [x] 3.3.2 Pass `{ suppressWelcomeHook: body.source === "start_fresh" }` to `provisionWorkspaceWithRepo()`
- [x] 3.4 Write tests for sentinel creation (extend `apps/web-platform/test/workspace-error-handling.test.ts`)
  - [x] 3.4.1 Test: `provisionWorkspace()` creates `.claude/soleur-welcomed.local`
  - [x] 3.4.2 Test: `provisionWorkspaceWithRepo()` without `suppressWelcomeHook` does NOT create sentinel
  - [x] 3.4.3 Test: `provisionWorkspaceWithRepo({ suppressWelcomeHook: true })` creates sentinel

## Phase 4: Create Vision API Endpoint

- [x] 4.1 Create `apps/web-platform/app/api/vision/route.ts`
  - [x] 4.1.1 POST handler: `validateOrigin` CSRF check (mandatory -- structural test enforces this)
  - [x] 4.1.2 Auth via `createClient().auth.getUser()`
  - [x] 4.1.3 Read request body `{ content: string }`, validate presence and type
  - [x] 4.1.4 Look up `workspace_path` from users table via service client
  - [x] 4.1.5 Call `tryCreateVision(workspace_path, content)` -- content validation is already in the function
  - [x] 4.1.6 Return `{ ok: true }` on success, appropriate error codes on failure
- [x] 4.2 Update dashboard first-run form to call vision API
  - [x] 4.2.1 In `handleFirstRunSend` in `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - [x] 4.2.2 Fire-and-forget `fetch("/api/vision", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ content: message }) }).catch(() => {})`
  - [x] 4.2.3 Place BEFORE the `router.push()` call so the request fires before navigation
- [x] 4.3 Write tests for vision API in new `apps/web-platform/test/vision-route.test.ts`
  - [x] 4.3.1 Test: POST with valid content calls tryCreateVision and returns 200
  - [x] 4.3.2 Test: POST with slash command content returns 200 (validation is in tryCreateVision, not the route)
  - [x] 4.3.3 Test: POST without auth returns 401
  - [x] 4.3.4 Test: POST with missing content field returns 400
  - [x] 4.3.5 Test: POST with no workspace_path returns 503

## Phase 5: QA and Verification

- [x] 5.1 Run existing test suite to verify no regressions (`cd apps/web-platform && npx vitest run`)
- [x] 5.2 Manual QA: Create fresh "Start Fresh" project, verify no import screen shown
- [x] 5.3 Manual QA: Verify "Connect Existing" flow still shows repo list correctly
- [x] 5.4 Manual QA: Verify vision.md contains typed idea after first-run form submission
- [x] 5.5 Manual QA: Verify welcome hook does not fire for Start Fresh workspace
- [x] 5.6 Run markdownlint on changed .md files (`npx markdownlint-cli2 --fix`)
