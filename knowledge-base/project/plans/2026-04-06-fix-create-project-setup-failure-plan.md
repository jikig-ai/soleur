---
title: "fix: create project setup failure — SSL certs, org repo creation, error resilience"
type: fix
date: 2026-04-06
deepened: 2026-04-06
---

# fix: create project setup failure — SSL certs, org repo creation, error resilience

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 4 (Implementation Detail, Technical Considerations, Test Scenarios, References)
**Research sources:** GitHub REST API docs (Context7), 3 institutional learnings, existing test patterns (`github-app-pr.test.ts`, `install-route-handler.test.ts`)

### Key Improvements

1. Discovered missing `administration:write` permission on GitHub App -- org repo creation will fail even with the correct API endpoint without this permission. Added as Phase 0 prerequisite.
2. Added concrete implementation details for `getInstallationAccount()` helper with response typing from GitHub API docs.
3. Added token cache isolation pattern from org membership learning -- each test must use a unique `installationId` to avoid cache interference.
4. Added `createRepo` error message extraction pattern matching the existing `createPullRequest` error handling (lines 448-465 of `github-app.ts`).

## Problem

Users clicking "Create Project" (Start Fresh flow) or "Connect Existing Repository" see "Project Setup Failed" with the message: "Something went wrong while setting up your project. This is usually a temporary issue." The failure is not temporary and persists on retry.

## Root Cause Analysis

Investigation via Sentry API and code analysis reveals three compounding issues:

### RC1: Missing CA certificates in Docker runner (FIXED — deploying)

**Status:** Fixed in PR #1645 (merged 2026-04-06, deployment in progress as v0.14.3)

The `node:22-slim` Docker base image does not include `ca-certificates`. Git HTTPS operations fail with:

```text
fatal: unable to access 'https://github.com/...': server certificate verification failed.
CAfile: none CRLfile: none
```

**Evidence:** Sentry issue #110097747 — single event at 2026-04-06T13:39:56Z.

The fix adds `ca-certificates` to the `apt-get install` line in the runner stage. This is currently deploying and should resolve the primary failure path.

### RC2: `createRepo` uses wrong GitHub API endpoint for organization installations

**Status:** Unfixed — active bug in code (two sub-issues)

**Location:** `apps/web-platform/server/github-app.ts:385-399`

The `createRepo` function uses `POST /user/repos` with a GitHub App installation token. This endpoint creates repositories under the authenticated user's account. However, GitHub App installation tokens do not have a "user" identity — they authenticate as the app itself.

For **user-account installations** (personal GitHub accounts), this works because GitHub routes the request through the installation's target account. For **organization installations** (like `jikig-ai` with installation ID 121112974), the request fails because:

1. The installation token is scoped to the org, not a personal account
2. `POST /user/repos` requires a user-scoped token (PAT or OAuth), not an app installation token
3. GitHub returns a 403 or 404 error

The correct endpoint for organization installations is `POST /orgs/{org}/repos`. The function needs to determine whether the installation is on a user account or an organization, then call the appropriate endpoint.

### Research Insights (GitHub REST API)

**Critical: Missing GitHub App permission.** Per the GitHub REST API docs, `POST /orgs/{org}/repos` requires `"Administration" repository permissions (write)` for fine-grained tokens (including GitHub App installation access tokens). The current GitHub App (`soleur-ai`, App ID 3261325) only has `contents:read+write`, `metadata:read`, `members:read` (per learning `github-app-install-url-404`). The `administration:write` permission must be added to the GitHub App before the endpoint fix will work.

**`POST /user/repos` does NOT require `administration:write`** -- it uses legacy scope-based auth (`repo` scope). This is why the user-account path works without the permission.

**Request/response format is identical** between `/user/repos` and `/orgs/{org}/repos` for the fields used by `createRepo`: `name`, `private`, `auto_init`, `description`. The response always includes `html_url` and `full_name`. No request body changes needed.

**Impact:** The "Start Fresh" (Create Project) flow fails for all organization-installed GitHub Apps. The "Connect Existing" flow is not affected because it uses `git clone`, not the repo creation API.

### RC3: "Start Fresh" flow silently fails with no error context

**Status:** Unfixed — poor error handling

**Location:** `apps/web-platform/app/(auth)/connect-repo/page.tsx:122-134`

When the `POST /api/repo/create` call fails, the page transitions directly to `setState("failed")` without:

1. Reading the error response body from the server
2. Passing the error to `setSetupError()` for display in `FailedState`
3. Logging any diagnostic information

