---
title: "Tasks — TR9 PR-6 strategy-review Inngest migration"
date: 2026-05-25
plan: knowledge-base/project/plans/2026-05-25-feat-tr9-pr6-strategy-review-inngest-migration-plan.md
issue: 4416
umbrella: 3948
lane: single-domain
---

# Tasks — TR9 PR-6 (scheduled-strategy-review → Inngest)

## Phase 0 — Preflight

- [ ] 0.1 Verify reference file: `ls apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` (PR-5 reference, 1226 lines)
- [ ] 0.2 Verify umbrella state: `gh issue view 3948 --json title,state` returns OPEN
- [ ] 0.3 Verify child issue: `gh issue view 4416` returns OPEN
- [ ] 0.4 Verify migration source files present: `git ls-files | grep -E "scripts/strategy-review-check.sh|.github/workflows/scheduled-strategy-review.yml"` returns BOTH
- [ ] 0.5 Confirm `cron_run_ledger` reconciliation: `grep -rn cron_run_ledger apps/web-platform/ supabase/migrations/` returns ZERO
- [ ] 0.6 Read existing route.ts registry to determine alphabetical insertion slot

## Phase 1 — Author Inngest function

- [ ] 1.1 Create `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` per plan §Phase 1 outline
- [ ] 1.2 Helpers: `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `buildSpawnEnv` (drops ANTHROPIC_API_KEY — not needed), `setupEphemeralWorkspace` (drops plugin symlink), `teardownEphemeralWorkspace`
- [ ] 1.3 `spawnStrategyReview` with AbortController (10 min) + SIGTERM→SIGKILL escalation (5s) + stdout/stderr pipe through redactToken
- [ ] 1.4 `postSentryHeartbeat` — single-step end-of-step.run POST (per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`)
- [ ] 1.5 `cronStrategyReviewHandler` — 5 step.run blocks: mint-installation-token → setup-workspace → strategy-review-check → sentry-heartbeat + finally:teardown
- [ ] 1.6 Validate manual-trigger `event.data.date_override` (regex `^\d{4}-\d{2}-\d{2}$`) before threading into spawn env as `DATE_OVERRIDE`
- [ ] 1.7 Register via `inngest.createFunction` with `id: "cron-strategy-review"`, concurrency keys (`fn`=1, `account`=`"cron-platform"`=1), triggers `[{ cron: "0 8 * * 1" }, { event: "cron/strategy-review.manual-trigger" }]`, retries=1

## Phase 2 — Register in route.ts

- [ ] 2.1 Edit `apps/web-platform/app/api/inngest/route.ts`: add `import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";` in alpha order
- [ ] 2.2 Add `cronStrategyReview,` to the `functions: [...]` array in alpha order

## Phase 3 — Add Sentry cron monitor

- [ ] 3.1 Edit `apps/web-platform/infra/sentry/cron-monitors.tf`: add `sentry_cron_monitor.scheduled_strategy_review` resource per plan §Phase 3 block (max_runtime=10, checkin_margin=30, schedule `0 8 * * 1`)
- [ ] 3.2 Verify: `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform validate` exits 0

## Phase 4 — DELETE GHA workflow

- [ ] 4.1 `git rm .github/workflows/scheduled-strategy-review.yml`
- [ ] 4.2 Confirm `scripts/strategy-review-check.sh` is UNCHANGED (not deleted)

## Phase 5 — Capture learning

- [ ] 5.1 Write `knowledge-base/project/learnings/<date>-tr9-pr6-strategy-review-shell-only-no-claude-eval-pattern.md` — pattern: "shell-only cron drops claude-eval surface; first TR9 child with no LLM"

## Phase 6 — Test

- [ ] 6.1 `cd apps/web-platform && bun test test/server/cron-no-byok-lease-sweep.test.ts` passes; output enumerates `cron-strategy-review.ts`
- [ ] 6.2 `cd apps/web-platform && bun run typecheck` exits 0
- [ ] 6.3 `cd apps/web-platform/infra/sentry && terraform validate` exits 0

## Phase 7 — Commit + PR

- [ ] 7.1 Stage all changes (NEW ts file, route.ts edit, cron-monitors.tf edit, YAML delete, learning) in a SINGLE commit
- [ ] 7.2 Verify atomic landing: `git show HEAD --name-status` shows all 5 paths in one commit
- [ ] 7.3 Push branch; open PR with body per plan §PR Body Template; ensure `Closes #4416` in body (NOT title; NOT umbrella #3948)
- [ ] 7.4 Run `/soleur:ship` for the pre-merge gate sequence

## Phase 8 — Post-merge

- [ ] 8.1 Verify `apply-sentry-infra.yml` ran successfully on the merge SHA: `gh run list --workflow=apply-sentry-infra.yml --limit=1 --json status,conclusion`
- [ ] 8.2 Fire manual trigger to confirm function registered: `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` (from Hetzner host)
- [ ] 8.3 Confirm Sentry monitor `scheduled-strategy-review` shows fresh `ok` check-in
- [ ] 8.4 Verify umbrella #3948 body updated: `scheduled-strategy-review` line marked done with PR-6 link
- [ ] 8.5 Confirm issue #4416 closed via PR merge auto-close
