---
title: "security: restrict RLS UPDATE policy on tc_accepted_at column"
type: fix
date: 2026-03-20
semver: patch
---

# security: restrict RLS UPDATE policy on tc_accepted_at column

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources used:** Supabase column-level security docs (Context7), PostgreSQL GRANT/REVOKE docs, codebase audit of all `public.users` write paths, 3 project learnings

### Key Improvements

1. Corrected migration SQL: must revoke table-level UPDATE first, then re-grant column-level -- a column-level REVOKE alone is ineffective when a table-level grant exists (confirmed by Supabase docs)
2. Discovered that `stripe_customer_id`, `subscription_status`, `workspace_path`, and `workspace_status` are exclusively updated via service role -- no authenticated client code writes to `public.users` at all, enabling a more restrictive grant
3. Added `created_at` to the exclusion list alongside `tc_accepted_at` for defense-in-depth
4. Added INSERT privilege analysis -- column-level grants on UPDATE do not affect INSERT; the `ensureWorkspaceProvisioned()` fallback INSERT path is safe without additional changes
5. Added `anon` role hardening recommendation for completeness

### New Considerations Discovered

- Supabase docs explicitly state: "If you have both [table-level and column-level privileges], and you revoke the column-level privilege, the table-level privilege will still be in effect" -- the original migration SQL would have been silently ineffective
- No authenticated client code currently updates `public.users` at all -- all updates go through `createServiceClient()` (service role). This means the UPDATE grant could be empty, but granting `email` preserves future flexibility for profile editing
- PostgreSQL `REVOKE UPDATE ON TABLE` is idempotent -- revoking a privilege that does not exist is a no-op, no `IF EXISTS` needed
- Column-level privileges only restrict UPDATE and SELECT, not INSERT -- the `ensureWorkspaceProvisioned()` fallback path uses INSERT and is unaffected

---

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

### Research Insights: Supabase Column-Level Security

