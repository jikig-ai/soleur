---
title: "fix: add NOT NULL constraints to iv and auth_tag columns"
type: fix
date: 2026-03-18
---

# fix: add NOT NULL constraints to iv and auth_tag columns

The `iv` and `auth_tag` columns in `api_keys` (added in migration 002) are nullable, but application code in `agent-runner.ts` assumes they are never null (`Buffer.from(data.iv, "base64")`). A null value would crash with an unhelpful `TypeError: argument must be of type string`. The TypeScript interface in `lib/types.ts` already declares both as non-optional `string`, so the schema is the only place where nullability leaks through.

Closes #681. Discovered by SpecFlow analysis during #667 fix.

## Acceptance Criteria

- [ ] New migration `004_add_not_null_iv_auth_tag.sql` adds `NOT NULL` constraints to `iv` and `auth_tag` columns on `api_keys`
- [ ] Migration includes a safety check: assert no null rows exist before altering (fail loudly rather than silently dropping data)
- [ ] Existing tests pass (`bun test`)
- [ ] Migration is idempotent-safe (running on a database where the constraint already exists does not error)

## Test Scenarios

- Given no null `iv` or `auth_tag` rows exist, when migration 004 runs, then both columns become NOT NULL and the migration succeeds
- Given a null `iv` row exists (edge case -- should not happen in practice), when migration 004 runs, then the migration fails with a clear error rather than silently dropping the row
- Given migration 004 has already been applied, when `bun test` runs the existing BYOK round-trip tests, then all tests pass (no regression)

## Context

### Affected files

- `apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql` -- new migration
- `apps/web-platform/supabase/migrations/002_add_byok_and_stripe_columns.sql` -- original migration that added the columns as nullable (read-only reference)
- `apps/web-platform/server/agent-runner.ts:48-52` -- code that assumes non-null (read-only reference)
- `apps/web-platform/lib/types.ts:30-31` -- TypeScript interface already declares non-optional `string` (no change needed)

### Migration approach

```sql
-- apps/web-platform/supabase/migrations/004_add_not_null_iv_auth_tag.sql

-- Safety check: fail if any null rows exist (should never happen,
-- but protects against silent data loss)
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

### Semver intent

`semver:patch` -- bug fix, no new features or breaking changes.

## References

- Related issue: #681
- Related PR: #667 (BYOK decryption fix that discovered this gap)
- Related brainstorm: `knowledge-base/brainstorms/2026-03-17-byok-decryption-fix-brainstorm.md`
