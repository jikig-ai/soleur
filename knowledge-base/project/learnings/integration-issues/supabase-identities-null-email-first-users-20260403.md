---
module: Web Platform
date: 2026-04-03
problem_type: integration_issue
component: authentication
symptoms:
  - "Project Setup Failed error page after GitHub App install redirect"
  - "POST /api/repo/install returns 403 for all users"
  - "0 out of 6 users have github_installation_id set despite successful GitHub App installs"
root_cause: wrong_api
resolution_type: code_fix
severity: critical
tags: [supabase, identities, github-app, oauth, email-first-users]
---

# Troubleshooting: Supabase user.identities is null for email-first users who later linked GitHub

## Problem

When connecting a GitHub repository through the Soleur web platform, the GitHub App installs successfully but redirecting back to Soleur shows "Project Setup Failed". The install route returned 403 for 100% of users because `user.identities` from `getUser()` was null.

## Environment

- Module: Web Platform
- Framework: Next.js 14 (App Router)
- Affected Component: `apps/web-platform/app/api/repo/install/route.ts`
- Date: 2026-04-03

## Symptoms

- "Project Setup Failed" error page with generic troubleshooting advice
- `POST /api/repo/install` returns `{ error: "No GitHub identity found on this account" }` with 403 status
- All 6 users in the database have `github_installation_id: null` despite successful GitHub App installations
- GitHub App installation 121112974 confirmed active on `jikig-ai` org

## What Didn't Work

**Direct solution:** The root cause was identified through database inspection — `user.identities` was null for the primary user despite having `app_metadata.providers: ["email", "github"]`. No wrong paths were attempted.

## Session Errors

**CWD drift during git commit** (session 1)

- **Recovery:** Re-ran `git add` and `git commit` from the worktree root instead of `apps/web-platform/`
- **Prevention:** Always `cd` to worktree root before running git commands, or use absolute paths

**vi.mock contamination across test describe blocks** (session 1)

- **Recovery:** Moved route handler tests to a separate file (`install-route-handler.test.ts`) to isolate `vi.mock` hoisting
- **Prevention:** Never put `vi.mock()` calls in the same file as tests that import the real module. Vitest hoists all `vi.mock()` to the top of the file, clobbering real imports for the entire file regardless of describe block scope.

**Test mocked an API pattern that doesn't work in production** (session 2)

- **Recovery:** Discovered via production debugging that `.schema("auth")` returns PGRST106. Fixed by switching to `auth.admin.getUserById()`.
- **Prevention:** When testing Supabase queries that use non-standard schemas or admin APIs, add an integration test or at minimum document the production API constraint in the test file comments.

**Sentry API returned 404 — wrong project slug** (session 2)

- **Recovery:** Fell back to direct API testing and Playwright reproduction.
- **Prevention:** Store the Sentry project slug in Doppler or document it in a reference learning.

**Health endpoint false alarm** (session 2)

- **Recovery:** Verified Supabase was reachable by testing with table-specific endpoints.
- **Prevention:** The `checkSupabase()` function in `server/index.ts` hits `/rest/v1/` (root, no table), which returns 401. Should query a specific table like `/rest/v1/users?limit=0` instead.

## Solution

**Root cause (layer 1):** `supabase.auth.getUser()` returns `identities: null` for users who signed up with email and later linked GitHub OAuth.

**Root cause (layer 2 — discovered 2026-04-03):** The initial fix queried `auth.identities` via PostgREST using `serviceClient.schema("auth").from("identities")`, but **PostgREST does not expose the `auth` schema**. Only `public` and `graphql_public` are exposed. The query silently returns `{ data: null }`, producing the same 403 error. The test mocked `.schema()` to return data, masking the production failure.

**Fix (v1 — broken in production):**

```typescript
// Silently fails: PostgREST returns PGRST106 "Invalid schema: auth"
const { data: identityData } = await serviceClient
    .schema("auth" as "public")
    .from("identities")
    .select("identity_data")
    .eq("user_id", user.id)
    .eq("provider", "github")
    .maybeSingle();
```

**Fix (v2 — correct):** Use the GoTrue admin API via `auth.admin.getUserById()`:

```typescript
const serviceClient = createServiceClient();
const { data: adminUser } = await serviceClient.auth.admin.getUserById(
    user.id,
);
const githubIdentity = adminUser?.user?.identities?.find(
    (i) => i.provider === "github",
);
const githubLogin = githubIdentity?.identity_data?.user_name as
    | string
    | undefined;
```

**Additional fixes in PR #1479:**

1. Check `res.ok` from `POST /api/repo/setup` to prevent 2-minute blind poll timeout
2. Merge two concurrent `useEffect` hooks into a single atomic effect to eliminate race condition where stale sessionStorage could overwrite install callback state

## Why This Works

1. **Root cause:** `getUser()` uses the user's session token and returns a User object from GoTrue. For email-first users who later linked GitHub, the `identities` array can be null.

2. **Why `.schema("auth")` fails:** PostgREST only serves schemas listed in `pgrst.db-schemas`. Supabase hosted instances expose `public` and `graphql_public`. The `auth` schema is managed by GoTrue and has its own REST endpoints (`/auth/v1/`). The Supabase JS client's `.schema()` method sets `Accept-Profile` header, which PostgREST rejects with `PGRST106`.

3. **Why `auth.admin.getUserById()` works:** It calls the GoTrue admin endpoint `GET /auth/v1/admin/users/{id}` using the service role key, which always returns the full user object with populated `identities` array.

4. **Security consideration:** `auth.admin.getUserById()` returns provider-controlled identity data (same trust level as the `auth.identities` table). The `user_metadata` fallback remains intentionally absent — it is user-mutable and exploitable for IDOR.

## Prevention

- **Never** query the `auth` schema via Supabase JS client `.schema("auth")` — PostgREST does not expose it and the query silently returns null
- For server-side identity resolution, use `auth.admin.getUserById()` or `auth.admin.listUsers()` — these use the GoTrue admin API, not PostgREST
- Never rely on `user.identities` from `getUser()` — it can be null for email-first users
- When writing tests for Supabase queries, verify the underlying API actually supports the query pattern in production (not just via mocks)
- Always check HTTP response status from API calls before proceeding to polling loops

## Related Issues

- See also: [GitHub org membership API redirect handling](./github-org-membership-api-redirect-handling-20260402.md) — related GitHub App integration issue
