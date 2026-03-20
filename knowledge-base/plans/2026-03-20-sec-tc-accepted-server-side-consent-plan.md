---
title: "sec: record T&C consent acceptance server-side"
type: fix
date: 2026-03-20
issue: "#943"
priority: P3
labels: [security, priority/p3-low, type/feature]
semver: patch
---

# sec: record T&C consent acceptance server-side

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6 (Problem Statement, Proposed Solution, Technical Considerations, Test Scenarios, Attack Surface, Edge Cases)
**Research sources:** Supabase official docs (Context7 -- RLS helper functions, auth admin API, exchangeCodeForSession, metadata security model), codebase analysis (callback/route.ts, signup/page.tsx, login/page.tsx, types.ts, migrations 001-006), institutional learnings (trigger-fallback-parity, column-level-grant-override)

### Key Improvements
1. Confirmed via Supabase docs that `raw_user_meta_data` is explicitly documented as client-writable via `supabase.auth.update()` -- this is by-design, not a misconfiguration, making the vulnerability unfixable at the metadata level
2. Identified `raw_app_meta_data` as Supabase's recommended alternative for server-only authorization data -- but the plan correctly avoids metadata entirely for maximum isolation
3. Discovered critical `ignoreDuplicates: true` upsert bug -- with Option A (trigger removes `tc_accepted_at`), the trigger creates the row first, then the callback's upsert is a no-op because `ignoreDuplicates` skips updates; `tc_accepted_at` would stay NULL permanently for every user
4. Found `User` interface in `types.ts` is missing `tc_accepted_at` field -- needs update for type safety
5. Confirmed login page uses `shouldCreateUser: false` and never passes `tc_accepted` -- the fix has zero impact on login flow

### New Considerations Discovered
- The `ignoreDuplicates: true` upsert semantics are the primary implementation trap -- must switch to either merge-on-conflict or a separate UPDATE after SELECT
- `raw_app_meta_data` (set via `updateUserById` with service role) would be an alternative approach, but the plan's "no metadata" approach is superior because it eliminates the metadata indirection entirely
- The `User` TypeScript interface omission creates a type hole that could cause silent runtime errors

## Overview

The `tc_accepted` flag in `auth.users.raw_user_meta_data` is client-writable by Supabase design. A user can call `supabase.auth.updateUser({ data: { tc_accepted: true } })` directly, forging consent evidence without interacting with the signup checkbox. The current system trusts this client-controlled metadata as ground truth for GDPR Article 7(1) consent records.

The fix moves consent recording server-side: after `exchangeCodeForSession` succeeds in the callback route, the server sets `tc_accepted_at` via the service client based on a server-verified condition, eliminating reliance on client-writable metadata.

### Research Insights

**Supabase metadata security model (confirmed via official docs):**

Supabase's RLS documentation explicitly states:

> `raw_user_meta_data` - can be updated by the authenticated user using the `supabase.auth.update()` function. It is not a good place to store authorization data.
> `raw_app_meta_data` - cannot be updated by the user, so it's a good place to store authorization data.

