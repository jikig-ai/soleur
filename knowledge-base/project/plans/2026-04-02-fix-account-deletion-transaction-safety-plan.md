---
title: "fix: account deletion cascade lacks transaction safety"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# fix: account deletion cascade lacks transaction safety

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 3 (Technical Approach, Test Scenarios, Edge Cases)
**Research sources:** Supabase docs (Context7), codebase FK schema analysis, institutional learnings

### Key Improvements

1. Added concrete before/after code snippets for the implementation change
2. Identified edge case: workspace deletion is non-reversible but happens before auth deletion -- documented as acceptable pre-existing behavior
3. Confirmed `auth.admin.deleteUser()` returns a proper `Promise` (not `PromiseLike`), so standard `await`/destructuring is correct
4. Verified `handle_new_user` trigger fires only on INSERT, not affected by DELETE flow

## Overview

The account deletion cascade in `apps/web-platform/server/account-delete.ts` deletes `public.users` (step 4) before `auth.users` (step 5). If the auth deletion fails (admin API unavailable, rate limited, network error), the user is left in a broken state: auth record exists but all data is gone, allowing login to a blank/errored account. This is a GDPR Article 17 violation -- partial erasure with an orphaned auth record.

## Problem Statement

**Current code flow (lines 54-71):**

1. Verify user exists and email matches
2. Abort active agent sessions (best-effort)
3. Delete workspace directory (best-effort)
4. Delete `public.users` row -- FK cascade deletes `api_keys`, `conversations`, `messages`
5. Delete `auth.users` record via admin API

**The bug:** Steps 4 and 5 are not atomic. If step 5 fails, the user's data is already gone from `public.users` (and all cascaded tables) but the auth record persists. The user can still log in but arrives at an empty, broken account.

**Root cause insight:** The FK relationship is `public.users.id REFERENCES auth.users(id) ON DELETE CASCADE`. This means deleting `auth.users` will automatically cascade to `public.users` and all downstream tables. The current code deletes `public.users` manually first, then deletes `auth.users` separately -- duplicating work the database already handles and creating the failure window.

## Proposed Solution

**Option B from the issue: delete `auth.users` first.** This is the simplest correct fix because:

1. The `ON DELETE CASCADE` FK on `public.users` means deleting `auth.users` automatically cascades to `public.users` -> `api_keys` -> `conversations` -> `messages`. No manual `public.users` deletion needed.
2. If `auth.admin.deleteUser()` fails, nothing has been deleted yet -- the user's data is intact and they can retry.
3. If `auth.admin.deleteUser()` succeeds, the database handles the rest atomically within a single transaction (Postgres FK cascades execute within the same transaction as the parent delete).

**Why not Option A (RPC function)?** There are no existing RPC functions in this codebase. The `auth.admin.deleteUser()` call goes through the Supabase GoTrue admin API, which cannot be called from within a Postgres function. An RPC function could only wrap the `public.users` delete -- but that is redundant since the FK cascade already handles it. Option A adds complexity without solving the actual problem (the auth API call is inherently outside the DB transaction).

**Why not Option C (retry with backoff)?** Retries mitigate transient failures but do not eliminate the race condition. If all retries exhaust, the user is still in a broken state. Option B eliminates the broken state entirely by making auth deletion the first destructive step.

## Technical Approach

### Changes to `apps/web-platform/server/account-delete.ts`

1. **Reorder steps:** Move `auth.admin.deleteUser()` before the `public.users` deletion.
2. **Remove the explicit `public.users` deletion.** The FK cascade handles it automatically when `auth.users` is deleted. Removing it eliminates the redundant query and the failure window.
3. **Update comments** to reflect the new flow and explain why the order matters.

**New flow:**

1. Verify user exists and email matches (unchanged)
2. Abort active agent sessions (best-effort, unchanged)
3. Delete workspace directory (best-effort, unchanged)
4. Delete `auth.users` via admin API (FK cascade handles `public.users` and all children)

### Research Insights

**FK cascade mechanics (verified via Supabase docs and schema):**

- `public.users.id REFERENCES auth.users(id) ON DELETE CASCADE` (migration 001, line 7) means Postgres deletes the `public.users` row in the same transaction that deletes the `auth.users` row
- Downstream cascades (`api_keys`, `conversations`, `messages`) all reference `public.users(id) ON DELETE CASCADE`, so they are included in the same transaction
- The `handle_new_user()` trigger fires `AFTER INSERT ON auth.users` only -- it is not involved in the deletion path

**`auth.admin.deleteUser()` API behavior:**

- Returns `Promise<{ data: { user: User }; error: AuthError | null }>` -- a proper `Promise`, not a Supabase query-builder `PromiseLike`
- The existing `await` + destructured `{ error }` pattern is correct
- GoTrue performs the `auth.users` DELETE server-side; the FK cascade fires within that same Postgres transaction

**Concrete before/after for `account-delete.ts`:**

Before (current, lines 54-71):

```typescript
// 4. Delete public.users row (FK cascade deletes api_keys, conversations, messages)
const { error: deletePublicError } = await service
  .from("users")
  .delete()
  .eq("id", userId);

if (deletePublicError) {
  log.error({ userId, err: deletePublicError }, "Failed to delete public.users");
  return { success: false, error: "Account deletion failed. Please try again." };
}

// 5. Delete auth record
const { error: deleteAuthError } = await service.auth.admin.deleteUser(userId);

if (deleteAuthError) {
  log.error({ userId, err: deleteAuthError }, "Failed to delete auth record");
  return { success: false, error: "Account deletion failed. Auth record could not be removed." };
}
```

After (fixed):

