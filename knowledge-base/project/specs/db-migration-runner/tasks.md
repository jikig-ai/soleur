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
  - 2.1.1 Create `_schema_migrations` tracking table (`CREATE TABLE IF NOT EXISTS`)
  - 2.1.2 Bootstrap detection: if tracking table is empty AND production tables exist, seed records for 001-010 without re-executing
  - 2.1.3 List `*.sql` files from migrations directory, sorted lexicographically
  - 2.1.4 For each unapplied file: compute SHA-256, execute in transaction, record in tracking table
  - 2.1.5 Exit non-zero on any failure
  - 2.1.6 Log applied/skipped counts for CI visibility
- [ ] 2.2 Add `migrate` job to `web-platform-release.yml`
  - File: `.github/workflows/web-platform-release.yml`
  - 2.2.1 New `migrate` job after `release`, before `deploy`
  - 2.2.2 `needs: release` with `if: needs.release.outputs.version != ''`
  - 2.2.3 Install Doppler CLI via `dopplerhq/cli-action@v3`
  - 2.2.4 Run `doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh`
  - 2.2.5 Update `deploy` job to `needs: [release, migrate]`

## Phase 3: Testing and Verification

- [ ] 3.1 Local dry run of migration script against a test database (if available)
- [ ] 3.2 After merge, trigger manual workflow run: `gh workflow run web-platform-release.yml`
- [ ] 3.3 Verify `migrate` job appears and succeeds in CI output
- [ ] 3.4 Verify tracking table populated: `doppler run -c prd -- psql "$DATABASE_URL" -c "SELECT * FROM public._schema_migrations ORDER BY filename"`
- [ ] 3.5 Re-run workflow to verify idempotency (0 migrations applied on second run)
- [ ] 3.6 File follow-up issue for duplicate `007_` prefix cleanup