The user sees a generic "Project Setup Failed" page with no error details card (because `setupError` is null). Compare this with the `startSetup` flow (lines 209-225) which also lacks error extraction from the response body.

Additionally, the `POST /api/repo/create` route handler (line 67-76) catches errors but returns a generic `"Failed to create repository"` message without including the GitHub API error. The GitHub API response (e.g., "Repository creation failed: 403 Forbidden" or "name already exists on this account") is logged server-side but never returned to the client.

## Implementation Plan

### Phase 0: Add `administration:write` permission to GitHub App (prerequisite)

**Goal:** Enable the GitHub App to create repositories in organizations.

This is a configuration change, not a code change. Without this permission, `POST /orgs/{org}/repos` returns 403 even with the correct endpoint.

#### Task 0.1: Update GitHub App permissions via Playwright

Navigate to `https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/permissions` and add `Repository permissions > Administration: Read and write`. After saving, existing installations must approve the new permission (GitHub sends an email to org admins). For the `jikig-ai` org, the founder is the admin so approval is immediate.

**Verification:** After approval, query `GET /app/installations/121112974` with the App JWT and verify `permissions.administration` is `"write"` in the response.

### Phase 1: Fix organization repo creation

**Goal:** Make `createRepo` work for both user and organization GitHub App installations.

#### Task 1.1: Extract `getInstallationAccount` helper

**File:** `apps/web-platform/server/github-app.ts`

Extract the installation account lookup from `verifyInstallationOwnership` (lines 195-215) into a reusable helper. This avoids duplicating the JWT + `GET /app/installations/{id}` call in `createRepo`:

```typescript
/**
 * Fetch the account (user or org) that owns a GitHub App installation.
 * Used by verifyInstallationOwnership and createRepo to determine
 * whether the installation is on a user account or an organization.
 */
async function getInstallationAccount(
  installationId: number,
): Promise<InstallationAccount> {
  const jwt = createAppJwt();
  const response = await githubFetch(
    `${GITHUB_API}/app/installations/${installationId}`,
    { headers: { Authorization: `Bearer ${jwt}` } },
  );

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error("Installation not found");
    }
    throw new Error(
      `Failed to fetch installation: ${response.status}`,
    );
  }

  const data = (await response.json()) as {
    account?: InstallationAccount;
  };
  if (!data.account?.login) {
    throw new Error("Installation has no account");
  }
  return data.account;
}
```

Then refactor `verifyInstallationOwnership` to call `getInstallationAccount` instead of duplicating the fetch.

#### Task 1.2: Route `createRepo` to the correct endpoint

**File:** `apps/web-platform/server/github-app.ts`

Update `createRepo` to use `getInstallationAccount` and branch on account type:

