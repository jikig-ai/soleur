# Tasks: GitHub App Reinstall Flow Improvement

**Issue:** #1678
**Plan:** [2026-04-06-feat-github-app-reinstall-flow-plan.md](../../plans/2026-04-06-feat-github-app-reinstall-flow-plan.md)

## Phase 1: Broaden callback handler

- [x] 1.1 Write failing test: `setup_action=update` callback processes correctly (register install + fetch repos)
  - File: `apps/web-platform/test/connect-repo-page.test.tsx`
  - Mock `useSearchParams` to return `installation_id=123&setup_action=update`
  - Assert `POST /api/repo/install` is called, then `GET /api/repo/repos`
- [x] 1.2 Write failing test: `setup_action=install` still works (regression)
  - Same test file, verify existing behavior unchanged
- [x] 1.3 Broaden `setup_action` checks inline at both call sites
  - File: `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - `useState` initializer: accept `install` or `update`
  - `useEffect` guard: accept `install` or `update`
- [x] 1.4 Verify tests pass

## Phase 2: Skip redirect via on-click fetch

- [x] 2.1 Write failing test: user with existing installation clicks "Connect Existing" -- skips redirect, shows repos
  - File: `apps/web-platform/test/connect-repo-page.test.tsx`
  - Mock `GET /api/repo/repos` to return 200 with repos (no callback params)
  - Simulate click on "Connect Existing", assert repo list shown (not GitHub redirect)
- [x] 2.2 Write failing test: user with existing installation clicks "Create New" -- creates repo directly
  - Simulate name input + submit, assert `POST /api/repo/create` called directly (no GitHub redirect)
- [x] 2.3 Write failing test: user without installation clicks "Connect Existing" -- redirect flow unchanged
  - Mock `GET /api/repo/repos` returning 400
  - Simulate click, assert `github_redirect` state shown
- [x] 2.4 Write failing test: user without installation clicks "Create New" -- redirect flow unchanged
  - Mock `GET /api/repo/repos` returning 400
  - Simulate name input + submit, assert sessionStorage set + redirect triggered
- [x] 2.5 Write failing test: network error on "Connect Existing" -- falls back to GitHub redirect
- [x] 2.6 Write failing test: direct create fails with error -- shows failed state with error message
- [x] 2.7 Make `handleConnectExisting` async with inline `GET /api/repo/repos` check
  - File: `apps/web-platform/app/(auth)/connect-repo/page.tsx`
  - 200 with repos → set repos, transition to `select_project`
  - 200 empty → transition to `no_projects`
  - 400 or error → transition to `github_redirect`
- [x] 2.8 Make `handleCreateSubmit` async with direct create when installation exists
  - Try `POST /api/repo/create` directly
  - If 400 (no installation) → fall back to sessionStorage + redirect
  - If other error → show error in `failed` state
  - If success → call `startSetup`
- [x] 2.9 Verify tests pass

## Phase 3: Refresh UI + auto-refresh

- [x] 3.1 Write failing test: Refresh button on `SelectProjectState` triggers `onRefresh`
  - File: `apps/web-platform/test/connect-repo-page.test.tsx`
  - Render `SelectProjectState` with `onRefresh` prop, click button, assert called
- [x] 3.2 Write failing test: Refresh button on `NoProjectsState` triggers `onRefresh`
- [x] 3.3 Write failing test: `visibilitychange` to `visible` triggers repo re-fetch in `select_project` state
- [x] 3.4 Write failing test: `visibilitychange` does NOT trigger fetch in `setting_up` state
- [x] 3.5 Write failing test: refresh error keeps current state (no transition to `interrupted`)
- [x] 3.6 Write failing test: refresh skipped when `reposLoading` is true (throttle)
- [x] 3.7 Add `onRefresh` prop and Refresh button to `SelectProjectState`
  - File: `apps/web-platform/components/connect-repo/select-project-state.tsx`
- [x] 3.8 Add `onRefresh` prop and Refresh button to `NoProjectsState`
  - File: `apps/web-platform/components/connect-repo/no-projects-state.tsx`
- [x] 3.9 Create `refreshRepos` wrapper in `page.tsx`
  - Catches errors silently (keeps current state)
  - Only updates repos on success
  - Respects `reposLoading` guard
- [x] 3.10 Add `visibilitychange` listener to `page.tsx`
  - Register once, gate on `stateRef` (only in `select_project` or `no_projects`)
  - Call `refreshRepos` (not `fetchRepos`)
- [x] 3.11 Pass `onRefresh={refreshRepos}` to both components in `page.tsx`
- [x] 3.12 Verify all tests pass
