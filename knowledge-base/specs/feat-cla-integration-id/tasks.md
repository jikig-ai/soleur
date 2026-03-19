# Tasks: CLA Ruleset Integration ID

## Phase 1: Update Ruleset via GitHub API (This PR)

- [ ] 1.1 Construct complete PUT payload for ruleset update
  - [ ] 1.1.1 Include all existing fields: name, target, enforcement, conditions, rules, bypass_actors
  - [ ] 1.1.2 Add `"integration_id": 15368` to `cla-check` entry in `required_status_checks`
  - [ ] 1.1.3 Add `{ "actor_id": 15368, "actor_type": "Integration", "bypass_mode": "always" }` to `bypass_actors`
  - [ ] 1.1.4 Preserve all 4 existing bypass actors in the payload
- [ ] 1.2 Execute API call: `gh api repos/jikig-ai/soleur/rulesets/13304872 --method PUT --input /tmp/ruleset-update.json`
- [ ] 1.3 Verify ruleset update via `gh api repos/jikig-ai/soleur/rulesets/13304872` -- confirm:
  - [ ] 1.3.1 `integration_id: 15368` present in `rules[0].parameters.required_status_checks[0]`
  - [ ] 1.3.2 5 bypass actors present (4 existing + github-actions 15368)
  - [ ] 1.3.3 All other fields unchanged (enforcement, conditions, rule parameters)

## Phase 2: Post-Merge Verification

- [ ] 2.1 Trigger `scheduled-weekly-analytics.yml` manually via `gh workflow run scheduled-weekly-analytics.yml`
- [ ] 2.2 Monitor the bot PR -- verify it auto-merges (synthetic status still in place, so this validates no regression)
- [ ] 2.3 Open a test human PR and verify CLA check still triggers and blocks merge for unsigned contributor
- [ ] 2.4 Test bypass without synthetic status:
  - [ ] 2.4.1 Create a throwaway bot branch manually, push, create PR via `gh pr create`
  - [ ] 2.4.2 Do NOT post synthetic cla-check status
  - [ ] 2.4.3 Attempt `gh pr merge --squash --auto` -- observe if auto-merge proceeds or stalls
  - [ ] 2.4.4 If auto-merge stalls, attempt `gh pr merge --squash` (immediate merge) -- observe if bypass allows it
  - [ ] 2.4.5 Document results in #773

## Phase 3: Remove Synthetic Statuses (Follow-up PR, conditional on Phase 2 results)

- [ ] 3.1 Only proceed if Phase 2.4 confirms bypass works with auto-merge OR immediate merge
- [ ] 3.2 Modify `.github/workflows/scheduled-weekly-analytics.yml`
  - [ ] 3.2.1 Remove synthetic `cla-check` status block (lines 101-108)
  - [ ] 3.2.2 Remove `statuses: write` from `permissions:` block
- [ ] 3.3 Modify `.github/workflows/scheduled-content-publisher.yml`
  - [ ] 3.3.1 Remove synthetic `cla-check` status block (lines 85-92)
  - [ ] 3.3.2 Remove `statuses: write` from `permissions:` block
- [ ] 3.4 If bypass works with immediate merge only (not auto-merge), update bot workflow merge commands:
  - [ ] 3.4.1 Change `gh pr merge --squash --auto || gh pr merge --squash` to `gh pr merge --squash` (skip auto-merge attempt)