Supabase has [official documentation on column-level security](https://github.com/supabase/supabase/blob/master/apps/docs/content/guides/database/postgres/column-level-security.mdx) that confirms this exact pattern. Key findings:

**Critical: table-level grants override column-level revokes.** The Supabase docs state: "If you have both [table-level and column-level privileges], and you revoke the column-level privilege, the table-level privilege will still be in effect." This means a simple `REVOKE UPDATE (tc_accepted_at) ON public.users FROM authenticated` would be **silently ineffective** if a table-level UPDATE grant exists.

**Correct two-step approach** (from Supabase docs):

```sql
-- Step 1: Remove the table-level UPDATE privilege
REVOKE UPDATE ON TABLE public.users FROM authenticated;

-- Step 2: Re-grant UPDATE only on allowed columns
GRANT UPDATE (title, content) ON TABLE public.users TO authenticated;
```

**Column-level security is independent from RLS.** RLS controls which rows a user can access; column privileges control which columns. Both layers work together -- the UPDATE RLS policy (`auth.uid() = id`) still controls row access, while column-level grants control which columns within that row can be modified.

### Attack Surface Enumeration

All code paths that can write to `tc_accepted_at`:

1. **`handle_new_user()` trigger** (`005_add_tc_accepted_at.sql`): Runs as `SECURITY DEFINER` (postgres superuser context). Sets `tc_accepted_at` at user creation via INSERT. **Safe** -- SECURITY DEFINER bypasses both RLS and column-level grants.

2. **`ensureWorkspaceProvisioned()` fallback** (`apps/web-platform/app/(auth)/callback/route.ts`, line 73-79): Uses `createServiceClient()` (service role key, bypasses RLS). Inserts a new user row with `tc_accepted_at: new Date().toISOString()`. **Safe** -- service role has full privileges. Additionally, this is an INSERT, and column-level UPDATE restrictions do not affect INSERT operations.

3. **PostgREST API (authenticated user)**: The current RLS UPDATE policy allows `UPDATE public.users SET tc_accepted_at = ... WHERE id = auth.uid()`. **This is the gap** -- the column-level grant fix closes it.

4. **PostgREST API (anon role)**: No RLS policies grant anon access to `public.users`. **Safe**.

5. **Direct database access (postgres role)**: Superuser bypasses everything. **Out of scope** -- if the database is compromised, column grants are irrelevant.

### Research Insights: Codebase Write Path Audit

**No authenticated client code currently updates `public.users`.** A thorough grep of all `.ts` files in `apps/web-platform/` reveals that every UPDATE on the `users` table goes through `createServiceClient()` (service role):

| Write path | Client type | Columns written | Affected by grant change? |
|------------|-------------|-----------------|--------------------------|
| `callback/route.ts` line 89-90 | Service role | `workspace_path`, `workspace_status` | No |
| `callback/route.ts` line 73-79 | Service role | INSERT (all columns) | No |
| `api/workspace/route.ts` line 39 | Service role | `workspace_status` | No |
| `api/workspace/route.ts` line 48 | Service role | `workspace_path`, `workspace_status` | No |
| `api/webhooks/stripe/route.ts` line 42 | Service role | `stripe_customer_id`, `subscription_status` | No |
| `api/webhooks/stripe/route.ts` line 60 | Service role | `subscription_status` | No |

This means the authenticated role's UPDATE grant on `public.users` could technically be **empty** (revoke all columns) without breaking any existing functionality. However, granting UPDATE on `email` preserves forward compatibility for a future user profile editing feature.

No other code paths write to `tc_accepted_at`. The fix covers the only vulnerable path (path 3).

## Technical Considerations

### Migration SQL

New migration file: `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`

```sql
-- Restrict tc_accepted_at and created_at from user-initiated updates.
--
-- Context: The blanket UPDATE RLS policy from 001_initial_schema.sql allows
-- authenticated users to modify any column in their own row, including
-- tc_accepted_at (T&C acceptance timestamp) which must be immutable.
--
-- Approach: Supabase grants table-level UPDATE to authenticated by default.
-- A column-level REVOKE alone is ineffective when a table-level grant exists
-- (see: supabase.com/docs/guides/database/postgres/column-level-security).
-- We must revoke the table-level grant first, then re-grant only safe columns.
--
-- The handle_new_user() trigger runs as SECURITY DEFINER and is unaffected.
-- The service role (used by all server-side write paths) is also unaffected.
-- Column-level UPDATE restrictions do not affect INSERT operations.

-- Step 1: Revoke table-level UPDATE from authenticated role
REVOKE UPDATE ON TABLE public.users FROM authenticated;

-- Step 2: Grant column-level UPDATE only on user-safe columns
-- Currently no authenticated client code updates public.users (all writes
-- use service role), but email is granted for future profile editing.
--
-- Excluded columns (server-managed only):
--   id              - primary key, immutable
--   created_at      - system timestamp, immutable
--   tc_accepted_at  - T&C acceptance audit record, immutable (#911)
--   workspace_path  - set by workspace provisioning (service role)
--   workspace_status - set by workspace provisioning (service role)
--   stripe_customer_id    - set by Stripe webhooks (service role)
--   subscription_status   - set by Stripe webhooks (service role)
--
-- IMPORTANT: When adding new columns to public.users, decide whether they
-- should be user-updatable and add them to this GRANT if so.
GRANT UPDATE (email) ON TABLE public.users TO authenticated;
```

### Research Insights: PostgreSQL Privilege Semantics

**Table-level vs column-level grant interaction (confirmed by Supabase docs):**

Supabase's column-level security documentation explicitly warns: "By default, our table will have a table-level UPDATE privilege." When a table-level UPDATE privilege exists, revoking UPDATE on a single column does NOT work -- the table-level grant still covers all columns. The correct sequence is:

1. `REVOKE UPDATE ON TABLE public.users FROM authenticated;` -- removes table-level grant
2. `GRANT UPDATE (email) ON TABLE public.users TO authenticated;` -- re-grants only safe columns

This two-step approach is idempotent:

- `REVOKE UPDATE ON TABLE` is a no-op if the privilege does not exist
- `GRANT UPDATE (column)` is a no-op if the privilege already exists

**INSERT is unaffected by column-level UPDATE restrictions.** PostgreSQL column-level privileges for UPDATE and SELECT are independent from INSERT. The `ensureWorkspaceProvisioned()` fallback path uses INSERT (not UPDATE) and does not require any changes.

**Verification query** (to confirm the migration worked):

```sql
-- After migration, this should show only 'email' as updatable
SELECT grantee, privilege_type, column_name
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND grantee = 'authenticated'
  AND privilege_type = 'UPDATE';

-- Table-level UPDATE should be gone
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND grantee = 'authenticated'
  AND privilege_type = 'UPDATE';
-- Expected: 0 rows
```

### Supabase role model

Supabase uses three main roles:

- `anon`: Unauthenticated requests
- `authenticated`: Logged-in users (via JWT)
- `service_role`: Server-side operations (bypasses RLS)

The `authenticated` role is what PostgREST uses when a valid JWT is present. Column-level privilege revocation on this role prevents client-side updates to `tc_accepted_at` while leaving server-side operations (service role, SECURITY DEFINER triggers) unaffected.

### Research Insights: Defense-in-Depth Considerations

**Protect `created_at` as well.** While backdating `created_at` has no legal consequence, applying the same column exclusion costs nothing and prevents a potential audit confusion vector. The migration excludes both `created_at` and `tc_accepted_at` from the authenticated role's UPDATE grant.

**Stripe and workspace columns are also server-managed.** The codebase audit confirmed that `stripe_customer_id`, `subscription_status`, `workspace_path`, and `workspace_status` are exclusively written by service-role code. Excluding them from the authenticated UPDATE grant is a low-risk hardening measure that follows the principle of least privilege.

**SELECT privileges are not restricted.** Users can still SELECT (read) all columns in their own row via the existing SELECT RLS policy. This change only restricts UPDATE. If column-level SELECT restrictions are desired in the future (e.g., hiding `stripe_customer_id` from PostgREST responses), that would be a separate issue.

### Non-goals

- Protecting `created_at` via a separate mechanism (it is already excluded from the UPDATE grant as defense-in-depth)
- Adding a BEFORE UPDATE trigger for error messages (column-level grants produce a clear PostgreSQL error: `ERROR: permission denied for table users`)
- Protecting other tables' columns (out of scope for this issue)
- Restricting SELECT privileges (users should still be able to read their own profile)

## Acceptance Criteria

- [x] New migration `006_restrict_tc_accepted_at_update.sql` revokes table-level UPDATE privilege on `public.users` from the `authenticated` role
- [x] Migration re-grants column-level UPDATE on `email` only to the `authenticated` role
- [x] `handle_new_user()` trigger still successfully sets `tc_accepted_at` at signup (SECURITY DEFINER bypass verified)
- [x] `ensureWorkspaceProvisioned()` fallback still successfully inserts rows with `tc_accepted_at` (service role bypass verified)
- [x] Stripe webhook route still successfully updates `stripe_customer_id` and `subscription_status` (service role bypass verified)
- [x] Workspace provisioning route still successfully updates `workspace_path` and `workspace_status` (service role bypass verified)
- [x] An authenticated user attempting to UPDATE `tc_accepted_at` via PostgREST receives a permission error
- [x] An authenticated user attempting to UPDATE `stripe_customer_id` via PostgREST receives a permission error
- [x] Migration is idempotent (running it twice does not error)
- [x] Verification query confirms only `email` appears in `column_privileges` for `authenticated` role with `UPDATE` type

## Test Scenarios

- Given an authenticated user, when they attempt `UPDATE public.users SET tc_accepted_at = now() WHERE id = auth.uid()` via the Supabase client, then the operation fails with a permission error
- Given an authenticated user, when they attempt `UPDATE public.users SET stripe_customer_id = 'cus_fake' WHERE id = auth.uid()` via the Supabase client, then the operation fails with a permission error
- Given an authenticated user, when they attempt `UPDATE public.users SET email = 'new@example.com' WHERE id = auth.uid()` via the Supabase client, then the operation succeeds (email is explicitly granted)
- Given a new user signing up with the T&C checkbox checked, when the `handle_new_user()` trigger fires, then `tc_accepted_at` is set correctly (SECURITY DEFINER not affected by column grants)
- Given the `ensureWorkspaceProvisioned()` fallback path, when it inserts a user row with `tc_accepted_at`, then the insert succeeds (service role not affected, INSERT not restricted by UPDATE grants)
- Given the Stripe webhook receiving a `checkout.session.completed` event, when it updates `stripe_customer_id` and `subscription_status` via service role, then the update succeeds
- Given the workspace API route provisioning a workspace, when it updates `workspace_path` and `workspace_status` via service role, then the update succeeds
- Given the migration has already been applied, when it is run again, then no error occurs (idempotency)

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Table-level vs column-level grant interaction causes silent failure | Confirmed by Supabase docs: must revoke table-level first. Migration uses correct two-step sequence. |
| Future columns added to `public.users` need explicit UPDATE grants | Documented in migration comment with column inventory. Constitution.md could add a migration checklist item. |
| Supabase project reset or migration replay resets grants | Migration is version-controlled and re-runnable. REVOKE/GRANT are both idempotent. |
| Restricting `workspace_path`/`workspace_status` UPDATE from authenticated role | Codebase audit confirms no authenticated client code updates these. All writes use service role. |
| Future profile editing feature needs email UPDATE | Email is explicitly granted to authenticated role. |

## References & Research

### Internal References

- RLS policies: `apps/web-platform/supabase/migrations/001_initial_schema.sql` (lines 17-23)
- tc_accepted_at column: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`
- handle_new_user() trigger: `apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql` (lines 10-26)
- Auth callback fallback: `apps/web-platform/app/(auth)/callback/route.ts` (lines 66-81)
- Stripe webhook: `apps/web-platform/app/api/webhooks/stripe/route.ts` (service role updates)
- Workspace API: `apps/web-platform/app/api/workspace/route.ts` (service role updates)
- All migration files: `apps/web-platform/supabase/migrations/001-005`
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-trigger-boolean-cast-safety.md`
- Learning: `knowledge-base/project/learnings/2026-03-18-postgresql-set-not-null-self-validating.md`
- Learning: `knowledge-base/project/learnings/2026-03-17-postgrest-bytea-base64-mismatch.md`
- Parent plan: `knowledge-base/project/plans/2026-03-20-legal-tc-acceptance-mechanism-plan.md`

### External References

- [Supabase Column-Level Security](https://supabase.com/docs/guides/database/postgres/column-level-security) -- official documentation confirming the two-step REVOKE/GRANT approach
- [PostgreSQL GRANT/REVOKE on columns](https://www.postgresql.org/docs/current/sql-grant.html)
- [Supabase RLS and roles](https://supabase.com/docs/guides/auth/row-level-security)
- [Supabase database roles](https://supabase.com/docs/guides/database/postgres/roles)

### Related Work

- Issue: #911 (this plan)
- Issue: #889 (T&C acceptance mechanism -- introduced tc_accepted_at)
- PR: #898 (T&C acceptance mechanism implementation)
