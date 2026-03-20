---
title: "security: enforce tc_accepted_at in middleware with server-side acceptance page"
type: fix
date: 2026-03-20
semver: patch
---

# security: enforce tc_accepted_at in middleware with server-side acceptance page

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

### Why a separate page, not inline in the callback?

1. **Distinct user action.** GDPR Article 7 requires consent to be "freely given, specific, informed and unambiguous indication of the data subject's wishes." A separate page with a checkbox is a clearer affirmative action than a redirect through a callback URL.
2. **Auditability.** The `POST /api/accept-terms` route creates a clean server-side record with no client-forgeable inputs.
3. **Reusability.** When T&C are updated, the same page can be re-shown to users who accepted a prior version.

## Proposed Solution

### 1. Middleware enhancement (`apps/web-platform/middleware.ts`)

After verifying the user is authenticated, query `public.users` for `tc_accepted_at`. If NULL, redirect to `/accept-terms`.

```typescript
// apps/web-platform/middleware.ts (additions)

// Add /accept-terms to PUBLIC_PATHS so the redirect does not loop
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws", "/accept-terms"];

// After auth check (line 54-60 in current file):
// Query tc_accepted_at from users table
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

**Performance consideration:** This adds one Supabase query per protected request. The `users` table is small (primary key lookup) and already queried in the callback route. For a pre-launch product with minimal users this is acceptable. If performance becomes a concern post-launch, `tc_accepted_at` can be cached in the JWT custom claims via a Supabase hook, eliminating the DB query. That optimization is out of scope for this fix.

### 2. Accept-terms page (`apps/web-platform/app/(auth)/accept-terms/page.tsx`)

A client component with:
- T&C text or link (matching the signup page pattern)
- Required checkbox
- Submit button that POSTs to `/api/accept-terms`
- Redirect to `/dashboard` on success (or `/setup-key` if no API key)

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
  ws.close(4003, "T&C not accepted");
  return;
}
```

This closes the WebSocket bypass path -- without this, a user could skip the middleware-protected pages and connect directly to `/ws` (which is in `PUBLIC_PATHS`).

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
- T&C enforcement logic (user with NULL `tc_accepted_at` redirects to `/accept-terms`)
- User with non-NULL `tc_accepted_at` proceeds normally

#### New test: `apps/web-platform/test/accept-terms.test.ts`

Test the API route logic:
- Unauthenticated request returns 401
- Authenticated user with NULL `tc_accepted_at` gets it set
- Authenticated user with existing `tc_accepted_at` is not re-stamped (immutability)

## Non-goals

