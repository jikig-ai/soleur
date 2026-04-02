---
title: "security: verify GitHub App installation ID ownership before storing"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# security: verify GitHub App installation ID ownership before storing

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 4 (Proposed Solution, Test Scenarios, Context, new Edge Cases section)
**Research sources:** GitHub REST API docs (Context7), Supabase Auth docs, 3 institutional learnings

### Key Improvements

1. Organization installation edge case identified and handled -- `account.type` can be "Organization", requiring membership verification instead of login comparison
2. Negative-space test pattern applied from institutional learning -- structural enforcement prevents future IDOR regressions
3. Rate limiting consideration for the GitHub API call added to prevent abuse of the verification endpoint itself
4. `SECURITY:` inline comment convention applied from adjacent-config-audit learning

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

Add a `verifyInstallationOwnership(installationId: number, githubLogin: string): Promise<{ verified: boolean; error?: string; status?: number }>` function to `server/github-app.ts`. This keeps the GitHub API interaction co-located with existing GitHub App code and makes it testable in isolation.

```typescript
// apps/web-platform/server/github-app.ts

interface InstallationAccount {
  login: string;
  id: number;
  type: string; // "User" or "Organization"
}

interface VerifyResult {
  verified: boolean;
  error?: string;
  status?: number; // HTTP status to return to client
}

export async function verifyInstallationOwnership(
  installationId: number,
  expectedLogin: string,
): Promise<VerifyResult> {
  const jwt = createAppJwt();
  const response = await githubFetch(
    `${GITHUB_API}/app/installations/${installationId}`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    if (response.status === 404) {
      return { verified: false, error: "Installation not found", status: 404 };
    }
    log.error(
      { status: response.status, installationId },
      "GitHub API error during installation verification",
    );
    return { verified: false, error: "Failed to verify installation", status: 502 };
  }

  const data = (await response.json()) as { account?: InstallationAccount };
  const account = data.account;
  if (!account?.login) {
    return { verified: false, error: "Installation has no account", status: 502 };
  }

  // SECURITY: Case-insensitive comparison -- GitHub usernames are case-insensitive
  if (account.type === "User") {
    return {
      verified: account.login.toLowerCase() === expectedLogin.toLowerCase(),
      error: account.login.toLowerCase() !== expectedLogin.toLowerCase()
        ? "Installation does not belong to this user"
        : undefined,
      status: account.login.toLowerCase() !== expectedLogin.toLowerCase() ? 403 : undefined,
    };
  }

  // Organization installations: account.login is the org name, not the user.
  // For MVP, reject org installations. See Edge Cases section for future handling.
  log.warn(
    { installationId, orgLogin: account.login, expectedLogin },
    "Organization installation not yet supported for ownership verification",
  );
  return {
    verified: false,
    error: "Organization installations are not yet supported",
    status: 403,
  };
}
```

### Research Insights: Verification Function

**GitHub API response shape (verified via Context7 docs):**

The `GET /app/installations/{installation_id}` endpoint returns:

- `account.login` (string) -- username or organization name
- `account.id` (integer) -- numeric GitHub user/org ID
- `account.type` (string) -- "User" or "Organization"

**Best practices applied:**

- Return structured `{ verified, error, status }` instead of throwing -- the caller can map directly to HTTP responses without try/catch
- Use the existing `log` child logger for structured error context
- Add `SECURITY:` inline comment on the case-insensitive comparison to prevent accidental removal during refactors (per learning: [adjacent-config-audit](../../learnings/2026-03-20-security-refactor-adjacent-config-audit.md))
- Type the API response with a local interface rather than `any`

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
- [ ] Returns 403 for organization installations (MVP scope -- see Edge Cases)
- [ ] Test covers the case where installation ID does not belong to the user (mocked)
- [ ] Test covers the happy path (installation matches user)
- [ ] No regression in the existing connect-repo onboarding flow

## Test Scenarios

- Given an authenticated user with GitHub login "alice", when they POST an installationId whose `account.login` is "alice" and `account.type` is "User", then the installation ID is stored successfully (200)
- Given an authenticated user with GitHub login "alice", when they POST an installationId whose `account.login` is "bob", then the server returns 403
- Given an authenticated user with GitHub login "alice", when they POST a non-existent installationId (GitHub returns 404), then the server returns 404
- Given an authenticated user with no GitHub identity (email-only signup), when they POST any installationId, then the server returns 403
- Given an authenticated user with GitHub login "alice", when they POST an installationId whose `account.type` is "Organization", then the server returns 403 with "Organization installations are not yet supported"
- Given an authenticated user with GitHub login "Alice" (uppercase), when they POST an installationId whose `account.login` is "alice" (lowercase), then the installation ID is stored successfully (case-insensitive match)
- Given an unauthenticated request, when they POST any installationId, then the server returns 401 (existing behavior, regression check)
- Given the GitHub API returns a 500 error during verification, when a user POSTs a valid installationId, then the server returns 502 (upstream failure, not stored)

