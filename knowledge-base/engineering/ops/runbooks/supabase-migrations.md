---
category: infrastructure
tags: [supabase, migrations, database, deploy, verification]
date: 2026-04-17
---

# Supabase Migrations: Pre-deploy, Apply, Verify, Rollback

Use this runbook any time a PR adds or modifies a file under
`apps/web-platform/supabase/migrations/`. A committed-but-unapplied
migration is a silent deployment failure — the code path that depends on
the new schema throws at runtime, not at build or deploy time.

The enforcing rule is AGENTS.md `wg-when-a-pr-includes-database-migrations`.

## Pre-deploy Checklist

- [ ] Migration filename is the next integer in sequence (`024_…`, `025_…`).
- [ ] Starts with a header comment describing intent, constraints, and any
      intentional deferrals (e.g., "no backfill — see plan section 2.1").
- [ ] DDL uses idempotent forms (`ADD COLUMN IF NOT EXISTS`,
      `CREATE INDEX IF NOT EXISTS`, `CREATE UNIQUE INDEX IF NOT EXISTS …
      WHERE …`). The Supabase runner is not transactional per-file for
      DDL; idempotency lets a mid-file retry succeed.
- [ ] If the migration adds a UNIQUE constraint or index, verify the
      target data has no pre-existing duplicates (see Baseline Capture).
- [ ] Rollback SQL is drafted (see Rollback Template) and lives in the
      PR body OR is obvious from the `DROP … IF EXISTS` inverse of the
      applied DDL.

## Baseline Capture (pre-apply SQL)

Run these against the production DB before applying. Keep the output in
the PR body so post-deploy deltas are diffable.

```sql
-- Baseline counts — compare before/after to detect unintended row moves.
SELECT COUNT(*) AS total,
       COUNT(DISTINCT user_id) AS users
  FROM public.<table>;

-- Detect any pre-existing dup keys that would block a UNIQUE index.
-- Replace <key_cols> with the column tuple the index spans.
SELECT <key_cols>, COUNT(*)
  FROM public.<table>
 WHERE <key_cols> IS NOT NULL
 GROUP BY <key_cols>
HAVING COUNT(*) > 1;

-- Confirm the column or index does NOT already exist (catches double-apply).
SELECT column_name
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name   = '<table>'
   AND column_name  = '<column>';

SELECT indexname, indexdef
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND tablename  = '<table>'
   AND indexname LIKE '%<pattern>%';
```

## Apply

### CI path (default)

Migrations are applied by the deploy workflow via the Supabase Management
API. The migration file's presence on `main` triggers application during
the next release run; no manual step is required.

### Manual path (when CI is unavailable)

```bash
# Fetch the access token from Doppler prd config.
export SUPABASE_ACCESS_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN \
  -p soleur -c prd --plain)
export SUPABASE_PROJECT_REF=$(doppler secrets get SUPABASE_PROJECT_REF \
  -p soleur -c prd --plain)

cd apps/web-platform
npx supabase db push \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --include-all
```

`--include-all` sends every un-applied migration since the last pushed
version; `db push` is idempotent as long as the migration file itself
uses `IF NOT EXISTS` guards.

## Verify

Two complementary checks — run both. The REST probe is cheap and covers
most failure modes; the Management API confirms column nullability,
index predicates, and CHECK constraints.

### 1. REST API probe (fastest)

A 400 response with PostgREST code `42703` is the signature of an
un-applied migration adding a new column.

```bash
export SUPABASE_URL=$(doppler secrets get SUPABASE_URL -p soleur -c prd --plain)
export SUPABASE_ANON_KEY=$(doppler secrets get SUPABASE_ANON_KEY -p soleur -c prd --plain)

curl -sS -o /dev/null -w "%{http_code}\n" \
  "$SUPABASE_URL/rest/v1/<table>?select=<new_column>&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY"
# 200 → column exists (migration applied).
# 400 → column missing (migration NOT applied).
```

If 400, read the body to confirm:

```bash
curl -sS \
  "$SUPABASE_URL/rest/v1/<table>?select=<new_column>&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" | jq .
# { "code": "42703", "message": "column <table>.<col> does not exist", ... }
```

This is the exact failure pattern captured in
`knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`.

### 2. Management API (detailed)

Use when the probe passes but you need to confirm constraints or index
predicates.

```bash
export SUPABASE_ACCESS_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
export SUPABASE_PROJECT_REF=$(doppler secrets get SUPABASE_PROJECT_REF -p soleur -c prd --plain)

# Confirm column definition (nullability, data type, default).
curl -sS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT column_name, is_nullable, data_type, column_default FROM information_schema.columns WHERE table_schema = '\''public'\'' AND table_name = '\''<table>'\'';"}'

# Confirm index definition (including the partial predicate).
curl -sS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = '\''public'\'' AND tablename = '\''<table>'\'';"}'
```

## Rollback

Rollbacks are destructive. Before running any `DROP COLUMN` or `DROP
INDEX`, capture the affected rows for recovery:

```bash
npx supabase db dump \
  --project-ref "$SUPABASE_PROJECT_REF" \
  --data-only \
  --schema public \
  --table <table> \
  > backup-pre-rollback-$(date +%Y%m%d-%H%M%S).sql
```

### Rollback template

Invert the applied DDL. For migration 024 as a worked example:

```sql
DROP INDEX IF EXISTS public.conversations_context_path_user_uniq;
DROP INDEX IF EXISTS public.idx_conversations_context_path;
ALTER TABLE public.conversations DROP COLUMN IF EXISTS context_path;
```

Run via the Management API:

```bash
curl -sS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "DROP INDEX IF EXISTS public.<index_name>; ALTER TABLE public.<table> DROP COLUMN IF EXISTS <column>;"}'
```

Then re-run the REST probe from Verify — a 400 with `42703` now indicates
the rollback succeeded.

## Post-merge Verification

Per `wg-when-a-pr-includes-database-migrations`, a PR is not done until
the migration is confirmed applied to production:

1. Watch the deploy workflow for completion on `main`.
2. Run the REST API probe (above) against production.
3. If 200, close the issue referencing the migration with a short note
   pointing at this runbook and the SHA that applied.
4. If 400, the migration did not apply — open an incident issue and
   follow the manual apply path.

## Cross-references

- `AGENTS.md` rule `wg-when-a-pr-includes-database-migrations`.
- `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`
- Worked example: PR #2347 (migration 024) — the KB-chat context_path
  rollout exercised the full apply/verify flow against production.
