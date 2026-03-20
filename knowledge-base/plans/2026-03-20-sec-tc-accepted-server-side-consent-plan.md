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

## Overview

The `tc_accepted` flag in `auth.users.raw_user_meta_data` is client-writable by Supabase design. A user can call `supabase.auth.updateUser({ data: { tc_accepted: true } })` directly, forging consent evidence without interacting with the signup checkbox. The current system trusts this client-controlled metadata as ground truth for GDPR Article 7(1) consent records.

The fix moves consent recording server-side: after `exchangeCodeForSession` succeeds in the callback route, the server sets `tc_accepted_at` via the service client based on a server-verified condition, eliminating reliance on client-writable metadata.

## Problem Statement

Three code paths currently read `tc_accepted` from `raw_user_meta_data` and trust it as proof of consent:

1. **Database trigger** (`005_add_tc_accepted_at.sql:19`): `handle_new_user()` checks `raw_user_meta_data->>'tc_accepted'` on `auth.users` INSERT.
2. **Callback fallback** (`callback/route.ts:29-31`): Reads `user.user_metadata?.tc_accepted` after `exchangeCodeForSession`.
3. **Both paths** write `tc_accepted_at` to `public.users` based on this untrusted value.

The vulnerability: `raw_user_meta_data` is a JSONB column that Supabase's auth API allows users to update via `auth.updateUser()`. Any authenticated user -- or even during the signup flow -- can inject `tc_accepted: true` without checking the checkbox. The T&C acceptance timestamp then records consent that never happened.

Migration 006 correctly prevents users from directly updating `tc_accepted_at` in `public.users`, but the forgery vector is upstream: the `raw_user_meta_data` source itself is tainted.

## Proposed Solution

Replace the client-metadata-based consent recording with a server-side mechanism tied to a verifiable condition. The approach:

1. **Remove `tc_accepted` from `options.data`** in the signup page's `signInWithOtp` call. The client no longer passes consent state through Supabase auth metadata.

2. **Record consent server-side in the callback route.** After `exchangeCodeForSession` succeeds, check a server-verifiable condition and set `tc_accepted_at` via the service client. The server-verifiable condition is: the user arrived at the callback from the signup flow (not login), which is the flow that requires T&C acceptance.

3. **Distinguish signup from login in the callback.** The callback currently handles both flows identically. To know whether this is a first-time signup (which requires T&C acceptance), check if the user row already exists in `public.users` -- this is already done by the `existing` check in `ensureWorkspaceProvisioned`. First-time users (no existing row) came through signup and must have accepted T&C (the checkbox is `required` on the form). Returning users already have their consent recorded.

4. **Update the database trigger** to no longer read `raw_user_meta_data`. The trigger sets `tc_accepted_at = now()` unconditionally for new signups (since the signup form enforces `required` on the checkbox -- if the user completed signup, they accepted). Alternatively, remove the trigger's `tc_accepted_at` logic entirely and let the callback route be the sole writer.

### Design Decision: Single Writer vs. Dual Writer

**Option A (Recommended): Callback-only writer.** Remove `tc_accepted_at` from the trigger entirely. The callback route's `ensureWorkspaceProvisioned` function becomes the single source of truth. If the trigger fires first and creates the row, the callback's upsert path updates `tc_accepted_at` via the service client. This eliminates the trigger-fallback parity problem documented in `2026-03-20-supabase-trigger-fallback-parity.md`.

**Option B: Trigger + Callback dual writer.** Keep both paths but have the trigger set `tc_accepted_at = now()` unconditionally (since the signup form HTML `required` attribute means the user accepted). This is simpler but still relies on an assumption about the form state.

Option A is preferred because it establishes a single writer for a legally significant field, making audit and debugging unambiguous.

### Why the form `required` attribute is a valid server-side signal

The signup form's T&C checkbox has `required` on the HTML input element. The browser will not submit the form (and therefore `signInWithOtp` will not fire) unless the checkbox is checked. A malicious user can bypass this with a direct API call, but that call goes through `signInWithOtp` with `shouldCreateUser: true`. The callback route runs server-side after email verification -- if a user completes the magic-link flow from `/signup`, they interacted with the signup form. The callback can therefore record consent for first-time users without needing the client to pass a flag.

However, a sophisticated attacker could call the Supabase auth REST API directly without ever loading the signup page. This is why the recommended approach also includes a future enhancement: a server-side consent record (signed timestamp or database flag set by a server action) that the callback verifies. For the current fix, the pragmatic approach is:

- First-time users via callback = consented (signup form enforces it)
- The `tc_accepted` metadata field is no longer used or trusted
- Document this as a known limitation and track a follow-up for cryptographic consent verification if needed

## Technical Considerations

### Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/app/(auth)/signup/page.tsx` | Remove `data: { tc_accepted: tcAccepted }` from `signInWithOtp` options |
| `apps/web-platform/app/(auth)/callback/route.ts` | Set `tc_accepted_at` server-side for first-time users; remove `user_metadata` reading |
| `apps/web-platform/supabase/migrations/007_server_side_tc_accepted.sql` | New migration: update `handle_new_user()` trigger to stop reading `raw_user_meta_data->>'tc_accepted'`; set `tc_accepted_at = now()` unconditionally or remove it from trigger |

