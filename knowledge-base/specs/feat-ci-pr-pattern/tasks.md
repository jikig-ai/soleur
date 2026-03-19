# Tasks: fix(ci) -- Migrate 7 Agent Workflows to PR-Based Commit Pattern

## Phase 1: Permissions Updates (all 7 workflows)

- [ ] 1.1 Add `pull-requests: write` and `statuses: write` to `scheduled-growth-audit.yml` permissions block
- [ ] 1.2 Add `pull-requests: write` and `statuses: write` to `scheduled-community-monitor.yml` permissions block
- [ ] 1.3 Add `pull-requests: write` and `statuses: write` to `scheduled-seo-aeo-audit.yml` permissions block
- [ ] 1.4 Add `pull-requests: write` and `statuses: write` to `scheduled-campaign-calendar.yml` permissions block
- [ ] 1.5 Add `pull-requests: write` and `statuses: write` to `scheduled-content-generator.yml` permissions block
- [ ] 1.6 Add `pull-requests: write` and `statuses: write` to `scheduled-competitive-analysis.yml` permissions block
- [ ] 1.7 Add `pull-requests: write` and `statuses: write` to `scheduled-growth-execution.yml` permissions block

## Phase 2: GH_TOKEN Environment Variable (all 7 workflows)

- [ ] 2.1 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-growth-audit.yml`
- [ ] 2.2 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-community-monitor.yml`
- [ ] 2.3 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-seo-aeo-audit.yml`
- [ ] 2.4 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-campaign-calendar.yml`
- [ ] 2.5 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-content-generator.yml`
- [ ] 2.6 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-competitive-analysis.yml`
- [ ] 2.7 Add `GH_TOKEN: ${{ github.token }}` to claude-code-action env in `scheduled-growth-execution.yml`

## Phase 3: Prompt Replacement (per workflow)

Each prompt replacement has three sub-tasks:
- (a) Replace authorization notice ("authorized to push" -> "Do NOT push directly to main")
- (b) Replace commit/push block with PR-based pattern (branch + push + CLA status + PR + auto-merge)
- (c) Use timestamp branch name format (`%Y-%m-%d-%H%M%S`), `${GITHUB_REPOSITORY}` for gh api, `[skip ci]` in commit message

- [ ] 3.1 Replace prompt in `scheduled-growth-audit.yml`: Step 6 push block -> PR-based pattern (branch `ci/growth-audit-<timestamp>`, add paths `knowledge-base/marketing/audits/soleur-ai/`)
- [ ] 3.2 Replace prompt in `scheduled-community-monitor.yml`: step 5 push block -> PR-based pattern (branch `ci/community-digest-<timestamp>`, add paths `knowledge-base/support/community/`)
- [ ] 3.3 Replace prompt in `scheduled-seo-aeo-audit.yml`: final step push block -> PR-based pattern (branch `ci/seo-aeo-audit-<timestamp>`, `git add -A`)
- [ ] 3.4 Replace prompt in `scheduled-campaign-calendar.yml`: final step push block -> PR-based pattern (branch `ci/campaign-calendar-<timestamp>`, add path `knowledge-base/marketing/campaign-calendar.md`)
- [ ] 3.5 Replace prompt in `scheduled-content-generator.yml`: final step push block -> PR-based pattern (branch `ci/content-gen-<timestamp>`, `git add -A`), **preserve conditional commit message logic** (queue path vs growth plan path)
- [ ] 3.6 Replace prompt in `scheduled-competitive-analysis.yml`: final step push block -> PR-based pattern (branch `ci/competitive-analysis-<timestamp>`, add path `knowledge-base/product/competitive-intelligence.md`)
- [ ] 3.7 Replace prompt in `scheduled-growth-execution.yml`: final step push block -> PR-based pattern (branch `ci/growth-execution-<timestamp>`, `git add -A`)

## Phase 4: Validation

- [ ] 4.1 Grep all 7 files for `git push origin main` -- should return zero matches
- [ ] 4.2 Grep all 7 files for `pull-requests: write` -- should return 7 matches
- [ ] 4.3 Grep all 7 files for `statuses: write` -- should return 7 matches
- [ ] 4.4 Grep all 7 files for `GH_TOKEN` in claude-code-action step -- should return 7 matches
- [ ] 4.5 Grep all 7 files for `GITHUB_REPOSITORY` -- should return 7 matches (agent prompt uses env var, not template expression)
- [ ] 4.6 Verify `scheduled-content-generator.yml` preserves both conditional commit messages
- [ ] 4.7 Grep all 7 files for `%H%M%S` -- should return 7 matches (timestamp branch names)
- [ ] 4.8 Grep all 7 files for `authorized to commit and push` -- should return zero matches (old notice removed)
- [ ] 4.9 YAML syntax validation: ensure all 7 files parse correctly
- [ ] 4.10 Run compound before commit
