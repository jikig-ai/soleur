# Tasks: ci: add e2e to required status checks

Source plan: `knowledge-base/project/plans/2026-04-03-ci-add-e2e-to-required-status-checks-plan.md`

## Phase 1: Add synthetic e2e check-runs to bot workflows

- [ ] 1.1 Add synthetic `e2e` check-run to `scheduled-content-publisher.yml` after existing `dependency-review` synthetic (line ~122)
- [ ] 1.2 Add synthetic `e2e` check-run to `scheduled-weekly-analytics.yml` after existing `dependency-review` synthetic (line ~132)
- [ ] 1.3 Commit and push Phase 1 changes

## Phase 2: Update CI Required ruleset

- [ ] 2.1 After Phase 1 merges to main, update ruleset 14145388 via `gh api` PUT -- include `bypass_actors`, `conditions`, and all 3 required checks
- [ ] 2.2 Verify ruleset shows all 3 required checks: `test`, `dependency-review`, `e2e`
- [ ] 2.3 Verify `bypass_actors` (2 entries) and `conditions` (`~DEFAULT_BRANCH`) are preserved

## Phase 3: Verification

- [ ] 3.1 Confirm no open bot PRs are stuck (`gh pr list --search "author:app/github-actions" --state open`)
- [ ] 3.2 Verify `e2e` appears as required on the next real PR