- **Removing the signup checkbox.** The existing signup clickwrap remains as-is. It provides a better UX for new users who accept during signup. The accept-terms page is for users who bypassed or were grandfathered.
- **T&C version tracking.** This fix gates on `tc_accepted_at IS NOT NULL` without versioning. T&C version tracking (re-showing acceptance when terms change) is a separate feature.
- **JWT custom claims caching.** Moving `tc_accepted_at` into JWT claims to avoid the DB query on every request is a performance optimization for later.
- **Remediating existing incorrect rows (#934).** That is a separate data migration issue.
- **Removing client-side `tc_accepted` metadata from signup.** The metadata is still useful for the trigger path. The server-side acceptance page is the enforcement layer; the metadata is a convenience layer.

## Technical Considerations

### Middleware performance

The middleware now makes two Supabase calls per protected request: `auth.getUser()` (existing) and a `users` table query (new). For a pre-launch product this is acceptable. The `users` query is a primary key lookup and returns a single column.

If this becomes a bottleneck:
1. Add `tc_accepted_at` to JWT custom claims via a Supabase auth hook (eliminates the DB query)
2. Or cache the result in a short-lived cookie (5 min TTL)

### Redirect loop prevention

`/accept-terms` is in `PUBLIC_PATHS`, so the middleware will not re-check T&C for that page. The `/api/accept-terms` endpoint is under `/api/` which is NOT in `PUBLIC_PATHS` but is covered by the auth check (returns 401 if unauthenticated). Since the middleware redirects to `/accept-terms` (not `/api/accept-terms`), there is no loop.

Wait -- the API route `/api/accept-terms` is NOT in `PUBLIC_PATHS`. The middleware will intercept it, find the user has NULL `tc_accepted_at`, and redirect to `/accept-terms` -- breaking the POST. Fix: either add `/api/accept-terms` to `PUBLIC_PATHS`, or restructure to bypass the T&C check for API routes that serve the acceptance flow.

The cleanest approach: add `/api/accept-terms` to `PUBLIC_PATHS`. The route already authenticates via `createClient()` internally, so the middleware auth check is redundant for it.

### Column-level grant compatibility

The `POST /api/accept-terms` route uses `createServiceClient()` (service role), which bypasses both RLS and column-level grants. This is consistent with how `callback/route.ts` and `api/workspace/route.ts` already write to `public.users`.

### WebSocket close code

Using `4003` for T&C not accepted. The WebSocket close code space 4000-4999 is reserved for application use. This is consistent with the existing codes: `4001` (auth timeout/unauthorized), `4002` (superseded connection), `4003` (auth required -- repurposed for T&C check). Consider using `4004` instead to avoid collision with the existing "Auth required" usage of `4003`. Will use `4004` with reason string "T&C not accepted".

## Acceptance Criteria

- [ ] Authenticated users with `tc_accepted_at IS NULL` are redirected to `/accept-terms` on every protected route
- [ ] `/accept-terms` page renders with a clickwrap checkbox and submit button
- [ ] Checkbox links to the live T&C and Privacy Policy URLs
- [ ] Submitting the form POSTs to `/api/accept-terms`
- [ ] `POST /api/accept-terms` sets `tc_accepted_at` to the current timestamp via service role
- [ ] `POST /api/accept-terms` does NOT overwrite an existing `tc_accepted_at` (immutability)
- [ ] After accepting, the user is redirected to `/dashboard`
- [ ] Users who accepted T&C during signup (existing flow) are not affected -- they have `tc_accepted_at` set and proceed normally
- [ ] WebSocket connections from users with `tc_accepted_at IS NULL` are rejected with close code 4004
- [ ] `/accept-terms` page is accessible without triggering a redirect loop
- [ ] `/api/accept-terms` is accessible from the accept-terms page (not blocked by middleware)
- [ ] The `User` type in `lib/types.ts` includes `tc_accepted_at`
- [ ] Existing middleware tests pass
- [ ] New tests cover the T&C enforcement paths

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
| Extra DB query in middleware on every request | Primary key lookup on small table. Cache in JWT claims if needed post-launch. |
| Redirect loop if `/accept-terms` is not in PUBLIC_PATHS | `/accept-terms` and `/api/accept-terms` both added to PUBLIC_PATHS. |
| WebSocket close code collision with existing 4003 | Use 4004 instead. |
| Service role required for tc_accepted_at write | Matches existing pattern (callback, workspace, stripe routes all use service role). |
| Grandfathered users blocked on next login | Intentional -- they must accept T&C to continue. The accept-terms page is the remediation path. |
| Users in active sessions when deployed | Next page navigation triggers middleware, redirecting to accept-terms. Active WebSocket sessions are unaffected until reconnect. |

## File Changes Summary

| File | Change |
|------|--------|
| `apps/web-platform/middleware.ts` | Add `tc_accepted_at` check after auth, add `/accept-terms` and `/api/accept-terms` to PUBLIC_PATHS |
| `apps/web-platform/app/(auth)/accept-terms/page.tsx` | New file -- accept-terms page component |
| `apps/web-platform/app/api/accept-terms/route.ts` | New file -- server-side T&C acceptance API route |
| `apps/web-platform/server/ws-handler.ts` | Add `tc_accepted_at` check after WebSocket auth |
| `apps/web-platform/lib/types.ts` | Add `tc_accepted_at` to `User` interface |
| `apps/web-platform/test/middleware.test.ts` | Add `/accept-terms` to PUBLIC_PATHS, add T&C enforcement tests |
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
