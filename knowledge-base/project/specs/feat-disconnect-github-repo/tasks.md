# Tasks: feat-disconnect-github-repo

## Phase 1: API Endpoint

- [ ] 1.1 Create `apps/web-platform/app/api/repo/disconnect/route.ts` with `DELETE` handler
  - [ ] 1.1.1 CSRF validation via `validateOrigin`/`rejectCsrf`
  - [ ] 1.1.2 Auth check via `createClient().auth.getUser()`
  - [ ] 1.1.3 Rate limit via `SlidingWindowCounter({ windowMs: 60_000, maxRequests: 1 })`
  - [ ] 1.1.4 Fetch current user record to get `workspace_path`
  - [ ] 1.1.5 Update user record: clear `github_installation_id`, `repo_url`, reset `repo_status` to `not_connected`, clear `repo_last_synced_at`, `repo_error`, `workspace_path`, `workspace_status`
  - [ ] 1.1.6 Call `deleteWorkspace(userId)` (best-effort, log errors)
  - [ ] 1.1.7 Return `{ ok: true }`

## Phase 2: UI Component

- [ ] 2.1 Create `apps/web-platform/components/settings/disconnect-repo-dialog.tsx`
  - [ ] 2.1.1 Client component with `isOpen`, `isDisconnecting`, `error` state
  - [ ] 2.1.2 Simple confirm/cancel pattern (no typed confirmation -- disconnect is reversible)
  - [ ] 2.1.3 Call `DELETE /api/repo/disconnect` on confirm
  - [ ] 2.1.4 Redirect to `/connect-repo` on success via `router.push`
  - [ ] 2.1.5 Error and loading states
- [ ] 2.2 Update `apps/web-platform/components/settings/project-setup-card.tsx`
  - [ ] 2.2.1 Import and render `DisconnectRepoDialog` in `repoStatus === "ready"` block
  - [ ] 2.2.2 Pass extracted repo name as confirmation target

## Phase 3: Tests

- [ ] 3.1 Create `apps/web-platform/test/disconnect-route.test.ts`
  - [ ] 3.1.1 Test 401 when unauthenticated
  - [ ] 3.1.2 Test 429 when rate limited
  - [ ] 3.1.3 Test 200 on successful disconnect
  - [ ] 3.1.4 Test workspace cleanup is called
- [ ] 3.2 Update `apps/web-platform/test/project-setup-card.test.tsx`
  - [ ] 3.2.1 Test disconnect button appears when `repoStatus === "ready"`
  - [ ] 3.2.2 Test disconnect button does NOT appear when `repoStatus !== "ready"`
