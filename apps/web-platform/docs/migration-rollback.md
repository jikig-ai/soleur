# Migration Rollback Procedure

This document covers rollback procedures for the Supabase/PostgreSQL migration
pipeline in `apps/web-platform/`.

## Forward-Only Principle

Production uses a **forward-only** migration strategy: the release migration
runner skips down files. Shared-dev reconciliation can execute eligible paired
downs under its separate ownership and safety checks.

**Why forward-only works:**

- PostgreSQL supports transactional DDL. The migration runner uses
  `--single-transaction`, so a failed migration rolls back automatically and
  leaves no partial state.

## Codex migration 145: retain the schema when reverting code

`145_codex_auth_mode_rebind.sql` is forward-only. Its historical paired down file
is **unsupported**: it drops both `workspace_engine_settings.codex_auth_mode`
(the owner's separate Codex mode choice) and `agent_engine_attempts.accepted_at`
(the evidence that an admitted turn may finish after a mode switch). Reapplying
the forward file cannot reconstruct those values reliably. Do not execute that
down file directly, remove its ledger row, or use an earlier destructive down
file to bypass this restriction.

Supported recovery retains the database schema, settings, attempt rows and
migration ledger. Keep `codex-engine` disabled and revert the application change
through the existing reviewed release/deploy path to a build compatible with
the retained schema and generation fencing. If no such build is verified,
keep execution disabled and ship a forward correction. The production migrate
job calls `scripts/run-migrations.sh`, which skips down files; the deployment
rollback does not reverse database migrations. Shared-dev reconciliation also
refuses migration 145, including with `--allow-later-rows`.

The reconciliation restriction also protects the entire retained ledger:
migration 138's down removes `workspace_engine_settings`, and migration 143's
down removes `agent_engine_attempts`. Either would erase migration 145's fields
without selecting 145 itself for discard. While 145 remains applied, the writer
therefore refuses **every eligible paired down**, regardless of ledger age,
migration ownership, advisory classification or `--allow-later-rows`. This
conservative restriction also blocks non-destructive and unrelated downs:
the advisory scanner strips executable dollar-quoted bodies and cannot prove
that a down preserves the protected fields. Unrelated ledger-only cleanup
remains available because it executes no down body; 145's own ledger row always
remains protected. Use forward corrections instead of paired-down shared-dev
reconciliation while the protected schema remains. Direct ancestor downs are
equally unsupported.

The read-only refusal classification is available without database credentials:

```bash
bash apps/web-platform/scripts/dev-ledger-reconcile.sh --scan-down \
  apps/web-platform/supabase/migrations/145_codex_auth_mode_rebind.down.sql
```

Its output includes `codex-forward-only`. This is an enforced refusal in the
reconciliation writer, not evidence that a snapshot or restoration has run.
Schema downgrade remains blocked until a separately reviewed implementation
captures **both** fields with their workspace/attempt identities under the same
bounded write exclusion as the downgrade, proves durable recoverability, and
restores the exact values before admitting any execution. Such a recovery must
preserve tenant isolation, erasure, retention and admission semantics; this PR
does not create a new backup store or claim snapshot restoration exists.

First production apply is also guarded in the runner's migration transaction.
Before executing migration 145, the runner acquires a bounded exclusive lock on
`workspace_engine_settings` and refuses unsupported Codex `default_auth_mode`
values before the unchanged body or its ledger insert runs. The lock stays held
through the constrained backfill. A separate aggregate count, even zero, is
only a point-in-time observation. A refusal leaves the migration unapplied;
obtain the affected owner's explicit supported mode choice before retrying,
without silently changing credentials or normalizing the value to Managed.

Release verification can use the following content-free aggregates through the
existing authorized database probe. They have not been executed by this PR.
The pre-apply observation is diagnostic; it cannot replace the transactional
guard. Post-apply requires zero invalid modes, one migration ledger row with
the deployed immutable blob SHA, and the admission-evidence column present.

```sql
-- Pre-apply: expected 0 unsupported modes.
SELECT count(*) AS unsupported_codex_modes
FROM public.workspace_engine_settings
WHERE default_engine_id = 'codex'
  AND (default_auth_mode IS NULL
       OR default_auth_mode NOT IN ('managed', 'api-key'));

-- Post-apply: expected 0 invalid modes.
SELECT count(*) AS invalid_codex_modes
FROM public.workspace_engine_settings
WHERE codex_auth_mode IS NULL
   OR codex_auth_mode NOT IN ('managed', 'api-key');

-- Post-apply: expected 1; also compare content_sha with the release blob SHA.
SELECT count(*) AS applied_rows
FROM public._schema_migrations
WHERE filename = '145_codex_auth_mode_rebind.sql';

-- Post-apply: expected 1 admission-evidence column.
SELECT count(*) AS admission_columns
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'agent_engine_attempts'
  AND column_name = 'accepted_at';
```

## Manual Rollback Procedure

When a successfully applied migration must be reversed:

This generic procedure does not authorize the unsupported Codex migration 145
downgrade described above.

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
2. **Push a fix** that adds a corrective migration. The next CI run picks
   up the fix. Removing or editing the broken file in place is what the
   migration-immutability gate (`detect-changes`) exists to stop — see the
   break-glass note in "Rollback Procedure" above for the only exception.
3. **Alternatively**, use `workflow_dispatch` with `skip_deploy: true` to
   release without deploying while you prepare the fix.

The deploy job depends on the migrate job succeeding
(`needs.migrate.result == 'success'`), so a failing migration automatically
blocks deployment.

## Schema-Cache Reload (PGRST205 after apply)

If supabase-js calls return `PGRST205: Could not find the table '…' in the
schema cache` shortly after a migration apply, PostgREST's schema cache hasn't
re-read yet. Causes: a direct-pg apply path (bypassing `run-migrations.sh`),
or a transient failure in the post-apply Management-API NOTIFY.

```bash
doppler run -p soleur -c prd -- bash apps/web-platform/scripts/postgrest-reload-schema.sh
bash apps/web-platform/scripts/postgrest-reload-schema.sh --help   # no secrets needed
```

The script POSTs `NOTIFY pgrst, 'reload schema'` to the Supabase Management
API; PostgREST picks up the change in ~1 s. Requires `SUPABASE_ACCESS_TOKEN`
(Doppler `prd` root, inherited by every `prd_*` branch; for a dev target read
it from `prd_terraform` — run the script with `--help` for the exact
one-liner; no `dev` config carries it by design). Without a token, PostgREST's
natural ~10-minute schema poll handles the reload on its own. A token the API
*rejects* is different: since #8028 the script exits 2 even under
`--best-effort`, and `run-migrations.sh` runs the refresh on every run and
propagates that exit — so re-running a red migration job after rotating the
token reloads the cache without re-applying anything. Context: learning
`2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md` §1.

## Prevention Patterns

- Use `IF EXISTS` / `IF NOT EXISTS` guards on all DDL statements.
- Prefer additive changes (add column, add table) over destructive ones.
