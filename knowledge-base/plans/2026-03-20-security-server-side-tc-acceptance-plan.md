---
title: "security: move T&C acceptance to server-side action"
type: fix
date: 2026-03-20
issue: "#931"
priority: P2
labels: [legal, priority/p2-medium, type/bug]
semver: patch
---

# security: move T&C acceptance to server-side action

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Test Scenarios, Attack Surface, Edge Cases)
**Research sources:** Supabase SSR docs (Context7), Supabase auth migration guide, codebase analysis (callback/route.ts, signup/page.tsx, middleware.ts, migrations 005-006), institutional learnings (trigger-fallback-parity, column-level-grant-override)

### Key Improvements
1. **getClaims() over getUser()**: Supabase docs now recommend `getClaims()` for middleware auth validation -- it verifies JWT locally via JWKS without a network request, unlike `getUser()` which always hits the auth server. The existing middleware should be migrated as part of this change.
2. **Redirect loop prevention**: If the `users` row does not yet exist (race between trigger and first middleware hit), the middleware T&C check would redirect to `/accept-terms` infinitely. Added a guard: treat missing `users` row the same as `tc_accepted_at IS NULL` but without a redirect loop by allowing `/accept-terms` through unconditionally.
3. **Cookie response preservation**: Supabase SSR docs emphasize that middleware MUST return the `supabaseResponse` object (not a fresh `NextResponse`). All redirect responses must copy cookies from the supabase response to prevent session desync and random logouts.
4. **Service role client isolation**: SSR clients initialized with service role keys inherit user sessions from cookies, causing RLS errors. The plan correctly uses `createClient()` from `@supabase/supabase-js` (not `createServerClient` from `@supabase/ssr`) for service role operations.
5. **Accept-terms redirect target**: The accept-terms page should check API key status after recording acceptance and redirect to `/setup-key` or `/dashboard` accordingly, rather than always routing to `/setup-key`.

### New Considerations Discovered
- The existing middleware uses `getUser()` which makes a network request on every request. Migrating to `getClaims()` is a performance improvement that should be bundled with this change since we're already modifying the middleware.
- Next.js middleware cannot use `cookies()` from `next/headers` -- it must use the request/response cookie pattern. The plan's API route correctly uses `createClient()` (which uses `cookies()`) but the middleware must use the `createServerClient` pattern with request cookies.
- The `supabase.from("users").select()` query in middleware uses the anon key client, which goes through RLS. The existing RLS SELECT policy must allow users to read their own row. This should be verified before implementation.

## Overview

The `tc_accepted` field in Supabase `user_metadata` is set client-side during signup via `signInWithOtp({ options: { data: { tc_accepted: true } } })`. An attacker can call the Supabase auth endpoint directly with `tc_accepted: true` without ever rendering the signup form or checking the T&C checkbox. Both the SQL trigger (`005_add_tc_accepted_at.sql`) and the TypeScript fallback (`callback/route.ts`) trust this client-controlled field.

This fix moves T&C acceptance to a distinct server-side action: after auth callback, users with `tc_accepted_at IS NULL` are redirected to a dedicated acceptance page that writes `tc_accepted_at` via a server route using the service role client. This also addresses #933 (no downstream enforcement of `tc_accepted_at`).

## Problem Statement

Under GDPR Article 7, consent records must be backed by actual affirmative action. The current mechanism records consent based on a client-controlled metadata field that an attacker can forge by calling the Supabase auth API directly. This undermines the legal enforceability of the T&C acceptance record.

**Root cause:** The consent recording mechanism trusts client-supplied data (`user_metadata.tc_accepted`) as the source of truth for a legally significant action.

**Impact:** Forgeable consent records. The current mechanism works for honest users but is trivially bypassed.

## Proposed Solution

Replace the client-side metadata-based T&C recording with a two-step server-side flow:

1. **Stop trusting `tc_accepted` metadata.** Remove `tc_accepted: tcAccepted` from the signup `signInWithOtp` call. Remove the conditional `tc_accepted_at` setting from both the trigger and the callback fallback -- new users always start with `tc_accepted_at = NULL`.

