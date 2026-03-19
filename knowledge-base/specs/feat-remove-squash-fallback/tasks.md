# Tasks: Remove Squash Fallback from Automated PR Workflows

## Phase 1: Implementation

- [ ] 1.1 Remove `|| gh pr merge "$BRANCH" --squash` fallback from `scheduled-weekly-analytics.yml`
- [ ] 1.2 Remove fallback from `scheduled-content-publisher.yml`
- [ ] 1.3 Remove fallback from `scheduled-growth-audit.yml`
- [ ] 1.4 Remove fallback from `scheduled-community-monitor.yml`
- [ ] 1.5 Remove fallback from `scheduled-content-generator.yml`
- [ ] 1.6 Remove fallback from `scheduled-growth-execution.yml`
- [ ] 1.7 Remove fallback from `scheduled-competitive-analysis.yml`
- [ ] 1.8 Remove fallback from `scheduled-campaign-calendar.yml`
- [ ] 1.9 Remove fallback from `scheduled-seo-aeo-audit.yml`

## Phase 2: Verification

- [ ] 2.1 Grep all workflow files to confirm no `|| gh pr merge` patterns remain
- [ ] 2.2 Verify each workflow still has Discord failure notification step (`if: failure()`)
- [ ] 2.3 Verify synthetic `cla-check` status posting is preserved in each workflow

## Phase 3: Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit and push
- [ ] 3.3 Create PR with `Closes #780` in body
- [ ] 3.4 Set `semver:patch` label
- [ ] 3.5 Queue auto-merge and poll until merged
- [ ] 3.6 Run cleanup-merged
