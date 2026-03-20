---
title: "fix: align fallback INSERT tc_accepted_at with trigger logic"
type: fix
date: 2026-03-20
issue: "#925"
priority: P2
labels: [legal, priority/p2-medium, type/bug]
---

# fix: align fallback INSERT tc_accepted_at with trigger logic

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Test Scenarios, Attack Surface, Edge Cases)
**Research sources:** Supabase JS Client docs (Context7), codebase analysis (callback/route.ts, signup/page.tsx, login/page.tsx, 005_add_tc_accepted_at.sql), security-sentinel patterns, data-integrity-guardian patterns

### Key Improvements
1. Confirmed `user_metadata` availability and type behavior via Supabase JS Client docs -- `options.data` passed during `signInWithOtp` is stored in `raw_user_meta_data` and exposed as `user_metadata` on the JS user object
2. Discovered login page uses `shouldCreateUser: false` and does NOT pass `tc_accepted` -- validates that only the signup flow sets this metadata, and the fallback correctly handles the login case (metadata absent -> `null`)
3. Added edge case analysis for the `ensureWorkspaceProvisioned` function scope -- the `user` object is in the parent `GET` handler scope but NOT passed to `ensureWorkspaceProvisioned`, requiring a minor signature change

### New Considerations Discovered
- The `ensureWorkspaceProvisioned` function does not currently receive the `user` object -- only `userId` and `email`. To access `user.user_metadata.tc_accepted`, either the full user object or the extracted boolean must be passed as a parameter
- No existing tests cover the callback route -- this is a pre-existing gap, not introduced by this fix

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

### Research Insights

**Supabase JS Client `user_metadata` behavior (confirmed via Context7 docs):**
- `signUp()` and `signInWithOtp()` both accept `options.data` which maps to `raw_user_meta_data` in PostgreSQL
- After `getUser()`, the user object exposes `user_metadata` as a plain JS object preserving the original types from the JSON column
- The signup page (`signup/page.tsx:24`) passes `tc_accepted: tcAccepted` where `tcAccepted` is a `useState(false)` boolean, so the stored value is a JSON boolean (`true`/`false`), not a string
- PostgreSQL's `->>` operator always returns text, which is why the trigger checks `= 'true'` (string comparison)
- The JS client returns the JSON value as-is, so `user.user_metadata.tc_accepted` will be a boolean `true` or `false` in practice

**Function signature change required:**
The `ensureWorkspaceProvisioned` function (line 53-95) currently accepts only `(userId: string, email: string)`. It does not have access to `user.user_metadata`. The fix must either:
1. Pass the extracted `tcAccepted` boolean as a third parameter (minimal change, preferred)
2. Pass the full `user` object (unnecessary coupling)

Option 1 is preferred -- it keeps the function signature narrow and avoids importing Supabase types.

### Attack Surface Enumeration

All code paths that set `tc_accepted_at`:

| Path | Location | Currently Correct? |
|------|----------|-------------------|
| `handle_new_user()` trigger | `005_add_tc_accepted_at.sql:18-22` | Yes -- checks `raw_user_meta_data->>'tc_accepted'` |
| Fallback INSERT | `callback/route.ts:73-79` | **No** -- unconditionally sets timestamp |

No other code paths write to `tc_accepted_at` (confirmed via codebase grep). RLS UPDATE policy from #911 restricts user-side writes separately.

**Auth entry points verified:**
| Entry Point | Sets `tc_accepted` in metadata? | Can trigger fallback INSERT? |
|------------|-------------------------------|------------------------------|
| Signup (`/signup`) | Yes -- `data: { tc_accepted: tcAccepted }` | Yes -- new user |
| Login (`/login`) | No -- uses `shouldCreateUser: false`, no `data` | No -- existing users only |

This confirms the fallback INSERT only fires for users who came through the signup flow (which does set `tc_accepted` metadata). A login-only user cannot trigger the fallback because `shouldCreateUser: false` prevents creating new `auth.users` rows.

## Acceptance Criteria

- [ ] `ensureWorkspaceProvisioned` signature extended to accept `tcAccepted: boolean` as third parameter
- [ ] Caller in `GET` handler extracts `tcAccepted` from `user.user_metadata` before calling `ensureWorkspaceProvisioned`
- [ ] Fallback INSERT in `callback/route.ts` only sets `tc_accepted_at` when `tcAccepted` is `true`
- [ ] When `tcAccepted` is `false`/absent, `tc_accepted_at` is set to `null` (not omitted -- explicit null matches trigger behavior)
- [ ] No changes to the database trigger logic (it is already correct)
- [ ] Comment updated to explain the conditional logic mirrors the trigger

