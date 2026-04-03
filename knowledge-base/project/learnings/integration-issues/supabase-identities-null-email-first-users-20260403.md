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

**CWD drift during git commit**

- **Recovery:** Re-ran `git add` and `git commit` from the worktree root instead of `apps/web-platform/`
- **Prevention:** Always `cd` to worktree root before running git commands, or use absolute paths

**vi.mock contamination across test describe blocks**

- **Recovery:** Moved route handler tests to a separate file (`install-route-handler.test.ts`) to isolate `vi.mock` hoisting
- **Prevention:** Never put `vi.mock()` calls in the same file as tests that import the real module. Vitest hoists all `vi.mock()` to the top of the file, clobbering real imports for the entire file regardless of describe block scope.

## Solution

**Root cause:** `supabase.auth.getUser()` returns `identities: null` for users who signed up with email and later linked GitHub OAuth. This is a known Supabase behavior — the `identities` field is not always populated on the User object returned by `getUser()`.

**Fix:** Query the `auth.identities` table directly via the Supabase service client:

```typescript
// Before (broken):
const githubLogin = user.identities?.find(
    (i) => i.provider === "github",
)?.identity_data?.user_name;

// After (fixed):
const serviceClient = createServiceClient();
const { data: identityData } = await serviceClient
    .schema("auth" as "public")
    .from("identities")
    .select("identity_data")
    .eq("user_id", user.id)
    .eq("provider", "github")
    .maybeSingle();

const githubLogin = identityData?.identity_data?.user_name as
    | string
    | undefined;
```

**Additional fixes in the same PR:**

1. Check `res.ok` from `POST /api/repo/setup` to prevent 2-minute blind poll timeout
2. Merge two concurrent `useEffect` hooks into a single atomic effect to eliminate race condition where stale sessionStorage could overwrite install callback state

## Why This Works

1. **Root cause:** `getUser()` uses the user's session token and returns a User object from GoTrue. For email-first users who later linked GitHub, the `identities` array can be null despite the identity existing in the `auth.identities` table.

2. **Why the fix works:** The `auth.identities` table is the source of truth for provider-controlled identity data. It is populated by the OAuth provider during authentication and is not mutable via `auth.updateUser()`. Querying it with the service role key bypasses RLS and returns the ground truth.

3. **Security consideration:** The previous code used `user.identities` (which was already secure). The `user_metadata` fallback was intentionally removed in PR #1400 because `user_metadata` is user-mutable and exploitable for IDOR. The `auth.identities` table query maintains the same security posture — it reads provider-controlled data, not user-controlled data.

## Prevention

- Never rely solely on `user.identities` from `getUser()` for identity resolution — it can be null for users with certain auth flows
- For server-side identity verification, query `auth.identities` directly via service client or use `auth.admin.getUserById()`
- The `as "public"` TypeScript cast on `.schema("auth")` is necessary because the Supabase JS client types don't expose the auth schema — this is a type workaround, not a security concern
- Always check HTTP response status from API calls before proceeding to polling loops

## Related Issues

- See also: [GitHub org membership API redirect handling](./github-org-membership-api-redirect-handling-20260402.md) — related GitHub App integration issue
