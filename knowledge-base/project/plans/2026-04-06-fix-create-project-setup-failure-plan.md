---
title: "fix: create project setup failure — SSL certs, org repo creation, error resilience"
type: fix
date: 2026-04-06
---

# fix: create project setup failure — SSL certs, org repo creation, error resilience

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

**Status:** Unfixed — active bug in code

**Location:** `apps/web-platform/server/github-app.ts:385-399`

The `createRepo` function uses `POST /user/repos` with a GitHub App installation token. This endpoint creates repositories under the authenticated user's account. However, GitHub App installation tokens do not have a "user" identity — they authenticate as the app itself.

For **user-account installations** (personal GitHub accounts), this works because GitHub routes the request through the installation's target account. For **organization installations** (like `jikig-ai` with installation ID 121112974), the request fails because:

1. The installation token is scoped to the org, not a personal account
2. `POST /user/repos` requires a user-scoped token (PAT or OAuth), not an app installation token
3. GitHub returns a 403 or 404 error

The correct endpoint for organization installations is `POST /orgs/{org}/repos`. The function needs to determine whether the installation is on a user account or an organization, then call the appropriate endpoint.

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

### Phase 1: Fix organization repo creation

**Goal:** Make `createRepo` work for both user and organization GitHub App installations.

#### Task 1.1: Add installation account type detection to `createRepo`

**File:** `apps/web-platform/server/github-app.ts`

Before calling the repo creation endpoint, query `GET /app/installations/{id}` (same call used by `verifyInstallationOwnership`) to determine the account type. Then route to the correct endpoint:

- **User account:** `POST /user/repos` (existing behavior)
- **Organization:** `POST /orgs/{account.login}/repos`

Implementation approach: extract the installation account lookup into a reusable helper (or reuse the existing `verifyInstallationOwnership` partially) that returns the account type and login. Then branch in `createRepo`:

```typescript
// Determine target account for repo creation
const jwt = createAppJwt();
const installResponse = await githubFetch(
  `${GITHUB_API}/app/installations/${installationId}`,
  { headers: { Authorization: `Bearer ${jwt}` } },
);
if (!installResponse.ok) {
  throw new Error(`Failed to fetch installation: ${installResponse.status}`);
}
const installData = (await installResponse.json()) as { account?: InstallationAccount };
const account = installData.account;
if (!account?.login) {
  throw new Error("Installation has no account");
}

const endpoint = account.type === "Organization"
  ? `${GITHUB_API}/orgs/${account.login}/repos`
  : `${GITHUB_API}/user/repos`;
```

#### Task 1.2: Cache installation account metadata

Since `verifyInstallationOwnership` already queries the same endpoint during the install flow, cache the account type/login alongside the installation token to avoid a redundant API call during repo creation.

Alternative: accept the extra API call (it is only made during "Create Project", which is a low-frequency operation). Simpler is better for a bug fix.

### Phase 2: Improve error propagation in the "Create Project" flow

**Goal:** Surface actionable error messages to the user.

#### Task 2.1: Return specific error from `POST /api/repo/create`

**File:** `apps/web-platform/app/api/repo/create/route.ts`

Update the catch handler (lines 67-76) to extract and return a user-friendly error message from the GitHub API response:

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

Also add Sentry capture (currently missing from this route — only `setup/route.ts` has it).

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

- [ ] `createRepo` uses the correct GitHub API endpoint for organization installations (`POST /orgs/{org}/repos`)
- [ ] `createRepo` continues to work for user-account installations (`POST /user/repos`)
- [ ] `POST /api/repo/create` returns specific error messages from the GitHub API (not just "Failed to create repository")
- [ ] `POST /api/repo/create` reports errors to Sentry via `captureException`
- [ ] The client displays specific error messages in the `FailedState` component when repo creation fails
- [ ] The client displays specific error messages when `POST /api/repo/setup` returns a non-200 response
- [ ] The "Start Fresh" flow completes successfully for an organization installation (creates repo + clones)
- [ ] The "Connect Existing" flow completes successfully after ca-certificates fix deploys
- [ ] No new unresolved Sentry errors related to project setup appear within 24 hours of deploy

## Test Scenarios

### Unit Tests

- Given an organization installation (account type "Organization"), when `createRepo` is called, then it sends `POST /orgs/{org}/repos` (not `/user/repos`)
- Given a user-account installation (account type "User"), when `createRepo` is called, then it sends `POST /user/repos`
- Given the GitHub API returns a 422 "name already exists" error, when `createRepo` is called, then the thrown error contains the GitHub error message
- Given the `POST /api/repo/create` handler catches an error, then `Sentry.captureException` is called with the error object
- Given `POST /api/repo/create` returns `{ error: "specific message" }`, when the client handles the failure, then `setupError` is set to "specific message"

### Integration Tests

- Given a user with an org-installed GitHub App, when they use the "Start Fresh" flow, then the repo is created under the org and the setup proceeds to cloning
- Given a user with a user-account GitHub App installation, when they use the "Start Fresh" flow, then the repo is created under their account and the setup proceeds to cloning

### E2E Verification (Post-deploy)

- **Browser:** Navigate to `https://app.soleur.ai/connect-repo`, select "Connect Existing Repository", complete GitHub App install flow, select a repo, verify setup completes to "ready" state
- **Browser:** Navigate to `https://app.soleur.ai/connect-repo`, select "Start Fresh", enter a project name, complete GitHub App install flow, verify repo creation and setup complete to "ready" state
- **API verify (Sentry):** `doppler run -c prd -- curl -s -H "Authorization: Bearer <SENTRY_API_TOKEN>" "https://de.sentry.io/api/0/projects/<SENTRY_ORG>/<SENTRY_PROJECT>/issues/?statsPeriod=24h&query=is:unresolved+setup+OR+clone+OR+create"` expects: no new issues
- **API verify (Supabase):** `doppler run -c prd -- curl -s -H "apikey: <SUPABASE_SERVICE_ROLE_KEY>" -H "Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>" "<SUPABASE_URL>/rest/v1/users?select=repo_status,repo_error&repo_status=eq.error&limit=5"` expects: no users stuck in error state

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

| Learning | Key Insight |
|----------|-------------|
| `silent-setup-failure-no-error-capture-20260403` | Background tasks need Sentry + DB persistence + user display |
| `sentry-dsn-missing-from-container-env-20260405` | Sentry DSN was missing from container; now fixed and verified |
| `supabase-identities-null-email-first-users-20260403` | Use `auth.admin.getUserById()` not `user.identities` |

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
| Detect account type at install time and store in DB | Over-engineering: the extra API call during `createRepo` is acceptable for a low-frequency operation |
| Add retry with exponential backoff to git clone | Masks the root cause (missing CA certs); the real fix is installing the certs |
| Disable SSL verification in git config | Security regression -- never acceptable |
