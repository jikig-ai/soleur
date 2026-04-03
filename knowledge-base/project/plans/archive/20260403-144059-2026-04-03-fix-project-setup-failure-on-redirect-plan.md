---
title: "fix: project setup fails on redirect back from GitHub App install"
type: fix
date: 2026-04-03
---

# fix: project setup fails on redirect back from GitHub App install

## Problem

When connecting an existing GitHub project (e.g., `jikig-ai/shelter-me`), the Soleur AI GitHub App installs successfully on GitHub, but when redirected back to `https://app.soleur.ai/connect-repo?installation_id=XXX&setup_action=install`, the user sees a "Project Setup Failed" error page.

The GitHub App IS installed on the repo (confirmed: installation ID 121112974 on jikig-ai org) but no users have `github_installation_id` set in the database, meaning `POST /api/repo/install` is failing for all users.

## Root Cause Analysis

Three compounding issues create the failure:

### RC1: `user.identities` is null despite valid GitHub OAuth link (Primary)

**Location:** `apps/web-platform/app/api/repo/install/route.ts:45-59`

The install route extracts the GitHub username exclusively from `user.identities`:

```typescript
const githubLogin = user.identities?.find(
    (i) => i.provider === "github",
)?.identity_data?.user_name;

if (!githubLogin) {
    return NextResponse.json(
        { error: "No GitHub identity found on this account" },
        { status: 403 },
    );
}
```

**Verified in production:** The primary user (`jean.deruelle@jikigai.com`) has `identities: null` in Supabase auth, despite having `app_metadata.providers: ["email", "github"]` and `user_metadata.user_name: "deruelle"`. This is a known Supabase state for users who signed up with email and later linked GitHub OAuth.

The `user_metadata` fallback was intentionally removed in PR #1400 (security fix to prevent IDOR via mutable `user_metadata`). The fix was correct for the IDOR vector but assumed `user.identities` would always be populated for users with a GitHub OAuth link -- that assumption is false.

**Impact:** 100% of install attempts fail with 403. No user can complete the GitHub App install flow.

### RC2: Client ignores HTTP response status from `POST /api/repo/setup` (Secondary)

**Location:** `apps/web-platform/app/(auth)/connect-repo/page.tsx:1109-1119`

```typescript
try {
    await fetch("/api/repo/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoUrl }),
    });
} catch {
    setState("failed");
    return;
}
```

Only network errors trigger the catch. HTTP 400/409/500 responses are silently ignored, and the client proceeds to poll `/api/repo/status`. Since no clone was started, the poll times out after 2 minutes (60 attempts x 2s interval) and sets `setState("failed")`.

### RC3: Concurrent useEffect race condition causes wrong error state (Tertiary)

**Location:** `apps/web-platform/app/(auth)/connect-repo/page.tsx:1021-1045` and `:1263-1298`

Two independent `useEffect` hooks fire on mount when `installation_id` is in the URL:

1. **Effect 1** (line 1021): Processes the install callback (`POST /api/repo/install`). On failure, sets `setState("interrupted")`.
2. **Effect 3** (line 1263): Checks sessionStorage for `soleur_create_project`. If present (stale from a prior "Create New" attempt), calls `POST /api/repo/create` which fails (no `github_installation_id`) and sets `setState("failed")`.

If both effects fire concurrently and the user has stale sessionStorage, the "failed" state from Effect 3 overwrites the "interrupted" state from Effect 1. This explains why the user sees "Project Setup Failed" instead of "Setup Was Interrupted" -- the wrong error state is displayed.

## Proposed Solution

### Phase 1: Fix GitHub identity resolution (RC1)

Replace the `identities`-only check with a secure multi-source resolution that avoids the IDOR vulnerability.

**Approach:** Query `auth.identities` via the Supabase admin API instead of relying on the `user.identities` field from `getUser()`. The admin API returns the full identity record from the `auth.identities` table, which is provider-controlled and immutable (unlike `user_metadata`).

