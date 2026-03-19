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

- [ ] 3.1 Replace prompt in `scheduled-growth-audit.yml`: update authorization notice, replace Step 6 push block with PR-based pattern (branch `ci/growth-audit-`, add paths `knowledge-base/marketing/audits/soleur-ai/`)
- [ ] 3.2 Replace prompt in `scheduled-community-monitor.yml`: update authorization notice, replace step 5 push block with PR-based pattern (branch `ci/community-digest-`, add paths `knowledge-base/support/community/`)
- [ ] 3.3 Replace prompt in `scheduled-seo-aeo-audit.yml`: update authorization notice, replace final step push block with PR-based pattern (branch `ci/seo-aeo-audit-`, `git add -A`)
- [ ] 3.4 Replace prompt in `scheduled-campaign-calendar.yml`: update authorization notice, replace final step push block with PR-based pattern (branch `ci/campaign-calendar-`, add path `knowledge-base/marketing/campaign-calendar.md`)
- [ ] 3.5 Replace prompt in `scheduled-content-generator.yml`: update authorization notice, replace final step push block with PR-based pattern (branch `ci/content-gen-`, `git add -A`), preserve conditional commit message logic
- [ ] 3.6 Replace prompt in `scheduled-competitive-analysis.yml`: update authorization notice, replace final step push block with PR-based pattern (branch `ci/competitive-analysis-`, add path `knowledge-base/product/competitive-intelligence.md`)
- [ ] 3.7 Replace prompt in `scheduled-growth-execution.yml`: update authorization notice, replace final step push block with PR-based pattern (branch `ci/growth-execution-`, `git add -A`)

## Phase 4: Validation

- [ ] 4.1 Grep all 7 files for `git push origin main` -- should return zero matches
- [ ] 4.2 Grep all 7 files for `pull-requests: write` -- should return 7 matches
- [ ] 4.3 Grep all 7 files for `statuses: write` -- should return 7 matches
- [ ] 4.4 Grep all 7 files for `GH_TOKEN` in claude-code-action env blocks -- should return 7 matches
- [ ] 4.5 Verify `scheduled-content-generator.yml` preserves both conditional commit messages
- [ ] 4.6 YAML syntax validation: ensure all 7 files parse correctly
- [ ] 4.7 Run compound before commit
