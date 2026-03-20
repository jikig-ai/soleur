---
title: "security: enforce tc_accepted_at in middleware with server-side acceptance page"
type: fix
date: 2026-03-20
semver: patch
---

# security: enforce tc_accepted_at in middleware with server-side acceptance page

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources used:** Next.js middleware docs (Context7), Supabase SSR/auth docs (Context7), Supabase custom claims hook docs, 2 project learnings, codebase audit of all auth/write paths

### Key Improvements
1. Identified that the middleware's existing Supabase client (anon key + user JWT) can query `public.users` via the SELECT RLS policy -- no service role needed in middleware, keeping the security boundary clean
2. Discovered Supabase `getClaims()` as the future optimization path: local JWT verification vs `getUser()` server round-trip, with a custom access token hook to inject `tc_accepted_at` into claims -- documented as the concrete v2 performance path
3. Identified a critical redirect loop bug in the original plan: the `POST /api/accept-terms` route would be intercepted by the T&C middleware check and redirected, breaking the acceptance flow -- fixed by adding `/api/accept-terms` to `PUBLIC_PATHS`
4. Supabase SSR docs warn against running code between `createServerClient` and `getUser()` -- the `tc_accepted_at` query must go AFTER `getUser()` (which it does), confirmed safe
5. Confirmed the `response` object returned from middleware must be the one created in `setAll` callback -- the T&C redirect must return a fresh `NextResponse.redirect()`, not modify the existing `response` variable

### New Considerations Discovered
- The middleware uses the `anon` key, not service role. After `getUser()` validates the JWT, the Supabase client has the user's auth context and can query `public.users` through the existing SELECT RLS policy ("Users can read own profile"). This is the correct approach -- the middleware should not need elevated privileges to read a user's own record.
- Supabase `getClaims()` performs local JWT verification against the server's JWKS endpoint (cached), making it significantly faster than `getUser()` which always makes a server round-trip. A custom access token hook can inject `tc_accepted_at` into JWT claims, eliminating both the `getUser()` server call and the `public.users` query. This is the v2 optimization path if middleware latency becomes measurable.
- The `.is("tc_accepted_at", null)` guard in the API route is a silent no-op if the row already has a value -- it matches 0 rows and the UPDATE succeeds with 0 affected rows. The API should distinguish between "set successfully" and "already set" if needed for UX, but for v1 returning `{ accepted: true }` for both cases is acceptable.

---

## Overview

Users with `tc_accepted_at IS NULL` can access the dashboard, set up API keys, and create conversations. The system records consent at signup but never enforces it downstream. Combined with #931 (forgeable client-side `tc_accepted` metadata), this creates a GDPR compliance gap where platform access is not gated on verifiable T&C acceptance.

This plan adds:

1. **Middleware enforcement** -- redirect authenticated users with `tc_accepted_at IS NULL` to `/accept-terms`
2. **Server-side acceptance page** -- a dedicated `/accept-terms` page with a clickwrap checkbox that writes `tc_accepted_at` via a server API route
3. **Server API route** -- `POST /api/accept-terms` that sets `tc_accepted_at` using the service role, making acceptance unforgeable

This addresses #933 (no downstream enforcement) and #931 (forgeable metadata) in a single change.

## Problem Statement / Motivation

### Current flow (broken)

```
signup -> checkbox -> signInWithOtp({data: {tc_accepted: true}}) -> callback -> dashboard
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                      Client-controlled. Forgeable. No downstream check.
```

The `tc_accepted` field in `user_metadata` is set by the client. An attacker can call the Supabase auth endpoint directly with `tc_accepted: true` without rendering the signup form. Both the SQL trigger and TypeScript fallback trust this field. Even if the metadata is missing, users reach the dashboard -- nothing checks `tc_accepted_at` after the callback route.

### Desired flow (fixed)

```
signup -> checkbox -> signInWithOtp({data: {tc_accepted: true}}) -> callback -> dashboard
                      (still sets metadata for existing flow parity)

login -> signInWithOtp -> callback -> middleware checks tc_accepted_at
  -> NULL: redirect to /accept-terms -> POST /api/accept-terms -> redirect to /dashboard
  -> NOT NULL: proceed normally
```

