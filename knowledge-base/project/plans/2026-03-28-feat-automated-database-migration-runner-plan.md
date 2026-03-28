---
title: "feat: automated database migration runner in deploy pipeline"
type: feat
date: 2026-03-28
---

# feat: automated database migration runner in deploy pipeline

## Overview

Add an automated `migrate` job to `web-platform-release.yml` that applies unapplied SQL migrations to production Supabase before deploying the new container. This closes the systemic gap where every PR adding a migration file relied on manual SQL execution, causing repeated production outages (most recently 2026-03-28: migrations 005-009 all unapplied, 4 rounds of manual fixes).

## Problem Statement

Database migrations exist in `apps/web-platform/supabase/migrations/` (currently 001-010) but there is no mechanism to apply them to production automatically. The deploy pipeline (`web-platform-release.yml`) has two jobs: `release` (build + tag + Docker push) and `deploy` (webhook + health check). Migrations are a gap between these two stages.

**Impact:** Any future PR that adds a migration will hit the same problem -- the server starts with code expecting columns/tables that do not exist, causing runtime crashes.

## Proposed Solution

### Architecture Decision: `psql` over `supabase db push`

The issue proposed using `supabase db execute` (which does not exist -- the CLI offers `supabase db query` and `supabase db push`). After investigation:

- **`supabase db push`** requires migration filenames in `<timestamp>_<name>.sql` format (e.g., `20260328120000_initial_schema.sql`). Our files use sequential numbering (`001_initial_schema.sql`, `002_...`, etc.). Renaming 11 existing files would break git history and require `supabase migration repair` on production.
- **`psql`** is pre-installed on `ubuntu-latest` and works directly with `DATABASE_URL`. It imposes no filename format requirements.

**Decision:** Use `psql` with a lightweight shell script that:

1. Creates a `_schema_migrations` tracking table if it does not exist
2. Reads `apps/web-platform/supabase/migrations/*.sql` in sorted order
3. Skips files already recorded in the tracking table (by filename)
4. Applies unapplied files in a transaction, recording each on success
5. Exits non-zero on any failure, blocking the deploy job

### Migration Tracking Table

```sql
CREATE TABLE IF NOT EXISTS public._schema_migrations (
  filename TEXT PRIMARY KEY,
  checksum TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- **filename** -- the basename (e.g., `001_initial_schema.sql`) for deduplication
- **checksum** -- SHA-256 of the file content at apply time, for drift detection
- **applied_at** -- when the migration was applied

### Workflow Changes

Current flow: `release` -> `deploy`

New flow: `release` -> `migrate` -> `deploy`

```yaml
# New job in web-platform-release.yml
migrate:
  needs: release
  if: needs.release.outputs.version != ''
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Install Doppler CLI
      uses: dopplerhq/cli-action@v3
    - name: Run migrations
      env:
        DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}
      run: |
        doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh

deploy:
  needs: [release, migrate]  # Changed: now depends on migrate too
  ...
