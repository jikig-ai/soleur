---
title: "fix: remediate existing rows with fabricated tc_accepted_at timestamps"
type: fix
date: 2026-03-20
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Technical Considerations, MVP, Acceptance Criteria, Test Scenarios, new Verification Runbook)
**Research sources:** Context7 Supabase docs, PostgreSQL UPDATE JOIN documentation, GDPR Article 7 compliance guidance, data-migration-expert review checklist, data-integrity-guardian privacy compliance checks

### Key Improvements

1. Upgraded bare UPDATE to a DO block with `GET DIAGNOSTICS` + `RAISE NOTICE` for auditable row count logging -- essential for GDPR remediation evidence
2. Added a post-migration verification runbook with concrete SQL queries to confirm correctness
3. Added `auth` schema safety note -- migration only reads from `auth.users`, never writes, so no risk of corrupting Supabase-managed schema
4. Added edge case for `tc_accepted = 'false'` (string) vs absent metadata -- both correctly handled by `IS DISTINCT FROM 'true'`
5. Added GDPR Article 7(1) documentation requirement: the remediation itself must be recorded as evidence of the controller's corrective action

### New Considerations Discovered

- The `auth.users.raw_user_meta_data` column stores JSONB; the `->>` operator returns text, so the comparison `IS DISTINCT FROM 'true'` correctly handles NULL (key absent), `'false'`, and any other non-`'true'` value
- PostgreSQL `UPDATE ... FROM` with a 1:1 join (both sides keyed on `users.id` PK) is safe from the multi-match pitfall documented in PostgreSQL docs
- Supabase docs warn against writing to auth-managed schemas in migrations, but this migration only reads from `auth.users` -- the write target is `public.users` which is application-managed

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

### Research Insights

