---
module: web-platform/auth
date: 2026-04-07
problem_type: security_issue
component: database
symptoms:
  - "New column writable by authenticated users via Supabase client SDK"
  - "Permissive RLS UPDATE policy applies to all columns including sensitive ones"
root_cause: missing_permission
resolution_type: migration
severity: critical
tags: [rls, supabase, security, installation-takeover, column-level-security]
---

# RLS Column-Level Security: New Columns Inherit Permissive UPDATE Policy

## Problem

When adding a new column (`github_username`) to the `public.users` table, the
existing permissive RLS policy ("Users can update own profile") automatically
allowed any authenticated user to update the new column via the Supabase client
SDK — bypassing the intended server-side-only OAuth flow.

**Attack scenario:** An attacker creates an email-only Soleur account, directly
updates their `github_username` to a victim's username via the anon-key client,
then calls `detect-installation` which reads the attacker-controlled username,
finds the victim's installation, and stores the victim's `github_installation_id`
on the attacker's account.

## Investigation

The security-sentinel review agent identified this during code review of PR
#1769. The vulnerability was not caught during brainstorm or plan phases because
the focus was on the OAuth flow's CSRF protection, not on the database layer's
column-level access control.

## Root Cause

Supabase RLS policies operate at the row level, not the column level. A
permissive `UPDATE` policy with `USING (auth.uid() = id)` grants write access
to ALL columns on the matched row. When a new column stores a value that should
only be written by a privileged flow (service role), the permissive policy
creates an unintended bypass.

## Solution

Add a **restrictive** RLS policy that prevents the `github_username` column
from being changed via the anon-key client:

```sql
CREATE POLICY "Users cannot update github_username directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    github_username IS NOT DISTINCT FROM
      (SELECT github_username FROM public.users WHERE id = auth.uid())
  );
```

The `AS RESTRICTIVE` modifier means this policy must pass IN ADDITION TO any
permissive policies. The `WITH CHECK` ensures the `github_username` value does
not change — only the service role (which bypasses RLS) can write it.

## Key Insight

**Every new column on a table with permissive RLS UPDATE policies is
client-writable by default.** When adding a column that should only be written
by server-side code (service role), add a restrictive policy in the same
migration to prevent client-side writes. This applies to any column that stores
values used for authorization decisions (installation IDs, role assignments,
username claims).

## Prevention

- When adding columns to RLS-enabled tables, audit existing UPDATE policies
- If the column stores values used for auth/authz decisions, add a restrictive
  policy preventing client-side writes in the same migration
- Pattern: `AS RESTRICTIVE ... WITH CHECK (col IS NOT DISTINCT FROM (SELECT col ...))`
  prevents the column value from changing through anon-key clients

## Session Errors

**1. Worktree creation failed silently on first attempt** — The `worktree-manager.sh`
reported success but the worktree had no `.git` link and wasn't in `git worktree list`.
Recovery: deleted directory and re-created. **Prevention:** After worktree creation,
verify with `git branch --show-current` before proceeding.

**2. CWD drift from `cd` in Bash tool calls** — Multiple `cd apps/web-platform`
commands stacked, causing `apps/web-platform/apps/web-platform` path errors.
Recovery: used absolute paths. **Prevention:** Always use absolute paths in Bash
tool calls; never rely on persistent CWD from prior `cd` commands.

**3. NextRequest.cookies.get() incompatible with plain Request in tests** —
Route handler used `request.cookies.get()` (NextRequest API) but vitest tests
pass plain `Request` objects without a cookie jar. Recovery: refactored to
manual cookie parsing from the `Cookie` header. **Prevention:** When writing
route handlers that will be unit-tested, use raw `Request` type with manual
header parsing instead of `NextRequest`-specific APIs.

**4. SameSite case mismatch in cookie assertion** — Test asserted `SameSite=Lax`
but Next.js normalizes to lowercase `samesite=lax`. Recovery: case-insensitive
assertion. **Prevention:** Use case-insensitive matching for cookie attribute
assertions in Next.js tests.

**5. Merged DB query broke positional test mocks** — After merging two SELECT
queries into one (review simplification), `mockReturnValueOnce` chains no longer
matched. Recovery: updated mock data to include both columns. **Prevention:**
When refactoring queries that change the number of DB calls, update positional
mock chains in tests simultaneously.

**6. Auth check addition broke initiate route tests** — Adding `getUser()` to
the initiate route caused 4 failures because the describe block lacked a
`beforeEach` mock for `mockGetUser`. Recovery: added mock setup. **Prevention:**
When adding auth checks to route handlers, always update the corresponding test
file's mock setup in the same edit.

## Tags

rls, supabase, column-level-security, restrictive-policy, installation-takeover,
github-username, oauth, service-role
