# Tasks — Inngest-dispatch three more recurring crons

Plan: `knowledge-base/project/plans/2026-06-02-feat-inngest-dispatch-three-more-crons-plan.md`
Lane: cross-domain (no spec.md present → TR2 fail-closed default)

## 0. Preconditions
- [ ] 0.1 Read `cron-terraform-drift.ts` + `cron-terraform-drift.test.ts` (literal templates).
- [ ] 0.2 Read learning `2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md` (4 gotchas).
- [ ] 0.3 Re-derive guard (a) baseline: `grep -cE '^[[:space:]]+\w+,$' apps/web-platform/app/api/inngest/route.ts` (expect 44; target = baseline + 3).
- [ ] 0.4 Confirm the 3 workflows still have a `schedule:` block + matching cron strings.

## 1. Three Inngest dispatch functions (TDD: tests first)
- [ ] 1.1 Write `test/server/inngest/cron-dev-migration-drift.test.ts` (mirror template; anchors `15 */6 * * *`, `scheduled-dev-migration-drift.yml`, event `cron/dev-migration-drift.manual-trigger`). RED.
- [ ] 1.2 Write `server/inngest/functions/cron-dev-migration-drift.ts` (mirror template; relative `_cron-shared` import; no `inputs`). GREEN.
- [ ] 1.3 Write `test/server/inngest/cron-main-health-monitor.test.ts` (anchors `0 */6 * * *`, `main-health-monitor.yml`, event `cron/main-health-monitor.manual-trigger`). RED.
- [ ] 1.4 Write `server/inngest/functions/cron-main-health-monitor.ts`. GREEN. (NON-GOAL: must NOT run test-all.sh in-process.)
- [ ] 1.5 Write `test/server/inngest/cron-review-reminder.test.ts` (anchors `0 0 1 * *`, `review-reminder.yml`, event `cron/review-reminder.manual-trigger`). RED.
- [ ] 1.6 Write `server/inngest/functions/cron-review-reminder.ts` (dispatch with NO `inputs` → workflow defaults date to today). GREEN.
- [ ] 1.7 Each fn: `(...args: unknown[])`-typed spies; failure-path asserts `.message` lacks token AND contains `[REDACTED-INSTALLATION-TOKEN]`.

## 2. Register the three functions
- [ ] 2.1 `app/api/inngest/route.ts`: add 3 imports + 3 served entries (alphabetical: cronDevMigrationDrift, cronMainHealthMonitor, cronReviewReminder).
- [ ] 2.2 `server/inngest/cron-manifest.ts`: add 3 `EXPECTED_CRON_FUNCTIONS` entries (alpha: dev-migration-drift after daily-triage; main-health-monitor after linkedin-token-check; review-reminder after roadmap-review, before rule-prune).
- [ ] 2.3 `test/server/inngest/function-registry-count.test.ts`: bump guard (a) 44 → 47 (use Phase-0 re-derived literal).

## 3. Remove `schedule:` from the three workflows
- [ ] 3.1 `.github/workflows/scheduled-dev-migration-drift.yml`: drop `schedule:`; keep `workflow_dispatch: {}`; fix trailing security comment (no longer triggers on `schedule`).
- [ ] 3.2 `.github/workflows/main-health-monitor.yml`: drop `schedule:`; keep bare `workflow_dispatch:`.
- [ ] 3.3 `.github/workflows/review-reminder.yml`: drop `schedule:`; keep `workflow_dispatch:` WITH `inputs.date_override`.
- [ ] 3.4 `actionlint` each edited workflow; job bodies unchanged byte-for-byte otherwise.

## 4. Verification
- [ ] 4.1 `cd apps/web-platform && bash scripts/test-all.sh` — read the `EXIT=` marker (tail-masking). Re-run timed-out webplat files in isolation before treating as regression.
- [ ] 4.2 `tsc --noEmit` (webplat) clean.
- [ ] 4.3 Confirm guards (a) 47, (b), (c), (c2), (d), (e), (f), (f2) green + `cron-substrate-imports.test.ts` green.
- [ ] 4.4 (post-merge, optional) smoke each manual-trigger via `/soleur:trigger-cron`; confirm a `workflow_dispatch` run via `gh run list --workflow=<file>`.