**Auth schema safety:** [Supabase docs](https://supabase.com/docs/guides/troubleshooting/resolving-500-status-authentication-errors-7bU5U8) warn that modifying structures in the auth schema (adding RLS, modifying columns, adding/dropping tables) can break Auth Server migrations. This migration is safe because it only _reads_ from `auth.users` -- the write target is `public.users`, which is application-managed. No auth schema modifications are made.

**JSONB text extraction:** The `raw_user_meta_data->>'tc_accepted'` operator returns a `text` value (not JSONB). The comparison `IS DISTINCT FROM 'true'` correctly handles three cases:

- Key absent (NULL result) -- IS DISTINCT FROM 'true' is TRUE
- Key present with value `'false'` (string) -- IS DISTINCT FROM 'true' is TRUE
- Key present with value `'true'` (string) -- IS DISTINCT FROM 'true' is FALSE (row preserved)

This is more robust than `!= 'true'` which would miss the NULL case (NULL != 'true' evaluates to NULL, not TRUE).

**UPDATE FROM join safety:** [PostgreSQL docs](https://www.postgresql.org/docs/current/sql-update.html) note that when the FROM clause join matches multiple source rows per target row, the target is updated once per match. This is a common pitfall for data remediation. However, in this case the join is on `public.users.id = auth.users.id` -- both are primary keys, guaranteeing a 1:1 relationship. No multi-match risk exists.

### Idempotency

The migration is idempotent: running it twice has no additional effect because after the first run, the affected rows already have `tc_accepted_at = NULL`, so the WHERE clause no longer matches them.

### Rollback

This migration is **not reversible** -- once `tc_accepted_at` is set to NULL, the fabricated timestamps are lost. This is intentional: the fabricated timestamps had no legal validity and retaining them creates liability. A `-- down` section is included for structural completeness but clearly documented as not applicable.

### SECURITY DEFINER context

The migration uses a DO block with `RAISE NOTICE` for audit logging. No `SECURITY DEFINER` context is needed because migrations run as superuser.

### GDPR remediation documentation

[GDPR Article 7(1)](https://gdpr-info.eu/art-7-gdpr/) requires the controller to demonstrate that consent was given. Fabricated timestamps create false evidence of consent. The remediation itself should be documented as evidence of the controller's corrective action. The migration header comments serve this purpose, and the `RAISE NOTICE` output provides an execution record. Additionally, the PR description and linked issues (#925, #927, #934) form a complete audit trail in the repository history.

## Non-goals

- Re-prompting affected users to accept T&C (separate UX concern, tracked by #933)
- Fixing the timestamp for users who DID accept T&C but whose trigger path failed (the trigger is the primary path; if it succeeded, the row is correct)
- Backfilling `tc_accepted_at` for pre-clickwrap users (intentionally NULL per migration 005 comment)

## Acceptance Criteria

- [x] Migration `007_remediate_fabricated_tc_accepted_at.sql` created in `apps/web-platform/supabase/migrations/`
- [x] Migration nulls `tc_accepted_at` only for rows where metadata does NOT confirm T&C acceptance
- [x] Migration is idempotent (safe to run multiple times)
- [x] Migration includes a preceding SELECT for dry-run verification (commented out or as a separate query)
- [x] Migration includes a comment documenting the bug, the fix PR (#927), and the GDPR rationale
- [x] No rows where `raw_user_meta_data->>'tc_accepted' = 'true'` are affected
- [x] Migration uses DO block with `GET DIAGNOSTICS` + `RAISE NOTICE` to log affected row count
- [x] Migration only reads from `auth.users` (no writes to auth-managed schema)
- [x] Migration header documents irreversibility rationale (fabricated timestamps must not be restored)
- [x] Existing test suite passes (no regressions)

## Test Scenarios

- Given a user created by the fallback path who did NOT accept T&C (metadata `tc_accepted` absent), when the migration runs, then `tc_accepted_at` is set to NULL
- Given a user created by the fallback path with metadata `tc_accepted = 'false'` (string), when the migration runs, then `tc_accepted_at` is set to NULL
- Given a user created by the trigger path who DID accept T&C (metadata `tc_accepted = 'true'`), when the migration runs, then `tc_accepted_at` is unchanged (still the original timestamp)
- Given a user created before the clickwrap feature (`tc_accepted_at` is already NULL), when the migration runs, then no change occurs
- Given the migration has already been run once, when it is run again, then RAISE NOTICE reports "Remediated 0 row(s)" (idempotency)
- Given a user with `tc_accepted_at IS NOT NULL` and no corresponding `auth.users` row (orphaned -- should not occur but defensive), when the migration runs, then the row is NOT affected (JOIN excludes it)

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
-- Fabricated timestamps fail this requirement. This remediation is itself
-- evidence of the controller's corrective action (documented in PR #927,
-- issue #934, and this migration's git history).
--
-- Auth schema safety: This migration only READS from auth.users (via JOIN).
-- It does NOT modify any auth-managed tables, columns, or constraints.
--
-- Idempotent: safe to run multiple times. The WHERE clause excludes rows
-- where tc_accepted_at is already NULL.
--
-- Not reversible: fabricated timestamps are intentionally discarded.
-- Restoring them would re-create false consent evidence.

-- Dry-run: uncomment to preview affected rows before executing
-- SELECT u.id, u.email, u.tc_accepted_at, u.created_at,
--        a.raw_user_meta_data->>'tc_accepted' as tc_meta
-- FROM public.users u
-- JOIN auth.users a ON a.id = u.id
-- WHERE u.tc_accepted_at IS NOT NULL
--   AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';

DO $$
DECLARE
  _affected integer;
BEGIN
  UPDATE public.users
  SET tc_accepted_at = NULL
  FROM auth.users a
  WHERE public.users.id = a.id
    AND public.users.tc_accepted_at IS NOT NULL
    AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';

  GET DIAGNOSTICS _affected = ROW_COUNT;
  RAISE NOTICE '[007] Remediated % row(s) with fabricated tc_accepted_at', _affected;
END
$$;
```

### Research Insights (MVP)

**Audit trail via RAISE NOTICE:** The DO block wrapping the UPDATE uses `GET DIAGNOSTICS` to capture the affected row count and `RAISE NOTICE` to log it. This produces a server-side log entry that serves as evidence the remediation was executed. For Supabase hosted projects, these NOTICE messages appear in the Postgres logs accessible via the dashboard.

**Why a DO block instead of a bare UPDATE:** A bare `UPDATE` statement does not report its row count in the migration output. Wrapping in a DO block with `RAISE NOTICE` provides operational visibility without requiring a separate verification query. The DO block also runs as a single transaction, same as a bare statement.

**Edge case -- all rows already clean:** If the migration runs on a database where no rows match (either because the fallback path never fired, or a previous run already remediated), `_affected` will be 0 and the NOTICE will confirm "Remediated 0 row(s)". No error, no side effects.

## Post-Migration Verification Runbook

Run these queries after executing the migration to confirm correctness.

### 1. Confirm zero fabricated rows remain

```sql
-- Should return 0 rows
SELECT u.id, u.email, u.tc_accepted_at, u.created_at,
       a.raw_user_meta_data->>'tc_accepted' as tc_meta
FROM public.users u
JOIN auth.users a ON a.id = u.id
WHERE u.tc_accepted_at IS NOT NULL
  AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';
```

### 2. Confirm legitimate acceptances are preserved

```sql
-- Should return all users who genuinely accepted T&C (count should match pre-migration count)
SELECT COUNT(*)
FROM public.users u
JOIN auth.users a ON a.id = u.id
WHERE u.tc_accepted_at IS NOT NULL
  AND (a.raw_user_meta_data->>'tc_accepted') = 'true';
```

### 3. Check NOTICE output in logs

In the Supabase dashboard, navigate to Database > Logs and search for `[007] Remediated` to confirm the migration ran and logged the affected row count. This log entry serves as the audit trail for the GDPR remediation.

## References

- Issue #934: This issue (remediate fabricated rows)
- Issue #925: The original bug report (fallback INSERT unconditionally sets tc_accepted_at)
- PR #927: The fix (conditional tc_accepted_at in fallback)
- PR #898: Introduction of T&C acceptance mechanism (where the bug was introduced)
- Migration `005_add_tc_accepted_at.sql`: The trigger with correct conditional logic
- Migration `006_restrict_tc_accepted_at_update.sql`: Column-level UPDATE restriction
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-trigger-fallback-parity.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-column-level-grant-override.md`
- `apps/web-platform/app/(auth)/callback/route.ts`: The fixed callback route

### External References

- [GDPR Article 7 -- Conditions for consent](https://gdpr-info.eu/art-7-gdpr/)
- [ISMS.online -- How to Demonstrate Compliance With GDPR Article 7](https://www.isms.online/general-data-protection-regulation-gdpr/gdpr-article-7-compliance/)
- [PostgreSQL UPDATE documentation (FROM clause)](https://www.postgresql.org/docs/current/sql-update.html)
- [Supabase -- Resolving 500 Status Authentication Errors (auth schema safety)](https://supabase.com/docs/guides/troubleshooting/resolving-500-status-authentication-errors-7bU5U8)
- [Supabase -- Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations)
