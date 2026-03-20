---
title: "fix: add NOT NULL constraints to iv and auth_tag columns"
type: fix
date: 2026-03-18
---

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 3 (Acceptance Criteria, Migration Approach, Test Scenarios)
**Research sources:** Context7 Supabase docs, PostgreSQL ALTER TABLE behavior, existing migration patterns in codebase

### Key Improvements
1. Clarified that PostgreSQL `SET NOT NULL` is naturally idempotent -- removed unnecessary acceptance criterion
2. Added comment explaining transactional safety (DO block + ALTER run in same Supabase migration transaction)
3. Noted `ACCESS EXCLUSIVE` lock requirement -- negligible for this small table but documented for awareness

### New Considerations Discovered
- The DO block safety check and the ALTER run atomically because Supabase migrations execute each file in a single transaction -- no TOCTOU risk
- `SET NOT NULL` on a column that already has the constraint is a silent no-op in PostgreSQL, so no `IF NOT EXISTS` guard is needed
- This is the first migration in the project using a PL/pgSQL DO block -- the pattern is valid with Supabase's `db push`

# fix: add NOT NULL constraints to iv and auth_tag columns

The `iv` and `auth_tag` columns in `api_keys` (added in migration 002) are nullable, but application code in `agent-runner.ts` assumes they are never null (`Buffer.from(data.iv, "base64")`). A null value would crash with an unhelpful `TypeError: argument must be of type string`. The TypeScript interface in `lib/types.ts` already declares both as non-optional `string`, so the schema is the only place where nullability leaks through.

Closes #681. Discovered by SpecFlow analysis during #667 fix.

## Acceptance Criteria

- [x] New migration `004_add_not_null_iv_auth_tag.sql` adds `NOT NULL` constraints to `iv` and `auth_tag` columns on `api_keys`
- [x] Migration includes a safety check: DO block asserts no null rows exist before altering (fail loudly via `RAISE EXCEPTION` rather than silently dropping data)
- [x] Existing tests pass (`bun test`)

### Research Insights

**Idempotency:** PostgreSQL's `ALTER COLUMN SET NOT NULL` is naturally idempotent -- running it on a column that already has a NOT NULL constraint is a silent no-op. No `IF NOT EXISTS` guard or conditional logic is needed. This was confirmed against PostgreSQL documentation and matches how the existing migration 002 uses `ADD COLUMN IF NOT EXISTS` (a different DDL pattern where idempotency is not automatic).

**Transactional safety:** Supabase `db push` wraps each migration file in a single transaction. The DO block safety check and the ALTER statement execute atomically -- there is no TOCTOU window where a null row could be inserted between the check and the constraint application.

## Test Scenarios

- Given no null `iv` or `auth_tag` rows exist, when migration 004 runs, then both columns become NOT NULL and the migration succeeds
- Given a null `iv` row exists (edge case -- should not happen in practice), when migration 004 runs, then the migration fails with `RAISE EXCEPTION` and the transaction rolls back (no partial constraint application)
- Given migration 004 has already been applied, when `bun test` runs the existing BYOK round-trip tests, then all tests pass (no regression)

### Research Insights

**Transaction rollback behavior:** Because Supabase migrations are transactional, if the DO block raises an exception, the entire migration rolls back cleanly. No manual cleanup is needed. This is the correct behavior -- a migration that detects data integrity issues should fail fast and visibly.

**Existing test coverage:** The `apps/web-platform/test/byok.test.ts` file tests the `encryptKey`/`decryptKey` round-trip at the Buffer level and the base64 serialization path. These tests validate the application-layer assumption that `iv` and `auth_tag` are non-null strings. The migration does not change application behavior, so no new tests are required -- the existing tests serve as regression guards.

## Context

### Affected files

- `apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql` -- new migration
- `apps/web-platform/supabase/migrations/002_add_byok_and_stripe_columns.sql` -- original migration that added the columns as nullable (read-only reference)
- `apps/web-platform/server/agent-runner.ts:48-52` -- code that assumes non-null (read-only reference)
- `apps/web-platform/lib/types.ts:30-31` -- TypeScript interface already declares non-optional `string` (no change needed)
- `apps/web-platform/app/api/keys/route.ts:34-49` -- upsert always provides `iv` and `auth_tag` (read-only reference, confirms no null rows should exist)

### Migration approach

```sql
-- apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql
--
-- Add NOT NULL constraints to iv and auth_tag columns.
-- These columns were added as nullable in migration 002 but application code
-- (agent-runner.ts, byok.ts) assumes they are always present.
-- The upsert in app/api/keys/route.ts always provides both values,
-- so no null rows should exist in production.
--
-- Locking: ALTER COLUMN SET NOT NULL acquires ACCESS EXCLUSIVE lock.
-- The api_keys table is small (one row per user per provider),
-- so lock duration is negligible.
--
-- Idempotency: SET NOT NULL on a column that already has the constraint
-- is a silent no-op in PostgreSQL. No conditional guard needed.

-- Safety check: fail if any null rows exist (should never happen,
-- but protects against silent data loss).
-- This runs in the same transaction as the ALTER below (Supabase wraps
-- each migration file in a single transaction), so no TOCTOU risk.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.api_keys
    WHERE iv IS NULL OR auth_tag IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot add NOT NULL constraints: null iv or auth_tag rows exist in api_keys';
  END IF;
END $$;

ALTER TABLE public.api_keys
  ALTER COLUMN iv SET NOT NULL,
  ALTER COLUMN auth_tag SET NOT NULL;
```

### Research Insights

**Large table alternative (not needed here):** For large tables (millions of rows), `SET NOT NULL` performs a full table scan to verify no nulls exist, which can lock the table for extended periods. The recommended pattern for large tables is to add a `CHECK (column IS NOT NULL) NOT VALID` constraint first (instant, no scan), then `VALIDATE CONSTRAINT` separately (scan with a weaker `SHARE UPDATE EXCLUSIVE` lock). The `api_keys` table has at most one row per user per provider, so the simple `SET NOT NULL` is appropriate.

**Write path confirmation:** The only code path that inserts/upserts into `api_keys` is `app/api/keys/route.ts:34-49`, which always provides `iv` (from `encryptKey().iv`) and `auth_tag` (from `encryptKey().tag`). Both are `randomBytes(12)` and `cipher.getAuthTag()` outputs respectively -- neither can produce null. This confirms the safety check is defense-in-depth, not a practical concern.

### Semver intent

`semver:patch` -- bug fix, no new features or breaking changes.

## References

- Related issue: #681
- Related PR: #667 (BYOK decryption fix that discovered this gap)
- Related brainstorm: `knowledge-base/project/brainstorms/2026-03-17-byok-decryption-fix-brainstorm.md`
- PostgreSQL ALTER TABLE docs: `SET NOT NULL` is idempotent (no-op if constraint already exists)
- Supabase migration transactionality: each migration file runs in a single transaction
