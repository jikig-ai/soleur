# Tasks: CI Required Status Check (#826)

## Phase 1: Create Ruleset

- [ ] 1.1 Write ruleset JSON payload to temp file
- [ ] 1.2 Create "CI Required" ruleset via `gh api repos/jikig-ai/soleur/rulesets -X POST --input`
- [ ] 1.3 Verify ruleset creation: `gh api repos/jikig-ai/soleur/rulesets --jq '.[] | select(.name == "CI Required")'`

## Phase 2: Update Bot Workflows

- [ ] 2.1 Update `scheduled-content-publisher.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.2 Update `scheduled-content-generator.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.3 Update `scheduled-weekly-analytics.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.4 Update `scheduled-competitive-analysis.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.5 Update `scheduled-growth-audit.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.6 Update `scheduled-seo-aeo-audit.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.7 Update `scheduled-community-monitor.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.8 Update `scheduled-campaign-calendar.yml` -- add synthetic `test` status POST after `cla-check` POST
- [ ] 2.9 Update `scheduled-growth-execution.yml` -- add synthetic `test` status POST after `cla-check` POST

## Phase 3: Verification

- [ ] 3.1 Run `bun test` to confirm no test regressions
- [ ] 3.2 Verify ruleset is active: `gh api repos/jikig-ai/soleur/rulesets --jq '.[] | select(.name == "CI Required") | {id, name, enforcement}'`
- [ ] 3.3 Verify `test` check context is required: `gh api repos/jikig-ai/soleur/rulesets --jq '.[] | select(.name == "CI Required") | .rules[].parameters.required_status_checks[].context'`
- [ ] 3.4 Open a test PR to verify CI runs and `test` check is required for merge

## Phase 4: Documentation

- [ ] 4.1 Create learning in `knowledge-base/learnings/` documenting the bot workflow synthetic status pattern for future workflows