## Test Scenarios

- Given a new user who accepted T&C (metadata `tc_accepted: true`), when the trigger fails and fallback INSERT fires, then `tc_accepted_at` is set to the current timestamp
- Given a new user who did NOT accept T&C (metadata `tc_accepted: false` or absent), when the trigger fails and fallback INSERT fires, then `tc_accepted_at` is `null`
- Given a new user created by the trigger (normal path), when callback runs, then `existing` is found and no INSERT occurs (no regression)

### Research Insights -- Edge Cases

- **Metadata absent entirely:** If `user.user_metadata` is `undefined` or empty (e.g., user created via admin API without metadata), the optional chaining `user.user_metadata?.tc_accepted` returns `undefined`, which does not match `true` or `"true"`, so `tc_accepted_at` correctly falls to `null`
- **String `"true"` vs boolean `true`:** The signup page passes a boolean, but Supabase's internal JSON handling could theoretically return either. The dual check (`=== true || === "true"`) is defensive and mirrors the SQL trigger's text comparison
- **Login-only users cannot reach fallback:** Login page uses `shouldCreateUser: false`, so no new `auth.users` row is created, so the trigger doesn't fire, so the fallback INSERT in the callback never runs for login-only users. This is a safe path.

## Technical Considerations

- **Supabase user object:** After `supabase.auth.getUser()`, the `user` object exposes `user_metadata` (JS client equivalent of `raw_user_meta_data` in PostgreSQL). The signup page at `app/(auth)/signup/page.tsx:24` passes `tc_accepted` via `options.data`, which Supabase stores in `raw_user_meta_data` / `user_metadata`.
- **Type safety:** `user.user_metadata.tc_accepted` can be `true`, `"true"`, `undefined`, or `false`. The conditional should handle all variants. Checking `=== true || === "true"` mirrors the SQL `->>'tc_accepted' = 'true'` (JSON text extraction always returns strings, but JS client may preserve the boolean).
- **Minimal diff:** This requires: (1) extracting `tcAccepted` in the `GET` handler, (2) adding a parameter to `ensureWorkspaceProvisioned`, (3) using the parameter in the fallback INSERT conditional. Three small, localized changes.
- **No test infrastructure exists** for the callback route. This is a pre-existing gap. The fix is small and deterministic enough to verify via type-check and manual inspection.

### Research Insights -- Simplicity Review

- The proposed change adds one parameter, one extraction line, and one conditional. No new abstractions, no new files, no new dependencies. This is the minimum viable fix.
- Do NOT add a shared utility function for the `tc_accepted` check -- it's used in exactly two places (SQL trigger and TS fallback) in different languages. Extracting it would add indirection without reuse benefit.
- Do NOT add logging for the fallback path beyond what already exists. The comment is sufficient documentation.

## MVP

### apps/web-platform/app/(auth)/callback/route.ts -- GET handler (line 26-28)

Extract `tcAccepted` before calling `ensureWorkspaceProvisioned`:

```typescript
if (user) {
  // Extract T&C acceptance from user metadata (set during signup via options.data)
  const tcAccepted = user.user_metadata?.tc_accepted === true
    || user.user_metadata?.tc_accepted === "true";

  // Ensure workspace is provisioned (first-time users)
  await ensureWorkspaceProvisioned(user.id, user.email ?? "", tcAccepted);
```

### apps/web-platform/app/(auth)/callback/route.ts -- ensureWorkspaceProvisioned signature (line 53)

Add `tcAccepted` parameter:

```typescript
async function ensureWorkspaceProvisioned(
  userId: string,
  email: string,
  tcAccepted: boolean,
): Promise<void> {
```

### apps/web-platform/app/(auth)/callback/route.ts -- fallback INSERT (lines 67-79)

Use conditional `tc_accepted_at`:

```typescript
    // First-time user — create row and provision
    // Note: this is a safety net path. The handle_new_user() trigger on
    // auth.users INSERT is the primary mechanism for creating the users row
    // (including tc_accepted_at). This fallback fires only if the trigger
    // failed silently or was not present.
    // Mirror the trigger logic: only set tc_accepted_at when metadata confirms acceptance.
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
- Login page (no tc_accepted): `apps/web-platform/app/(auth)/login/page.tsx`
- RLS policy for tc_accepted_at: #911
- Original T&C acceptance mechanism: #889
- Supabase JS Client docs: `user_metadata` maps to `raw_user_meta_data`, preserving JSON types
