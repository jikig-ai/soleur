# Tasks: CLA Ruleset Integration ID

## Phase 1: Update Ruleset via GitHub API

- [ ] 1.1 Update CLA Required ruleset (ID 13304872) via `gh api repos/jikig-ai/soleur/rulesets/13304872 --method PUT`
  - [ ] 1.1.1 Add `integration_id: 15368` to `cla-check` required status check
  - [ ] 1.1.2 Add `{ "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "pull_request" }` to `bypass_actors`
  - [ ] 1.1.3 Preserve all existing bypass actors and rules in the PUT payload
- [ ] 1.2 Verify ruleset update via `gh api repos/jikig-ai/soleur/rulesets/13304872` and confirm both changes applied

## Phase 2: Remove Synthetic CLA Status from Bot Workflows

- [ ] 2.1 Modify `.github/workflows/scheduled-weekly-analytics.yml`
  - [ ] 2.1.1 Remove the 4-line synthetic `cla-check` status block (lines 101-108)
  - [ ] 2.1.2 Remove `statuses: write` from `permissions:` block
- [ ] 2.2 Modify `.github/workflows/scheduled-content-publisher.yml`
  - [ ] 2.2.1 Remove the 5-line synthetic `cla-check` status block (lines 85-92)
  - [ ] 2.2.2 Remove `statuses: write` from `permissions:` block

## Phase 3: Verification

- [ ] 3.1 Trigger `scheduled-weekly-analytics.yml` manually via `gh workflow run`
- [ ] 3.2 Verify bot PR auto-merges without `cla-check` status (bypass active)
- [ ] 3.3 Open a test human PR and verify CLA check still triggers and blocks merge
- [ ] 3.4 Confirm `integration_id` is present in ruleset via API query
