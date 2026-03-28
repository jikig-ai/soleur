---
title: "feat: automated database migration runner in deploy pipeline"
type: feat
date: 2026-03-28
---

# feat: automated database migration runner in deploy pipeline

## Enhancement Summary

**Deepened on:** 2026-03-28
**Sections enhanced:** 5 (Workflow, Script, Bootstrapping, Failure Modes, Risks)
**Research sources:** GitHub Actions docs, PostgreSQL docs, project learnings, Doppler CLI action repo

### Key Improvements

1. Resolved pinned SHAs for all GitHub Actions (checkout, Doppler CLI)
2. Added `--single-transaction` and `ON_ERROR_STOP` psql flags from PostgreSQL best practices
3. Identified critical GitHub Actions gotcha: skipped `migrate` job silently skips `deploy` -- requires `if: always() && ...` pattern on `deploy`
4. Applied bash operator precedence learning to script design (explicit `{ ...; }` grouping)
5. Added `--set ON_ERROR_STOP=1` to prevent silent partial execution within migration files

### New Considerations Discovered

- GitHub Actions treats skipped and failed jobs identically for `needs` -- deploy will skip if migrate skips, requiring an explicit `if` condition on deploy that checks `needs.migrate.result != 'failure'`
- `psql -f` without `ON_ERROR_STOP` continues executing after errors within a file, potentially leaving partial state even inside a transaction block
- Doppler `DOPPLER_TOKEN` cannot be validated in job-level `if` conditions (secrets masking) -- must check inside the step

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
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- **filename** -- the basename (e.g., `001_initial_schema.sql`) for deduplication
- **applied_at** -- when the migration was applied

*[Updated 2026-03-28: checksum column removed per review -- YAGNI, no consumer reads it. Add later if drift detection becomes a real need.]*

### Workflow Changes

Current flow: `release` -> `deploy`

New flow: `release` -> `migrate` -> `deploy`

```yaml
# New job in web-platform-release.yml
migrate:
  needs: release
  if: needs.release.outputs.version != '' && (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
  runs-on: ubuntu-latest
  concurrency:
    group: migrate-web-platform
    cancel-in-progress: false
  steps:
    - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    - name: Install Doppler CLI
      uses: dopplerhq/cli-action@014df23b1329b615816a38eb5f473bb9000700b1 # v3
    - name: Run migrations
      env:
        DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}
      run: |
        doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh

deploy:
  needs: [release, migrate]
  if: >-
    always() &&
    needs.release.outputs.version != '' &&
    needs.migrate.result != 'failure' &&
    (github.event_name != 'workflow_dispatch' || !inputs.skip_deploy)
  ...
```

*[Updated 2026-03-28: pinned action SHAs, added concurrency group, added `skip_deploy` guard to `if` condition per review.]*

### Research Insights: GitHub Actions Job Dependencies

**Critical gotcha -- skipped jobs propagate as skips, not successes:**

When `migrate` is skipped (e.g., `needs.release.outputs.version` is empty), GitHub Actions treats this as a skip, not a success. Without intervention, `deploy` would also be skipped even though the existing behavior (deploy without migrate) should still work for no-op releases. The `if: always() && ... && needs.migrate.result != 'failure'` pattern ensures:

- If `migrate` **succeeds**: deploy runs (normal path)
- If `migrate` **fails**: deploy is blocked (migration error -- do not deploy)
- If `migrate` is **skipped**: deploy still runs based on its own conditions (preserves existing behavior for non-release pushes)