### Migration Strategy

A new migration (007) updates the `handle_new_user()` trigger. Two sub-options:

**Sub-option A (Recommended):** Remove `tc_accepted_at` from the trigger INSERT entirely. The trigger creates the row with `tc_accepted_at = NULL`. The callback route's `ensureWorkspaceProvisioned` then updates it to `now()` for first-time users via the service client.

```sql
-- 007_server_side_tc_accepted.sql
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

### Callback Route Changes

```typescript
// After exchangeCodeForSession succeeds and user is retrieved:
if (user) {
  await ensureWorkspaceProvisioned(user.id, user.email ?? "");
  // ... existing API key check and redirect logic
}
```

The `ensureWorkspaceProvisioned` function:
- Reverts to `(userId: string, email: string)` signature (removes `tcAccepted` param)
- For first-time users (no existing row): creates row with `tc_accepted_at: new Date().toISOString()` unconditionally
- For existing users with missing `tc_accepted_at`: does NOT backfill (preserves audit integrity)

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
| `handle_new_user()` trigger | `007_server_side_tc_accepted.sql` | Trigger (service role) | Yes -- trigger runs with `security definer`; no longer reads client metadata |
| `ensureWorkspaceProvisioned` fallback | `callback/route.ts` | Service client | Yes -- runs server-side after email verification |

Vectors that no longer set consent:
| Vector | Why Eliminated |
|--------|---------------|
| `raw_user_meta_data` via `signInWithOtp` | Signup page no longer passes `tc_accepted` in `options.data` |
| `auth.updateUser()` direct call | `tc_accepted` metadata is no longer read by any code path |
| Database trigger reading metadata | Migration 007 removes the `raw_user_meta_data` conditional |

### Existing Users

No backfill needed. Users who already have `tc_accepted_at` set retain their timestamps. Users with `tc_accepted_at = NULL` are grandfathered users who signed up before clickwrap was introduced (per migration 005 comment). The fix only affects new signups going forward.

## Acceptance Criteria

- [ ] Signup page no longer passes `tc_accepted` in `signInWithOtp` `options.data`
- [ ] Callback route sets `tc_accepted_at` server-side for first-time users without reading `user_metadata`
- [ ] New migration (007) updates `handle_new_user()` trigger to stop reading `raw_user_meta_data->>'tc_accepted'`
- [ ] `ensureWorkspaceProvisioned` no longer accepts `tcAccepted` parameter
- [ ] Calling `supabase.auth.updateUser({ data: { tc_accepted: true } })` has no effect on `tc_accepted_at`
- [ ] Existing users' `tc_accepted_at` values are preserved (no migration backfill)
- [ ] Login flow (returning users) is unaffected -- no consent re-recording
- [ ] T&C checkbox remains `required` on signup form for UX enforcement

## Test Scenarios

- Given a new user who checks the T&C checkbox and completes signup, when the callback fires, then `tc_accepted_at` is set to the current timestamp server-side
- Given a new user whose trigger-created row has `tc_accepted_at = NULL`, when the callback runs `ensureWorkspaceProvisioned`, then `tc_accepted_at` is updated to `now()` via the service client
- Given a returning user who logs in, when the callback fires, then `tc_accepted_at` is not modified
- Given a user who calls `supabase.auth.updateUser({ data: { tc_accepted: true } })` directly, when they next log in, then `tc_accepted_at` is unchanged (metadata is not read)
- Given an existing user with `tc_accepted_at` already set, when the callback fires, then the existing value is preserved (no overwrite)

## Non-goals

- Cryptographic consent verification (signed tokens, server-side form submission records) -- tracked as a potential follow-up but out of scope for this fix
- Remediation of existing rows created via the old client-metadata path -- existing timestamps are not invalidated; they were set during legitimate signup flows even if the mechanism was theoretically forgeable
- Changes to the T&C checkbox UX or consent language

## MVP

### apps/web-platform/app/(auth)/signup/page.tsx

Remove `data: { tc_accepted: tcAccepted }` from the `signInWithOtp` options. Keep the checkbox state for button-disable UX.

### apps/web-platform/app/(auth)/callback/route.ts

1. Remove `tcAccepted` extraction from `user.user_metadata`
2. Remove `tcAccepted` parameter from `ensureWorkspaceProvisioned`
3. In the first-time user path, set `tc_accepted_at: new Date().toISOString()` unconditionally
4. Add an UPDATE call for the case where the trigger created the row but `tc_accepted_at` is NULL (race between trigger and callback)

### apps/web-platform/supabase/migrations/007_server_side_tc_accepted.sql

Update `handle_new_user()` trigger to remove `tc_accepted_at` from the INSERT (or set it unconditionally to `now()`). Remove the `raw_user_meta_data` conditional.

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
