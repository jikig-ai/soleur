# Tasks — Inngest-dispatch three more recurring crons

Plan: `knowledge-base/project/plans/2026-06-02-feat-inngest-dispatch-three-more-crons-plan.md`
Lane: cross-domain (no spec.md present → TR2 fail-closed default)

## 0. Preconditions
- [x] 0.1 Read `cron-terraform-drift.ts` + `cron-terraform-drift.test.ts` (literal templates).
- [x] 0.2 Read learning `2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md` (4 gotchas).
- [x] 0.3 Re-derive guard (a) baseline: `grep -cE '^[[:space:]]+\w+,$' apps/web-platform/app/api/inngest/route.ts` (expect 44; target = baseline + 3).
- [x] 0.4 Confirm the 3 workflows still have a `schedule:` block + matching cron strings.

## 1. Three Inngest dispatch functions (TDD: tests first)
- [x] 1.1 Write `test/server/inngest/cron-dev-migration-drift.test.ts` (mirror template; anchors `15 */6 * * *`, `scheduled-dev-migration-drift.yml`, event `cron/dev-migration-drift.manual-trigger`). RED.
- [x] 1.2 Write `server/inngest/functions/cron-dev-migration-drift.ts` (mirror template; relative `_cron-shared` import; no `inputs`). GREEN.
- [x] 1.3 Write `test/server/inngest/cron-main-health-monitor.test.ts` (anchors `0 */6 * * *`, `main-health-monitor.yml`, event `cron/main-health-monitor.manual-trigger`). RED.
- [x] 1.4 Write `server/inngest/functions/cron-main-health-monitor.ts`. GREEN. (NON-GOAL: must NOT run test-all.sh in-process.)
- [x] 1.5 Write `test/server/inngest/cron-review-reminder.test.ts` (anchors `0 0 1 * *`, `review-reminder.yml`, event `cron/review-reminder.manual-trigger`). RED.
- [x] 1.6 Write `server/inngest/functions/cron-review-reminder.ts` (dispatch with NO `inputs` → workflow defaults date to today). GREEN.
- [x] 1.7 Each fn: `(...args: unknown[])`-typed spies; failure-path asserts `.message` lacks token AND contains `[REDACTED-INSTALLATION-TOKEN]`.

## 2. Register the three functions
- [x] 2.1 `app/api/inngest/route.ts`: add 3 imports + 3 served entries (alphabetical: cronDevMigrationDrift, cronMainHealthMonitor, cronReviewReminder).
- [x] 2.2 `server/inngest/cron-manifest.ts`: add 3 `EXPECTED_CRON_FUNCTIONS` entries (alpha: dev-migration-drift after daily-triage; main-health-monitor after linkedin-token-check; review-reminder **before** roadmap-review — `review` < `roadmap` since `e` < `o`; plan's "after roadmap-review" was an alpha slip, corrected here. Ordering is convention-only; parity guards (b)/(e) check set membership, not order).
- [x] 2.3 `test/server/inngest/function-registry-count.test.ts`: bump guard (a) 44 → 47 (use Phase-0 re-derived literal).

## 3. Remove `schedule:` from the three workflows
- [x] 3.1 `.github/workflows/scheduled-dev-migration-drift.yml`: drop `schedule:`; keep `workflow_dispatch: {}`; fix trailing security comment (no longer triggers on `schedule`).
- [x] 3.2 `.github/workflows/main-health-monitor.yml`: drop `schedule:`; keep bare `workflow_dispatch:`.
- [x] 3.3 `.github/workflows/review-reminder.yml`: drop `schedule:`; keep `workflow_dispatch:` WITH `inputs.date_override`.
- [x] 3.4 `actionlint` each edited workflow; job bodies unchanged byte-for-byte otherwise.

## 4. Verification
- [x] 4.1 `cd apps/web-platform && bash scripts/test-all.sh` — read the `EXIT=` marker (tail-masking). Re-run timed-out webplat files in isolation before treating as regression.
- [x] 4.2 `tsc --noEmit` (webplat) clean.
- [x] 4.3 Confirm guards (a) 47, (b), (c), (c2), (d), (e), (f), (f2) green + `cron-substrate-imports.test.ts` green.
- [ ] 4.4 (post-merge, optional) smoke each manual-trigger via `/soleur:trigger-cron`; confirm a `workflow_dispatch` run via `gh run list --workflow=<file>`.