```typescript
export async function createRepo(
  installationId: number,
  name: string,
  isPrivate: boolean,
): Promise<{ repoUrl: string; fullName: string }> {
  const account = await getInstallationAccount(installationId);
  const token = await generateInstallationToken(installationId);

  const endpoint = account.type === "Organization"
    ? `${GITHUB_API}/orgs/${account.login}/repos`
    : `${GITHUB_API}/user/repos`;

  const response = await githubFetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `token ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name,
      private: isPrivate,
      auto_init: true,
      description: "Knowledge base managed by Soleur",
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    // Extract useful error from GitHub response (same pattern as createPullRequest)
    let errorMessage = `GitHub create repo failed: ${response.status}`;
    try {
      const parsed = JSON.parse(body);
      if (parsed.errors?.[0]?.message) {
        errorMessage = parsed.errors[0].message;
      } else if (parsed.message) {
        errorMessage = `GitHub create repo failed: ${response.status} - ${parsed.message}`;
      }
    } catch {
      // Non-JSON response
    }
    log.error(
      { status: response.status, body: body.slice(0, 500), installationId, name },
      "Failed to create repo",
    );
    throw new Error(errorMessage);
  }

  const data = (await response.json()) as GitHubRepoResponse;
  return {
    repoUrl: data.html_url,
    fullName: data.full_name,
  };
}
```

### Research Insights (Implementation Detail)

**Error message extraction:** The current `createRepo` throws a generic `GitHub create repo failed: ${response.status}` that swallows the actual error. The existing `createPullRequest` function (lines 448-465) already implements proper error extraction from the GitHub API response, parsing `errors[0].message` and `message` fields. Apply the same pattern to `createRepo`.

**Token cache isolation (from learning `github-org-membership-api-redirect-handling-20260402`):** The `tokenCache` Map in `github-app.ts` is module-level and persists across vitest tests. Each test for `createRepo` must use a unique `installationId` to avoid cache interference. The existing `github-app-pr.test.ts` already uses a `uniqueInstallationId()` helper (lines 37-39) -- follow the same pattern.

**No caching of account metadata:** The extra `GET /app/installations/{id}` call during `createRepo` is acceptable. It adds ~100ms to a low-frequency operation (create project happens once per user). Caching account metadata would add complexity with no meaningful benefit -- the installation's account type never changes.

**`redirect: "manual"` not needed here:** Unlike the org membership check in `verifyInstallationOwnership`, the `GET /app/installations/{id}` endpoint does not redirect. The `redirect: "manual"` pattern from the org membership learning is specific to `GET /orgs/{org}/members/{username}`.

### Phase 2: Improve error propagation in the "Create Project" flow

**Goal:** Surface actionable error messages to the user.

#### Task 2.1: Add Sentry capture and specific error return to `POST /api/repo/create`

**File:** `apps/web-platform/app/api/repo/create/route.ts`

Two changes to the catch handler (lines 67-76):

1. Add `import * as Sentry from "@sentry/nextjs"` (currently not imported in this route)
2. Add `Sentry.captureException(err)` before the response
3. Return the actual error message from `createRepo` instead of the generic string

```typescript
catch (err) {
  logger.error(
    { err, userId: user.id, repoName: name },
    "Failed to create repository",
  );
  Sentry.captureException(err);
  const message = err instanceof Error ? err.message : "Failed to create repository";
  return NextResponse.json({ error: message }, { status: 500 });
}
```

### Research Insights (Error Handling)

**Consistency with `setup/route.ts`:** The setup route (lines 121-138) already has `Sentry.captureException(err)` and stores the truncated error message in `repo_error`. The create route should follow the same pattern. However, `repo_error` persistence is NOT needed for create failures because the repo creation happens synchronously (not in a background task) -- the error is returned directly in the HTTP response.

**Error message sanitization:** The `createRepo` function (after Task 1.2 changes) extracts the error message from GitHub's response body. GitHub error messages are safe to display to users -- they contain field names and validation messages, not internal paths. No additional sanitization is needed (unlike git stderr which is sanitized in `workspace.ts:170` to strip filesystem paths).

**Learning applied (`silent-setup-failure-no-error-capture-20260403`):** Background tasks that fire-and-forget need Sentry + DB persistence + user display at the catch site. Synchronous routes only need Sentry + user display (the HTTP response IS the display channel). The create route is synchronous, so Sentry + response error is sufficient.

#### Task 2.2: Surface create-repo errors in the client

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

Update the create-repo callback (lines 122-134) to read the error from the response and display it:

```typescript
if (!createRes.ok) {
  const data = await createRes.json().catch(() => null);
  setSetupError(data?.error ?? "Failed to create repository");
  setState("failed");
  return;
}
```

**Edge case:** If the server returns a non-JSON response (e.g., 502 from a proxy), `.json().catch(() => null)` returns null and the fallback message is used. This is correct.

#### Task 2.3: Surface setup POST errors in the client

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

In the `startSetup` function (lines 209-225), when `POST /api/repo/setup` returns a non-200 response, read the error body:

```typescript
if (!res.ok) {
  if (stepTimerRef.current) clearInterval(stepTimerRef.current);
  const data = await res.json().catch(() => null);
  setSetupError(data?.error ?? "Failed to start project setup");
  setState("failed");
  return;
}
```

**Edge case:** The setup route returns `{ error: "Setup already in progress" }` with status 409 when a concurrent request is detected (optimistic lock, line 83-87). This message will now be surfaced to the user, which is correct -- it tells them why "Try Again" appears to do nothing.

### Phase 3: Post-deploy verification

**Goal:** Verify the full setup flow works end-to-end after RC1 fix deploys.

#### Task 3.1: Verify CA certificates fix is deployed

Query the health endpoint to confirm v0.14.3+ is running. Query Sentry to confirm no new "server certificate verification failed" errors appear after deploy.

#### Task 3.2: End-to-end flow test via Playwright

Authenticate via OTP and walk through both flows:

1. **Connect Existing:** Select an existing repo, verify clone succeeds
2. **Create New:** Enter a project name, verify repo creation + clone succeeds

#### Task 3.3: Cleanup Sentry

Resolve the two stale unresolved issues in Sentry:

- "Workspace cleanup failed. Some files may be owned by root..." (fixed in #1540)
- "Git clone failed: ...server certificate verification failed..." (fixed in #1645)

## Acceptance Criteria

- [ ] The GitHub App has `administration:write` repository permission (required for `POST /orgs/{org}/repos`) — Phase 0, requires Playwright
- [x] `getInstallationAccount` helper is extracted and reused by both `verifyInstallationOwnership` and `createRepo`
- [x] `createRepo` uses `POST /orgs/{org}/repos` for organization installations
- [x] `createRepo` continues to use `POST /user/repos` for user-account installations
- [x] `createRepo` extracts specific error messages from GitHub API responses (matching `createPullRequest` pattern)
- [x] `POST /api/repo/create` returns specific error messages from the GitHub API (not just "Failed to create repository")
- [x] `POST /api/repo/create` reports errors to Sentry via `captureException`
- [x] The client displays specific error messages in the `FailedState` component when repo creation fails
- [x] The client displays specific error messages when `POST /api/repo/setup` returns a non-200 response
- [ ] The "Start Fresh" flow completes successfully for an organization installation (creates repo + clones) — E2E post-deploy
- [ ] The "Connect Existing" flow completes successfully after ca-certificates fix deploys — E2E post-deploy
- [ ] No new unresolved Sentry errors related to project setup appear within 24 hours of deploy — E2E post-deploy

## Test Scenarios

### Unit Tests (`apps/web-platform/test/github-app-create-repo.test.ts`)

Follow the existing test pattern from `github-app-pr.test.ts`: generate a real RSA key, set env vars before imports, mock `globalThis.fetch`, and use `uniqueInstallationId()` for token cache isolation.

- Given an organization installation (account type "Organization", login "my-org"), when `createRepo` is called, then the repo creation fetch is sent to `https://api.github.com/orgs/my-org/repos` (not `/user/repos`)
- Given a user-account installation (account type "User", login "alice"), when `createRepo` is called, then the repo creation fetch is sent to `https://api.github.com/user/repos`
- Given the GitHub API returns 422 with `{ "message": "Validation Failed", "errors": [{ "message": "name already exists on this account" }] }`, when `createRepo` is called, then the thrown error message contains "name already exists on this account"
- Given the installation lookup returns 404, when `createRepo` is called, then it throws with message matching `/Installation not found/`
- Given `getInstallationAccount` is extracted, when `verifyInstallationOwnership` is called for an org installation, then it delegates to `getInstallationAccount` (existing org verification tests should still pass)

