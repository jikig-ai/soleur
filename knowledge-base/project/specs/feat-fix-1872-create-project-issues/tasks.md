# Tasks: Fix Create Project Start Fresh Flow

**Plan:** [2026-04-10-fix-create-project-start-fresh-flow-plan.md](../../plans/2026-04-10-fix-create-project-start-fresh-flow-plan.md)
**Issue:** #1872
**Branch:** `feat-fix-1872-create-project-issues`

## Phase 1: Fix Import Screen Shown After Start Fresh

- [ ] 1.1 Add create-flow flag to sessionStorage in `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - [ ] 1.1.1 In `handleCreateNew()`, set `sessionStorage.setItem("soleur_create_flow", "true")`
  - [ ] 1.1.2 In `handleOpenDashboard()` and `handleStartOver()`, clear `sessionStorage.removeItem("soleur_create_flow")`
- [ ] 1.2 Guard auto-detect effect against create flow and ready status
  - [ ] 1.2.1 In the auto-detect effect (line 97-123), check `soleur_create_flow` flag and skip if set
  - [ ] 1.2.2 After auto-detect finds repos, check `/api/repo/status`. If `status === "ready"`, redirect to `/dashboard` instead of showing repo list
- [ ] 1.3 Guard callback effect against lost sessionStorage
  - [ ] 1.3.1 In the callback effect (line 125-185), when `pendingCreateData` is null, check `/api/repo/status`
  - [ ] 1.3.2 If `status === "ready"`, redirect to `/dashboard` instead of calling `fetchRepos()`
  - [ ] 1.3.3 If `status !== "ready"`, proceed to `fetchRepos()` (existing behavior for Connect Existing)
- [ ] 1.4 Write tests for auto-detect guard
  - [ ] 1.4.1 Test: auto-detect skipped when `soleur_create_flow` is in sessionStorage
  - [ ] 1.4.2 Test: auto-detect redirects to `/dashboard` when repo_status is "ready"
  - [ ] 1.4.3 Test: callback with no sessionStorage data and repo_status "ready" redirects to `/dashboard`
  - [ ] 1.4.4 Test: callback with no sessionStorage data and repo_status "not_connected" falls through to fetchRepos
  - [ ] 1.4.5 Test: "Connect Existing" flow still works with auto-detect (regression)

## Phase 2: Fix Vision.md Content Validation

- [ ] 2.1 Add content validation to `tryCreateVision()` in `apps/web-platform/server/vision-helpers.ts`
  - [ ] 2.1.1 Reject content shorter than 10 characters (too short to be a vision)
  - [ ] 2.1.2 Reject content starting with `/` (slash command)
  - [ ] 2.1.3 Reject content matching pattern `### Vision` followed by `/soleur:` (malformed sync output)
- [ ] 2.2 Write tests for content validation in `apps/web-platform/test/vision-creation.test.ts`
  - [ ] 2.2.1 Test: slash command `/soleur:sync --headless` is rejected
  - [ ] 2.2.2 Test: short content `@cpo` is rejected
  - [ ] 2.2.3 Test: valid vision "I'm building a marketplace for designers" is accepted
  - [ ] 2.2.4 Test: content with `### Vision /soleur:sync` pattern is rejected

## Phase 3: Suppress Welcome Hook for Start Fresh Workspaces

- [ ] 3.1 Create sentinel file during workspace provisioning in `apps/web-platform/server/workspace.ts`
  - [ ] 3.1.1 In `provisionWorkspace()` (used for Start Fresh), add `writeFileSync(join(claudeDir, "soleur-welcomed.local"), "")`
  - [ ] 3.1.2 Verify `provisionWorkspaceWithRepo()` does NOT create the sentinel (Connect Existing should get the sync suggestion)
- [ ] 3.2 Write tests for sentinel creation
  - [ ] 3.2.1 Test: `provisionWorkspace()` creates `.claude/soleur-welcomed.local`
  - [ ] 3.2.2 Test: `provisionWorkspaceWithRepo()` does NOT create `.claude/soleur-welcomed.local`

## Phase 4: Create Vision API Endpoint

- [ ] 4.1 Create `apps/web-platform/app/api/vision/route.ts`
  - [ ] 4.1.1 POST handler: validates auth, reads request body `{ content: string }`
  - [ ] 4.1.2 Validates content (same rules as `tryCreateVision`)
  - [ ] 4.1.3 Writes vision.md to user's workspace via `tryCreateVision()`
  - [ ] 4.1.4 CSRF protection via `validateOrigin`
- [ ] 4.2 Update dashboard first-run form to call vision API
  - [ ] 4.2.1 In `handleFirstRunSend` in `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
  - [ ] 4.2.2 Fire-and-forget `fetch("/api/vision", { method: "POST", body: JSON.stringify({ content: message }) })`
  - [ ] 4.2.3 This ensures vision.md is created from the user's typed input, not from agent output
- [ ] 4.3 Write tests for vision API
  - [ ] 4.3.1 Test: POST with valid content creates vision.md
  - [ ] 4.3.2 Test: POST with slash command returns 400
  - [ ] 4.3.3 Test: POST without auth returns 401

## Phase 5: QA and Verification

- [ ] 5.1 Run existing test suite to verify no regressions
- [ ] 5.2 Manual QA: Create fresh "Start Fresh" project, verify no import screen shown
- [ ] 5.3 Manual QA: Verify "Connect Existing" flow still shows repo list correctly
- [ ] 5.4 Manual QA: Verify vision.md contains typed idea after first-run form submission
- [ ] 5.5 Run markdownlint on changed .md files
