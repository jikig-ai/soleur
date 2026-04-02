---
module: AccountDelete
date: 2026-04-02
problem_type: logic_error
component: authentication
symptoms:
  - "User left with auth record but no data after partial deletion failure"
  - "GDPR Article 17 violation — orphaned auth record persists after public data deleted"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [account-deletion, gdpr, fk-cascade, transaction-safety, supabase]
---

# Troubleshooting: Account deletion cascade lacks transaction safety

## Problem

The account deletion in `account-delete.ts` deleted `public.users` (step 4) before `auth.users` (step 5). If the auth deletion failed (API unavailable, rate limited), the user was left with an auth record but no data -- they could still log in to a blank, broken account. This is a GDPR Article 17 violation.

## Environment

- Module: AccountDelete (`apps/web-platform/server/account-delete.ts`)
- Framework: Next.js + Supabase
- Affected Component: Authentication / account deletion cascade
- Date: 2026-04-02

## Symptoms

- User left with orphaned auth record after partial deletion failure
- Login to blank account after failed deletion attempt
- GDPR Article 17 non-compliance (partial erasure)

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The root cause was clear from code inspection -- the deletion order created a non-atomic failure window.

## Session Errors

**`worktree-manager.sh draft-pr` failed with "Cannot run from bare repo root"**

- **Recovery:** Used `git push -u origin` and `gh pr create` directly instead
- **Prevention:** Always `cd` into the worktree before running worktree-manager commands that require a working tree

**Background review agents did not return results within timeout (4 agents)**

- **Recovery:** Performed inline review covering security, architecture, performance, and simplicity
- **Prevention:** For small, focused fixes (2 files), consider using inline review directly rather than launching multiple background agents that may not complete in time

## Solution

Reorder the deletion cascade: delete `auth.users` first via `auth.admin.deleteUser()`. The FK constraint (`public.users.id REFERENCES auth.users(id) ON DELETE CASCADE`) automatically cascades to `public.users` and all downstream tables (`api_keys`, `conversations`, `messages`) within the same Postgres transaction.

**Code changes:**

```typescript
// Before (broken): deleted public.users first, then auth
// If auth failed, user had auth record but no data
const { error: deletePublicError } = await service
  .from("users")
  .delete()
  .eq("id", userId);
// ... then auth.admin.deleteUser(userId)

// After (fixed): delete auth first, FK cascade handles the rest
// If auth fails, no data is lost — user can retry
const { error: deleteAuthError } = await service.auth.admin.deleteUser(userId);
```

The explicit `public.users` deletion was removed entirely -- it was redundant with the FK cascade and was the source of the failure window.

## Why This Works

1. **Root cause:** The deletion was non-atomic -- two separate operations (public.users delete, then auth.users delete) with a failure window between them.
2. **Solution:** By deleting auth.users first, the FK CASCADE triggers within the same Postgres transaction, making the entire cascade atomic. If auth deletion fails, nothing has been deleted yet.
3. **Key insight:** When an FK CASCADE exists, the database handles the cascade atomically. Manually deleting the child table first is both redundant and dangerous -- it creates a window where the parent can exist without children.

## Prevention

- When deleting records with FK CASCADE relationships, always delete the parent (referenced) table first -- the cascade handles children atomically
- Never manually delete child records that are covered by ON DELETE CASCADE -- it creates a failure window
- For multi-step destructive operations, order steps so that failure at any point leaves the system in a valid state (fail-safe ordering)

## Related Issues

- Source issue: [#1376](https://github.com/jikig-ai/soleur/issues/1376)
- PR that introduced the original code: #1361
