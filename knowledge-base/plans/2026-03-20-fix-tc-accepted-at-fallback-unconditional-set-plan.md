---
title: "fix: align fallback INSERT tc_accepted_at with trigger logic"
type: fix
date: 2026-03-20
issue: "#925"
priority: P2
labels: [legal, priority/p2-medium, type/bug]
---

# fix: align fallback INSERT tc_accepted_at with trigger logic

## Overview

The fallback INSERT path in `apps/web-platform/app/(auth)/callback/route.ts` (line 73-79) unconditionally sets `tc_accepted_at: new Date().toISOString()` for new users whose row was not created by the `handle_new_user()` trigger. This creates a false T&C acceptance record for users who did not actually accept the terms.

The database trigger in `005_add_tc_accepted_at.sql` correctly uses a conditional:

```sql
case
  when (new.raw_user_meta_data->>'tc_accepted') = 'true'
  then now()
  else null
end
```

The fallback INSERT must mirror this logic.

## Problem Statement

When the `handle_new_user()` trigger fails silently or is not present, the fallback INSERT in the auth callback creates the user row. Currently it stamps `tc_accepted_at` regardless of whether the user actually checked the T&C checkbox during signup. This undermines GDPR/contract law audit trail integrity -- a `tc_accepted_at` value should only exist when there is verifiable evidence of acceptance.

## Proposed Solution

Read `user.user_metadata.tc_accepted` from the Supabase auth user object (already available in the callback as `user` from `supabase.auth.getUser()`). Only set `tc_accepted_at` when `tc_accepted === true` (or the string `"true"`); otherwise set it to `null`.

### Attack Surface Enumeration

All code paths that set `tc_accepted_at`:

| Path | Location | Currently Correct? |
|------|----------|-------------------|
| `handle_new_user()` trigger | `005_add_tc_accepted_at.sql:18-22` | Yes -- checks `raw_user_meta_data->>'tc_accepted'` |
| Fallback INSERT | `callback/route.ts:73-79` | **No** -- unconditionally sets timestamp |

No other code paths write to `tc_accepted_at` (confirmed via codebase grep). RLS UPDATE policy from #911 restricts user-side writes separately.

## Acceptance Criteria

- [ ] Fallback INSERT in `callback/route.ts` only sets `tc_accepted_at` when `user.user_metadata.tc_accepted` is truthy
- [ ] When `tc_accepted` is falsy/absent, `tc_accepted_at` is set to `null` (not omitted -- explicit null matches trigger behavior)
- [ ] No changes to the database trigger logic (it is already correct)
- [ ] Comment updated to explain the conditional logic mirrors the trigger

## Test Scenarios

- Given a new user who accepted T&C (metadata `tc_accepted: true`), when the trigger fails and fallback INSERT fires, then `tc_accepted_at` is set to the current timestamp
- Given a new user who did NOT accept T&C (metadata `tc_accepted: false` or absent), when the trigger fails and fallback INSERT fires, then `tc_accepted_at` is `null`
- Given a new user created by the trigger (normal path), when callback runs, then `existing` is found and no INSERT occurs (no regression)

## Technical Considerations

- **Supabase user object:** After `supabase.auth.getUser()`, the `user` object exposes `user_metadata` (JS client equivalent of `raw_user_meta_data` in PostgreSQL). The signup page at `app/(auth)/signup/page.tsx:24` passes `tc_accepted` via `options.data`, which Supabase stores in `raw_user_meta_data` / `user_metadata`.
- **Type safety:** `user.user_metadata.tc_accepted` can be `true`, `"true"`, `undefined`, or `false`. The conditional should handle all variants. Checking `=== true || === "true"` mirrors the SQL `->>'tc_accepted' = 'true'` (JSON text extraction always returns strings, but JS client may preserve the boolean).
- **Minimal diff:** This is a one-line change (conditional expression) plus a comment update. No structural changes needed.

## MVP

### apps/web-platform/app/(auth)/callback/route.ts (lines 72-79)

```typescript
// First-time user — create row and provision
// Note: this is a safety net path. The handle_new_user() trigger on
// auth.users INSERT is the primary mechanism for creating the users row
// (including tc_accepted_at). This fallback fires only if the trigger
// failed silently or was not present.
// Mirror the trigger logic: only set tc_accepted_at when metadata confirms acceptance.
const tcAccepted = user.user_metadata?.tc_accepted === true
  || user.user_metadata?.tc_accepted === "true";
const workspacePath = await provisionWorkspace(userId);
await serviceClient.from("users").insert({
  id: userId,
  email,
  workspace_path: workspacePath,
  workspace_status: "ready",
  tc_accepted_at: tcAccepted ? new Date().toISOString() : null,
});
```

## References

- Issue: #925
- Trigger logic: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- Fallback INSERT: `apps/web-platform/app/(auth)/callback/route.ts:73-79`
- Signup metadata: `apps/web-platform/app/(auth)/signup/page.tsx:24`
- RLS policy for tc_accepted_at: #911
- Original T&C acceptance mechanism: #889
