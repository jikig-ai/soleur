# Tasks: Extract Synthetic Status Script

## Phase 1: Setup

- [ ] 1.1 Create `scripts/post-bot-statuses.sh` with shebang, `set -euo pipefail`, and argument validation
- [ ] 1.2 Add status definitions array (`STATUSES`) with `cla-check` and `test` entries
- [ ] 1.3 Add loop that posts each status via `gh api`
- [ ] 1.4 Make script executable (`chmod +x`)

## Phase 2: Core Implementation

- [ ] 2.1 Update `scheduled-campaign-calendar.yml` -- replace inline status block with `bash scripts/post-bot-statuses.sh "$SHA"`
- [ ] 2.2 Update `scheduled-community-monitor.yml`
- [ ] 2.3 Update `scheduled-competitive-analysis.yml`
- [ ] 2.4 Update `scheduled-content-generator.yml`
- [ ] 2.5 Update `scheduled-content-publisher.yml` (uses `${{ github.repository }}` style -- confirm replacement works)
- [ ] 2.6 Update `scheduled-growth-audit.yml`
- [ ] 2.7 Update `scheduled-growth-execution.yml`
- [ ] 2.8 Update `scheduled-seo-aeo-audit.yml`
- [ ] 2.9 Update `scheduled-weekly-analytics.yml` (uses `${{ github.repository }}` style -- confirm replacement works)

## Phase 3: Verification

- [ ] 3.1 Grep all 9 workflow files for `context=cla-check` and `context=test` -- should return zero matches (only the script should have these)
- [ ] 3.2 Grep all 9 workflow files for `post-bot-statuses.sh` -- should return 9 matches
- [ ] 3.3 Run `bash -n scripts/post-bot-statuses.sh` to validate script syntax
- [ ] 3.4 Verify `scripts/create-ci-required-ruleset.sh` does not need updates (it references the statuses conceptually, not the inline pattern)
