---
title: "security: restrict RLS UPDATE policy on tc_accepted_at column"
type: fix
date: 2026-03-20
semver: patch
---

# security: restrict RLS UPDATE policy on tc_accepted_at column

## Overview

The `public.users` table has an unrestricted UPDATE RLS policy (`"Users can update own profile"`) that allows authenticated users to modify any column in their own row, including `tc_accepted_at`. This column records when a user accepted the Terms & Conditions via the clickwrap checkbox at signup. It should be immutable once set -- only the `handle_new_user()` trigger (running as `SECURITY DEFINER`) should write it.

A user could theoretically call the Supabase PostgREST API directly to update their `tc_accepted_at` to any timestamp, undermining audit trail integrity. This is a P2 security gap discovered during the review of #889.

## Problem Statement / Motivation

The `tc_accepted_at` column was added in migration `005_add_tc_accepted_at.sql` as part of #889. The column is correctly populated by the `handle_new_user()` trigger (running as `SECURITY DEFINER`, which bypasses RLS). However, the pre-existing UPDATE RLS policy from `001_initial_schema.sql` grants blanket UPDATE access to authenticated users on their own row:

```sql
-- 001_initial_schema.sql, line 22-23
create policy "Users can update own profile"
  on public.users for update
  using (auth.uid() = id);
```

This policy has no `WITH CHECK` clause and no column restriction. An authenticated user can issue:

```sql
UPDATE public.users SET tc_accepted_at = '2020-01-01T00:00:00Z' WHERE id = auth.uid();
```

This rewrites their consent timestamp, which could be used to:
- Backdate T&C acceptance to before the current T&C version took effect
- Set it to NULL, claiming they never accepted
- Set it to a future date

The consent timestamp is a legal audit record and must be tamper-proof from the user's perspective.

## Proposed Solution

Use **column-level grants** to revoke UPDATE on `tc_accepted_at` from the `authenticated` role. This is the simplest, most maintainable approach.

### Why column-level grants (not alternatives)

| Approach | Pros | Cons |
|----------|------|------|
| **Column-level grant (recommended)** | Single DDL statement, declarative, PostgreSQL-native, no procedural logic | Requires understanding of Supabase's role model |
| WITH CHECK on UPDATE policy | Works within RLS framework | Fragile -- requires `OLD.tc_accepted_at = NEW.tc_accepted_at` which is awkward to express for nullable columns and can be bypassed if the policy is ever replaced |
| BEFORE UPDATE trigger | Explicit error message | Adds procedural complexity, harder to audit, trigger ordering with existing triggers is a concern |

Column-level grants are the standard PostgreSQL mechanism for this exact problem. They operate at a layer below RLS (the privilege system), meaning even if the RLS policy is modified or replaced in the future, the column remains protected. Supabase's `authenticated` role is the role used by PostgREST for authenticated API requests.

### Attack Surface Enumeration

All code paths that can write to `tc_accepted_at`:

1. **`handle_new_user()` trigger** (`005_add_tc_accepted_at.sql`): Runs as `SECURITY DEFINER` (postgres superuser context). Sets `tc_accepted_at` at user creation. **Safe** -- SECURITY DEFINER bypasses both RLS and column-level grants.

2. **`ensureWorkspaceProvisioned()` fallback** (`apps/web-platform/app/(auth)/callback/route.ts`, line 73-79): Uses `createServiceClient()` (service role key, bypasses RLS). Inserts a new user row with `tc_accepted_at: new Date().toISOString()`. **Safe** -- service role has full privileges.

3. **PostgREST API (authenticated user)**: The current RLS UPDATE policy allows `UPDATE public.users SET tc_accepted_at = ... WHERE id = auth.uid()`. **This is the gap** -- the column-level grant fix closes it.

4. **PostgREST API (anon role)**: No RLS policies grant anon access to `public.users`. **Safe**.

5. **Direct database access (postgres role)**: Superuser bypasses everything. **Out of scope** -- if the database is compromised, column grants are irrelevant.

No other code paths write to `tc_accepted_at`. The fix covers the only vulnerable path (path 3).

## Technical Considerations

### Migration SQL

New migration file: `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`

```sql
-- Restrict tc_accepted_at from user-initiated updates.
-- The handle_new_user() trigger runs as SECURITY DEFINER and is unaffected.
-- The service role (used by ensureWorkspaceProvisioned) is also unaffected.

-- Step 1: Revoke UPDATE on tc_accepted_at from authenticated role
REVOKE UPDATE (tc_accepted_at) ON public.users FROM authenticated;

-- Step 2: Explicitly grant UPDATE on the columns users SHOULD be able to update
-- This is needed because PostgreSQL column-level grants interact with
-- table-level grants -- once any column-level GRANT/REVOKE is issued,
-- the privilege check becomes column-aware.
-- List all user-updatable columns explicitly:
GRANT UPDATE (email, workspace_path, workspace_status, stripe_customer_id, subscription_status) ON public.users TO authenticated;
```

