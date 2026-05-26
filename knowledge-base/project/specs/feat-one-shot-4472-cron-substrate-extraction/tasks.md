---
title: "refactor: extract shared cron-substrate helpers"
branch: feat-one-shot-4472-cron-substrate-extraction
plan: knowledge-base/project/plans/2026-05-26-refactor-cron-substrate-extraction-plan.md
lane: single-domain
---

# Tasks — Cron Substrate Extraction

## Phase 0: Preconditions

- [ ] 0.1 Verify all 14 cron-*.ts files compile: `cd apps/web-platform && npx tsc --noEmit`
- [ ] 0.2 Run existing guard test: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts`

## Phase 1: Create `_cron-shared.ts`

- [ ] 1.1 Create `apps/web-platform/server/inngest/functions/_cron-shared.ts`
  - [ ] 1.1.1 Export `REPO_OWNER`, `REPO_NAME` constants
  - [ ] 1.1.2 Export `SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE` regexes
  - [ ] 1.1.3 Export `HandlerArgs` interface
  - [ ] 1.1.4 Export `redactToken(s, token)` function
  - [ ] 1.1.5 Export `buildAuthenticatedCloneUrl(token)` function
  - [ ] 1.1.6 Export `mintInstallationToken(opts: { tokenMinLifetimeMs })` function
  - [ ] 1.1.7 Export `postSentryHeartbeat(args: { ok, sentryMonitorSlug, cronName, logger })` function
- [ ] 1.2 Verify `tsc --noEmit` passes with new file

## Phase 2: Create `_cron-claude-eval-substrate.ts`

- [ ] 2.1 Create `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
  - [ ] 2.1.1 Import from `_cron-shared.ts` (NO re-exports — plan-review P2)
  - [ ] 2.1.2 Export `SpawnResult` interface
  - [ ] 2.1.3 Export `KILL_ESCALATION_MS` constant
  - [ ] 2.1.4 Export `resolveClaudeBin()` function
  - [ ] 2.1.5 Export `spawnSimple(cmd, args, opts)` function
  - [ ] 2.1.6 Export `setupEphemeralWorkspace(args: { installationToken, cronName })` function
  - [ ] 2.1.7 Export `teardownEphemeralWorkspace(ephemeralRoot, cronName)` function
  - [ ] 2.1.8 Export `spawnClaudeEval(args: { spawnCwd, installationToken, flags, prompt, maxTurnDurationMs, cronName, buildSpawnEnv, logger })` function
- [ ] 2.2 Verify `tsc --noEmit` passes

## Phase 3: Migrate 7 claude-eval handlers (ephemeral-workspace cohort)

- [ ] 3.1 cron-roadmap-review.ts: replace local helpers with imports
- [ ] 3.2 cron-competitive-analysis.ts: replace local helpers with imports
- [ ] 3.3 cron-bug-fixer.ts: replace local helpers with imports
- [ ] 3.4 cron-agent-native-audit.ts: replace local helpers with imports
- [ ] 3.5 cron-legal-audit.ts: replace local helpers with imports
- [ ] 3.6 cron-community-monitor.ts: replace local helpers with imports
- [ ] 3.7 cron-ux-audit.ts: replace local helpers with imports
- [ ] 3.8 Verify `tsc --noEmit` passes after all 7 migrations

## Phase 4: Migrate 2 no-workspace claude-eval handlers

- [ ] 4.1 cron-daily-triage.ts: import shared symbols, delete local definitions, refactor inline heartbeat to use shared `postSentryHeartbeat`
- [ ] 4.2 cron-follow-through-monitor.ts: import shared symbols, delete local definitions, refactor inline heartbeat to use shared `postSentryHeartbeat`
- [ ] 4.3 Verify `tsc --noEmit` passes

## Phase 5: Migrate 5 pure-TS handlers

### Tier C (full shared set): strategy-review, compound-promote
- [ ] 5.1 cron-strategy-review.ts: import `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `postSentryHeartbeat`, Sentry regexes, `REPO_OWNER`, `REPO_NAME`, `HandlerArgs` from `_cron-shared.ts`; delete local definitions
- [ ] 5.2 cron-compound-promote.ts: same import set as 5.1; delete local definitions

### Tier D (Sentry-only shared set): oauth-probe, stale-deferred-scope-outs, github-app-drift-guard
- [ ] 5.3 cron-oauth-probe.ts: import `postSentryHeartbeat`, Sentry regexes, `HandlerArgs` from `_cron-shared.ts`; refactor inline heartbeat to use shared function; delete local definitions
- [ ] 5.4 cron-stale-deferred-scope-outs.ts: same import set as 5.3; refactor inline heartbeat; delete local definitions
- [ ] 5.5 cron-github-app-drift-guard.ts: same import set as 5.3; refactor inline heartbeat; delete local definitions
- [ ] 5.6 Verify `tsc --noEmit` passes

## Phase 6: Delete stale GHA workflow

- [ ] 6.1 Delete `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml`

## Phase 7: Guard test

- [ ] 7.1 Create `apps/web-platform/test/server/cron-substrate-imports.test.ts`
  - [ ] 7.1.1 Test: every cron-*.ts imports from shared substrate
  - [ ] 7.1.2 Test: no cron-*.ts locally redefines extracted symbols
  - [ ] 7.1.3 Fixture proof tests (positive + negative synthetic source strings)
- [ ] 7.2 Run guard test: `./node_modules/.bin/vitest run test/server/cron-substrate-imports.test.ts`

## Phase 8: Tick umbrella checkboxes (pre-merge)

- [ ] 8.1 Tick community-monitor and gdpr-gate checkboxes on #3948 via `gh api`

## Phase 9: Final verification

- [ ] 9.1 `cd apps/web-platform && npx tsc --noEmit` passes
- [ ] 9.2 `./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts` passes
- [ ] 9.3 `./node_modules/.bin/vitest run test/server/cron-substrate-imports.test.ts` passes
- [ ] 9.4 Verify `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` is deleted
- [ ] 9.5 Verify net LoC delta is negative via `git diff --stat`
