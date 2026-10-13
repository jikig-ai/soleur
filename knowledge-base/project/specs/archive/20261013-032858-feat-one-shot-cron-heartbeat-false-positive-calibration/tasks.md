---
title: "Tasks — calibrate cloud-task-heartbeat watchdog"
plan: knowledge-base/project/plans/2026-06-03-fix-cron-cloud-task-heartbeat-false-positive-calibration-plan.md
lane: cross-domain
---

# Tasks — fix(cron): cloud-task-heartbeat false-positive calibration

## Phase 1 — Tests first (RED)

- [x] 1.1 In `cron-cloud-task-heartbeat.test.ts`, add a `describe` block driving `cronCloudTaskHeartbeatHandler` with mocked `step.run` + mocked `@octokit/core` `Octokit.request` + observability spies (`warnSilentFallback`, `reportSilentFallback`), mirroring `cron-shared.test.ts`.
  - [x] 1.1.1 Never-produced case: zero matching issues → `silent:false`, `warnSilentFallback` called at `op:"task-pending-first-run"`, NO `POST /repos/{owner}/{repo}/issues`.
  - [x] 1.1.2 Control: one issue older than `maxGapDays` → `silent:true`.
  - [x] 1.1.3 Control: issues request throws → `reportSilentFallback` at `op:"check-task"`, `silent:true` (error ≠ pending).
  - [x] 1.1.4 Control (recommended): issue with unparseable `created_at` → `daysSince===null` via `:142`, `silent:true` (corrupt data ≠ pending).
- [x] 1.2 Update `TASK_INVENTORY` assertions: `toHaveLength(6)` → `toHaveLength(5)`; drop the `strategy-review` `it.each` row; extend the non-producer guard to include `"strategy-review"`; keep the legal-audit 92-day-floor anchor.
- [x] 1.3 Confirm RED (new grace tests fail against current source).

## Phase 2 — Implement watchdog (GREEN)

- [x] 2.1 Import `warnSilentFallback` from `@/server/observability` in `cron-cloud-task-heartbeat.ts`.
- [x] 2.2 In `check-task-silence`, flip ONLY the `if (issues.length === 0)` arm (`:123`) to `silent:false` (pending-first-run) + `warnSilentFallback(null, { feature, op:"task-pending-first-run", message, extra })`. Leave BOTH other `silent:true` sites untouched: the `catch` arm (`:146`, API error) AND the in-band `:142` `daysSince === null` (NaN-parsed `created_at` = corrupt data, not pending).
- [x] 2.3 Guard the recovery-branch comment so `daysSince === null` renders `pending first run (never produced an issue)` instead of `null days ago`.
- [x] 2.4 Remove the `strategy-review` entry from `TASK_INVENTORY`.
- [x] 2.5 Update the INVENTORY SCOPE comment: add strategy-review to the excluded conditional-producer list + a one-line never-produced-grace note.
- [x] 2.6 Confirm GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts test/server/inngest/cron-shared.test.ts`; `tsc --noEmit` clean.

## Phase 3 — Runbook

- [x] 3.1 Remove strategy-review from the *Task Inventory* table and the *Threshold Derivation* table.
- [x] 3.2 Add strategy-review to the *Excluded NON-PRODUCERS (do not re-add)* table with the conditional-producer reason (liveness via Sentry `scheduled-strategy-review`).
- [x] 3.3 Add the never-produced-grace note (legal-audit worked example) near *When NOT to use* §3 / the Excluded-Non-Producers block.

## Phase 4 — Ship + issue lifecycle

- [ ] 4.1 PR body: 5 alerts #4873–#4877; 3 genuine + self-healing (link PR #4770 / #4870); 2 false positives fixed here; `Closes #4874` `Closes #4875`; `references #2714`; note rejected alternative + `warnSilentFallback` refinement.
- [ ] 4.2 Post-merge: `gh issue close 4874` with the conditional-producer root-cause comment (AC11).
- [ ] 4.3 Post-merge: `gh issue close 4875` with the never-fired/pending-first-run root-cause comment (AC12).