**Implementation in `apps/web-platform/app/api/repo/install/route.ts`:**

1. After getting the user from `supabase.auth.getUser()`, use the service client to query the auth identities:

    ```typescript
    // SECURITY: Query provider-controlled identity from auth.identities table.
    // user.identities from getUser() can be null for email-first users who
    // later linked GitHub. user_metadata is user-mutable -- never trust it
    // for security decisions.
    const serviceClient = createServiceClient();
    const { data: identityData } = await serviceClient
        .schema("auth" as "public")
        .from("identities")
        .select("identity_data")
        .eq("user_id", user.id)
        .eq("provider", "github")
        .maybeSingle();

    const githubLogin = identityData?.identity_data?.user_name;
    ```

2. If no identity found, return 403 with a descriptive error message that helps the user:
   `"No GitHub identity linked to this account. Please sign in with GitHub first."`

3. Update the security comment to explain why `user_metadata` is not used and why the admin query is necessary.

**Why this is secure:** The `auth.identities` table is populated by the OAuth provider during authentication. It is not mutable by `auth.updateUser()`. Querying it via the service client (which bypasses RLS) gives us the ground truth about the user's linked providers.

**Implementation risk (from review):** The `.schema("auth" as "public")` TypeScript cast suggests the Supabase JS client may not officially support querying the `auth` schema via the query builder. Verify this works against the production Supabase instance before committing to this approach. If the query builder does not support `auth` schema access, use the Supabase admin API instead: `GET /auth/v1/admin/users/{user_id}` with the service role key, which returns the full user object including identities.

**Alternative considered:** Re-adding the `user_metadata` fallback with a warning log. Rejected because `user_metadata` IS mutable and the IDOR vector from PR #1400 would be reintroduced.

### Phase 2: Check setup response status (RC2)

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

In the `startSetup` function, check the response status from `POST /api/repo/setup`:

```typescript
const res = await fetch("/api/repo/setup", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ repoUrl }),
});
if (!res.ok) {
    setState("failed");
    return;
}
```

This prevents the client from entering a 2-minute poll timeout when the server has already rejected the request.

### Phase 3: Eliminate useEffect race condition (RC3)

**File:** `apps/web-platform/app/(auth)/connect-repo/page.tsx`

Merge the two callback-handling `useEffect` hooks (line 1021 and 1263) into a single effect that processes the `installation_id` callback atomically:

```typescript
useEffect(() => {
    const installationId = searchParams.get("installation_id");
    const setupAction = searchParams.get("setup_action");

    if (!installationId || setupAction !== "install") return;

    (async () => {
        try {
            // Step 1: Register the installation
            const installRes = await fetch("/api/repo/install", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    installationId: Number(installationId),
                }),
            });
            if (!installRes.ok) {
                setState("interrupted");
                return;
            }

            // Step 2: Check for pending create (from "Start Fresh" flow)
            let pendingCreateData: {
                name: string;
                isPrivate: boolean;
            } | null = null;
            try {
                const raw = sessionStorage.getItem(
                    "soleur_create_project",
                );
                if (raw) {
                    pendingCreateData = JSON.parse(raw);
                    sessionStorage.removeItem("soleur_create_project");
                }
            } catch {
                // sessionStorage unavailable
            }

            if (pendingCreateData) {
                // Create flow: create repo then start setup
                const createRes = await fetch("/api/repo/create", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        name: pendingCreateData.name,
                        private: pendingCreateData.isPrivate,
                    }),
                });
                if (!createRes.ok) {
                    setState("failed");
                    return;
                }
                const data = await createRes.json();
                startSetup(data.repoUrl, data.fullName);
            } else {
                // Connect existing flow: fetch repos for selection
                await fetchRepos();
            }
        } catch {
            setState("interrupted");
        }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
}, []);
```

This ensures:

- The install callback is always processed first
- The create flow only fires if install succeeds
- No concurrent state updates from independent effects
- Stale sessionStorage is cleaned up atomically

