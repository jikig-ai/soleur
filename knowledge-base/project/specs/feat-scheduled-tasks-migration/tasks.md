# Tasks: Migrate Scheduled Workflows to Cloud Scheduled Tasks

**Plan:** [2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md](../../plans/2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md)
**Issue:** #1094
**Branch:** `scheduled-tasks-migration`

## Phase 0: Validate and Setup

- [ ] 0.1 Create Doppler `prd_scheduled` config
  - [ ] 0.1.1 Create config under `soleur` project in Doppler
  - [ ] 0.1.2 Copy 11 community-monitor secrets from GHA repository secrets
  - [ ] 0.1.3 Verify all secret values are current
- [ ] 0.2 Create Cloud environment `soleur-scheduled`
  - [ ] 0.2.1 Configure: Limited network, `DOPPLER_TOKEN` env var, setup script (Doppler CLI + npm ci)
  - [ ] 0.2.2 Create campaign-calendar Cloud task with adapted prompt
  - [ ] 0.2.3 Run via "Run now" — verify plugin loads, skill executes, PR + issue created
  - [ ] 0.2.4 Test concurrency: trigger while a task is already running, document behavior
  - [ ] 0.2.5 Compare output with latest GHA run — confirm equivalence

## Phase 1: Migrate All 9 Workflows

- [ ] 1.1 Migrate campaign-calendar (already created in Phase 0)
  - [ ] 1.1.1 Disable GHA schedule trigger (keep dispatch)
- [ ] 1.2 Migrate competitive-analysis (Monthly 1st)
  - [ ] 1.2.1 Create Cloud task, run "Run now", verify output
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
- [ ] 1.6 Migrate daily-triage (Daily)
  - [ ] 1.6.1 Create Cloud task with triage prompt, verify label application
  - [ ] 1.6.2 Disable GHA schedule trigger
- [ ] 1.7 Migrate community-monitor (Daily)
  - [ ] 1.7.1 Create Cloud task, verify Doppler secrets accessible (Discord, X, LinkedIn, Bluesky)
  - [ ] 1.7.2 Verify all 4 platform APIs authenticate
  - [ ] 1.7.3 Disable GHA schedule trigger
- [ ] 1.8 Migrate content-generator (Tue + Thu)
  - [ ] 1.8.1 Verify WebSearch/WebFetch work with Limited network
  - [ ] 1.8.2 Verify Eleventy build works in Cloud env
  - [ ] 1.8.3 Create Cloud task with full prompt, run "Run now"
  - [ ] 1.8.4 Disable GHA schedule trigger
- [ ] 1.9 Migrate growth-audit (Weekly Monday)
  - [ ] 1.9.1 Create Cloud task, verify output
  - [ ] 1.9.2 Disable GHA schedule trigger

## Phase 2: Verify and Monitor (1 week)

- [ ] 2.1 Confirm all 9 Cloud tasks fire on schedule
- [ ] 2.2 Verify cross-platform dependencies: triage (Cloud) → bug-fixer (GHA), content-gen (Cloud) → content-pub (GHA)
- [ ] 2.3 Assess interactive rate limit impact
- [ ] 2.4 Update `soleur:schedule list` to note active Cloud tasks
- [ ] 2.5 Create GitHub issue for full schedule skill `--target cloud` update (deferred)