2. **Add a T&C acceptance page** at `/accept-terms`. This is a server-rendered page that:
   - Displays the T&C checkbox and links (similar to the current signup form's checkbox)
   - On submission, calls a server API route that writes `tc_accepted_at` using the service role client
   - Only accessible to authenticated users with `tc_accepted_at IS NULL`

3. **Add middleware enforcement.** Extend `middleware.ts` to check `tc_accepted_at` on the `users` table. If `NULL`, redirect to `/accept-terms` instead of the dashboard. This gates all platform access on server-verified T&C acceptance.

4. **Update the callback route.** After auth exchange, redirect users with `tc_accepted_at IS NULL` to `/accept-terms` instead of `/dashboard` or `/setup-key`.

### Attack Surface Enumeration

All code paths that write `tc_accepted_at`:

| Path | Location | After Fix |
|------|----------|-----------|
| `handle_new_user()` trigger | `005_add_tc_accepted_at.sql` | Always sets `NULL` (no longer reads metadata) |
| Fallback INSERT | `callback/route.ts` | Always sets `NULL` (no longer reads metadata) |
| **New: Accept Terms API** | `app/api/accept-terms/route.ts` | Sets `now()` via service role client after server-side form submission |

All code paths that read `tc_accepted_at`:

| Path | Location | After Fix |
|------|----------|-----------|
| **New: Middleware check** | `middleware.ts` | Redirects to `/accept-terms` if `NULL` |
| **New: Callback redirect** | `callback/route.ts` | Redirects to `/accept-terms` if `NULL` |

**Bypass analysis:**
- Direct Supabase auth API call: User gets authenticated but `tc_accepted_at` stays `NULL`. Middleware blocks access to any protected route until they visit `/accept-terms` and submit the form.
- Direct call to `/api/accept-terms`: Requires valid auth session (middleware enforces this). The server route verifies the session via `getUser()` and writes using service role. No client-controlled metadata involved.
- RLS bypass: Migration `006_restrict_tc_accepted_at_update.sql` already prevents authenticated users from writing `tc_accepted_at` directly. The service role client bypasses RLS by design (it is a server-side trusted client).
- CSRF on POST `/api/accept-terms`: Next.js API routes in App Router are same-origin by default (no CORS). The `fetch()` call from the accept-terms page includes the session cookie automatically. An attacker-controlled page cannot POST to `/api/accept-terms` with the victim's cookies because the request originates from a different origin (blocked by SameSite cookie attribute, which Supabase sets by default). No additional CSRF token needed.
- Replay/re-stamp attack: The `AND tc_accepted_at IS NULL` guard in the UPDATE query prevents re-stamping. Once set, the timestamp is immutable from both the client side (RLS) and the server side (idempotency guard). Only a service role migration can reset it.
- Session fixation: The auth session is validated via `getClaims()` / `getUser()` which verifies the JWT. A stolen or fixated session cannot bypass the T&C check -- the middleware still queries the `users` row for that session's user ID.

## Technical Considerations

### Files to Modify

1. **`apps/web-platform/app/(auth)/signup/page.tsx`** -- Remove `tc_accepted` from `signInWithOtp` options.data. Keep the checkbox UI as a client-side UX hint (disabled submit button) but do not send the value to Supabase metadata.

2. **`apps/web-platform/supabase/migrations/007_remove_tc_accepted_metadata_trust.sql`** -- New migration that updates `handle_new_user()` to always set `tc_accepted_at = NULL`. The column comment should be updated to reflect that acceptance is now recorded by the server-side accept-terms route.

3. **`apps/web-platform/app/(auth)/callback/route.ts`** -- Remove `tcAccepted` extraction and parameter passing. `ensureWorkspaceProvisioned` reverts to `(userId, email)` signature. Fallback INSERT always sets `tc_accepted_at: null`. After workspace provisioning, check `tc_accepted_at` on the user row: if `NULL`, redirect to `/accept-terms`; otherwise redirect to `/setup-key` or `/dashboard` as before.

4. **`apps/web-platform/app/(auth)/accept-terms/page.tsx`** -- New page. Server component or client component that renders the T&C acceptance form (checkbox + links + submit button). On submission, calls `POST /api/accept-terms`.

5. **`apps/web-platform/app/api/accept-terms/route.ts`** -- New API route. Validates auth session via `createClient()` + `getUser()`. Uses `createServiceClient()` to UPDATE `users SET tc_accepted_at = now() WHERE id = <user_id> AND tc_accepted_at IS NULL`. Returns success/failure. The `AND tc_accepted_at IS NULL` guard makes the operation idempotent and prevents re-stamping.

6. **`apps/web-platform/middleware.ts`** -- Add `/accept-terms` to `PUBLIC_PATHS` (it is accessible to authenticated users who haven't accepted T&C). For authenticated users on non-public paths, query `users.tc_accepted_at` and redirect to `/accept-terms` if `NULL`. This requires a lightweight DB query in middleware -- use the session's Supabase client (not service role) to read the user's own row.

### Research Insights -- Supabase Auth Best Practices (Context7)

**Use `getClaims()` instead of `getUser()` in middleware:**
Supabase docs (2025+) recommend `getClaims()` for middleware auth validation. It verifies the JWT locally against the project's JWKS endpoint (`/.well-known/jwks.json`), which is cached, resulting in significantly faster responses than `getUser()` which always sends a network request to the auth server. The existing middleware uses `getUser()` -- this should be migrated to `getClaims()` as part of this change.

```typescript
// Before (current -- network request every time)
const { data: { user } } = await supabase.auth.getUser();

// After (recommended -- local JWT verification, often cached)
const { data } = await supabase.auth.getClaims();
const user = data?.claims;
```

**Critical: No code between client creation and auth check:**
Supabase docs warn: "Do not run code between createServerClient and supabase.auth.getClaims(). A simple mistake could make it very hard to debug issues with users being randomly logged out." The middleware T&C query must happen AFTER the auth check, not between client creation and auth validation.

**Cookie response preservation:**
The middleware MUST return the `supabaseResponse` object as-is. When creating redirect responses, cookies must be copied from the supabase response to the redirect response to prevent session desynchronization:

```typescript
// When redirecting, copy cookies to prevent session desync
const redirectUrl = request.nextUrl.clone();
redirectUrl.pathname = "/accept-terms";
const redirectResponse = NextResponse.redirect(redirectUrl);
supabaseResponse.cookies.getAll().forEach(cookie =>
  redirectResponse.cookies.set(cookie.name, cookie.value)
);
return redirectResponse;
```

**Service role client isolation:**
SSR clients (`createServerClient`) initialized with a service role key will have the user session override the Authorization header from cookies, causing RLS errors. Always use `createClient` from `@supabase/supabase-js` directly for service role operations -- never the SSR wrapper. The plan's `createServiceClient()` correctly uses `createClient` from `@supabase/supabase-js`.

### Middleware Performance Consideration

Adding a DB query to middleware on every request is a concern. Mitigation options:

- **Option A (recommended):** Query `tc_accepted_at` from the `users` table using the session client. This goes through RLS (user can only read their own row). Supabase reads from the `users` table are indexed by `id` (primary key) -- this is a single-row lookup, sub-millisecond in practice. Additionally, migrating from `getUser()` to `getClaims()` eliminates one network request per middleware invocation, partially offsetting the new DB query.
- **Option B:** Store `tc_accepted` in a JWT custom claim via Supabase Auth hook. This avoids the DB query entirely but requires configuring a Supabase Auth hook (additional infrastructure complexity).

Option A is preferred for simplicity. The net performance impact is approximately neutral: `getClaims()` saves one network request (auth server round-trip), the `users` query adds one (Supabase PostgREST round-trip). Both are to the same Supabase instance, and the PK lookup is faster than JWT verification on the auth server.

### Research Insights -- Edge Cases and Redirect Loops

**Redirect loop when `users` row does not exist:**
There is a race window between the auth trigger creating the `users` row and the first middleware check. If the trigger has not fired yet (or fails), the middleware query returns no row, which is indistinguishable from `tc_accepted_at IS NULL`. The middleware must handle this gracefully:
- If `userRow` is `null` (no row at all), redirect to `/accept-terms` -- the accept-terms page will handle the "row not created yet" case by showing the form and relying on the API route to wait for the row to exist.
- No infinite redirect loop risk because `/accept-terms` is in `PUBLIC_PATHS` and is not subject to the T&C check.

**RLS SELECT policy prerequisite:**
The middleware uses the anon-key session client to query `users.tc_accepted_at`. This query goes through RLS. Verify that the existing RLS SELECT policy allows authenticated users to read their own row. Check `001_initial_schema.sql` for the policy definition. If no SELECT policy exists for `tc_accepted_at`, the query will return empty results and trigger an unnecessary redirect.

**API route paths and middleware:**
Both `/api/accept-terms` and `/accept-terms` must be in `PUBLIC_PATHS`. However, other API routes (`/api/keys`, `/api/checkout`, `/api/workspace`) should NOT be in `PUBLIC_PATHS` -- they are gated by both auth AND T&C acceptance. A user who bypasses T&C should not be able to call these endpoints.

### Interaction with Existing Migrations

- `005_add_tc_accepted_at.sql`: The trigger's conditional logic becomes dead code since we always set `NULL`. Migration 007 replaces the function to always set `NULL`, making the intent explicit.
- `006_restrict_tc_accepted_at_update.sql`: Still needed -- prevents authenticated users from writing `tc_accepted_at` via client-side Supabase calls. The service role client bypasses RLS by design.

### Interaction with Related Issues

- **#933 (no downstream enforcement):** This plan fully addresses #933 by adding middleware enforcement. The PR body should include `Closes #933`.
- **#934 (remediate existing incorrectly-stamped rows):** Out of scope for this PR. Existing rows with potentially forged `tc_accepted_at` values need a separate migration/audit. However, the middleware enforcement means these users will still be able to access the platform (they have `tc_accepted_at IS NOT NULL`). A separate issue should determine whether to null out and re-prompt those users.

## Acceptance Criteria

- [ ] `signInWithOtp` in signup page no longer sends `tc_accepted` in metadata (`apps/web-platform/app/(auth)/signup/page.tsx`)
- [ ] New migration `007_remove_tc_accepted_metadata_trust.sql` updates `handle_new_user()` to always set `tc_accepted_at = NULL`
- [ ] Callback route no longer reads `user_metadata.tc_accepted`; fallback INSERT always sets `tc_accepted_at: null` (`apps/web-platform/app/(auth)/callback/route.ts`)
- [ ] New `/accept-terms` page renders T&C checkbox with links to Terms & Conditions and Privacy Policy (`apps/web-platform/app/(auth)/accept-terms/page.tsx`)
- [ ] New `POST /api/accept-terms` route writes `tc_accepted_at` via service role client with `AND tc_accepted_at IS NULL` idempotency guard (`apps/web-platform/app/api/accept-terms/route.ts`)
- [ ] Callback route redirects to `/accept-terms` when `tc_accepted_at IS NULL` on the user row
- [ ] Middleware redirects authenticated users with `tc_accepted_at IS NULL` to `/accept-terms` for all protected routes (`apps/web-platform/middleware.ts`)
- [ ] `/accept-terms` and `/api/accept-terms` are in the middleware public paths list
- [ ] Signup form still shows the T&C checkbox (disabled submit) as UX hint but does not transmit the value to Supabase
- [ ] Middleware migrated from `getUser()` to `getClaims()` for auth validation performance
- [ ] All middleware redirect responses copy cookies from `supabaseResponse` to prevent session desync
- [ ] RLS SELECT policy on `public.users` verified to allow reading `tc_accepted_at` for authenticated users

## Test Scenarios

- Given a new user who signs up normally, when they complete the magic link flow, then they are redirected to `/accept-terms` (not dashboard)
- Given a user on `/accept-terms` who checks the T&C box and submits, when the POST succeeds, then `tc_accepted_at` is set to a non-null timestamp and they are redirected to `/setup-key` or `/dashboard`
- Given an attacker who calls the Supabase auth API directly with `tc_accepted: true` in metadata, when they try to access `/dashboard`, then middleware redirects them to `/accept-terms` (metadata is ignored)
- Given a user who has already accepted T&C (`tc_accepted_at IS NOT NULL`), when they log in, then they proceed to `/dashboard` without seeing `/accept-terms`
- Given a user on `/accept-terms` who submits the form twice, when the second POST fires, then the `AND tc_accepted_at IS NULL` guard makes it a no-op (idempotent)
- Given an unauthenticated user who visits `/accept-terms` directly, when middleware runs, then they are redirected to `/login`
- Given a user with `tc_accepted_at IS NULL` who tries to access `/api/keys` or any protected route, when middleware runs, then they are redirected to `/accept-terms`
- Given a new user whose `users` row has not yet been created by the trigger (race condition), when middleware queries `tc_accepted_at`, then the query returns no row and the user is redirected to `/accept-terms` (no crash, no infinite loop)
- Given a user on `/accept-terms` who has already accepted (navigated back), when the page loads, then they are redirected to `/dashboard` (or the page shows "already accepted" state)
- Given a user who completes the accept-terms flow, when they are redirected, then the redirect goes to `/setup-key` if no valid API key exists, or `/dashboard` if one does

### Research Insights -- Additional Edge Cases

- **Middleware cookie preservation on redirect:** When the middleware redirects to `/accept-terms`, it must copy all cookies from the `supabaseResponse` to the redirect response. Failing to do this causes session desynchronization -- the browser and server go out of sync, leading to random logouts on subsequent requests. This is documented in Supabase's SSR migration guide.
- **`getClaims()` returns `user_metadata`:** The claims object includes `user_metadata` which still contains the attacker-forged `tc_accepted: true`. This field is irrelevant after the fix (we never read it server-side), but it is worth noting that the metadata persists in the JWT. It does not affect security because the middleware checks the `users` table, not the JWT claims.
- **Concurrent accept-terms submissions:** Two browser tabs open on `/accept-terms`, both submit simultaneously. The first UPDATE succeeds (sets `tc_accepted_at`). The second UPDATE matches zero rows (`tc_accepted_at IS NULL` is no longer true) and is a no-op. Both POST responses return 200. The Supabase `.update()` does not return an error when zero rows match -- it returns `data: null` with no error. The API route should not treat this as an error.

## Non-Goals

- Remediating existing rows with potentially forged `tc_accepted_at` values (tracked in #934)
- Adding comprehensive test infrastructure for the callback route (pre-existing gap, not introduced here)
- Implementing JWT custom claims for `tc_accepted` (Option B middleware optimization -- only if performance proves problematic)
- Changing the subscription/checkout T&C flow (tracked separately in the cancellation policy work)

## MVP

### apps/web-platform/supabase/migrations/007_remove_tc_accepted_metadata_trust.sql

```sql
-- Stop trusting client-supplied tc_accepted metadata.
-- T&C acceptance is now recorded by the server-side /api/accept-terms route.
-- New users always start with tc_accepted_at = NULL until they explicitly
-- accept terms on the /accept-terms page.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, workspace_path, tc_accepted_at)
  VALUES (
    new.id,
    new.email,
    '/workspaces/' || new.id::text,
    NULL  -- always NULL; server-side acceptance route sets the real timestamp
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON COLUMN public.users.tc_accepted_at IS
  'Timestamp when user accepted T&C via server-side /accept-terms page. NULL = not yet accepted. Set exclusively by POST /api/accept-terms using service role client.';
```

### apps/web-platform/app/(auth)/signup/page.tsx

Remove `tc_accepted` from OTP options. Keep checkbox as UX guard only:

```typescript
const { error } = await supabase.auth.signInWithOtp({
  email,
  options: {
    emailRedirectTo: `${window.location.origin}/callback`,
    // tc_accepted is NOT sent in metadata -- acceptance is recorded
    // server-side via /accept-terms after auth callback
  },
});
```

### apps/web-platform/app/(auth)/callback/route.ts

Remove `tcAccepted` logic. Check `tc_accepted_at` on user row for redirect:

```typescript
if (user) {
  await ensureWorkspaceProvisioned(user.id, user.email ?? "");

  // Check T&C acceptance status
  const serviceClient = createServiceClient();
  const { data: userRow } = await serviceClient
    .from("users")
    .select("tc_accepted_at")
    .eq("id", user.id)
    .single();

  if (!userRow?.tc_accepted_at) {
    return NextResponse.redirect(`${origin}/accept-terms`);
  }

  // Check if user has an API key set up
  const { data: keys } = await supabase
    .from("api_keys")
    .select("id")
    .eq("user_id", user.id)
    .eq("provider", "anthropic")
    .eq("is_valid", true)
    .limit(1);

  if (!keys || keys.length === 0) {
    return NextResponse.redirect(`${origin}/setup-key`);
  }
  return NextResponse.redirect(`${origin}/dashboard`);
}
```

### apps/web-platform/app/(auth)/accept-terms/page.tsx

New client component for T&C acceptance:

```typescript
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AcceptTermsPage() {
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const router = useRouter();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const res = await fetch("/api/accept-terms", { method: "POST" });

    if (!res.ok) {
      setError("Failed to record acceptance. Please try again.");
      setLoading(false);
      return;
    }

    router.push("/setup-key");
  }

  // Renders checkbox + T&C/Privacy links + submit button
  // (similar to signup form's checkbox section)
}
```

### apps/web-platform/app/api/accept-terms/route.ts

New server route that records acceptance:

```typescript
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

export async function POST() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();
  const { error } = await serviceClient
    .from("users")
    .update({ tc_accepted_at: new Date().toISOString() })
    .eq("id", user.id)
    .is("tc_accepted_at", null); // idempotency guard

  if (error) {
    console.error("[accept-terms] Failed to record acceptance:", error);
    return NextResponse.json(
      { error: "Failed to record acceptance" },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true });
}
```

### apps/web-platform/middleware.ts

Add T&C enforcement. Migrate from `getUser()` to `getClaims()` for performance. Preserve cookies on all redirect responses:

```typescript
const PUBLIC_PATHS = [
  "/login",
  "/signup",
  "/callback",
  "/accept-terms",
  "/api/accept-terms",
  "/api/webhooks",
  "/ws",
];

// ... inside middleware function, after creating supabase client ...

// IMPORTANT: Do not run code between createServerClient and getClaims().
const { data } = await supabase.auth.getClaims();
const user = data?.claims;

if (!user) {
  const url = request.nextUrl.clone();
  url.pathname = "/login";
  const redirectResponse = NextResponse.redirect(url);
  // Preserve cookies to prevent session desync
  supabaseResponse.cookies.getAll().forEach(cookie =>
    redirectResponse.cookies.set(cookie.name, cookie.value)
  );
  return redirectResponse;
}

// Check T&C acceptance for non-public paths
const { data: userRow } = await supabase
  .from("users")
  .select("tc_accepted_at")
  .eq("id", user.sub)  // getClaims() returns claims object; user ID is in 'sub'
  .single();

if (!userRow?.tc_accepted_at) {
  const url = request.nextUrl.clone();
  url.pathname = "/accept-terms";
  const redirectResponse = NextResponse.redirect(url);
  // CRITICAL: Copy cookies to redirect response to prevent session desync
  supabaseResponse.cookies.getAll().forEach(cookie =>
    redirectResponse.cookies.set(cookie.name, cookie.value)
  );
  return redirectResponse;
}

return supabaseResponse;
```

### Research Insights -- Middleware Implementation Details

**`getClaims()` vs `getUser()` migration:**
The `getClaims()` method returns a `claims` object with standard JWT fields (`sub`, `email`, `aud`, `exp`, `user_metadata`, `app_metadata`). The user ID is in `claims.sub` (not `claims.id`). When migrating, replace `user.id` references in middleware with `user.sub`.

**`supabaseResponse` must be returned:**
Supabase SSR docs state: "You *must* return the supabaseResponse object as it is." When creating redirect responses, all cookies from the supabase response must be copied to the redirect. Failure to do this causes the browser and server to go out of sync, terminating the user's session prematurely.

**RLS SELECT check (verified):**
The `supabase.from("users").select("tc_accepted_at")` query uses the session's anon-key client with the user's JWT. The existing RLS SELECT policy in `001_initial_schema.sql` is: `"Users can read own profile" on public.users for select using (auth.uid() = id)`. This is a table-level policy covering all columns, including `tc_accepted_at`. No additional migration needed for the middleware query to work.

## References

- Issue: #931 -- forgeable `tc_accepted` metadata
- Issue: #933 -- no downstream enforcement of `tc_accepted_at` (addressed by this plan)
- Issue: #934 -- remediate existing incorrectly-stamped rows (out of scope)
- Issue: #889 -- original T&C acceptance mechanism
- Issue: #925 -- fallback INSERT parity fix (already merged, partially superseded by this plan)
- Learning: `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md`
- Learning: `knowledge-base/learnings/2026-03-20-supabase-column-level-grant-override.md`
- Migration: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- Migration: `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`
- Callback route: `apps/web-platform/app/(auth)/callback/route.ts`
- Signup page: `apps/web-platform/app/(auth)/signup/page.tsx`
- Middleware: `apps/web-platform/middleware.ts`
