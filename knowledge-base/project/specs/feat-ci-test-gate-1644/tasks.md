# Tasks: fix: enforce CI test gate to block PR approval

Source plan: `knowledge-base/project/plans/2026-04-06-fix-ci-test-gate-blocking-pr-approval-plan.md`

## Phase 1: Tighten ruleset bypass mode and update script

- [ ] 1.1 Update live CI Required ruleset (ID 14145388) via `gh api` PUT: change `bypass_mode` from `"always"` to `"pull_request"` for both bypass actors
- [ ] 1.2 Verify updated ruleset: `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors[] | "\(.actor_type) -> \(.bypass_mode)"'` shows `pull_request` for both
- [ ] 1.3 Update `scripts/create-ci-required-ruleset.sh`: change `bypass_mode` values from `"always"` to `"pull_request"` with explanatory comment

## Phase 2: Verification

- [ ] 2.1 Run `bash scripts/lint-bot-synthetic-completeness.sh` to confirm no regressions
- [ ] 2.2 Run `bash scripts/test-all.sh` to confirm all tests pass