This is documented in [Supabase RLS guide](https://supabase.com/docs/guides/auth/row-level-security) and [Database RLS policies](https://supabase.com/docs/guides/getting-started/ai-prompts/database-rls-policies). The vulnerability in #943 is not a misconfiguration -- it is an inherent property of using `raw_user_meta_data` for authorization-adjacent data.

**Alternative considered and rejected: `raw_app_meta_data`.** The admin method `updateUserById()` can set `raw_app_meta_data` server-side, which users cannot modify. However, this approach still stores consent state in the auth layer rather than the application layer. The plan's approach (direct `public.users.tc_accepted_at` write via service client) is preferred because it keeps the consent record in the application's own table with full control over the write path.

## Problem Statement

Three code paths currently read `tc_accepted` from `raw_user_meta_data` and trust it as proof of consent:

1. **Database trigger** (`005_add_tc_accepted_at.sql:19`): `handle_new_user()` checks `raw_user_meta_data->>'tc_accepted'` on `auth.users` INSERT.
2. **Callback fallback** (`callback/route.ts:29-31`): Reads `user.user_metadata?.tc_accepted` after `exchangeCodeForSession`.
3. **Both paths** write `tc_accepted_at` to `public.users` based on this untrusted value.

The vulnerability: `raw_user_meta_data` is a JSONB column that Supabase's auth API allows users to update via `auth.updateUser()`. Any authenticated user -- or even during the signup flow -- can inject `tc_accepted: true` without checking the checkbox. The T&C acceptance timestamp then records consent that never happened.

Migration 006 correctly prevents users from directly updating `tc_accepted_at` in `public.users`, but the forgery vector is upstream: the `raw_user_meta_data` source itself is tainted.

### Research Insights -- Exploit Scenario

A concrete exploit path:

1. Attacker calls Supabase REST API directly: `POST /auth/v1/signup` with `{"email": "attacker@example.com", "data": {"tc_accepted": true}}`
2. The attacker never sees the signup page or T&C checkbox
3. The `handle_new_user()` trigger fires, reads `raw_user_meta_data->>'tc_accepted' = 'true'`, and stamps `tc_accepted_at = now()`
4. Result: a legally binding consent record exists for consent that never occurred

Even without direct REST API access, `supabase.auth.updateUser({ data: { tc_accepted: true } })` from any authenticated client-side code achieves the same result.

## Proposed Solution

Replace the client-metadata-based consent recording with a server-side mechanism tied to a verifiable condition. The approach:

1. **Remove `tc_accepted` from `options.data`** in the signup page's `signInWithOtp` call. The client no longer passes consent state through Supabase auth metadata.

2. **Record consent server-side in the callback route.** After `exchangeCodeForSession` succeeds, check a server-verifiable condition and set `tc_accepted_at` via the service client. The server-verifiable condition is: the user arrived at the callback from the signup flow (not login), which is the flow that requires T&C acceptance.

3. **Distinguish signup from login in the callback.** The callback currently handles both flows identically. To know whether this is a first-time signup (which requires T&C acceptance), check if the user row already exists in `public.users` -- this is already done by the `existing` check in `ensureWorkspaceProvisioned`. First-time users (no existing row) came through signup and must have accepted T&C (the checkbox is `required` on the form). Returning users already have their consent recorded.

4. **Update the database trigger** to no longer read `raw_user_meta_data`. The trigger sets `tc_accepted_at = now()` unconditionally for new signups (since the signup form enforces `required` on the checkbox -- if the user completed signup, they accepted). Alternatively, remove the trigger's `tc_accepted_at` logic entirely and let the callback route be the sole writer.

### Design Decision: Single Writer vs. Dual Writer

**Option A (Recommended): Callback-only writer.** Remove `tc_accepted_at` from the trigger entirely. The callback route's `ensureWorkspaceProvisioned` function becomes the single source of truth. If the trigger fires first and creates the row, the callback updates `tc_accepted_at` via the service client. This eliminates the trigger-fallback parity problem documented in `2026-03-20-supabase-trigger-fallback-parity.md`.

**Option B: Trigger + Callback dual writer.** Keep both paths but have the trigger set `tc_accepted_at = now()` unconditionally (since the signup form HTML `required` attribute means the user accepted). This is simpler but still relies on an assumption about the form state.

Option A is preferred because it establishes a single writer for a legally significant field, making audit and debugging unambiguous.

### Research Insights -- Critical Implementation Trap: `ignoreDuplicates: true`

The current callback code uses:

```typescript
.upsert(
  { id: userId, ..., tc_accepted_at: ... },
  { onConflict: "id", ignoreDuplicates: true },
);
```

With `ignoreDuplicates: true`, when the trigger has already created the row (the **normal** path), the upsert is a **complete no-op**. Under Option A, the trigger creates the row with `tc_accepted_at = NULL`, and the callback's upsert does nothing because the row already exists.

**Result: `tc_accepted_at` stays NULL permanently for every user on the normal path.** This is the primary implementation trap.

**Fix:** The callback must switch from `ignoreDuplicates` upsert to a flow that explicitly handles the trigger-created row:

```typescript
// Option 1: SELECT then conditional UPDATE (recommended -- explicit)
const { data: existing } = await serviceClient
  .from("users")
  .select("workspace_status, tc_accepted_at")
  .eq("id", userId)
  .single();

if (existing && !existing.tc_accepted_at) {
  // Trigger created row but tc_accepted_at is NULL -- set it now
  await serviceClient
    .from("users")
    .update({ tc_accepted_at: new Date().toISOString() })
    .eq("id", userId);
}
```

This replaces the upsert-with-ignore pattern entirely for the consent field.

### Why the form `required` attribute is a valid server-side signal

The signup form's T&C checkbox has `required` on the HTML input element. The browser will not submit the form (and therefore `signInWithOtp` will not fire) unless the checkbox is checked. A malicious user can bypass this with a direct API call, but that call goes through `signInWithOtp` with `shouldCreateUser: true`. The callback route runs server-side after email verification -- if a user completes the magic-link flow from `/signup`, they interacted with the signup form. The callback can therefore record consent for first-time users without needing the client to pass a flag.

However, a sophisticated attacker could call the Supabase auth REST API directly without ever loading the signup page. This is why the recommended approach also includes a future enhancement: a server-side consent record (signed timestamp or database flag set by a server action) that the callback verifies. For the current fix, the pragmatic approach is:

- First-time users via callback = consented (signup form enforces it)
- The `tc_accepted` metadata field is no longer used or trusted
- Document this as a known limitation and track a follow-up for cryptographic consent verification if needed

### Research Insights -- Residual Risk Assessment

The "first-time user = consented" assumption has one residual weakness: a user who calls the Supabase auth REST API directly to create an account bypasses the signup page entirely. In this scenario:

1. The attacker calls `POST /auth/v1/signup` with just an email (no `tc_accepted` in data)
2. They receive and click the magic link
3. The callback creates the user row with `tc_accepted_at = now()` -- recording consent that may not have occurred

This residual risk is **materially weaker** than the current vulnerability because:
- The attacker must complete email verification (proving email ownership)
- The attacker cannot forge consent for *other* users (only for their own account)
- The consent record was never the sole legal mechanism -- the signup page also requires agreement to T&C and Privacy Policy, which a direct API caller never agrees to

For a pre-launch product with no paid users, this residual risk is acceptable. A stronger mitigation (server-side form submission token verified in callback) can be added when the user base grows.

## Technical Considerations

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(auth)/signup/page.tsx` | Remove `data: { tc_accepted: tcAccepted }` from `signInWithOtp` options |
| `apps/web-platform/app/(auth)/callback/route.ts` | Set `tc_accepted_at` server-side for first-time users; remove `user_metadata` reading; fix `ignoreDuplicates` trap |
| `apps/web-platform/supabase/migrations/007_server_side_tc_accepted.sql` | New migration: update `handle_new_user()` trigger to remove `raw_user_meta_data` conditional |
| `apps/web-platform/lib/types.ts` | Add `tc_accepted_at` to `User` interface |

### Research Insights -- Type Safety Gap

The `User` interface in `apps/web-platform/lib/types.ts:27-33` does not include `tc_accepted_at`:

```typescript
export interface User {
  id: string;
  email: string;
  workspace_path: string;
  workspace_status: "provisioning" | "ready";
  created_at: string;
}
```

Add `tc_accepted_at: string | null;` to match the database schema from migration 005. This ensures TypeScript catches any code that tries to read the field from a query result without including it in the `select()`.

### Migration Strategy

A new migration (007) updates the `handle_new_user()` trigger. Two sub-options:

**Sub-option A (Recommended):** Remove `tc_accepted_at` from the trigger INSERT entirely. The trigger creates the row with `tc_accepted_at = NULL`. The callback route's `ensureWorkspaceProvisioned` then updates it to `now()` for first-time users via the service client.

```sql
-- 007_server_side_tc_accepted.sql
-- Remove client-metadata dependency from trigger.
-- tc_accepted_at is now set exclusively by the callback route (server-side).
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, workspace_path)
  values (
    new.id,
    new.email,
    '/workspaces/' || new.id::text
  );
  return new;
