---
title: "fix: remediate existing rows with fabricated tc_accepted_at timestamps"
type: fix
date: 2026-03-20
semver: patch
---

# fix: remediate existing rows with fabricated tc_accepted_at timestamps

## Overview

Before PR #927 fixed the fallback INSERT in `callback/route.ts`, the safety-net code path unconditionally set `tc_accepted_at = now()` for every user created via the fallback path -- regardless of whether they actually accepted T&C. Any such rows now carry fabricated consent timestamps, which is a GDPR legal liability (false evidence of affirmative consent under Article 7(1)).

This plan creates a remediation migration to identify and null out those incorrectly-stamped rows.

## Problem Statement

The fallback INSERT path in `apps/web-platform/app/(auth)/callback/route.ts` (introduced in PR #898, fixed in PR #927) set `tc_accepted_at: new Date().toISOString()` unconditionally. The database trigger in `005_add_tc_accepted_at.sql` correctly checked `raw_user_meta_data->>'tc_accepted' = 'true'` before stamping, but the TypeScript fallback did not mirror this conditional.

**Bug window:** 2026-03-20T14:07:57Z (PR #898 merged) to 2026-03-20T17:28:27Z (PR #927 merged) -- approximately 3 hours and 20 minutes.

**Affected rows:** Users whose `public.users` row was created by the fallback path during this window, where the user did NOT actually accept T&C (i.e., `auth.users.raw_user_meta_data->>'tc_accepted'` is not `'true'`), but `tc_accepted_at` is non-null.

## Proposed Solution

A single Supabase SQL migration (`007_remediate_fabricated_tc_accepted_at.sql`) that:

1. Identifies rows where `tc_accepted_at IS NOT NULL` but the user's `auth.users.raw_user_meta_data->>'tc_accepted'` is not `'true'`
2. Sets `tc_accepted_at = NULL` for those rows
3. Logs the remediation for audit trail purposes

### Discriminator Strategy

The issue suggests comparing `tc_accepted_at` with `created_at` (rows within seconds of each other are suspect). However, this approach has a false-positive problem: legitimate trigger-path users who DID accept T&C also have `tc_accepted_at` and `created_at` within seconds of each other (both are set to `now()` at INSERT time).

**The authoritative discriminator is the user metadata itself.** `auth.users.raw_user_meta_data->>'tc_accepted'` is the ground truth for whether the user actually accepted T&C. The migration should:

- Join `public.users` with `auth.users` on `id`
- Filter for rows where `tc_accepted_at IS NOT NULL` AND `raw_user_meta_data->>'tc_accepted'` IS DISTINCT FROM `'true'`
- NULL out `tc_accepted_at` for those rows

This is both more precise (no false positives on legitimate acceptances) and more robust (works regardless of timestamp proximity).

**Secondary guard (belt-and-suspenders):** The migration can additionally scope to users created within the bug window (2026-03-20T14:07:57Z to 2026-03-20T17:28:27Z) to further limit blast radius. However, the metadata check alone is sufficient -- the time window guard is defense-in-depth.

### Why NOT timestamp proximity alone

If a user legitimately accepted T&C and was created by the trigger path, their `tc_accepted_at` and `created_at` will also be within seconds of each other. Timestamp proximity cannot distinguish:
- **Legitimate:** Trigger fired, user accepted T&C, both timestamps are `now()`
- **Fabricated:** Fallback fired, user did NOT accept T&C, both timestamps are `now()`

Only the metadata check can distinguish these cases.

## Technical Considerations

### Database access

The migration needs to read `auth.users.raw_user_meta_data`, which is in the `auth` schema. Supabase migrations run with superuser privileges, so this is accessible. The migration file runs via `supabase db push` or the Supabase dashboard SQL editor.

### Idempotency

The migration is idempotent: running it twice has no additional effect because after the first run, the affected rows already have `tc_accepted_at = NULL`, so the WHERE clause no longer matches them.

### Rollback

This migration is **not reversible** -- once `tc_accepted_at` is set to NULL, the fabricated timestamps are lost. This is intentional: the fabricated timestamps had no legal validity and retaining them creates liability. A `-- down` section is included for structural completeness but clearly documented as not applicable.

### SECURITY DEFINER context

The migration uses a DO block or direct UPDATE statement, not a stored function. No `SECURITY DEFINER` context is needed because migrations run as superuser.

## Non-goals

- Re-prompting affected users to accept T&C (separate UX concern, tracked by #933)
- Fixing the timestamp for users who DID accept T&C but whose trigger path failed (the trigger is the primary path; if it succeeded, the row is correct)
- Backfilling `tc_accepted_at` for pre-clickwrap users (intentionally NULL per migration 005 comment)

## Acceptance Criteria

- [ ] Migration `007_remediate_fabricated_tc_accepted_at.sql` created in `apps/web-platform/supabase/migrations/`
- [ ] Migration nulls `tc_accepted_at` only for rows where metadata does NOT confirm T&C acceptance
- [ ] Migration is idempotent (safe to run multiple times)
- [ ] Migration includes a preceding SELECT for dry-run verification (commented out or as a separate query)
- [ ] Migration includes a comment documenting the bug, the fix PR (#927), and the GDPR rationale
- [ ] No rows where `raw_user_meta_data->>'tc_accepted' = 'true'` are affected
- [ ] Existing test suite passes (no regressions)

## Test Scenarios

- Given a user created by the fallback path who did NOT accept T&C (metadata `tc_accepted` absent or false), when the migration runs, then `tc_accepted_at` is set to NULL
- Given a user created by the trigger path who DID accept T&C (metadata `tc_accepted = 'true'`), when the migration runs, then `tc_accepted_at` is unchanged (still the original timestamp)
- Given a user created before the clickwrap feature (no `tc_accepted_at` column yet, or `tc_accepted_at` is already NULL), when the migration runs, then no change occurs
- Given the migration has already been run once, when it is run again, then no rows are affected (idempotency)

## MVP

### `apps/web-platform/supabase/migrations/007_remediate_fabricated_tc_accepted_at.sql`

```sql
-- Remediation: null out fabricated tc_accepted_at timestamps
--
-- Bug: PR #898 introduced a fallback INSERT in callback/route.ts that
-- unconditionally set tc_accepted_at = now() regardless of whether the
-- user accepted T&C. Fixed in PR #927. This migration remediates any
-- rows created by the buggy fallback path.
--
-- Discriminator: Join auth.users to check raw_user_meta_data->>'tc_accepted'.
-- Rows where tc_accepted_at IS NOT NULL but the user metadata does not
-- confirm T&C acceptance are fabricated and must be nulled.
--
-- GDPR Article 7(1): Controller must demonstrate consent was given.
-- Fabricated timestamps fail this requirement.
--
-- Idempotent: safe to run multiple times.

-- Dry-run: uncomment to preview affected rows before executing
-- SELECT u.id, u.email, u.tc_accepted_at, u.created_at,
--        a.raw_user_meta_data->>'tc_accepted' as tc_meta
-- FROM public.users u
-- JOIN auth.users a ON a.id = u.id
-- WHERE u.tc_accepted_at IS NOT NULL
--   AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';

UPDATE public.users
SET tc_accepted_at = NULL
FROM auth.users a
WHERE public.users.id = a.id
  AND public.users.tc_accepted_at IS NOT NULL
  AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';
```

## References

- Issue #934: This issue (remediate fabricated rows)
- Issue #925: The original bug report (fallback INSERT unconditionally sets tc_accepted_at)
- PR #927: The fix (conditional tc_accepted_at in fallback)
- PR #898: Introduction of T&C acceptance mechanism (where the bug was introduced)
- Migration `005_add_tc_accepted_at.sql`: The trigger with correct conditional logic
- Migration `006_restrict_tc_accepted_at_update.sql`: Column-level UPDATE restriction
- Learning: `knowledge-base/learnings/2026-03-20-supabase-trigger-fallback-parity.md`
- Learning: `knowledge-base/learnings/2026-03-20-supabase-column-level-grant-override.md`
- `apps/web-platform/app/(auth)/callback/route.ts`: The fixed callback route
