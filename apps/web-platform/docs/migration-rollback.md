# Migration Rollback Procedure

This document covers rollback procedures for the Supabase/PostgreSQL migration
pipeline in `apps/web-platform/`.

## Forward-Only Principle

This project uses a **forward-only** migration strategy. There are no automated
down-migrations or rollback commands.

**Why forward-only works:**

- PostgreSQL supports transactional DDL. The migration runner uses
  `--single-transaction`, so a failed migration rolls back automatically and
  leaves no partial state.

## Manual Rollback Procedure

When a successfully applied migration must be reversed:

### 1. Identify the migration to reverse

```bash
# List applied migrations
doppler run -c prd -- bash -c 'psql "$DATABASE_URL" -c \
  "SELECT filename, applied_at FROM public._schema_migrations ORDER BY applied_at DESC;"'
```

### 2. Write and test the reversal SQL

Write a reversal script that undoes the migration's changes (adapt for
columns, constraints, etc.):

```sql
DROP TABLE IF EXISTS public.my_table;
```

Test the reversal SQL against a development database first.

### 3. Apply the reversal

```bash
doppler run -c prd -- bash -c 'psql "$DATABASE_URL" --single-transaction \
  --set ON_ERROR_STOP=1 -f reversal.sql'
```

### 4. Remove the migration record

After the reversal succeeds, remove the entry from the tracking table so
the migration runner does not consider it applied:

```bash
doppler run -c prd -- bash -c 'psql "$DATABASE_URL" -c \
  "DELETE FROM public._schema_migrations WHERE filename = '"'"'<migration_filename>.sql'"'"';"'
```

### 5. Commit a corrective migration

Create a new forward migration that applies the correct schema change.
This keeps the migration history linear and auditable.

## Emergency Deploy Blocking

If a bad migration reaches production and you need to stop further deploys
while fixing it:

1. **Cancel the running workflow** in GitHub Actions to prevent the deploy job
   from executing.
2. **Push a fix** that either removes the broken migration file or adds a
   corrective migration. The next CI run picks up the fix.
3. **Alternatively**, use `workflow_dispatch` with `skip_deploy: true` to
   release without deploying while you prepare the fix.

The deploy job depends on the migrate job succeeding
(`needs.migrate.result == 'success'`), so a failing migration automatically
blocks deployment.

## Prevention Patterns

- Use `IF EXISTS` / `IF NOT EXISTS` guards on all DDL statements.
- Prefer additive changes (add column, add table) over destructive ones.
