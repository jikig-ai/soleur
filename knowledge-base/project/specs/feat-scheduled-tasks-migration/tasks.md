# Tasks: Migrate Scheduled Workflows to Cloud Scheduled Tasks

**Plan:** [2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md](../../plans/2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md)
**Issue:** #1094
**Branch:** `scheduled-tasks-migration`

## Phase 0: Validation

- [ ] 0.1 Verify Cloud task plugin marketplace support
  - [ ] 0.1.1 Create test Cloud task via web UI or `/schedule` CLI
  - [ ] 0.1.2 Test prompt: `Run /soleur:help and report what you see`
  - [ ] 0.1.3 Confirm Soleur skills are loadable → proceed or abort
- [ ] 0.2 Create Cloud environment `soleur-scheduled`
  - [ ] 0.2.1 Configure: Limited network, setup script (`npm ci`)
  - [ ] 0.2.2 Test environment with a throwaway task
- [ ] 0.3 Test with campaign-calendar
  - [ ] 0.3.1 Create Cloud task with adapted prompt
  - [ ] 0.3.2 Run via "Run now"
  - [ ] 0.3.3 Compare output with latest GHA run
  - [ ] 0.3.4 Verify PR creation, labels, issue output

## Phase 1: Weekly/Monthly Workflows

- [ ] 1.1 Migrate campaign-calendar (Weekly Monday)
  - [ ] 1.1.1 Create Cloud task, verify output
  - [ ] 1.1.2 Disable GHA schedule trigger (keep dispatch)
- [ ] 1.2 Migrate competitive-analysis (Monthly 1st)
  - [ ] 1.2.1 Create Cloud task, verify output
  - [ ] 1.2.2 Disable GHA schedule trigger
- [ ] 1.3 Migrate roadmap-review (Monthly 1st)
  - [ ] 1.3.1 Create Cloud task, verify output
  - [ ] 1.3.2 Disable GHA schedule trigger
- [ ] 1.4 Migrate growth-execution (Bi-monthly 1st, 15th)
  - [ ] 1.4.1 Create Cloud task, verify output
  - [ ] 1.4.2 Disable GHA schedule trigger
- [ ] 1.5 Migrate seo-aeo-audit (Weekly Monday)
  - [ ] 1.5.1 Create Cloud task, verify output
  - [ ] 1.5.2 Disable GHA schedule trigger

## Phase 2: Daily Workflows

- [ ] 2.1 Record rate limit baseline (interactive usage patterns)
- [ ] 2.2 Migrate daily-triage (Daily)
  - [ ] 2.2.1 Create Cloud task with triage prompt
  - [ ] 2.2.2 Verify label application, issue comments
  - [ ] 2.2.3 Disable GHA schedule trigger
- [ ] 2.3 Migrate community-monitor (Daily)
  - [ ] 2.3.1 Create Cloud task, verify output
  - [ ] 2.3.2 Disable GHA schedule trigger
- [ ] 2.4 Monitor rate limits for 1 week

## Phase 3: Medium-Complexity Workflows

- [ ] 3.1 Migrate content-generator (Tue + Thu)
  - [ ] 3.1.1 Adapt 100-line prompt for Cloud task context
  - [ ] 3.1.2 Verify Eleventy build works in Cloud env
  - [ ] 3.1.3 Verify WebSearch/WebFetch with Limited network
  - [ ] 3.1.4 Create Cloud task, run manually, verify full pipeline
  - [ ] 3.1.5 Disable GHA schedule trigger
- [ ] 3.2 Migrate growth-audit (Weekly Monday)
  - [ ] 3.2.1 Create Cloud task, verify output
  - [ ] 3.2.2 Disable GHA schedule trigger

## Phase 4: Cleanup

- [ ] 4.1 Document Cloud task monitoring procedure
- [ ] 4.2 Remove Discord webhook notifications from disabled GHA workflows
- [ ] 4.3 Update expense ledger with note about API cost reduction
- [ ] 4.4 Create GitHub issue for schedule skill `--target cloud` update (deferred)
- [ ] 4.5 Verify API spend reduction on console.anthropic.com after 2 weeks
