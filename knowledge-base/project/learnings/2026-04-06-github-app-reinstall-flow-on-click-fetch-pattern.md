---
module: ConnectRepo
date: 2026-04-06
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Users redirected to GitHub even when the app is already installed"
  - "setup_action=update callback silently ignored, stranding users"
  - "No way to refresh repo list without full page reload"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [github-app, connect-repo, state-machine, on-click-fetch, visibilitychange]
---

# Learning: On-Click Fetch Pattern for GitHub App Installation Detection

## Problem

The `/connect-repo` page always redirected users to GitHub to install the app, even when the installation was already complete. Additionally, GitHub's `setup_action=update` callback was silently ignored because the code only checked for `setup_action=install`.

## Solution

Three changes to the connect-repo state machine:

1. **Broadened callback handler** to accept both `setup_action=install` and `setup_action=update` — a 2-line change at the `useState` initializer and the `useEffect` guard.

2. **On-click fetch instead of mount-time speculative fetch** — `handleConnectExisting` tries `GET /api/repo/repos` inline when clicked. If 200, shows repos directly (skip redirect). If 400 or network error, falls through to GitHub redirect. Same pattern for `handleCreateSubmit`: tries `POST /api/repo/create` directly, falls back to sessionStorage + redirect on 400.

3. **Error-safe `refreshRepos` wrapper + `visibilitychange` listener** — `refreshRepos` catches errors silently (keeps current state), gated by `stateRef` (only runs in `select_project` or `no_projects`), throttled by `reposLoading`. Refresh button added to both `SelectProjectState` and `NoProjectsState`.

## Key Insight

When a page component needs to detect server state (like "does the user have an installation?") before deciding a UI path, prefer **on-click async fetch** over **mount-time speculative fetch**. The on-click pattern:

- Eliminates race conditions (user clicking before mount check resolves)
- Avoids stale data (no preloaded repos going stale while user sits on the page)
- Requires zero new state variables (no `hasInstallation`, no `preloadedRepos`)
- The API response at click-time is the single source of truth

This was validated by three independent plan reviewers (DHH, Kieran, code-simplicity) who all converged on the same recommendation.

## Prevention

- When adding installation detection or feature-gating to UI flows, check on-click rather than on-mount unless the check result affects the initial render (e.g., showing/hiding a button).
- When reusing `fetchRepos` (or similar state-transitioning functions) as a refresh handler, create an error-safe wrapper that keeps the current state on failure instead of transitioning to an error state.

## Tags

category: ui-bugs
module: ConnectRepo
