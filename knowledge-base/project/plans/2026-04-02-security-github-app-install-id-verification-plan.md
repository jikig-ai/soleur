---
title: "security: verify GitHub App installation ID ownership before storing"
type: fix
date: 2026-04-02
---

# security: verify GitHub App installation ID ownership before storing

## Overview

The `POST /api/repo/install` endpoint accepts a `github_installation_id` from the client and stores it directly on the user record without verifying the authenticated user actually owns that GitHub App installation. Installation IDs are sequential integers visible in GitHub URLs, making them trivially guessable. An attacker who is authenticated on the platform could claim another user's GitHub App installation and gain access to their repositories.

**Source:** OWASP security audit finding (issue #1381)

## Problem Statement

**Location:** `apps/web-platform/app/api/repo/install/route.ts:28-39`

The current flow:

1. User installs the Soleur GitHub App on their GitHub account
2. GitHub redirects back with `installation_id` as a URL query parameter
3. The connect-repo page sends `POST /api/repo/install { installationId: <number> }` to the server
4. The server stores the installation ID on the user record without checking ownership

The vulnerability is an IDOR (Insecure Direct Object Reference): any authenticated user can supply any valid `installationId` and the server will store it. Downstream routes (`/api/repo/repos`, `/api/repo/setup`, `/api/repo/create`) then use this stored ID to generate GitHub App installation tokens scoped to the stolen installation.

## Proposed Solution

After receiving the `installationId`, call `GET /app/installations/{installation_id}` using the App JWT to verify the installation exists and retrieve the installation's `account.login`. Then compare it against the authenticated user's GitHub identity (available from Supabase `user.user_metadata` which is populated by the GitHub OAuth flow or from `user.identities` array).

### Implementation

Modify `apps/web-platform/app/api/repo/install/route.ts`:

1. After authentication, extract the user's GitHub username from Supabase auth metadata:
   - `user.user_metadata?.user_name` (GitHub login, set by Supabase GitHub OAuth provider)
   - Fallback to `user.identities?.find(i => i.provider === 'github')?.identity_data?.user_name`
   - If no GitHub identity found, return 403 (user signed in with a non-GitHub provider)

2. Call `GET https://api.github.com/app/installations/{installationId}` with the App JWT (reuse `createAppJwt()` from `server/github-app.ts`):
   - If 404 -> return 404 "Installation not found"
   - If other error -> return 502 "Failed to verify installation"

3. Compare `response.account.login` (case-insensitive) against the user's GitHub username:
   - If mismatch -> return 403 "Installation does not belong to this user"
   - If match -> proceed to store

### New helper function

Add a `verifyInstallationOwnership(installationId: number, githubLogin: string): Promise<boolean>` function to `server/github-app.ts`. This keeps the GitHub API interaction co-located with existing GitHub App code and makes it testable in isolation.

```typescript
// apps/web-platform/server/github-app.ts
export async function verifyInstallationOwnership(
  installationId: number,
  expectedLogin: string,
): Promise<{ verified: boolean; error?: string }> {
  const jwt = createAppJwt();
  const response = await githubFetch(
    `${GITHUB_API}/app/installations/${installationId}`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    return {
      verified: false,
      error: response.status === 404
        ? "Installation not found"
        : `GitHub API error: ${response.status}`,
    };
  }

  const data = await response.json();
  const actualLogin = data.account?.login;
  if (!actualLogin) {
    return { verified: false, error: "Installation has no account" };
  }

  return {
    verified: actualLogin.toLowerCase() === expectedLogin.toLowerCase(),
  };
}
```

### Attack Surface Enumeration

All code paths that touch `github_installation_id`:

| Path | Input Source | Needs Fix? |
|------|------------|-----------|
| `POST /api/repo/install` | Client-provided body parameter | **Yes -- this is the vulnerability** |
| `GET /api/repo/repos` | Reads from DB (`users.github_installation_id`) | No -- uses stored value |
| `POST /api/repo/setup` | Reads from DB | No -- uses stored value |
| `POST /api/repo/create` | Reads from DB | No -- uses stored value |
| `server/session-sync.ts` | Reads from DB | No -- uses stored value |
| `server/workspace.ts` | Receives from caller (setup route) | No -- caller reads from DB |

Only the `/api/repo/install` route accepts installation IDs from untrusted input. All other routes read the stored value from the database, which will be verified at write time after this fix.

## Acceptance Criteria

- [ ] Server-side ownership verification before storing installation ID
- [ ] `verifyInstallationOwnership()` function in `server/github-app.ts` calls `GET /app/installations/{id}` with App JWT
- [ ] Route compares `account.login` against user's GitHub identity (case-insensitive)
- [ ] Returns 403 when installation does not belong to the authenticated user
- [ ] Returns 404 when installation does not exist
- [ ] Returns 403 when user has no GitHub identity (signed in with non-GitHub provider)
- [ ] Test covers the case where installation ID does not belong to the user (mocked)
- [ ] Test covers the happy path (installation matches user)
- [ ] No regression in the existing connect-repo onboarding flow

## Test Scenarios

- Given an authenticated user with GitHub login "alice", when they POST an installationId whose `account.login` is "alice", then the installation ID is stored successfully (200)
- Given an authenticated user with GitHub login "alice", when they POST an installationId whose `account.login` is "bob", then the server returns 403
- Given an authenticated user with GitHub login "alice", when they POST a non-existent installationId (GitHub returns 404), then the server returns 404
- Given an authenticated user with no GitHub identity (email-only signup), when they POST any installationId, then the server returns 403
- Given an unauthenticated request, when they POST any installationId, then the server returns 401 (existing behavior, regression check)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- security fix for an existing endpoint with no user-facing changes.

## Context

- The GitHub App installation flow is documented in the [repo connection learning](../../learnings/2026-03-29-repo-connection-implementation.md)
- The `createAppJwt()` function already exists in `server/github-app.ts` and produces the RS256 JWT needed for the `GET /app/installations/{id}` call
- The `githubFetch()` helper already exists and handles GitHub API headers
- Supabase populates `user_metadata.user_name` with the GitHub login when users authenticate via GitHub OAuth
- The GitHub API `GET /app/installations/{installation_id}` endpoint returns `{ account: { login: string, id: number, type: string }, ... }` and is documented at [GitHub Apps REST API](https://docs.github.com/en/rest/apps/apps#get-an-installation-for-the-authenticated-app)

## References

- Related issue: #1381
- Target file: `apps/web-platform/app/api/repo/install/route.ts`
- GitHub App module: `apps/web-platform/server/github-app.ts`
- Connect-repo page (client caller): `apps/web-platform/app/(auth)/connect-repo/page.tsx`
- GitHub API docs: [Get an installation for the authenticated app](https://docs.github.com/en/rest/apps/apps#get-an-installation-for-the-authenticated-app)
