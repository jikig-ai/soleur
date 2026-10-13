---
title: "Tasks: terraform-drift Inngest-dispatch migration"
branch: feat-one-shot-terraform-drift-inngest-dispatch
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-feat-terraform-drift-inngest-dispatch-plan.md
---

# Tasks — terraform-drift Inngest-dispatch migration

Derived from `2026-06-02-feat-terraform-drift-inngest-dispatch-plan.md`. Design A (no own Sentry
monitor) is the recommended path; Design B tasks (1.x-B) are conditional on review adjudication.

## Phase 1 — New Inngest cron function (dispatch-only)
- [ ] 1.1 Create `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts` with header
      comment (dispatch-hybrid rationale, HARD NON-GOAL, ADR-033 reference).
- [ ] 1.2 Implement handler: `step.run("mint-installation-token", …)` via `mintInstallationToken`.
- [ ] 1.3 Implement `step.run("dispatch-workflow", …)`: `@octokit/core` request
      `POST …/actions/workflows/{workflow_id}/dispatches` with `workflow_id: "scheduled-terraform-drift.yml"`, `ref: "main"`.
- [ ] 1.4 Error path: `catch` → `redactToken` + `reportSilentFallback`; return `{ ok: false }`.
      Success: `return { ok: true }`. NO `postSentryHeartbeat`, NO `SENTRY_MONITOR_SLUG` (Design A).
- [ ] 1.5 `inngest.createFunction({ id, concurrency [fn=1, account "cron-platform"=1], retries: 1 },
      [{ cron: "0 6,18 * * *" }, { event: "cron/terraform-drift.manual-trigger" }], handler)`.
- [ ] 1.6 (RED first) Create `test/server/inngest/cron-terraform-drift.test.ts`: registration-shape
      smoke + dispatch-call assertion (mock octokit; assert POST shape + `ref: "main"`).
- [ ] _(1.x-B, Design B only)_ Add `SENTRY_MONITOR_SLUG = "scheduled-terraform-drift-dispatcher"` +
      `postSentryHeartbeat(ok)` on success.

## Phase 2 — GHA workflow becomes dispatch-only
- [ ] 2.1 Remove the `schedule:` block (lines 11-12) from `.github/workflows/scheduled-terraform-drift.yml`; keep `workflow_dispatch:`.
- [ ] 2.2 Update header comment to note Inngest-dispatched (`cron-terraform-drift.ts`), workflow_dispatch-only.
- [ ] 2.3 Confirm `jobs.drift-check` (setup-terraform, Doppler prd_terraform, R2/AWS, `terraform plan -detailed-exitcode`, drift/error email, `sentry-heartbeat`) is UNCHANGED.

## Phase 3 — Register the function
- [ ] 3.1 Add `"cron-terraform-drift"` to `EXPECTED_CRON_FUNCTIONS` (cron-manifest.ts, alphabetical before `cron-ux-audit`).
- [ ] 3.2 Add import + `cronTerraformDrift,` to `app/api/inngest/route.ts` served array (alphabetical).
- [ ] 3.3 Bump `function-registry-count.test.ts` guard (a) `43 → 44`.
- [ ] 3.4 Confirm manual-trigger allowlist auto-updates (derived) — no edit to `lib/inngest/manual-trigger-allowlist.ts`.

## Phase 4 — Retune Sentry monitor margin
- [ ] 4.1 `cron-monitors.tf` `sentry_cron_monitor.scheduled_terraform_drift` `checkin_margin_minutes` 480 → 60.
- [ ] 4.2 Rewrite the rationale comment (Inngest-dispatched, ≤2-min jitter; cite this PR + superseded #4772).
- [ ] _(4.x-B, Design B only)_ Add new `scheduled_terraform_drift_dispatcher` resource + `-target=` line in apply-sentry-infra.yml.

## Phase 5 — ADR / docs
- [ ] 5.1 Read ADR-033; append a migration entry IF it carries an enumerated list.

## Phase 6 — Verify
- [ ] 6.1 `tsc --noEmit` green.
- [ ] 6.2 `./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts` + new function test green.
- [ ] 6.3 Full vitest suite green.
- [ ] 6.4 Walk Acceptance Criteria AC1-AC10 (pre-merge); record AC11-AC12 as post-merge automated checks.
