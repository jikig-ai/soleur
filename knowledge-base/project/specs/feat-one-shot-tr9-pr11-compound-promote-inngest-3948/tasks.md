# Tasks — TR9 PR-11 compound-promote Inngest migration

Plan: `knowledge-base/project/plans/2026-05-25-feat-tr9-pr11-compound-promote-inngest-plan.md`

## Phase 0 — Preconditions & invariants

- [ ] 0.1. Verify worktree CWD
- [ ] 0.2. Read all three references: `cron-strategy-review.ts`, `cron-roadmap-review.ts`, `scripts/compound-promote.sh`
- [ ] 0.3. Read guard tests: `cron-strategy-review-graymatter.test.ts`, `cron-no-byok-lease-sweep.test.ts`
- [ ] 0.4. Read `apps/web-platform/app/api/inngest/route.ts` registration pattern
- [ ] 0.5. Read `apps/web-platform/infra/sentry/cron-monitors.tf` PR-7 resource template
- [ ] 0.6. Confirm `compound-promote` label does NOT exist; use `self-healing/auto`

## Phase 1 — RED tests

- [ ] 1.1. Create `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` (AC8–AC18)
- [ ] 1.2. Create `apps/web-platform/test/server/inngest/cron-compound-promote-graymatter.test.ts`
- [ ] 1.3. Confirm all tests FAIL

## Phase 2 — GREEN handler implementation

- [ ] 2.1. Write `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` (~500 LoC). ALL GitHub API calls via Octokit (NOT `gh` CLI — absent from Hetzner Dockerfile).
- [ ] 2.2. Run vitest until every test passes

## Phase 3 — Wire-up

- [ ] 3.1. Edit `apps/web-platform/app/api/inngest/route.ts` (import + array entry)
- [ ] 3.2. Edit `apps/web-platform/infra/sentry/cron-monitors.tf` (new `scheduled_compound_promote` resource)
- [ ] 3.3. Edit `.github/workflows/apply-sentry-infra.yml` — append BOTH `-target=sentry_cron_monitor.scheduled_stale_deferred_scope_outs` (missing from PR #4457) AND `-target=sentry_cron_monitor.scheduled_compound_promote`
- [ ] 3.4. Delete `.github/workflows/scheduled-compound-promote.yml`
- [ ] 3.5. Add banner comments to `scripts/compound-promote.sh` and `scripts/compound-promote.test.sh`

## Phase 4 — Runbook

- [ ] 4.1. Update `knowledge-base/engineering/ops/runbooks/compound-promote-runbook.md`

## Phase 5 — CI green + multi-agent review

- [ ] 5.1. `bun tsc --noEmit` + `bun vitest run` + lint
- [ ] 5.2. Push branch, open draft PR with `Refs #3948`
- [ ] 5.3. Multi-agent review (handled by one-shot pipeline)

## Phase 6 — Substrate extraction tracking issue

- [ ] 6.1. `gh issue create --label priority/p3-low,domain/engineering,type/chore` with extraction proposal
- [ ] 6.2. Reference new issue in PR body