This is a [documented GitHub Actions limitation](https://github.com/actions/runner/issues/491) where `success()` returns false if dependent jobs are skipped.

**Secret validation in `if` conditions:**

Per project learning ([CI for notifications and infrastructure setup](../../knowledge-base/project/learnings/implementation-patterns/2026-02-12-ci-for-notifications-and-infrastructure-setup.md)): `secrets.*` cannot be evaluated in job-level `if` conditions -- they always evaluate false due to masking. The `DOPPLER_TOKEN` must be validated inside the step script, not in the job `if`.

### Migration Runner Script

New file: `apps/web-platform/scripts/run-migrations.sh`

This script:

1. Resolves its own directory via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and references `"$SCRIPT_DIR/../supabase/migrations/"` -- no CWD dependency
2. Connects to the database using `DATABASE_URL` from Doppler
3. Creates the `_schema_migrations` table if it does not exist
4. Bootstraps: if tracking table is empty, seeds records for all known pre-existing migrations (hardcoded list of 001-010 filenames) without re-executing them
5. Lists all `.sql` files in the migrations directory, sorted
6. For each file, checks if already applied (by filename in tracking table)
7. If unapplied: runs in a transaction, records success
8. If any migration fails: exits 1 immediately (no partial state)

Key properties:

- **Idempotent** -- re-running skips already-applied migrations
- **Ordered** -- files are sorted lexicographically (001 < 002 < 010)
- **Atomic per-migration** -- each file runs in its own transaction (PostgreSQL supports transactional DDL, unlike MySQL, so `CREATE TABLE` / `ALTER TABLE` within a transaction roll back cleanly on failure)
- **Fail-fast** -- first failure aborts, preventing deploy of incompatible code
- **Path-safe** -- uses `SCRIPT_DIR` for relative path resolution, not CWD

### Research Insights: psql Best Practices for CI

**Critical flags for each `psql` invocation:**

```bash
psql "$DATABASE_URL" \
  --no-psqlrc \
  --single-transaction \
  --set ON_ERROR_STOP=1 \
  -f "$migration_file"
```

- `--no-psqlrc` -- prevents user `.psqlrc` from interfering (CI runner may have unexpected defaults)
- `--single-transaction` -- wraps the entire file in `BEGIN`/`COMMIT` automatically; on error, issues `ROLLBACK` instead of `COMMIT`. This is cleaner than manually wrapping with `BEGIN`/`COMMIT` in the script.
- `--set ON_ERROR_STOP=1` -- **critical**: without this, psql continues executing subsequent statements after an error within a file. A migration file with `ALTER TABLE ... ADD COLUMN` followed by `CREATE INDEX` would partially execute if the ALTER fails, leaving the database in an inconsistent state even within a transaction. `ON_ERROR_STOP=1` aborts at the first error.

**Bash operator precedence -- project learning:**

Per [SSH Operator Precedence learning](../../knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md): when chaining commands with `&&` and `||`, always use `{ ...; }` grouping around any `|| true` fallback. This prevents `|| true` from silently absorbing failures from earlier commands in the chain. The migration runner script must NOT use bare `|| true` in command chains.

**References:**

- [PostgreSQL psql documentation](https://www.postgresql.org/docs/current/app-psql.html)
- [What Should a PostgreSQL Migrator Do?](https://medium.com/@jonathangfischoff/what-should-a-postgresql-migrator-do-47fd34804be)

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
| Migration SQL error | `ON_ERROR_STOP=1` aborts psql, `--single-transaction` rolls back, script exits 1, deploy blocked |
| Partial SQL error within file | `ON_ERROR_STOP=1` prevents continuation past the error line; `--single-transaction` rolls back all prior statements in the file |
| Network timeout to Supabase | `psql` fails, script exits 1, deploy blocked |
| Tracking table already exists | `CREATE TABLE IF NOT EXISTS` is a no-op |
| Migration already applied | Skipped (filename match in tracking table) |
| New migration added in PR | Applied before deploy, server starts with correct schema |
| Doppler token missing | `doppler run` fails, script exits 1, deploy blocked |
| `migrate` job skipped (no version) | `deploy` job still runs via `always()` + `result != 'failure'` pattern |
| `migrate` job fails | `deploy` job is blocked (`needs.migrate.result == 'failure'`) |

### Rollback Safety

Migration failures abort before the deploy job runs. The old container continues running with the old schema -- both remain consistent. There is no automated rollback of applied migrations (this is a deliberate simplification for MVP -- migrations should be forward-only).

### Bootstrapping

The first run of the migration runner will find no `_schema_migrations` table. It will create it, then attempt to apply all 11 migration files. Migrations 001-010 have already been applied manually to production, so they need to be pre-seeded in the tracking table.

**Approach:** The script checks if the tracking table is empty on first run. If empty, it inserts a hardcoded list of the 11 known pre-existing migration filenames (001 through 010, including both `007_` files) with `applied_at = now()`. This is a static seed -- no runtime object scanning, no detection logic. The filenames are known at implementation time.

*[Updated 2026-03-28: simplified bootstrap to hardcoded seed per review -- runtime object scanning was overengineered for a one-time event.]*

## Acceptance Criteria

- [x] `_schema_migrations` table is created automatically on first run
- [x] Unapplied migrations are applied in filename-sorted order before deploy
- [x] Already-applied migrations are skipped (idempotent)
- [x] Migration failure blocks the deploy job (exit code propagation)
- [x] `DATABASE_URL` is injected from Doppler, never hardcoded
- [x] Existing production schema (001-010) is bootstrapped without re-execution
- [x] Script follows project shell conventions (`set -euo pipefail`, `#!/usr/bin/env bash`)
- [x] `deploy` job depends on `migrate` job succeeding
- [x] Duplicate `007_` prefix files both execute in correct order

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
| Bootstrap seeds wrong state | Hardcoded seed list of 11 known filenames -- deterministic, no runtime detection |
| Migration naming collision (007) | Track by full filename, not prefix; file cleanup issue separately |
| `psql` not available on runner | Pre-installed on `ubuntu-latest`; verified in GitHub docs |
| Long-running migration blocks deploy | Migrations are small DDL; add `--set statement_timeout=30000` (30s) to psql |
| Partial SQL execution within file | `ON_ERROR_STOP=1` + `--single-transaction` prevent partial state |
| `migrate` skip propagates to `deploy` | `deploy` uses `always()` + `result != 'failure'` pattern to handle skipped `migrate` |
| Secrets masking breaks job conditions | `DOPPLER_TOKEN` checked inside step, not in job `if` (per project learning) |

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