## Acceptance Criteria

- [ ] Users with `identities: null` but valid GitHub OAuth link can complete the install flow
- [ ] The `user_metadata` IDOR vector from PR #1400 remains closed (no `user_metadata` fallback for security decisions)
- [ ] `POST /api/repo/setup` error responses are reflected immediately in the UI (no 2-minute timeout)
- [ ] Stale `soleur_create_project` in sessionStorage does not cause a race condition with the install callback
- [ ] The correct error state is shown: "Setup Was Interrupted" for install failures, "Project Setup Failed" for setup/clone failures
- [ ] Existing 13 install-route tests continue to pass
- [ ] New tests cover the `identities: null` scenario

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- targeted bug fix to existing authentication/identity resolution code with no user-facing UI changes, no new infrastructure, no legal/marketing/sales impact.

## Test Scenarios

- Given a user with `identities: null` and valid GitHub identity in `auth.identities` table, when `POST /api/repo/install` is called, then the install succeeds and `github_installation_id` is stored
- Given a user with no GitHub identity in `auth.identities` table, when `POST /api/repo/install` is called, then a 403 is returned with a descriptive error
- Given a user with a populated `identities` array containing a GitHub provider, when `POST /api/repo/install` is called, then the install succeeds (regression test)
- Given `POST /api/repo/setup` returns 409 (already cloning), when the client handles the response, then `setState("failed")` is called immediately without polling
- Given `POST /api/repo/setup` returns 500, when the client handles the response, then `setState("failed")` is called immediately without polling
- Given stale `soleur_create_project` in sessionStorage and `installation_id` in URL, when the page mounts, then install is processed before create, and both use the same atomic flow

## Context

### Files to modify

| File | Change |
|------|--------|
| `apps/web-platform/app/api/repo/install/route.ts` | Replace `user.identities` lookup with `auth.identities` table query via service client |
| `apps/web-platform/app/(auth)/connect-repo/page.tsx` | Check `/api/repo/setup` response status; merge concurrent useEffect hooks |
| `apps/web-platform/test/install-route.test.ts` | Add test for `identities: null` scenario with valid `auth.identities` record |

### Related issues and PRs

| Reference | Description |
|-----------|-------------|
| PR #1400 | Security fix that removed `user_metadata` fallback (correct, but revealed the `identities: null` gap) |
| PR #1396 | Org installation support that made the fallback exploitable |
| PR #1387 | Original installation ownership verification |
| PR #1461 | GitHub App install URL 404 fix (app creation) |
| PR #1464 | Settings page project setup card |
| Learning | `knowledge-base/project/learnings/integration-issues/github-org-membership-api-redirect-handling-20260402.md` |

### Production data

- GitHub App installation 121112974 exists on `jikig-ai` org
- 0 out of 6 users have `github_installation_id` set (all installs failing)
- User `jean.deruelle@jikigai.com` has `identities: null`, `app_metadata.providers: ["email", "github"]`, `user_metadata.user_name: "deruelle"`
- GitHub username `deruelle` is a member of `jikig-ai` org

### Supabase identity model

- `user.identities` from `getUser()` can be null for email-first users who later linked GitHub
- `user_metadata` is user-mutable via `auth.updateUser()` -- never trust for security decisions
- `auth.identities` table is provider-controlled and immutable -- the correct source for identity verification
- The service client (with service role key) can query `auth.identities` directly using `.schema("auth")`

### Alternative approaches considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Re-add `user_metadata` fallback | Rejected | Reopens IDOR vulnerability from PR #1400 |
| Force GitHub OAuth re-link for affected users | Rejected | Poor UX, manual intervention required |
| Use Supabase admin API `GET /admin/users/{id}` | Considered | Viable but admin API is HTTP overhead vs direct table query |
| Query `auth.identities` via service client | Chosen | Direct, secure, no HTTP overhead, immutable source |
