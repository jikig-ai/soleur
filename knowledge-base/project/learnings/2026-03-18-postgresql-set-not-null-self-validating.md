# Learning: PostgreSQL SET NOT NULL is self-validating

## Problem

When adding NOT NULL constraints to existing columns, the plan included a PL/pgSQL DO block to pre-check for null rows before running `ALTER COLUMN SET NOT NULL`. The code-simplicity-reviewer identified this as redundant during review.

## Solution

Remove the DO block. PostgreSQL's `SET NOT NULL` already scans for null values and raises a clear error if any exist:

```
ERROR: column "iv" of relation "api_keys" contains null values
```

The simplified migration:

```sql
ALTER TABLE public.api_keys
  ALTER COLUMN iv SET NOT NULL,
  ALTER COLUMN auth_tag SET NOT NULL;
```

No defensive pre-check needed — the database engine handles validation.

## Key Insight

PostgreSQL DDL commands often have built-in safety that makes defensive wrapper code redundant. `SET NOT NULL` validates, `SET NOT NULL` on an already-constrained column is a no-op (idempotent), and `ADD COLUMN IF NOT EXISTS` handles re-runs. Trust the database engine's built-in constraints before adding application-level checks.

## Session Errors

1. `git pull` fails in bare repos — use `git fetch origin main` instead
2. Renaming an untracked file (pending→complete todo) then trying `git add` on the old name fails — only stage the new name

## Tags

category: database-issues
module: web-platform