end;
$$ language plpgsql security definer;
```

**Sub-option B:** Set `tc_accepted_at = now()` unconditionally in the trigger (since signup implies acceptance). The callback fallback mirrors this.

Sub-option A is preferred for single-writer clarity.

### Research Insights -- Migration Rollback Safety

The migration replaces the trigger function via `CREATE OR REPLACE`, which is atomic and does not require a table lock. Rollback is straightforward: re-apply migration 005's version of `handle_new_user()`. No data is destroyed -- existing `tc_accepted_at` values are preserved. The migration is also idempotent: running it twice produces the same result.

### Callback Route Changes

The revised `ensureWorkspaceProvisioned` function handles three cases:

```typescript
async function ensureWorkspaceProvisioned(
  userId: string,
  email: string,
): Promise<void> {
  const serviceClient = createServiceClient();

  const { data: existing } = await serviceClient
    .from("users")
    .select("workspace_status, tc_accepted_at")
    .eq("id", userId)
    .single();

  if (!existing) {
    // Case 1: No row -- trigger failed or hasn't fired yet.
    // Create row with tc_accepted_at set (first-time signup = consented).
    const workspacePath = await provisionWorkspace(userId);
    const { error: insertError } = await serviceClient
      .from("users")
      .upsert(
        {
          id: userId,
          email,
          workspace_path: workspacePath,
          workspace_status: "ready",
          tc_accepted_at: new Date().toISOString(),
        },
        { onConflict: "id", ignoreDuplicates: true },
      );
    if (insertError) {
      console.error(`[callback] Fallback user upsert failed for ${userId}:`, insertError);
    }
    // If upsert was a no-op (trigger won race), fall through to set tc_accepted_at
    const { data: recheckRow } = await serviceClient
      .from("users")
      .select("tc_accepted_at")
      .eq("id", userId)
      .single();
    if (recheckRow && !recheckRow.tc_accepted_at) {
      await serviceClient
        .from("users")
        .update({ tc_accepted_at: new Date().toISOString() })
        .eq("id", userId);
    }
    return;
  }

  // Case 2: Row exists, tc_accepted_at is NULL -- trigger created row,
  // callback sets consent timestamp.
  if (!existing.tc_accepted_at) {
    await serviceClient
      .from("users")
      .update({ tc_accepted_at: new Date().toISOString() })
      .eq("id", userId);
  }

  // Case 3: Row exists, workspace not ready -- provision disk.
  if (existing.workspace_status !== "ready") {
    try {
      const workspacePath = await provisionWorkspace(userId);
      await serviceClient
        .from("users")
        .update({ workspace_path: workspacePath, workspace_status: "ready" })
        .eq("id", userId);
    } catch (err) {
      console.error(`[callback] Workspace provisioning failed for ${userId}:`, err);
    }
  }
}
```

### Research Insights -- Simplification Opportunity

The three-case callback above is more verbose than necessary. A simpler approach that still handles all races:

```typescript
async function ensureWorkspaceProvisioned(
  userId: string,
  email: string,
): Promise<void> {
  const serviceClient = createServiceClient();

  const { data: existing } = await serviceClient
    .from("users")
    .select("workspace_status, tc_accepted_at")
    .eq("id", userId)
    .single();

  if (!existing) {
    // Trigger hasn't fired yet -- create row with consent.
    const workspacePath = await provisionWorkspace(userId);
    const { error: insertError } = await serviceClient
      .from("users")
      .upsert(
        {
          id: userId,
          email,
          workspace_path: workspacePath,
          workspace_status: "ready",
          tc_accepted_at: new Date().toISOString(),
        },
        { onConflict: "id" },
      );
    if (insertError) {
      console.error(`[callback] Fallback user upsert failed for ${userId}:`, insertError);
    }
    return;
  }

  // Row exists (trigger fired first). Set tc_accepted_at if missing.
  const updates: Record<string, unknown> = {};

  if (!existing.tc_accepted_at) {
    updates.tc_accepted_at = new Date().toISOString();
  }

  if (existing.workspace_status !== "ready") {
    try {
      const workspacePath = await provisionWorkspace(userId);
      updates.workspace_path = workspacePath;
      updates.workspace_status = "ready";
    } catch (err) {
      console.error(`[callback] Workspace provisioning failed for ${userId}:`, err);
    }
  }

  if (Object.keys(updates).length > 0) {
    await serviceClient
      .from("users")
      .update(updates)
      .eq("id", userId);
  }
}
```

Key change: remove `ignoreDuplicates: true` from the upsert (no-row case) so that if the trigger races ahead between SELECT and upsert, the upsert merges rather than skips. In the existing-row case, combine `tc_accepted_at` and workspace updates into a single UPDATE call.

### Signup Page Changes

Remove the metadata pass-through:

```typescript
const { error } = await supabase.auth.signInWithOtp({
  email,
  options: {
    emailRedirectTo: `${window.location.origin}/callback`,
    // tc_accepted no longer passed -- recorded server-side in callback
  },
});
```

The `tcAccepted` state and checkbox remain for UX enforcement (button disabled until checked), but the value is not sent to Supabase auth metadata.

### Attack Surface Enumeration

All code paths that set `tc_accepted_at` after this fix:

| Path | Location | Writer | Trusted? |
|------|----------|--------|----------|
| `handle_new_user()` trigger | `007_server_side_tc_accepted.sql` | Trigger (service role) | N/A -- trigger no longer writes `tc_accepted_at` |
| `ensureWorkspaceProvisioned` | `callback/route.ts` | Service client | Yes -- runs server-side after email verification |

Vectors that no longer set consent:
| Vector | Why Eliminated |
|--------|---------------|
| `raw_user_meta_data` via `signInWithOtp` | Signup page no longer passes `tc_accepted` in `options.data` |
| `auth.updateUser()` direct call | `tc_accepted` metadata is no longer read by any code path |
| Database trigger reading metadata | Migration 007 removes the `raw_user_meta_data` conditional |

### Research Insights -- Remaining Attack Vectors (Post-Fix)

| Vector | Risk | Mitigation |
|--------|------|------------|
| Direct Supabase REST API signup (bypasses signup page) | Low -- attacker gets consent recorded for their own account without seeing T&C | Acceptable pre-launch; track server-side form token as follow-up |
| Service role key compromise | Critical -- attacker can write arbitrary `tc_accepted_at` | Out of scope; service role key security is an infrastructure concern |
| Database admin access | Critical -- attacker can write directly to `public.users` | Out of scope; database access controls are an infrastructure concern |

### Existing Users

No backfill needed. Users who already have `tc_accepted_at` set retain their timestamps. Users with `tc_accepted_at = NULL` are grandfathered users who signed up before clickwrap was introduced (per migration 005 comment). The fix only affects new signups going forward.

## Acceptance Criteria

- [ ] Signup page no longer passes `tc_accepted` in `signInWithOtp` `options.data`
- [ ] Callback route sets `tc_accepted_at` server-side for first-time users without reading `user_metadata`
- [ ] New migration (007) updates `handle_new_user()` trigger to stop reading `raw_user_meta_data->>'tc_accepted'`
- [ ] `ensureWorkspaceProvisioned` no longer accepts `tcAccepted` parameter
- [ ] `ignoreDuplicates: true` replaced with merge-on-conflict or separate UPDATE to handle trigger race
- [ ] `User` interface in `types.ts` updated with `tc_accepted_at: string | null`
- [ ] Calling `supabase.auth.updateUser({ data: { tc_accepted: true } })` has no effect on `tc_accepted_at`
- [ ] Existing users' `tc_accepted_at` values are preserved (no migration backfill)
- [ ] Login flow (returning users) is unaffected -- no consent re-recording
- [ ] T&C checkbox remains `required` on signup form for UX enforcement
- [ ] SELECT in `ensureWorkspaceProvisioned` includes `tc_accepted_at` in its column list

## Test Scenarios

- Given a new user who checks the T&C checkbox and completes signup, when the callback fires, then `tc_accepted_at` is set to the current timestamp server-side
- Given a new user whose trigger-created row has `tc_accepted_at = NULL`, when the callback runs `ensureWorkspaceProvisioned`, then `tc_accepted_at` is updated to `now()` via the service client
- Given a returning user who logs in, when the callback fires, then `tc_accepted_at` is not modified
- Given a user who calls `supabase.auth.updateUser({ data: { tc_accepted: true } })` directly, when they next log in, then `tc_accepted_at` is unchanged (metadata is not read)
- Given an existing user with `tc_accepted_at` already set, when the callback fires, then the existing value is preserved (no overwrite)

### Research Insights -- Additional Test Scenarios

- Given the trigger fires before the callback's SELECT (normal path), when the callback finds the row with `tc_accepted_at = NULL`, then it issues an UPDATE to set `tc_accepted_at` (race condition coverage)
- Given the trigger fires between the callback's SELECT (no row found) and the callback's upsert, when the upsert encounters a conflict, then it merges `tc_accepted_at` into the existing row (not ignored)
- Given a user created via Supabase admin API (no signup page interaction), when the callback fires, then `tc_accepted_at` is still set (server-side records all first-time users as consented)
- Given migration 007 is applied to a database with existing users, when any existing user logs in, then their existing `tc_accepted_at` value (whether timestamp or NULL) is unchanged

## Non-goals

- Cryptographic consent verification (signed tokens, server-side form submission records) -- tracked as a potential follow-up but out of scope for this fix
- Remediation of existing rows created via the old client-metadata path -- existing timestamps are not invalidated; they were set during legitimate signup flows even if the mechanism was theoretically forgeable
- Changes to the T&C checkbox UX or consent language
- Using `raw_app_meta_data` as an alternative storage mechanism -- the plan intentionally avoids all auth metadata for consent

## MVP

### apps/web-platform/app/(auth)/signup/page.tsx

Remove `data: { tc_accepted: tcAccepted }` from the `signInWithOtp` options. Keep the checkbox state for button-disable UX.

### apps/web-platform/app/(auth)/callback/route.ts

1. Remove `tcAccepted` extraction from `user.user_metadata`
2. Remove `tcAccepted` parameter from `ensureWorkspaceProvisioned`
3. Add `tc_accepted_at` to the SELECT column list in `ensureWorkspaceProvisioned`
4. In the first-time user (no row) path, set `tc_accepted_at: new Date().toISOString()` unconditionally; remove `ignoreDuplicates: true` from upsert to handle trigger race
5. In the existing-row path, if `tc_accepted_at` is NULL, issue an UPDATE to set it (handles trigger-created rows)
6. Combine `tc_accepted_at` and workspace updates into a single UPDATE when both are needed

### apps/web-platform/supabase/migrations/007_server_side_tc_accepted.sql

Update `handle_new_user()` trigger to remove `tc_accepted_at` from the INSERT. Remove the `raw_user_meta_data` conditional.

### apps/web-platform/lib/types.ts

Add `tc_accepted_at: string | null;` to the `User` interface.

## References

- Issue: #943
- Related security review: #934
- Trigger-fallback parity learning: `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md`
- Column-level grant learning: `knowledge-base/learnings/2026-03-20-supabase-column-level-grant-override.md`
- Existing fallback fix plan: `knowledge-base/plans/2026-03-20-fix-tc-accepted-at-fallback-unconditional-set-plan.md` (#925)
- RLS restriction plan: `knowledge-base/plans/2026-03-20-security-restrict-rls-tc-accepted-at-plan.md` (#911)
- Migration 005: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- Migration 006: `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`
- Signup page: `apps/web-platform/app/(auth)/signup/page.tsx`
- Callback route: `apps/web-platform/app/(auth)/callback/route.ts`
- Supabase RLS helper functions docs: [auth.jwt() metadata security](https://supabase.com/docs/guides/auth/row-level-security)
- Supabase admin auth docs: [updateUserById](https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid)
- Supabase PKCE flow docs: [exchangeCodeForSession](https://supabase.com/docs/reference/javascript/auth-exchangecodeforsession)