### Testing approach (mock sequence per test)

Each test requires this mock sequence (same pattern as `github-app-pr.test.ts`):

1. **Mock 1:** `GET /app/installations/{id}` -- returns `{ account: { login, type } }` (for `getInstallationAccount`)
2. **Mock 2:** `POST /app/installations/{id}/access_tokens` -- returns `{ token, expires_at }` (for `generateInstallationToken`)
3. **Mock 3:** `POST /orgs/{org}/repos` or `POST /user/repos` -- returns `{ html_url, full_name, ... }` (for repo creation)

**Token cache isolation:** Use unique `installationId` per test (starting from a range that does not collide with existing test files: `github-app-pr.test.ts` starts at 9000, `install-route-handler.test.ts` uses 1-100 range). Start at 8000 for this file.

### Route Handler Tests (`apps/web-platform/test/create-route-error.test.ts`)

Follow the existing pattern from `install-route-handler.test.ts`: mock `@/lib/supabase/server`, `@/lib/auth/validate-origin`, `@/server/logger`, and `@/server/github-app`.

- Given `createRepo` throws with "name already exists on this account", when `POST /api/repo/create` handles it, then the response body contains `{ error: "name already exists on this account" }` and status is 500
- Given `createRepo` throws, when `POST /api/repo/create` handles it, then `Sentry.captureException` is called with the error object (mock `@sentry/nextjs`)

### Integration Tests

- Given a user with an org-installed GitHub App, when they use the "Start Fresh" flow, then the repo is created under the org and the setup proceeds to cloning
- Given a user with a user-account GitHub App installation, when they use the "Start Fresh" flow, then the repo is created under their account and the setup proceeds to cloning

### E2E Verification (Post-deploy)

