# Tasks — TR9 PR-5 bug-fixer → Inngest

Source: `knowledge-base/project/plans/2026-05-24-feat-tr9-pr5-bug-fixer-inngest-migration-plan.md`

## Phase 0 — Pre-implementation verification

- [x] P0.1 Sharp Edge #6 — verify `/mnt/data/repos/jikig-ai-soleur` exists via Terraform/cloud-init inspection (NO SSH).
  - **Result:** does NOT exist. Cloud-init has no `git clone --bare` or `/mnt/data/repos` refs.
  - **Resolution:** in-handler fallback (option c) — clone via installation token into ephemeral workspace per cron fire. ~30s setup, absorbable.

## Phase 1 — Implementation

- [ ] T1 Create `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` (handler + helpers, ~600 LoC)
- [ ] T2 Create `apps/web-platform/test/server/cron-bug-fixer.test.ts` (~300 LoC, AC16 5-case test matrix)
- [ ] T3 Register `cronBugFixer` in `apps/web-platform/app/api/inngest/route.ts`
- [ ] T4 Add `sentry_cron_monitor.scheduled_bug_fixer` to `apps/web-platform/infra/sentry/cron-monitors.tf`
- [ ] T5 Delete `.github/workflows/scheduled-bug-fixer.yml`

## Phase 2 — Verification gates

- [ ] G1 `bun run typecheck` PASS
- [ ] G2 `vitest cron-bug-fixer.test.ts` ALL GREEN
- [ ] G3 `vitest cron-no-byok-lease-sweep.test.ts` (AC17 BYOK sweep auto-extends)
- [ ] G4 `vitest cron-daily-triage.test.ts` (PR-1 sibling regression check)
- [ ] G5 `terraform validate` on `apps/web-platform/infra/sentry/`
- [ ] G6 `scripts/test-all.sh` EXIT=0
