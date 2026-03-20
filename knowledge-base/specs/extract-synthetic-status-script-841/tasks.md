# Tasks: Extract Synthetic Status Script

## Phase 1: Setup

- [ ] 1.1 Create `scripts/post-bot-statuses.sh` with shebang, `set -euo pipefail`, header comment (Usage, Environment variables, Exit codes), and argument validation
- [ ] 1.2 Add status definitions array (`STATUSES`) with `cla-check` and `test` entries, including cross-reference comment to `create-ci-required-ruleset.sh`
- [ ] 1.3 Add loop that posts each status via `gh api` with proper quoting on all variable expansions
- [ ] 1.4 Make script executable (`chmod +x`)
- [ ] 1.5 Run `bash -n scripts/post-bot-statuses.sh` to validate script syntax

## Phase 2: Core Implementation -- claude-code-action workflows (7 files)

These workflows embed bash in a `prompt:` field. Replace the inline `gh api` block with `bash scripts/post-bot-statuses.sh "$SHA"`.

- [ ] 2.1 Update `scheduled-campaign-calendar.yml`
- [ ] 2.2 Update `scheduled-community-monitor.yml`
- [ ] 2.3 Update `scheduled-competitive-analysis.yml`
- [ ] 2.4 Update `scheduled-content-generator.yml`
- [ ] 2.5 Update `scheduled-growth-audit.yml`
- [ ] 2.6 Update `scheduled-growth-execution.yml`
- [ ] 2.7 Update `scheduled-seo-aeo-audit.yml`

## Phase 3: Core Implementation -- direct `run:` step workflows (2 files)

These workflows use native `run:` blocks with `${{ github.repository }}` expressions. Replace the inline block and the preceding comment with `bash scripts/post-bot-statuses.sh "$SHA"`.

- [ ] 3.1 Update `scheduled-content-publisher.yml` -- also remove the inline comment block above the status code
- [ ] 3.2 Update `scheduled-weekly-analytics.yml` -- also remove the inline comment block above the status code

## Phase 4: Verification

- [ ] 4.1 Grep all 9 workflow files for `context=cla-check` and `context=test` -- should return zero matches (only the script should have these)
- [ ] 4.2 Grep all 9 workflow files for `post-bot-statuses.sh` -- should return 9 matches
- [ ] 4.3 Verify `scripts/create-ci-required-ruleset.sh` does not need updates (it references the statuses conceptually, not the inline pattern)
- [ ] 4.4 Verify all 9 workflow files still declare `statuses: write` permission (no accidental removal during editing)
