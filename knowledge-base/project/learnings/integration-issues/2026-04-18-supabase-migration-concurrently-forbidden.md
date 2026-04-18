---
module: apps/web-platform/supabase/migrations
date: 2026-04-18
problem_type: integration_issue
component: supabase_migrations
symptoms:
  - "Migration deploy fails with SQLSTATE 25001 'CREATE INDEX CONCURRENTLY cannot run inside a transaction block'"
  - "Every seed or write path that assumed the index fails with 42P10 post-merge"
  - "Plan prescribes CONCURRENTLY citing general Postgres docs without checking sibling migrations"
root_cause: migration_runner_transaction_vs_concurrently
severity: high
tags: [supabase, migrations, ddl, indexes, deployment]
synced_to: [plan]
---

# Supabase migrations cannot use CREATE INDEX CONCURRENTLY

## Problem

Supabase's migration runner wraps each migration file in a single transaction.
Postgres rejects `CREATE INDEX CONCURRENTLY` inside any transaction block with
`ERROR: CREATE INDEX CONCURRENTLY cannot run inside a transaction block`
(SQLSTATE `25001`). The error only surfaces at deploy time — `terraform fmt`,
`tsc --noEmit`, `bun test`, and local SQL validation all pass.

**Real incident (PR #2579):** The plan prescribed
`CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS` for migration 028 to avoid
blocking writes on the `conversations` table. The deepen-pass added a
Postgres/PostgREST verification for the `on_conflict` behavior but did NOT
check adjacent migrations for runner-specific constraints. Review
(data-integrity-guardian) caught the bug by reading siblings:

- `025_context_path_archived_predicate.sql`: "CONCURRENTLY is not used here
  because Supabase's migration runner..."
- `027_mtd_cost_aggregate.sql`: "Supabase migrations run in a transaction, so
  CONCURRENTLY is not used."

Both prior migrations documented the constraint inline. Had either been read,
the plan would have dropped CONCURRENTLY from the start.

## Solution

Drop `CONCURRENTLY`. Use plain `CREATE ... INDEX IF NOT EXISTS` with a header
comment explaining the choice. For tables large enough that a blocking build
is actually a concern, apply the index manually via the SQL editor outside
the migration runner (not common at our scale).

```sql
-- CONCURRENTLY is not used here because Supabase's migration runner wraps
-- each migration in a transaction, and CREATE INDEX CONCURRENTLY cannot
-- run inside a transaction block (SQLSTATE 25001). Matches the pattern
-- documented in 025_context_path_archived_predicate.sql and
-- 027_mtd_cost_aggregate.sql.
create unique index if not exists
  uniq_conversations_user_id_session_id
  on public.conversations (user_id, session_id)
  where session_id is not null;
```

For baseline-dup-check safety (runbook
`knowledge-base/engineering/ops/runbooks/supabase-migrations.md`), the
blocking index is actually preferable: it fails loudly on dup rows, whereas
`CONCURRENTLY` + `IF NOT EXISTS` would leave you with a partial half-built
`INVALID` index that Postgres ignores for uniqueness enforcement.

## Key Insight

**Before prescribing DDL in a migration, `ls` the sibling migrations and grep
for the same DDL construct.** If others avoided a construct and left a
comment, the reason usually applies to your migration too. Postgres docs are
correct but incomplete — they describe native Postgres, not the wrapper your
runner imposes.

## Prevention

- **Plan gate:** when a plan includes a migration, the deepen-pass must
  include `rg -l "concurrently|CONCURRENTLY" apps/web-platform/supabase/migrations/`
  and read at least the two most recent migrations for runner-specific notes.
- **Review gate:** data-integrity-guardian should check every new migration's
  DDL against sibling-migration comments — this case was caught on review
  but cost a full plan-review-fix cycle.
- **Runner-level fix (future):** wrap Supabase's migration apply in a
  `set autocommit on` hook for migrations whose first comment line contains
  `NON-TRANSACTIONAL` — out of scope for a one-off learning but worth
  tracking in an infra ticket if the pattern repeats.

## Session Errors

- **Plan prescribed CREATE INDEX CONCURRENTLY verbatim** — Recovery: dropped
  CONCURRENTLY after review caught sibling-migration comments in 025/027.
  Prevention: plan skill's deepen-pass must grep adjacent migrations for
  documented DDL constraints, not rely on general Postgres docs alone.

## Related

- `apps/web-platform/supabase/migrations/025_context_path_archived_predicate.sql`
- `apps/web-platform/supabase/migrations/027_mtd_cost_aggregate.sql`
- `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`
- PR #2579 (incident + fix)