```typescript
// 4. Delete auth record -- FK cascade handles public.users and all children
//    IMPORTANT: auth deletion must come first. If it fails, no data is lost.
//    If public.users were deleted first and auth deletion failed, the user
//    would have an auth record but no data (GDPR Article 17 violation).
const { error: deleteAuthError } = await service.auth.admin.deleteUser(userId);

if (deleteAuthError) {
  log.error({ userId, err: deleteAuthError }, "Failed to delete auth record");
  return { success: false, error: "Account deletion failed. Please try again." };
}
```

### Changes to `apps/web-platform/test/account-delete.test.ts`

1. **Update the cascade order test** to expect: `abort -> workspace -> auth -> (cascade)` instead of `abort -> workspace -> public.users -> auth`.
2. **Add a new test for the partial-failure scenario:** mock `auth.admin.deleteUser()` to fail and verify that `public.users` is NOT deleted (i.e., `from("users").delete()` is never called).
3. **Update the auth failure test** to verify the user's data remains intact.
4. **Remove or update the `public.users` deletion failure test** since explicit `public.users` deletion is removed.

## Acceptance Criteria

- [ ] If `auth.admin.deleteUser()` fails, `public.users` and all cascaded data remain intact
- [ ] If `auth.admin.deleteUser()` succeeds, `public.users` and all FK-cascaded rows (`api_keys`, `conversations`, `messages`) are deleted by the database
- [ ] No orphaned auth records can persist after a partial deletion attempt
- [ ] The explicit `public.users` deletion is removed (FK cascade handles it)
- [ ] Existing tests updated to reflect the new deletion order
- [ ] New test covers the partial-failure scenario (auth fails -> data intact)
- [ ] GDPR Article 17 compliance maintained -- successful deletion still removes all user data

## Test Scenarios

- Given a valid user, when `auth.admin.deleteUser()` succeeds, then `public.users` and all cascaded tables are cleaned up by FK cascade, and the function returns `{ success: true }`
- Given a valid user, when `auth.admin.deleteUser()` fails (e.g., API unavailable), then no data is deleted from `public.users` or cascaded tables, and the function returns `{ success: false }` with an error message
- Given a valid user, when deletion succeeds, then the cascade order is `abort -> workspace -> auth` (no explicit `public.users` delete step)
- Given an invalid email confirmation, when `deleteAccount` is called, then no deletion occurs (unchanged behavior)
- Given a non-existent user, when `deleteAccount` is called, then it returns an error (unchanged behavior)

## Edge Cases and Considerations

**Workspace deletion ordering:** Step 3 (workspace directory deletion) runs before step 4 (auth deletion). If auth deletion fails, the workspace directory is already gone but the user account persists. This is a pre-existing behavior, not introduced by this fix. It is acceptable because: (a) workspace deletion is already marked best-effort with try/catch, (b) the workspace is re-provisioned on next login via `ensureWorkspaceProvisioned()`, and (c) workspace files are ephemeral session data, not user-owned content.

**Session abort ordering:** Step 2 (abort active sessions) also runs before auth deletion. If auth deletion fails, any active WebSocket sessions have already been aborted. This is benign -- the user can start a new session on next page load.

**Rate limiting interaction:** The route handler (`app/api/account/delete/route.ts`) rate-limits to 1 request per 60 seconds per user. If auth deletion fails and the user retries within 60 seconds, they will be rate-limited. This is acceptable -- the error message tells them to try again, and the 60-second window is short enough to not impede a legitimate retry.

**No migration required:** This fix changes only application code ordering. The FK constraint (`ON DELETE CASCADE`) already exists in the schema. No new migration is needed.

## Domain Review

**Domains relevant:** Legal

### Legal

**Status:** reviewed
**Assessment:** This fix directly supports GDPR Article 17 (Right to Erasure) compliance. The current bug creates a scenario where partial deletion leaves an orphaned auth record -- the user can still authenticate but their data is gone. This violates Article 17 because the user requested full erasure but only partial erasure occurred, and the remaining auth record (email, auth metadata) constitutes personal data that was not erased. The fix eliminates this compliance gap by ensuring deletion is all-or-nothing: either the auth record and all cascaded data are deleted together, or nothing is deleted and the user can retry.

### Product/UX Gate

Not applicable -- no user-facing UI changes. The API contract (`POST /api/account/delete`) and response shape remain identical.

## Alternative Approaches Considered

| Approach | Verdict | Reasoning |
|----------|---------|-----------|
| A: Supabase RPC function (single transaction) | Rejected | Cannot call GoTrue admin API from Postgres. RPC would only wrap the `public.users` delete, which FK cascade already handles. Adds complexity without solving the actual problem. |
| B: Delete auth first, rely on FK cascade | **Chosen** | Eliminates the failure window entirely. Simplest correct fix. Leverages existing DB constraints. |
| C: Retry with exponential backoff | Rejected | Mitigates but does not eliminate the broken state. If all retries fail, user is still in a broken state. Could be added later as defense-in-depth on top of Option B. |
| D: Soft-delete with async cleanup | Rejected | Overengineered for the current scale. Adds a `deleted_at` column, background job infrastructure, and cleanup logic. Appropriate for a system with millions of users, not for beta. |

## References

- Source issue: #1376
- PR that introduced the code: #1361
- File: `apps/web-platform/server/account-delete.ts:54-75`
- Test file: `apps/web-platform/test/account-delete.test.ts`
- Schema: `apps/web-platform/supabase/migrations/001_initial_schema.sql` (FK definition at line 7)
- Supabase docs: FK `ON DELETE CASCADE` executes within the same Postgres transaction as the parent delete
- Constitution: `knowledge-base/project/constitution.md` line 100 -- Supabase query builders return `PromiseLike`, use `.then(onFulfilled, onRejected)` not `.catch()`
