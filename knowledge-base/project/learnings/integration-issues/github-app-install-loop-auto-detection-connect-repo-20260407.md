---
module: Web Platform
date: 2026-04-07
problem_type: integration_issue
component: authentication
symptoms:
  - "Users with GitHub App already installed get redirected to GitHub install page"
  - "GitHub does not redirect back to Soleur after repo access changes on already-installed app"
  - "Reloading Soleur in another tab creates infinite loop at /connect-repo"
  - "github_installation_id is NULL despite app being installed on GitHub"
root_cause: incomplete_setup
resolution_type: code_fix
severity: high
tags: [github-app, connect-repo, installation-detection, redirect-loop, onboarding]
---

# Troubleshooting: GitHub App Install Redirect Loop When App Already Installed

## Problem

Users who already have the Soleur GitHub App installed on their GitHub account get stuck in an infinite redirect loop during project setup. The connect-repo flow always sends them to GitHub's install page instead of detecting the existing installation, and GitHub may not redirect back after configuration changes.

## Environment

- Module: Web Platform (connect-repo onboarding flow)
- Affected Component: `apps/web-platform/app/(auth)/connect-repo/page.tsx`, `apps/web-platform/server/github-app.ts`, `apps/web-platform/app/api/repo/` routes
- Date: 2026-04-07

## Symptoms

- Clicking "Connect Existing" always redirects to GitHub App install page even when the app is installed
- After changing repo access on GitHub's app settings page, GitHub does not redirect back to Soleur
- Reloading Soleur in another tab sends the user right back to `/connect-repo` (callback route checks `repo_status` = `"not_connected"`)
- The `github_installation_id` column in the `users` table is NULL despite the app being installed on GitHub

## What Didn't Work

**Attempted Solution 1 (PR #1677):** On-click fetch pattern — check `/api/repo/repos` before redirecting to GitHub.

- **Why it was insufficient:** This only works when `github_installation_id` is already stored in the database. If the install callback from GitHub never fired (user installed app directly from GitHub, or GitHub didn't redirect back after `setup_action=update`), the installation ID is never stored. `/api/repo/repos` returns 400 → falls through to GitHub redirect → loop.

## Session Errors

**Test failure from on-mount auto-detection interference**

- **Recovery:** Used a counter-based mock that returns `{ installed: false }` on the first call (mount-time) and `{ installed: true }` on the second call (user-action time), preventing mount-time detection from changing state before the test interacts with the UI.
- **Prevention:** When adding on-mount async effects that change component state, always verify existing tests still see the expected initial state. Counter-based mocks are a reliable pattern for testing multi-call flows where the same endpoint should return different results at different lifecycle stages.

## Solution

Three-pronged fix:

**1. Server: `findInstallationForLogin()` in `github-app.ts`**

Uses GitHub's `GET /users/{login}/installation` API (authenticated with App JWT) to check if the app is installed on a user's GitHub account without requiring the install callback.

```typescript
// New function in server/github-app.ts
export async function findInstallationForLogin(
  githubLogin: string,
): Promise<number | null> {
  const jwt = createAppJwt();
  const response = await githubFetch(
    `${GITHUB_API}/users/${encodeURIComponent(githubLogin)}/installation`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );
  if (!response.ok) return null;
  const data = await response.json();
  return typeof data.id === "number" ? data.id : null;
}
```

**2. API: `POST /api/repo/detect-installation` endpoint**

New endpoint that:

1. Checks if `github_installation_id` is already stored (fast path)
2. Resolves the user's GitHub login from their Supabase identity
3. Calls `findInstallationForLogin()` to detect existing installations
4. Verifies ownership via `verifyInstallationOwnership()`
5. Stores the installation ID in the `users` table
6. Returns repos from the detected installation

**3. Client: Auto-detection in connect-repo page**

- **On mount:** Calls `POST /api/repo/detect-installation` to auto-detect and skip to repo selection (breaks the redirect loop for users returning without callback params)
- **handleConnectExisting():** After `/api/repo/repos` returns 400, tries detection before falling through to GitHub redirect
- **handleCreateSubmit():** After create returns 400 (no installation), tries detection then retries the create

## Why This Works

**Root cause:** The previous fix (PR #1677) assumed `github_installation_id` would always be in the database if the app was installed. But the installation callback (`setup_action=install|update`) can fail to fire when:

1. The user installs the app directly from GitHub (not through Soleur's flow)
2. GitHub's install page shows "already installed" and the user clicks "Configure" which takes them to a settings page that does NOT redirect back via `setup_url`
3. The network request to register the callback fails silently

The fix adds a server-side detection layer using GitHub's `GET /users/{login}/installation` API, which works regardless of whether the callback fired. This detection runs proactively on page mount and reactively when the client-side flow would otherwise redirect to GitHub.

## Prevention

- When building OAuth/App install flows, never assume the callback will always fire. Add server-side detection as a fallback using the platform's API (GitHub's `GET /users/{login}/installation` in this case).
- Test the full flow including the "app already installed" path, not just the fresh install path.
- When GitHub App configuration changes happen on GitHub's settings page (vs the `/installations/new` page), no redirect occurs — the app must detect this state independently.

## Related Issues

- See also: [supabase-identities-null-email-first-users-20260403.md](./supabase-identities-null-email-first-users-20260403.md) — related issue where `github_installation_id` was NULL for all users
- See also: [2026-04-03-github-app-install-url-404.md](./2026-04-03-github-app-install-url-404.md) — earlier connect-repo onboarding failure
- See also: [2026-04-06-supabase-server-side-connectivity-docker-container.md](./2026-04-06-supabase-server-side-connectivity-docker-container.md) — related GitHub App install/create issues