- **Browser:** Navigate to `https://app.soleur.ai/connect-repo`, select "Connect Existing Repository", complete GitHub App install flow, select a repo, verify setup completes to "ready" state
- **Browser:** Navigate to `https://app.soleur.ai/connect-repo`, select "Start Fresh", enter a project name, complete GitHub App install flow, verify repo creation and setup complete to "ready" state
- **API verify (Sentry):** Query Sentry EU API (`de.sentry.io`) for unresolved issues in the last 24h matching `setup OR clone OR create`. Org slug is `jikigai` (not `jikig`). Expects: no new issues.
- **API verify (Supabase):** Query `users` table for `repo_status=eq.error`. Expects: no users stuck in error state.
- **API verify (health):** `curl -s https://app.soleur.ai/health | jq '.version'` confirms v0.14.3+ is deployed (includes ca-certificates fix).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- bug fix in existing infrastructure with no new user-facing pages, no cost changes, and no legal implications.

## Context

### Relevant Files

| File | Role |
|------|------|
| `apps/web-platform/server/github-app.ts` | GitHub App JWT, token exchange, repo creation, PR creation |
| `apps/web-platform/app/api/repo/create/route.ts` | POST handler for creating new repos via GitHub App |
| `apps/web-platform/app/api/repo/setup/route.ts` | POST handler that starts workspace provisioning |
| `apps/web-platform/app/api/repo/status/route.ts` | GET handler polled for setup progress |
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Client-side setup flow orchestrator |
| `apps/web-platform/components/connect-repo/failed-state.tsx` | Error display component |
| `apps/web-platform/components/connect-repo/create-project-state.tsx` | "Start Fresh" form component |
| `apps/web-platform/server/workspace.ts` | `provisionWorkspaceWithRepo()` -- git clone + scaffolding |
| `apps/web-platform/Dockerfile` | Production Docker image (ca-certificates fix) |

### Prior PRs in This Area

| PR | What It Fixed | Status |
|----|---------------|--------|
| #1645 | Added ca-certificates to Docker runner | Merged, deploying |
| #1540 | Workspace cleanup mv-aside for root-owned files | Merged, deployed |
| #1494 | Error handling: Sentry capture, error persistence, error display | Merged, deployed |
| #1490 | `persistSession: false` for service client | Merged, deployed |
| #1487 | GoTrue admin API for identity resolution | Merged, deployed |
| #1479 | Identity resolution for email-first users | Merged, deployed |

### Relevant Learnings

| Learning | Key Insight | Applied Where |
|----------|-------------|---------------|
| `silent-setup-failure-no-error-capture-20260403` | Background tasks need Sentry + DB persistence + user display | Phase 2 -- create route is synchronous so only needs Sentry + response |
| `sentry-dsn-missing-from-container-env-20260405` | Sentry DSN was missing from container; now fixed and verified | Phase 3 -- Sentry events should now appear for new errors |
| `supabase-identities-null-email-first-users-20260403` | Use `auth.admin.getUserById()` not `user.identities` | Already applied in install route (PR #1487) |
| `github-org-membership-api-redirect-handling-20260402` | Token cache is module-level; use unique installationIds per test | Test Scenarios -- each test uses unique installationId range |
| `github-app-install-url-404-20260403` | GitHub App permissions: `contents:read+write`, `metadata:read`, `members:read` | Phase 0 -- missing `administration:write` for org repo creation |

### Sentry Issues (Current)

| Issue | Status | Resolution |
|-------|--------|------------|
| "Git clone failed: ...certificate verification failed" | Unresolved | Fixed by #1645 (deploying) |
| "Workspace cleanup failed: ...root-owned files" | Unresolved | Fixed by #1540 (deployed) — resolve in Sentry |
| "Server startup v0.14.2" | Unresolved | Info-level startup event, not an error |

## Alternative Approaches Considered

| Approach | Why Not Chosen |
|----------|---------------|
| Use `GET /installation/repositories` to list repos then filter | Does not solve repo creation for orgs; only relevant for listing |
| Detect account type at install time and store in DB | Over-engineering: the extra API call during `createRepo` is acceptable for a low-frequency operation. Also couples install flow to create flow (if user reinstalls without going through create, the DB is stale) |
| Add retry with exponential backoff to git clone | Masks the root cause (missing CA certs); the real fix is installing the certs |
| Disable SSL verification in git config | Security regression -- never acceptable |
| Cache `getInstallationAccount` result alongside installation token | The account type never changes for an installation, so caching would be correct. But it adds complexity for no meaningful performance gain -- `createRepo` is called at most once per user. YAGNI. |
| Use GitHub App user access token instead of installation token | User access tokens have broader scopes but require a separate OAuth flow per user and are harder to manage. Installation tokens are the correct mechanism for GitHub App operations. |