### Research Insights: Test Strategy

**Negative-space test pattern** (from learning: [structural enforcement](../../learnings/2026-03-20-csrf-prevention-structural-enforcement-via-negative-space-tests.md)):

Consider adding a structural test that verifies the install route calls `verifyInstallationOwnership` before `serviceClient.from("users").update()`. This prevents future regressions where a refactor might accidentally remove the verification call:

```typescript
// Structural verification: the install route must verify before storing
test("install route calls verifyInstallationOwnership before storing", () => {
  const routeSource = readFileSync(
    "app/api/repo/install/route.ts",
    "utf-8",
  );
  const verifyIndex = routeSource.indexOf("verifyInstallationOwnership");
  const updateIndex = routeSource.indexOf('.update({ github_installation_id');
  expect(verifyIndex).toBeGreaterThan(-1);
  expect(updateIndex).toBeGreaterThan(-1);
  expect(verifyIndex).toBeLessThan(updateIndex);
});
```

**Mock strategy:** Mock `global.fetch` or the `githubFetch` helper to return controlled responses for the `GET /app/installations/{id}` call. Do not mock Supabase auth -- use the existing mock patterns from `apps/web-platform/test/` (e.g., `callback.test.ts` pattern).

## Edge Cases

### Organization installations (account.type === "Organization")

When a user installs the GitHub App on an organization (not their personal account), `account.login` is the org name, not the user's login. The simple login comparison fails.

**MVP approach (implemented above):** Reject organization installations with a clear error message. The connect-repo flow currently uses `/user/repos` which is scoped to user accounts, so org support is not yet needed.

**Future approach (tracked separately):** To support org installations, verify the user is a member of the organization by calling `GET /orgs/{org}/memberships/{username}` with the installation token. This requires an additional API call but correctly handles the ownership chain: user -> org member -> org owns installation.

### GitHub API rate limits

The `GET /app/installations/{id}` endpoint is rate-limited to 5,000 requests per hour per App JWT. Each install verification adds one API call. This is unlikely to be a bottleneck (would require 5,000 installations per hour), but the rate limit should be monitored.

**Mitigation:** The existing install flow is a one-time event per user (during onboarding). If abuse is detected (many verification requests from the same user), the existing CSRF/auth layer already limits this to authenticated users.

### GitHub API downtime

If the GitHub API is unreachable during verification, the user cannot complete installation. This is acceptable -- the installation flow already depends on GitHub being available (the redirect comes from GitHub). Return 502 and let the user retry.

### Supabase user_metadata population timing

`user_metadata.user_name` is populated during the GitHub OAuth flow. If a user signs up with email/OTP and later links a GitHub account, the metadata may not be immediately available. The fallback to `user.identities` array handles this case, as identities are updated when providers are linked.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- security fix for an existing endpoint with no user-facing changes.

## Context

- The GitHub App installation flow is documented in the [repo connection learning](../../learnings/2026-03-29-repo-connection-implementation.md)
- The `createAppJwt()` function already exists in `server/github-app.ts` and produces the RS256 JWT needed for the `GET /app/installations/{id}` call
- The `githubFetch()` helper already exists and handles GitHub API headers (Accept, X-GitHub-Api-Version)
- Supabase populates `user_metadata.user_name` with the GitHub login when users authenticate via GitHub OAuth
- The GitHub API `GET /app/installations/{installation_id}` endpoint returns `{ account: { login: string, id: number, type: string }, ... }` and is documented at [GitHub Apps REST API](https://docs.github.com/en/rest/apps/apps#get-an-installation-for-the-authenticated-app)

### Research Insights: Institutional Learnings Applied

Three institutional learnings directly inform this fix:

1. **[Attack surface enumeration](../../learnings/2026-03-20-security-fix-attack-surface-enumeration.md):** "Enumerate the full attack surface, not just the reported vector." The plan's Attack Surface Enumeration table covers all 6 code paths that touch `github_installation_id`. Only the install route accepts untrusted input.

2. **[Negative-space structural enforcement](../../learnings/2026-03-20-csrf-prevention-structural-enforcement-via-negative-space-tests.md):** "When a security property should be always present, enforce it via a test, not documentation." The structural test in the Test Scenarios section ensures the verification call cannot be accidentally removed during future refactors.

3. **[Adjacent config audit](../../learnings/2026-03-20-security-refactor-adjacent-config-audit.md):** "Add `SECURITY:` inline comments on critical config options to prevent accidental removal." The `verifyInstallationOwnership` function uses `// SECURITY:` comments on the case-insensitive comparison.

## References

- Related issue: #1381
- Target file: `apps/web-platform/app/api/repo/install/route.ts`
- GitHub App module: `apps/web-platform/server/github-app.ts`
- Connect-repo page (client caller): `apps/web-platform/app/(auth)/connect-repo/page.tsx`
- GitHub API docs: [Get an installation for the authenticated app](https://docs.github.com/en/rest/apps/apps#get-an-installation-for-the-authenticated-app)