### PostgreSQL privilege semantics

When a table-level UPDATE privilege exists (as Supabase grants by default to `authenticated`), revoking UPDATE on a single column does not work as expected -- the table-level grant still covers all columns. The correct approach is:

1. Revoke the table-level UPDATE privilege
2. Re-grant UPDATE only on the specific columns users should be able to modify

Alternatively, if Supabase has already granted column-level UPDATE privileges rather than table-level, a simple `REVOKE UPDATE (tc_accepted_at)` suffices. The migration must verify which grant model is in effect.

**Verification query** (to run in Supabase SQL editor or via migration):

```sql
-- Check current grants on public.users for the authenticated role
SELECT grantee, privilege_type, column_name
FROM information_schema.column_privileges
WHERE table_schema = 'public' AND table_name = 'users' AND grantee = 'authenticated';

-- Check table-level grants
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'users' AND grantee = 'authenticated';
```

### Supabase role model

Supabase uses three main roles:
- `anon`: Unauthenticated requests
- `authenticated`: Logged-in users (via JWT)
- `service_role`: Server-side operations (bypasses RLS)

The `authenticated` role is what PostgREST uses when a valid JWT is present. Column-level privilege revocation on this role prevents client-side updates to `tc_accepted_at` while leaving server-side operations (service role, SECURITY DEFINER triggers) unaffected.

### Non-goals

- Protecting `created_at` (already effectively immutable -- no business logic updates it, and backdating it has no legal consequence)
- Adding a BEFORE UPDATE trigger for error messages (column-level grants produce a clear PostgreSQL error: `ERROR: permission denied for table users`)
- Protecting other tables' columns (out of scope for this issue)

## Acceptance Criteria

- [ ] New migration `006_restrict_tc_accepted_at_update.sql` revokes UPDATE privilege on `tc_accepted_at` from the `authenticated` role
- [ ] `handle_new_user()` trigger still successfully sets `tc_accepted_at` at signup (SECURITY DEFINER bypass verified)
- [ ] `ensureWorkspaceProvisioned()` fallback still successfully inserts rows with `tc_accepted_at` (service role bypass verified)
- [ ] Authenticated users can still update their own `email`, `workspace_path`, `workspace_status`, `stripe_customer_id`, and `subscription_status` columns
- [ ] An authenticated user attempting to UPDATE `tc_accepted_at` via PostgREST receives a permission error
- [ ] Migration is idempotent (running it twice does not error)

## Test Scenarios

- Given an authenticated user, when they attempt `UPDATE public.users SET tc_accepted_at = now() WHERE id = auth.uid()` via the Supabase client, then the operation fails with a permission error
- Given an authenticated user, when they attempt to update `workspace_status` via the Supabase client, then the operation succeeds (no regression)
- Given a new user signing up with the T&C checkbox checked, when the `handle_new_user()` trigger fires, then `tc_accepted_at` is set correctly (SECURITY DEFINER not affected by column grants)
- Given the `ensureWorkspaceProvisioned()` fallback path, when it inserts a user row with `tc_accepted_at`, then the insert succeeds (service role not affected)
- Given the migration has already been applied, when it is run again, then no error occurs (idempotency)

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Table-level vs column-level grant interaction | Verify current grant model before applying; migration includes both REVOKE and explicit column GRANT |
| Future columns added to `public.users` need explicit UPDATE grants | Document in migration comment; add to migration checklist for future schema changes |
| Supabase dashboard or client library updates could reset grants | Migration is version-controlled and re-runnable; Supabase migrations are applied in order |
| PostgREST error message may be opaque to users | No user-facing flow updates `tc_accepted_at` -- this only affects direct API abuse |

## References & Research

### Internal References

- RLS policies: `apps/web-platform/supabase/migrations/001_initial_schema.sql` (lines 17-23)
- tc_accepted_at column: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- handle_new_user() trigger: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql` (lines 10-26)
- Auth callback fallback: `apps/web-platform/app/(auth)/callback/route.ts` (lines 66-81)
- All migration files: `apps/web-platform/supabase/migrations/001-005`
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-trigger-boolean-cast-safety.md`
- Parent plan: `knowledge-base/project/plans/2026-03-20-legal-tc-acceptance-mechanism-plan.md`

### External References

- [PostgreSQL GRANT/REVOKE on columns](https://www.postgresql.org/docs/current/sql-grant.html)
- [Supabase RLS and roles](https://supabase.com/docs/guides/auth/row-level-security)
- [Supabase database roles](https://supabase.com/docs/guides/database/postgres/roles)

### Related Work

- Issue: #911 (this plan)
- Issue: #889 (T&C acceptance mechanism -- introduced tc_accepted_at)
- PR: #898 (T&C acceptance mechanism implementation)
