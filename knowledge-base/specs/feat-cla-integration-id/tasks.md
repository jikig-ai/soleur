# Tasks: CLA Ruleset Integration ID

## Phase 1: Update Ruleset via GitHub API (This PR)

- [x] 1.1 Construct complete PUT payload for ruleset update
  - [x] 1.1.1 Include all existing fields: name, target, enforcement, conditions, rules, bypass_actors
  - [x] 1.1.2 Add `"integration_id": 15368` to `cla-check` entry in `required_status_checks`
  - [x] ~~1.1.3 Add `github-actions` (15368) to `bypass_actors`~~ **NOT FEASIBLE** — `github-actions` is a built-in platform app, not an installable integration. GitHub API returns 422: "Actor GitHub Actions integration must be part of the ruleset source or owner organization." Bypass actor approach dropped.
  - [x] 1.1.4 Preserve all 4 existing bypass actors in the payload
- [x] 1.2 Execute API call: `gh api repos/jikig-ai/soleur/rulesets/13304872 --method PUT --input /tmp/ruleset-update.json`
- [x] 1.3 Verify ruleset update via `gh api repos/jikig-ai/soleur/rulesets/13304872` -- confirm:
  - [x] 1.3.1 `integration_id: 15368` present in `rules[0].parameters.required_status_checks[0]`
  - [x] 1.3.2 4 bypass actors preserved (bypass actor addition not feasible)
  - [x] 1.3.3 All other fields unchanged (enforcement, conditions, rule parameters)

## Phase 2: Post-Merge Verification (deferred — no bypass actor to test)

Since the bypass actor could not be added, Phase 2's bypass testing is moot. The remaining verification:

- [ ] 2.1 Trigger `scheduled-weekly-analytics.yml` manually to verify bot PRs still auto-merge with `integration_id` set (synthetic status posted by `github-actions` app matches `integration_id: 15368`)
- [ ] 2.2 Verify human PR CLA check still triggers correctly with `integration_id` constraint

## Phase 3: Remove Synthetic Statuses — NOT POSSIBLE

Without a bypass actor, bot workflows must continue posting synthetic `cla-check` statuses. This phase is cancelled. The synthetic statuses work correctly because they're posted by `github-actions` (matching `integration_id: 15368`).