```

### Migration Runner Script

New file: `apps/web-platform/scripts/run-migrations.sh`

This script:

1. Connects to the database using `DATABASE_URL` from Doppler
2. Creates the `_schema_migrations` table if it does not exist
3. Lists all `.sql` files in the migrations directory, sorted
4. For each file, checks if already applied (by filename in tracking table)
5. If unapplied: computes SHA-256 checksum, runs in a transaction, records success
6. If any migration fails: exits 1 immediately (no partial state)

Key properties:

- **Idempotent** -- re-running skips already-applied migrations
- **Ordered** -- files are sorted lexicographically (001 < 002 < 010)
- **Atomic per-migration** -- each file runs in its own transaction
- **Fail-fast** -- first failure aborts, preventing deploy of incompatible code

### Secrets Configuration

`DATABASE_URL` must be added to Doppler `prd` config. The value is the PostgreSQL connection string from Supabase Dashboard > Settings > Database > Connection string (URI format).

Additionally, `DOPPLER_TOKEN_PRD` must exist as a GitHub Actions secret (service token scoped to the `prd` config). If it already exists for other workflows, reuse it.

### Duplicate Migration Prefix

During research, a naming collision was discovered: two files share the `007_` prefix:

- `007_remediate_fabricated_tc_accepted_at.sql`
- `007_remove_tc_accepted_metadata_trust.sql`

Both files exist and both need to run. Lexicographic sort handles this correctly (`007_re...` before `007_remove...`), but this should be cleaned up in a separate issue to prevent confusion. The migration runner handles this correctly because it tracks by full filename, not prefix.

## Technical Considerations

### Security

- `DATABASE_URL` contains credentials and is stored only in Doppler (never in workflow YAML or repo)
- The script uses Doppler CLI injection (`doppler run`) so the secret is never written to disk or logs
- GitHub Actions logs mask secrets injected via `${{ secrets.* }}`

### Failure Modes

| Scenario | Behavior |
|----------|----------|
| Migration SQL error | Transaction rolls back, script exits 1, deploy blocked |
| Network timeout to Supabase | `psql` fails, script exits 1, deploy blocked |
| Tracking table already exists | `CREATE TABLE IF NOT EXISTS` is a no-op |
| Migration already applied | Skipped (filename match in tracking table) |
| New migration added in PR | Applied before deploy, server starts with correct schema |
| Doppler token missing | `doppler run` fails, script exits 1, deploy blocked |

### Rollback Safety

Migration failures abort before the deploy job runs. The old container continues running with the old schema -- both remain consistent. There is no automated rollback of applied migrations (this is a deliberate simplification for MVP -- migrations should be forward-only).

### Bootstrapping

The first run of the migration runner will find no `_schema_migrations` table. It will create it, then attempt to apply all 11 migration files. Migrations 001-010 have already been applied manually to production, so they need to be pre-seeded in the tracking table.

**Bootstrap approach:** Include a one-time seed step in `run-migrations.sh` that checks if `_schema_migrations` is empty AND the target tables already exist, then inserts records for all existing migrations without re-running them. This avoids "table already exists" errors on first automated run.

Alternatively, create a bootstrap migration (`000_seed_migration_history.sql`) that is the first file processed and populates the tracking table for 001-010.

**Recommended:** The simpler approach is to have the runner script detect "first run" (empty tracking table) and seed it by scanning for already-applied objects. This keeps the migration directory clean.

## Acceptance Criteria

- [ ] `_schema_migrations` table is created automatically on first run
- [ ] Unapplied migrations are applied in filename-sorted order before deploy
- [ ] Already-applied migrations are skipped (idempotent)
- [ ] Migration failure blocks the deploy job (exit code propagation)
- [ ] `DATABASE_URL` is injected from Doppler, never hardcoded
- [ ] Existing production schema (001-010) is bootstrapped without re-execution
- [ ] Script follows project shell conventions (`set -euo pipefail`, `#!/usr/bin/env bash`)
- [ ] `deploy` job depends on `migrate` job succeeding
- [ ] Duplicate `007_` prefix files both execute in correct order

## Test Scenarios

- Given a clean `_schema_migrations` table and existing production tables, when the runner executes for the first time, then all 11 migrations are recorded as applied without re-executing SQL that would fail on existing objects
- Given migrations 001-010 are recorded as applied, when a PR adds `011_new_feature.sql`, then only `011_new_feature.sql` is executed
- Given a migration with a SQL syntax error, when the runner processes it, then the transaction rolls back, the migration is NOT recorded, and the script exits 1
- Given `DATABASE_URL` is not set in Doppler, when the runner executes, then it fails immediately with a clear error message
- Given all migrations are already applied, when the runner executes, then it completes successfully in under 5 seconds with no SQL executed
- Given the `migrate` job fails, when CI evaluates the `deploy` job, then `deploy` is skipped

### Integration Verification

- **CI verify:** After merging, trigger `gh workflow run web-platform-release.yml`, poll until complete, verify the `migrate` job appears and succeeds
- **DB verify:** `doppler run -c prd -- psql "$DATABASE_URL" -c "SELECT * FROM public._schema_migrations ORDER BY filename"` shows all 11 migrations recorded
- **Idempotency verify:** Re-run the workflow; `migrate` job succeeds with "0 migrations applied"

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change affecting the CI/CD pipeline only. No user-facing changes, no legal/marketing/product impact.

## Dependencies and Risks

### Dependencies

- `DATABASE_URL` must be added to Doppler `prd` config (automatable via `doppler secrets set`)
- `DOPPLER_TOKEN_PRD` must exist as a GitHub Actions secret (may already exist)

### Risks

| Risk | Mitigation |
|------|-----------|
| Bootstrap seeds wrong state | Detect existing objects (tables, columns) before seeding |
| Migration naming collision (007) | Track by full filename, not prefix; file cleanup issue separately |
| `psql` not available on runner | Pre-installed on `ubuntu-latest`; verified in GitHub docs |
| Long-running migration blocks deploy | Migrations are small DDL; add timeout to `psql` commands |

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `apps/web-platform/scripts/run-migrations.sh` | Create | Migration runner shell script |
| `.github/workflows/web-platform-release.yml` | Modify | Add `migrate` job between `release` and `deploy` |

## References

- Related issue: #1239
- Related issue: #1238 (post-merge CD resilience)
- Deploy workflow: `.github/workflows/web-platform-release.yml`
- Migration directory: `apps/web-platform/supabase/migrations/`
- Supabase CLI docs: `supabase db push` requires timestamp filenames (incompatible with current naming)
- Constitution: shell scripts must use `#!/usr/bin/env bash` and `set -euo pipefail`
