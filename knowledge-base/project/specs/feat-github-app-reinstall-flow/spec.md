# Spec: GitHub App Reinstall Flow Improvement

**Issue:** TBD
**Branch:** feat-github-app-reinstall-flow
**Brainstorm:** [2026-04-06-github-app-reinstall-flow-brainstorm.md](../../brainstorms/2026-04-06-github-app-reinstall-flow-brainstorm.md)

## Problem Statement

When the Soleur GitHub App is already installed, the `/connect-repo` page still redirects users to GitHub to "install" it. On GitHub's configure page, changing repo access and clicking Save either doesn't redirect back to Soleur or redirects with `setup_action=update` which the callback ignores. Users get stranded.

## Goals

- Eliminate unnecessary GitHub redirect when the app is already installed
- Handle `setup_action=update` callback so permission changes are processed
- Provide auto-refresh and manual refresh for the repo list

## Non-Goals

- Webhook handling for installation revocation events (separate feature)
- Background installation health checks
- Periodic re-verification of installation ownership

## Functional Requirements

### FR1: Skip GitHub redirect when installation exists

On the `/connect-repo` page, check if the user already has a `github_installation_id` stored. If yes:

- **Connect Existing:** Call `GET /api/repo/repos` directly instead of redirecting to GitHub. Show `select_project` or `no_projects` based on result.
- **Create New:** After project name input, call `POST /api/repo/create` directly instead of redirecting to GitHub.

If no installation exists, fall through to the current GitHub redirect flow.

### FR2: Handle `setup_action=update` callback

Broaden the callback handler in `connect-repo/page.tsx` to accept both `setup_action=install` and `setup_action=update`. Both should trigger the same flow: register/update installation ID, then fetch repos or handle pending create.

### FR3: Auto-refresh repo list on window focus

Add a `visibilitychange` event listener that re-fetches repos when the user returns to the Soleur tab (from `select_project` or `no_projects` state).

### FR4: Manual Refresh button

Add a "Refresh" button to `SelectProjectState` and `NoProjectsState` components that re-fetches the repo list on click.

## Technical Requirements

### TR1: Installation detection

Use the existing `GET /api/repo/repos` endpoint for installation detection. A 400 response with "GitHub App not installed" indicates no installation; a 200 response (with or without repos) confirms installation exists.

### TR2: No new API endpoints

All changes are frontend-only (state machine logic in `page.tsx` and component updates). No new API routes needed.

### TR3: Callback broadening

In `page.tsx`, change the `setup_action` check from `=== "install"` to include `"update"`. This applies in both the `useState` initializer (line 57) and the `useEffect` callback (line 91).

### TR4: Debounced auto-refresh

The `visibilitychange` listener should debounce re-fetches to avoid rapid-fire API calls when the user switches tabs quickly.

## Test Scenarios

1. User with existing installation clicks "Connect Existing" -- skips GitHub redirect, shows repo list
2. User with existing installation clicks "Create New" -- skips GitHub redirect, creates repo directly
3. User without installation clicks "Connect Existing" -- goes through GitHub redirect (current flow)
4. User returns from GitHub with `setup_action=update` -- callback processes correctly
5. User switches to GitHub tab, updates access, returns -- repo list auto-refreshes
6. User clicks Refresh button on repo list -- repos re-fetched
7. User clicks Refresh on empty repo list -- repos re-fetched
