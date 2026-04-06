---
title: "feat: skip GitHub redirect when app already installed"
type: feat
date: 2026-04-06
---

# Skip GitHub Redirect When App Already Installed

Ref #1678

When the Soleur GitHub App is already installed, the `/connect-repo` page forces an unnecessary GitHub round-trip. Additionally, GitHub's `setup_action=update` callback is silently ignored, stranding users who change repo access.

## Acceptance Criteria

- [ ] User with existing `github_installation_id` clicks "Connect Existing" -- skips GitHub redirect, sees repo list directly
- [ ] User with existing `github_installation_id` clicks "Create New" -- skips GitHub redirect, creates repo directly after name input
- [ ] User without installation -- goes through current GitHub redirect flow (no regression)
- [ ] Callback processes both `setup_action=install` and `setup_action=update`
- [ ] Repo list auto-refreshes when user returns to tab (via `visibilitychange`)
- [ ] Manual "Refresh" button on `SelectProjectState` and `NoProjectsState`
- [ ] Auto-refresh debounced to prevent rapid-fire API calls

## Test Scenarios

- Given a user with `github_installation_id` stored, when they click "Connect Existing", then `GET /api/repo/repos` is called directly (no redirect to GitHub)
- Given a user with `github_installation_id` stored, when they submit a project name in "Create New", then `POST /api/repo/create` is called directly (no redirect)
- Given a user without `github_installation_id`, when they click "Connect Existing", then they see the GitHub redirect screen
- Given a GitHub callback with `setup_action=update`, when the page loads, then the installation is registered and repos are fetched
- Given the user is on the repo list and switches tabs then returns, when `visibilitychange` fires with `visible`, then repos are re-fetched
- Given the user clicks "Refresh" on the repo list, when the fetch completes, then the list updates
- Given rapid tab switches, when `visibilitychange` fires multiple times within 2s, then only one fetch is made

## Implementation

### Phase 1: Broaden callback handler (FR2)

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

Change the `setup_action` check from `=== "install"` to accept both `install` and `update`. Inline the check at both call sites (`action === "install" || action === "update"`):

- `useState` initializer (checks `setup_action`): accept `install` or `update`
- `useEffect` guard (checks `setupAction`): accept `install` or `update`

**Test file:** `apps/web-platform/test/connect-repo-page.test.tsx`

### Phase 2: Skip redirect via on-click fetch (FR1)

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

No new state variables. No mount-time fetch. The installation check happens on-click:

1. Make `handleConnectExisting` async — try `GET /api/repo/repos` inline:
   - 200 with repos → `setRepos(data.repos)`, `setState("select_project")`
   - 200 with empty → `setState("no_projects")`
   - 400 (no installation) → `setState("github_redirect")` (current behavior)
   - Network error → `setState("github_redirect")` (safe fallback)

2. Make `handleCreateSubmit` async — try `POST /api/repo/create` directly:
   - If 200 → call `startSetup(data.repoUrl, data.fullName)`
   - If 400 (no installation, checked via error message or separate pre-check) → fall back to sessionStorage + redirect
   - If other error → `setSetupError(data?.error)`, `setState("failed")`
   - Show a loading state during the create call (transition to `setting_up` or use `reposLoading`)

This eliminates the race condition of a mount-time speculative fetch, the stale `preloadedRepos` data path, and the tri-state `hasInstallation` variable. The user clicks a button, the API call fires, and the result determines the next state.

**Test file:** extend `apps/web-platform/test/connect-repo-page.test.tsx`

### Phase 3: Refresh UI + auto-refresh (FR3, FR4)

**Files:**

- `apps/web-platform/components/connect-repo/select-project-state.tsx` — add `onRefresh` prop + Refresh button
- `apps/web-platform/components/connect-repo/no-projects-state.tsx` — add `onRefresh` prop + Refresh button
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` — add `visibilitychange` listener, pass `onRefresh` to both components

**Error handling for refresh:** Do NOT reuse `fetchRepos` directly as the refresh handler — it transitions to `interrupted` on error, which would destructively blow away the user's current repo list on a network blip. Instead, create a `refreshRepos` wrapper that catches errors silently (keep current state) and only updates repos on success.

**Throttle:** Guard with `reposLoading` (skip if already fetching). No need for a separate `lastRefreshRef` — the existing loading state is sufficient. Register the `visibilitychange` listener once and gate on a `stateRef` that tracks current state (only refresh in `select_project` or `no_projects`).

**Test file:** extend `apps/web-platform/test/connect-repo-page.test.tsx`

Additional test scenarios from review:

- Given the user transitions from `select_project` to `setting_up`, when `visibilitychange` fires, then no fetch is made
- Given a refresh fails with a network error while on `select_project`, then the state remains `select_project` (no transition to `interrupted`)

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted — modifies existing flow with minimal UI additions (one Refresh button per component)
**Agents invoked:** none
**Skipped specialists:** N/A

No new pages or multi-step flows introduced. Changes simplify an existing flow by removing unnecessary steps.

## Context

- Current callback only checks `setup_action === "install"` at `page.tsx:57` and `page.tsx:91`
- GitHub sends `setup_action=update` when permissions change on an already-installed app
- Existing `GET /api/repo/repos` returns 400 if no `github_installation_id` — usable as installation detection
- No new API endpoints needed

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-06-github-app-reinstall-flow-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-github-app-reinstall-flow/spec.md`
- Main page: `apps/web-platform/app/(auth)/connect-repo/page.tsx`
- SelectProjectState: `apps/web-platform/components/connect-repo/select-project-state.tsx`
- NoProjectsState: `apps/web-platform/components/connect-repo/no-projects-state.tsx`
- Repos endpoint: `apps/web-platform/app/api/repo/repos/route.ts`
- Install endpoint: `apps/web-platform/app/api/repo/install/route.ts`
- Existing test patterns: `apps/web-platform/test/install-route.test.ts`, `disconnect-route.test.ts`
