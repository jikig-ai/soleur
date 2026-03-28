---
module: System
date: 2026-03-28
problem_type: best_practice
component: development_workflow
symptoms:
  - "Database migrations not applied automatically to production"
  - "4 rounds of manual SQL execution to fix missing migrations"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [psql, migration, ci, supabase, github-actions, doppler]
---

# Learning: psql migration runner CI patterns

## Problem

Database migrations existed in `apps/web-platform/supabase/migrations/` but were never applied automatically to production. Every PR that added a migration relied on someone manually running SQL against Supabase, causing repeated outages when migrations were forgotten.

## Solution

Created a shell-based migration runner (`run-migrations.sh`) invoked by a new `migrate` job in the CI workflow, positioned between `release` and `deploy`.

### Key implementation patterns

**1. psql variable binding for shell scripts:**

```bash
# WRONG — SQL injection risk from filename interpolation
run_sql "SELECT count(*) FROM t WHERE filename = '$filename';"

# RIGHT — psql -v binding with :'varname' syntax
psql "$DATABASE_URL" --no-psqlrc --set ON_ERROR_STOP=1 -tAq \
  -v fname="$filename" \
  -c "SELECT count(*) FROM t WHERE filename = :'fname';"
```

The `:'varname'` syntax produces a properly quoted SQL literal. This is the idiomatic way to parameterize queries in psql from shell scripts.

**2. Atomic migration apply + tracking record:**

```bash
# WRONG — two separate psql invocations, non-atomic
psql ... -f "$migration_file"
psql ... -c "INSERT INTO _schema_migrations ..."

# RIGHT — pipe migration + INSERT into single --single-transaction
{
  cat "$migration_file"
  printf "\nINSERT INTO public._schema_migrations (filename) VALUES (:'fname');\n"
} | psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1 \
    -v fname="$filename"
```

If the migration and tracking INSERT are separate invocations, a failure between them leaves the migration applied but unrecorded — causing re-application on the next run.

**3. GitHub Actions job dependency with `always()` pattern:**

```yaml
deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.version != '' &&
    (needs.migrate.result == 'success' || needs.migrate.result == 'skipped') &&
    ...
```

Without `always()`, a skipped `migrate` job silently skips `deploy` too (GitHub Actions treats skipped and failed identically for `needs`). The explicit `success || skipped` pattern is safer than `!= 'failure'` because it also rejects `cancelled`.

**4. Critical psql flags for CI:**

- `--no-psqlrc` — prevents user `.psqlrc` from interfering
- `--single-transaction` — wraps file in BEGIN/COMMIT, ROLLBACK on error
- `--set ON_ERROR_STOP=1` — without this, psql continues past errors within a file

## Key Insight

When writing shell scripts that execute SQL, always use psql's `-v` variable binding instead of string interpolation, and always combine related SQL operations into a single `--single-transaction` invocation. Two separate psql calls are never atomic, even if each is individually transactional.

## Session Errors

1. **Edit tool blocked by security_reminder_hook on workflow file** — Recovery: re-attempted the edit (hook warns but doesn't block). **Prevention:** Expected behavior — the hook is a security reminder for GH Actions files, not a blocker.

2. **psql not available locally** — Recovery: skipped local integration testing, relied on syntax checks and CI verification. **Prevention:** This is expected — `psql` is pre-installed on `ubuntu-latest` CI runners, not dev machines. Add `command -v psql` guard at script start (done).

3. **`npx markdownlint` failed, needed `bunx markdownlint-cli`** — Recovery: switched to `bunx markdownlint-cli`. **Prevention:** This is a known pattern in this repo (bun, not npm).

4. **`shellcheck` not available** — Recovery: used `bash -n` for syntax checking only. **Prevention:** Install shellcheck to `~/.local/bin` if needed, or rely on CI.

## Tags

category: implementation-patterns
module: System
