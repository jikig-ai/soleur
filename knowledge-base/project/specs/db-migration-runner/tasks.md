# Tasks: Automated Database Migration Runner

## Phase 1: Setup

- [ ] 1.1 Add `DATABASE_URL` to Doppler `prd` config
  - Retrieve connection string from Supabase Dashboard > Settings > Database > Connection string (URI)
  - `doppler secrets set DATABASE_URL --config prd --project soleur`
- [ ] 1.2 Verify `DOPPLER_TOKEN_PRD` exists as GitHub Actions secret
  - Check via `gh secret list` or create a Doppler service token scoped to `prd`
  - `gh secret set DOPPLER_TOKEN_PRD`

## Phase 2: Core Implementation

- [ ] 2.1 Create migration runner script
  - File: `apps/web-platform/scripts/run-migrations.sh`
  - Shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`
  - 2.1.1 Resolve `SCRIPT_DIR` via `BASH_SOURCE[0]` -- reference migrations dir as `"$SCRIPT_DIR/../supabase/migrations/"`
  - 2.1.2 Validate `DATABASE_URL` is set (fail early with clear message)
  - 2.1.3 Create `_schema_migrations` tracking table (`CREATE TABLE IF NOT EXISTS` -- filename TEXT PK, applied_at TIMESTAMPTZ)
  - 2.1.4 Bootstrap: if tracking table is empty, seed hardcoded list of 11 known filenames (001-010 including both 007 files)
  - 2.1.5 List `*.sql` files from migrations directory, sorted lexicographically
  - 2.1.6 For each unapplied file: run with `psql --no-psqlrc --single-transaction --set ON_ERROR_STOP=1 -f`, then record in tracking table
  - 2.1.7 Exit non-zero on any failure; use `{ ...; }` grouping for any `|| true` (bash operator precedence learning)
  - 2.1.8 Log applied/skipped counts for CI visibility
- [ ] 2.2 Add `migrate` job to `web-platform-release.yml`
  - File: `.github/workflows/web-platform-release.yml`
  - 2.2.1 New `migrate` job: `needs: release`, `if: needs.release.outputs.version != '' && (... || !inputs.skip_deploy)`
  - 2.2.2 Add `concurrency: group: migrate-web-platform, cancel-in-progress: false`
  - 2.2.3 Pin `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1)
  - 2.2.4 Pin `dopplerhq/cli-action@014df23b1329b615816a38eb5f473bb9000700b1` (v3)
  - 2.2.5 Run `doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh`
  - 2.2.6 Update `deploy` job: `needs: [release, migrate]` with `if: always() && needs.migrate.result != 'failure' && ...`

## Phase 3: Testing and Verification

- [ ] 3.1 Local dry run of migration script against a test database (if available)
- [ ] 3.2 After merge, trigger manual workflow run: `gh workflow run web-platform-release.yml`
- [ ] 3.3 Verify `migrate` job appears and succeeds in CI output
- [ ] 3.4 Verify tracking table populated: `doppler run -c prd -- psql "$DATABASE_URL" -c "SELECT * FROM public._schema_migrations ORDER BY filename"`
- [ ] 3.5 Re-run workflow to verify idempotency (0 migrations applied on second run)
- [ ] 3.6 File follow-up issue for duplicate `007_` prefix cleanup
