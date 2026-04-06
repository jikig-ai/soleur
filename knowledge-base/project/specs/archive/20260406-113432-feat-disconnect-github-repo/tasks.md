# Tasks: feat-disconnect-github-repo

## Phase 1: API Endpoint

- [x] 1.1 Create `apps/web-platform/app/api/repo/disconnect/route.ts` with `DELETE` handler
  - [x] 1.1.1 CSRF validation via `validateOrigin`/`rejectCsrf`
  - [x] 1.1.2 Auth check via `createClient().auth.getUser()`
  - [x] 1.1.3 Rate limit via `SlidingWindowCounter({ windowMs: 60_000, maxRequests: 1 })`
  - [x] 1.1.4 Fetch current user record to get `workspace_path`
  - [x] 1.1.5 Update user record: clear `github_installation_id`, `repo_url`, reset `repo_status` to `not_connected`, clear `repo_last_synced_at`, `repo_error`, `workspace_path`, `workspace_status`
  - [x] 1.1.6 Call `deleteWorkspace(userId)` (best-effort, log errors, add `Sentry.captureException` on failure)
  - [x] 1.1.7 Return `{ ok: true }`

## Phase 2: UI Component

- [x] 2.1 Create `apps/web-platform/components/settings/disconnect-repo-dialog.tsx`
  - [x] 2.1.1 Client component with `isOpen`, `isDisconnecting`, `error` state
  - [x] 2.1.2 Simple confirm/cancel pattern (no typed confirmation -- disconnect is reversible)
  - [x] 2.1.3 Call `DELETE /api/repo/disconnect` on confirm
  - [x] 2.1.4 Redirect to `/connect-repo` on success via `router.push`
  - [x] 2.1.5 Error and loading states with `role="alert"` on error element
  - [x] 2.1.6 Neutral button style (not red -- reversible action, not destructive)
- [x] 2.2 Update `apps/web-platform/components/settings/project-setup-card.tsx`
  - [x] 2.2.1 Add `"use client"` directive (needed for DisconnectRepoDialog's useState/useRouter)
  - [x] 2.2.2 Import and render `DisconnectRepoDialog` in `repoStatus === "ready"` block
  - [x] 2.2.3 Pass extracted repo name as display context

## Phase 3: Tests

- [x] 3.1 Create `apps/web-platform/test/disconnect-route.test.ts`
  - [x] 3.1.1 Test 401 when unauthenticated
  - [x] 3.1.2 Test 429 when rate limited
  - [x] 3.1.3 Test 200 on successful disconnect (verify DB fields cleared)
  - [x] 3.1.4 Test workspace cleanup is called (mock `deleteWorkspace`)
  - [x] 3.1.5 Test idempotency -- 200 when user already has `repo_status: "not_connected"`
- [x] 3.2 Update `apps/web-platform/test/project-setup-card.test.tsx`
  - [x] 3.2.1 Test disconnect button appears when `repoStatus === "ready"`
  - [x] 3.2.2 Test disconnect button does NOT appear when `repoStatus !== "ready"`
- [x] 3.3 Update `apps/web-platform/lib/auth/csrf-coverage.test.ts`
  - [x] 3.3.1 Extend regex to scan DELETE, PUT, PATCH routes (not just POST)