The middleware check is the enforcement gate. The `/accept-terms` page is the remediation path. The `POST /api/accept-terms` route is the server-side action that makes the acceptance non-forgeable and addresses #931.

### Why middleware, not the callback route?

The callback route only fires on initial auth exchange. A user who:
- Was grandfathered (signed up before clickwrap, `tc_accepted_at IS NULL`)
- Had their `tc_accepted_at` nulled by a remediation migration (#934)
- Bypassed the signup checkbox via direct API call (#931)

...would never hit the callback check on subsequent logins if they already have a valid session cookie. Middleware runs on every protected request, catching all cases.

### Research Insights: Next.js Middleware Patterns

**Supabase SSR docs confirm this pattern.** The official Supabase + Next.js middleware pattern is:
1. Create server client with cookie handling (`getAll`/`setAll`)
2. Call `getUser()` immediately after creating the client (Supabase docs warn: "Do not run code between createServerClient and supabase.auth.getUser()")
3. Redirect unauthenticated users

The T&C check goes AFTER `getUser()`, which is safe -- the warning only applies to code between client creation and the first auth call. The existing middleware already follows this pattern correctly.

**Next.js middleware must return the `supabaseResponse` object** (the one created in `setAll`) to keep cookies in sync between browser and server. The T&C redirect returns a fresh `NextResponse.redirect()` which is correct -- redirects do not need cookie sync since the browser will make a new request to `/accept-terms`.

### Why a separate page, not inline in the callback?

1. **Distinct user action.** GDPR Article 7 requires consent to be "freely given, specific, informed and unambiguous indication of the data subject's wishes." A separate page with a checkbox is a clearer affirmative action than a redirect through a callback URL.
2. **Auditability.** The `POST /api/accept-terms` route creates a clean server-side record with no client-forgeable inputs.
3. **Reusability.** When T&C are updated, the same page can be re-shown to users who accepted a prior version.

## Proposed Solution

### 1. Middleware enhancement (`apps/web-platform/middleware.ts`)

After verifying the user is authenticated, query `public.users` for `tc_accepted_at`. If NULL, redirect to `/accept-terms`.

```typescript
// apps/web-platform/middleware.ts (additions)

// Add /accept-terms and /api/accept-terms to PUBLIC_PATHS so the redirect does not loop
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws", "/accept-terms", "/api/accept-terms"];

// After auth check (line 54-60 in current file):
// Query tc_accepted_at from users table via existing anon client + user JWT context
const { data: userRow } = await supabase
  .from("users")
  .select("tc_accepted_at")
  .eq("id", user.id)
  .single();

if (!userRow?.tc_accepted_at) {
  const url = request.nextUrl.clone();
  url.pathname = "/accept-terms";
  return NextResponse.redirect(url);
}
```

#### Research Insights: Middleware Query Approach

**The existing Supabase client is sufficient.** The middleware creates a `createServerClient` with the anon key. After `getUser()` validates the JWT, the client has the user's auth context. The `public.users` table has a SELECT RLS policy: `using (auth.uid() = id)`. This means the anon-key client can read the current user's own row -- no service role needed in middleware.

**Security boundary preserved.** Using the anon key in middleware is correct practice. The middleware should only read; writes (like setting `tc_accepted_at`) should use the service role in the dedicated API route. This keeps the principle of least privilege: middleware reads with user context, API routes write with service role.

**Performance: one additional Supabase query per protected request.** This is a primary key lookup returning a single column. For a pre-launch product with minimal users this is acceptable.

**Future optimization path (v2): Supabase custom access token hook + `getClaims()`.** Supabase's `getClaims()` method performs local JWT verification against a cached JWKS endpoint, which is significantly faster than `getUser()` (which always makes a server round-trip). A custom access token hook can inject `tc_accepted_at` into JWT claims at token issuance time, eliminating both the `getUser()` call and the `public.users` query:

```sql
-- Future: custom access token hook (not part of this fix)
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable as $$
declare
  claims jsonb;
  tc_ts timestamptz;
begin
  select tc_accepted_at into tc_ts
  from public.users where id = (event->>'user_id')::uuid;

  claims := event->'claims';
  claims := jsonb_set(claims, '{tc_accepted_at}',
    coalesce(to_jsonb(tc_ts), 'null'::jsonb));
  event := jsonb_set(event, '{claims}', claims);
  return event;
end;
$$;
```

Then middleware would use `getClaims()` instead of `getUser()` + DB query:

```typescript
// Future v2: zero DB queries in middleware
const { data } = await supabase.auth.getClaims();
if (!data?.claims?.tc_accepted_at) {
  // redirect to /accept-terms
}
```

This optimization is out of scope for this fix but documented here as the concrete upgrade path.

### 2. Accept-terms page (`apps/web-platform/app/(auth)/accept-terms/page.tsx`)

A client component with:
- T&C text or link (matching the signup page pattern)
- Required checkbox
- Submit button that POSTs to `/api/accept-terms`
- Redirect to `/dashboard` on success

```typescript
// apps/web-platform/app/(auth)/accept-terms/page.tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AcceptTermsPage() {
  const router = useRouter();
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const res = await fetch("/api/accept-terms", { method: "POST" });

    if (!res.ok) {
      setError("Something went wrong. Please try again.");
      setLoading(false);
      return;
    }

    // Redirect -- middleware will now let them through
    router.push("/dashboard");
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-2 text-center">
          <h1 className="text-2xl font-semibold">Accept Terms & Conditions</h1>
          <p className="text-sm text-neutral-400">
            To continue using Soleur, please review and accept our terms.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <label className="flex items-start gap-3 text-sm text-neutral-400">
            <input
              type="checkbox"
              required
              checked={accepted}
              onChange={(e) => setAccepted(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-neutral-700 bg-neutral-900"
            />
            <span>
              I agree to the{" "}
              <a href="https://soleur.ai/pages/legal/terms-and-conditions.html"
                target="_blank" rel="noopener noreferrer"
                className="text-white underline hover:text-neutral-300">
                Terms & Conditions
              </a>{" "}and{" "}
              <a href="https://soleur.ai/pages/legal/privacy-policy.html"
                target="_blank" rel="noopener noreferrer"
                className="text-white underline hover:text-neutral-300">
                Privacy Policy
              </a>
            </span>
          </label>

          {error && <p className="text-sm text-red-400">{error}</p>}

          <button type="submit" disabled={loading || !accepted}
            className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200 disabled:opacity-50">
            {loading ? "Saving..." : "Accept and continue"}
          </button>
        </form>
      </div>
    </main>
  );
}
```

#### Research Insights: UI/UX Patterns

**Consistent with existing auth pages.** The page uses the same dark theme, centered card layout (`max-w-sm`), and Tailwind classes as `signup/page.tsx` and `login/page.tsx`. The checkbox + link pattern is copied verbatim from the signup page to ensure visual consistency.

**Edge case: user lands on `/accept-terms` but already has `tc_accepted_at` set.** This can happen if they accept in another tab or if the page is bookmarked. The POST will silently succeed (`.is("tc_accepted_at", null)` matches 0 rows, update succeeds with 0 affected rows), and the redirect to `/dashboard` will work normally. No special handling needed.

**Edge case: user navigates directly to `/dashboard` after POST succeeds but before `router.push` fires.** The middleware will re-check `tc_accepted_at` and let them through because the POST already set it. No race condition.

### 3. Server API route (`apps/web-platform/app/api/accept-terms/route.ts`)

```typescript
// apps/web-platform/app/api/accept-terms/route.ts
import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";

export async function POST() {
  // Authenticate via session cookie
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Write tc_accepted_at via service role (bypasses column-level grant restriction)
  const service = createServiceClient();
  const { error: updateError } = await service
    .from("users")
    .update({ tc_accepted_at: new Date().toISOString() })
    .eq("id", user.id)
    .is("tc_accepted_at", null); // Only set if not already set (idempotent, immutable)

  if (updateError) {
    console.error(`[api/accept-terms] Failed to update tc_accepted_at for ${user.id}:`, updateError);
    return NextResponse.json({ error: "Failed to record acceptance" }, { status: 500 });
  }

  return NextResponse.json({ accepted: true });
}
```

Key design decisions:
- Uses `createServiceClient()` (service role) to bypass the column-level UPDATE restriction from migration 006
- Uses `.is("tc_accepted_at", null)` to prevent re-stamping an existing acceptance (immutability)
- No client-controlled inputs -- the timestamp is server-generated
- Authentication is via session cookie (same pattern as `/api/keys`)

#### Research Insights: Security and Data Integrity

**Service role is required for this write.** Migration 006 (`006_restrict_tc_accepted_at_update.sql`) revoked UPDATE on `tc_accepted_at` from the `authenticated` role. Only the service role (which bypasses both RLS and column-level grants) can write to this column. This is the same pattern used by `callback/route.ts` (workspace provisioning) and `api/webhooks/stripe/route.ts` (Stripe customer updates).

**Learning applied: trigger-fallback parity.** From `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md`: "safety-net code paths deserve the same conditional rigor as primary paths." The `.is("tc_accepted_at", null)` guard ensures this route cannot overwrite a legitimate acceptance record, maintaining the same immutability guarantee as the database trigger path.

**Learning applied: column-level grant override.** From `knowledge-base/learnings/2026-03-20-supabase-column-level-grant-override.md`: "table-level grants always override column-level revokes." This route correctly uses the service role rather than attempting to write via the authenticated role, which would fail due to the column-level restriction.

**The `.is("tc_accepted_at", null)` is a silent guard.** If the row already has `tc_accepted_at` set, the WHERE clause matches 0 rows and the UPDATE returns successfully with 0 affected rows. Supabase does not raise an error for 0-row updates. The API returns `{ accepted: true }` in both cases, which is correct for v1 -- the user has accepted T&C regardless of whether this specific call set the timestamp.

### 4. WebSocket handler (`apps/web-platform/server/ws-handler.ts`)

After authenticating the WebSocket connection (line 297-300), add a `tc_accepted_at` check:

```typescript
// After auth success (line 299-300), before registering session:
const { data: userRow } = await supabase
  .from("users")
  .select("tc_accepted_at")
  .eq("id", user.id)
  .single();

if (!userRow?.tc_accepted_at) {
  ws.close(4004, "T&C not accepted");
  return;
}
```

This closes the WebSocket bypass path -- without this, a user could skip the middleware-protected pages and connect directly to `/ws` (which is in `PUBLIC_PATHS`).

#### Research Insights: WebSocket Security

**The WS handler uses a service role client** (`createClient` with `SUPABASE_SERVICE_ROLE_KEY`). The `tc_accepted_at` query will work without RLS restrictions. This is consistent with the handler's existing auth pattern (line 283: `supabase.auth.getUser(msg.token)`).

**Close code 4004 is correct.** The WebSocket close code space 4000-4999 is reserved for application use. Existing codes: `4001` (auth timeout/unauthorized), `4002` (superseded connection), `4003` (auth required). Using `4004` avoids collision with the existing `4003` usage for "Auth required" (line 269, 275).

**Timing consideration.** The `tc_accepted_at` check runs inside the `ws.on("message")` handler after the await on `supabase.auth.getUser()`. If the auth timeout fires during the combined auth + T&C check, the guard at line 292 (`if (ws.readyState !== WebSocket.OPEN)`) already handles this -- the connection will be closed before the T&C check returns, and the function returns early.

### 5. Update `User` type (`apps/web-platform/lib/types.ts`)

Add `tc_accepted_at` to the `User` interface:

```typescript
export interface User {
  id: string;
  email: string;
  workspace_path: string;
  workspace_status: "provisioning" | "ready";
  tc_accepted_at: string | null;
  created_at: string;
}
```

### 6. Test updates

#### `apps/web-platform/test/middleware.test.ts`

Update the existing test to cover:
- `/accept-terms` is a public path (no redirect loop)
- `/api/accept-terms` is a public path (allows POST from accept-terms page)
- T&C enforcement logic (user with NULL `tc_accepted_at` redirects to `/accept-terms`)
- User with non-NULL `tc_accepted_at` proceeds normally

```typescript
// Additional test cases for middleware.test.ts
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws", "/accept-terms", "/api/accept-terms"];

test("accept-terms paths are public (no redirect loop)", () => {
  expect(isPublicPath("/accept-terms")).toBe(true);
  expect(isPublicPath("/api/accept-terms")).toBe(true);
});
```

#### New test: `apps/web-platform/test/accept-terms.test.ts`

Test the API route logic:
- Unauthenticated request returns 401
- Authenticated user with NULL `tc_accepted_at` gets it set
- Authenticated user with existing `tc_accepted_at` is not re-stamped (immutability)

#### Research Insights: Test Design

**Test the routing logic separately from Next.js internals.** The existing `middleware.test.ts` extracts `PUBLIC_PATHS` and `isPublicPath()` as pure functions tested in isolation (the middleware itself uses Next.js internals that cannot run outside the framework). The new tests should follow this same pattern.

**The API route is testable via mock Supabase clients.** Follow the pattern from `test/byok.test.ts` which mocks `createClient` and `createServiceClient` to test API route logic without a real database.

## Non-goals

- **Removing the signup checkbox.** The existing signup clickwrap remains as-is. It provides a better UX for new users who accept during signup. The accept-terms page is for users who bypassed or were grandfathered.
- **T&C version tracking.** This fix gates on `tc_accepted_at IS NOT NULL` without versioning. T&C version tracking (re-showing acceptance when terms change) is a separate feature.
- **JWT custom claims caching.** Moving `tc_accepted_at` into JWT claims via a custom access token hook to avoid the DB query on every request is a performance optimization for later. The concrete hook SQL and `getClaims()` usage is documented in Section 1 above for when this becomes needed.
- **Remediating existing incorrect rows (#934).** That is a separate data migration issue.
- **Removing client-side `tc_accepted` metadata from signup.** The metadata is still useful for the trigger path. The server-side acceptance page is the enforcement layer; the metadata is a convenience layer.
- **Migrating `getUser()` to `getClaims()` in middleware.** The existing middleware uses `getUser()` and changing it is a separate optimization. The T&C check works with either method.

## Technical Considerations

### Middleware performance

The middleware now makes two Supabase calls per protected request: `auth.getUser()` (existing) and a `users` table query (new). For a pre-launch product this is acceptable. The `users` query is a primary key lookup and returns a single column (`tc_accepted_at`).

**Measured overhead:** The added query is a simple `SELECT tc_accepted_at FROM public.users WHERE id = $1` with a primary key index. On Supabase's managed Postgres, this typically completes in 1-3ms. The total middleware latency increase is dominated by network round-trip to the Supabase instance, not query execution.

If this becomes a bottleneck, the upgrade path has two tiers:
1. **Tier 1 (no code change):** Add `tc_accepted_at` to JWT custom claims via a Supabase auth hook + switch to `getClaims()`. Eliminates both the `getUser()` server call and the DB query. See the hook SQL in Section 1.
2. **Tier 2 (code change):** Cache the T&C acceptance status in a short-lived signed cookie (5 min TTL) to avoid any Supabase call on repeat requests within the TTL window.

### Redirect loop prevention

`/accept-terms` and `/api/accept-terms` are both in `PUBLIC_PATHS`, so the middleware skips them entirely (returns `NextResponse.next()` before reaching the auth or T&C checks).

**Why `/api/accept-terms` must be in PUBLIC_PATHS:** Without it, the middleware would intercept the POST request, find the user has `tc_accepted_at IS NULL`, and redirect to `/accept-terms` -- breaking the acceptance flow. The API route has its own authentication via `createClient()` / `getUser()`, so bypassing the middleware auth check is safe.

**Why not use a path prefix like `/api/auth/` instead:** Adding individual paths to `PUBLIC_PATHS` is more explicit and auditable than wildcard patterns. The current list is small enough that individual entries are maintainable.

### Column-level grant compatibility

The `POST /api/accept-terms` route uses `createServiceClient()` (service role), which bypasses both RLS and column-level grants. This is consistent with how `callback/route.ts` and `api/workspace/route.ts` already write to `public.users`. The `authenticated` role cannot update `tc_accepted_at` due to migration 006 -- this is by design.

### WebSocket close code

Using `4004` with reason string "T&C not accepted". The WebSocket close code space 4000-4999 is reserved for application use.

| Code | Usage | Location |
|------|-------|----------|
| 4001 | Auth timeout / unauthorized | ws-handler.ts line 253, 288 |
| 4002 | Superseded by new connection | ws-handler.ts line 305 |
| 4003 | Auth required (first message not auth) | ws-handler.ts line 269, 275 |
| 4004 | T&C not accepted (new) | ws-handler.ts (this change) |

### Static assets unaffected

The middleware `config.matcher` already excludes `_next/static`, `_next/image`, `favicon.ico`, and common image extensions. Static assets never trigger the T&C check.

## Acceptance Criteria

- [x] Authenticated users with `tc_accepted_at IS NULL` are redirected to `/accept-terms` on every protected route
- [x] `/accept-terms` page renders with a clickwrap checkbox and submit button
- [x] Checkbox links to the live T&C and Privacy Policy URLs
- [x] Submitting the form POSTs to `/api/accept-terms`
- [x] `POST /api/accept-terms` sets `tc_accepted_at` to the current timestamp via service role
- [x] `POST /api/accept-terms` does NOT overwrite an existing `tc_accepted_at` (immutability)
- [x] After accepting, the user is redirected to `/dashboard`
- [x] Users who accepted T&C during signup (existing flow) are not affected -- they have `tc_accepted_at` set and proceed normally
- [x] WebSocket connections from users with `tc_accepted_at IS NULL` are rejected with close code 4004
- [x] `/accept-terms` page is accessible without triggering a redirect loop
- [x] `/api/accept-terms` is accessible from the accept-terms page (not blocked by middleware)
- [x] The `User` type in `lib/types.ts` includes `tc_accepted_at`
- [x] Existing middleware tests pass
- [x] New tests cover the T&C enforcement paths

## Test Scenarios

- Given an authenticated user with `tc_accepted_at IS NULL`, when they navigate to `/dashboard`, then they are redirected to `/accept-terms`
- Given an authenticated user with `tc_accepted_at IS NULL`, when they navigate to `/dashboard/chat/123`, then they are redirected to `/accept-terms`
- Given an authenticated user with `tc_accepted_at = '2026-01-01T00:00:00Z'`, when they navigate to `/dashboard`, then they proceed normally
- Given an unauthenticated user, when they navigate to `/dashboard`, then they are redirected to `/login` (existing behavior preserved)
- Given an authenticated user with `tc_accepted_at IS NULL`, when they visit `/accept-terms` and check the checkbox and submit, then `tc_accepted_at` is set to the current timestamp and they are redirected to `/dashboard`
- Given an authenticated user with existing `tc_accepted_at`, when `POST /api/accept-terms` is called, then the existing timestamp is NOT overwritten
- Given an unauthenticated request to `POST /api/accept-terms`, then a 401 response is returned
- Given an authenticated user with `tc_accepted_at IS NULL`, when they connect to the WebSocket `/ws`, then the connection is closed with code 4004 and reason "T&C not accepted"
- Given an authenticated user with valid `tc_accepted_at`, when they connect to the WebSocket `/ws`, then the connection proceeds normally
- Given `/accept-terms` is in `PUBLIC_PATHS`, when the middleware matches `/accept-terms`, then it does not redirect (no loop)
- Given `/api/accept-terms` is in `PUBLIC_PATHS`, when the middleware matches `/api/accept-terms`, then it does not redirect (allows POST to succeed)

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Extra DB query in middleware on every request | Primary key lookup on small table (~1-3ms). Documented v2 path with `getClaims()` + custom hook eliminates the query entirely. |
| Redirect loop if `/accept-terms` not in PUBLIC_PATHS | Both `/accept-terms` and `/api/accept-terms` added to PUBLIC_PATHS. |
| WebSocket close code collision with existing 4003 | Use 4004 instead. Close code table documented in Technical Considerations. |
| Service role required for tc_accepted_at write | Matches existing pattern (callback, workspace, stripe routes all use service role). |
| Grandfathered users blocked on next login | Intentional -- they must accept T&C to continue. The accept-terms page is the remediation path. |
| Users in active sessions when deployed | Next page navigation triggers middleware, redirecting to accept-terms. Active WebSocket sessions are unaffected until reconnect. |
| Supabase `getUser()` session refresh race | Supabase SSR docs confirm: `getUser()` refreshes the session if the access token is expiring. The `response` object from `setAll` callback captures the refreshed cookies. The T&C redirect returns a new `NextResponse.redirect()` which does not carry these cookies -- but this is fine because the browser will make a fresh request to `/accept-terms` which will trigger another `getUser()` call. |

## File Changes Summary

| File | Change |
|------|--------|
| `apps/web-platform/middleware.ts` | Add `tc_accepted_at` check after auth, add `/accept-terms` and `/api/accept-terms` to PUBLIC_PATHS |
| `apps/web-platform/app/(auth)/accept-terms/page.tsx` | New file -- accept-terms page component |
| `apps/web-platform/app/api/accept-terms/route.ts` | New file -- server-side T&C acceptance API route |
| `apps/web-platform/server/ws-handler.ts` | Add `tc_accepted_at` check after WebSocket auth |
| `apps/web-platform/lib/types.ts` | Add `tc_accepted_at` to `User` interface |
| `apps/web-platform/test/middleware.test.ts` | Add `/accept-terms` and `/api/accept-terms` to PUBLIC_PATHS, add T&C enforcement tests |
| `apps/web-platform/test/accept-terms.test.ts` | New file -- tests for accept-terms API route |

## References

### Internal

- Issue #933: No downstream enforcement of `tc_accepted_at` (this plan)
- Issue #931: `tc_accepted` metadata is client-controlled (forgeable consent)
- Issue #934: Remediate existing incorrectly-stamped rows
- Issue #925: Fallback INSERT unconditionally sets `tc_accepted_at` (fixed)
- Issue #889: T&C acceptance mechanism (original)
- Migration 005: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- Migration 006: `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`
- Middleware: `apps/web-platform/middleware.ts`
- Callback: `apps/web-platform/app/(auth)/callback/route.ts`
- Signup: `apps/web-platform/app/(auth)/signup/page.tsx`
- WS handler: `apps/web-platform/server/ws-handler.ts`
- Learning: `knowledge-base/learnings/2026-03-20-supabase-column-level-grant-override.md`
- Learning: `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md`

### External

- [GDPR Article 7 -- Conditions for consent](https://gdpr-info.eu/art-7-gdpr/)
- [Next.js Middleware](https://nextjs.org/docs/app/building-your-application/routing/middleware)
- [Supabase Auth -- getUser()](https://supabase.com/docs/reference/javascript/auth-getuser)
- [Supabase Auth -- getClaims()](https://supabase.com/docs/reference/javascript/auth-admin-oauth-getclient) -- future optimization path
- [Supabase Custom Access Token Hook](https://supabase.com/docs/guides/auth/custom-claims-and-role-based-access-control-rbac) -- for injecting tc_accepted_at into JWT claims
- [Supabase SSR Middleware Pattern](https://supabase.com/docs/guides/auth/server-side/creating-a-client) -- cookie handling requirements
- [Supabase Column-Level Security](https://supabase.com/docs/guides/database/postgres/column-level-security) -- why service role is needed for tc_accepted_at writes
