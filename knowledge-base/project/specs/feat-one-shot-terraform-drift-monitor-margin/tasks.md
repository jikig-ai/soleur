---
title: "Tasks — fix scheduled-terraform-drift checkin_margin (GHA jitter)"
plan: knowledge-base/project/plans/2026-06-02-fix-terraform-drift-monitor-checkin-margin-plan.md
branch: feat-one-shot-terraform-drift-monitor-margin
lane: procedural
---

# Tasks

## Phase 1 — Edit the monitor config

- [ ] 1.1 In `apps/web-platform/infra/sentry/cron-monitors.tf`, change line 53 on the
      `scheduled_terraform_drift` resource: `checkin_margin_minutes  = 180` → `checkin_margin_minutes  = 480`.
- [ ] 1.2 Add a per-monitor rationale comment immediately above the
      `resource "sentry_cron_monitor" "scheduled_terraform_drift"` block (line 48), styled like the
      `scheduled_gh_pages_cert_state` (lines 224-234) and `scheduled_realtime_probe` (lines 157-166)
      blocks. Comment MUST contain: the word `jitter`; the observed max `339` (min); the value `480`;
      a reference to `scheduled_gh_pages_cert_state` and/or `scheduled_realtime_probe`; the survey date
      (2026-06-02); and a note that 480 < the 720-min inter-fire gap.

## Phase 2 — Local verification

- [ ] 2.1 `cd apps/web-platform/infra/sentry && terraform fmt` (write mode), then `terraform fmt -check`
      returns exit 0. Re-stage if `fmt` reformatted anything.
- [ ] 2.2 `grep -n "checkin_margin_minutes" apps/web-platform/infra/sentry/cron-monitors.tf` — confirm
      `scheduled_terraform_drift` shows `480` and no `= 180` remains anywhere in the file.
- [ ] 2.3 `grep -n` the new comment block for each required token (`jitter`, `339`, `480`,
      `scheduled_gh_pages_cert_state` or `scheduled_realtime_probe`, `2026-06-02`, `720`).
- [ ] 2.4 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts`
      passes unchanged (parity-only test; margin edit must not affect it).

## Phase 3 — Ship

- [ ] 3.1 Commit on this branch; PR body explains the false-alarm root cause + jitter survey.
      `Closes #<N>` is acceptable (the fix auto-applies in the same merge; no deferred operator step).
      Do NOT touch `.github/workflows/scheduled-terraform-drift.yml` or the `-target=` list in
      `apply-sentry-infra.yml`.

## Phase 4 — Post-merge (auto-applied; verify via CLI/API, no operator step)

- [ ] 4.1 `gh run list --workflow=apply-sentry-infra.yml --branch main --limit 3 --json conclusion,headSha`
      — the run on the merge commit concluded `success`.
- [ ] 4.2 Read-only GET against the Sentry monitors API with `SENTRY_AUTH_TOKEN` and assert
      `scheduled-terraform-drift` reports `checkin_margin_minutes == 480` (per
      `hr-no-dashboard-eyeball-pull-data-yourself` — pull the value, don't eyeball the dashboard).
- [ ] 4.3 Observe the next several fires: no new `scheduled-terraform-drift` missed-checkin/regressed
      issue opens for a successful-but-late run within 480 min of a fire.
