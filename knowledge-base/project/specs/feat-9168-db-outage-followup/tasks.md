---
feature: 9168-db-outage-followup
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-28-feat-9168-db-outage-followup-plan.md
created: 2026-09-28
---

# Tasks — DB-outage paging path + bounded Supabase auto-restart

## Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- [ ] **1.1** Write `scripts/supabase-watchdog-classify.test.sh` covering the
      Guard Contract matrix: exact-signature + corroboration →
      `hang-signature`; corroborator reachable-but-healthy or unreachable →
      `ambiguous`; pooler-also-unhealthy or extra service (e.g. `storage`)
      unhealthy → `ambiguous`; mid-window `COMING_UP`/missing key →
      `ambiguous`; empty/unparseable response → non-zero exit +
      `probe-unavailable`; cooldown marker inside window → no restart;
      `vars.WATCHDOG_ARMED` unset → detect-only verdict, zero write intent.
- [ ] **1.2** Pin the workflow contract in a parity test (mirroring
      `sentry-monitor-iac-parity.test.ts`): `workflow_dispatch` + `schedule:`
      triggers, `concurrency: supabase-watchdog` `cancel-in-progress: false`,
      `issues: write`.
- [ ] **1.3** Unit-test the sentinel-comment protocol: restart-attempt marker
      written at POST time; unparseable/absent sentinel on a claimed-restart
      run → fail-closed + error check-in.

## Phase 2 — Classifier + workflow (GREEN)

- [ ] **2.1** Write `scripts/supabase-watchdog-classify.sh` (pure predicate;
      bearer-on-stdin transport contract per `scripts/supabase-logs-query.sh`).
- [ ] **2.2** Write `.github/workflows/scheduled-supabase-watchdog.yml`:
      3 reads ~60s apart, corroborator fetch (app `/health`), classifier,
      `vars.WATCHDOG_ARMED` gate on the write, sentinel-comment protocol,
      never-retry on non-2xx/timeout restart POST, audit issue
      (label `supabase-auto-restart`), Sentry check-in via the composite.
- [ ] **2.3** Write
      `apps/web-platform/server/inngest/functions/cron-supabase-watchdog-dispatch.ts`
      (5-min cadence, `cron-main-health-monitor.ts` shape, GitHub App token,
      `permissions: {actions: write}` scope) and register in
      `cron-manifest.ts`.
- [ ] **2.4** Add the Sentry cron monitor in
      `apps/web-platform/infra/sentry/cron-monitors.tf` (margin ~30 min).

## Phase 3 — Alerting + Terraform

- [ ] **3.1** `push = true` on `betteruptime_monitor.app_health`
      (`uptime-alerts.tf`); document the revert-on-vendor-refusal plan.
- [ ] **3.2** `main.tf`: `supabase/supabase` in `required_providers` (pin ≥7d
      old) + `provider "supabase" { access_token = var.supabase_access_token }`.
- [ ] **3.3** `supabase-project.tf`: import block + resource with the measured
      live values (`organization_id = "vttwegzidmuaiefjlysl"`,
      `name = "soleur-web-platform"`, `region = "eu-west-1"`,
      `instance_size = "micro"`, `legacy_api_keys_enabled = true`,
      `database_password = "unmanaged-9168"` + `ignore_changes`). Commit the
      `.terraform.lock.hcl` diff after `terraform init`.
- [ ] **3.4** `apply-web-platform-infra.yml`: `-target=supabase_project.prd`
      allowlist entry + keep `terraform-target-parity.test.ts` green.

## Phase 4 — Artifacts

- [ ] **4.1** 2026-09-28 postmortem (09-15 template; every action item cites a
      filed issue).
- [ ] **4.2** Support-ticket draft (minimized evidence; both windows).
- [ ] **4.3** ADR-260 (provisional ordinal — re-verify next-free at ship).
- [ ] **4.4** `model.c4`/`views.c4`: `slack` element + `betterstack -> slack`,
      `slack -> founder`, `github -> supabase` edges; amend
      `betterstack -> founder` prose; run C4 tests.
- [ ] **4.5** Runbook update (Slack primary; watchdog behavior; ops@ invite).
- [ ] **4.6** `expenses.md` + `cost-model.md`: Small +$5/mo recorded; Responder
      deferral trigger-fired note.

## Phase 5 — Verify

- [ ] **5.1** `terraform fmt -check` + `terraform validate` on the root.
- [ ] **5.2** `bash scripts/supabase-watchdog-classify.test.sh` green.
- [ ] **5.3** Related lints/tests green (target parity, sentry parity, C4,
      inngest manifest tests).

## Operator steps (credential-entry only — non-blocking for merge)

- Connect Better Stack → Slack (one-time dashboard OAuth).
- Submit the committed Supabase ticket draft via the dashboard.
- Confirm `ops@jikigai.com` Better Stack invite accepted.
- Set `vars.WATCHDOG_ARMED=1` after the detect-only soak validates.
- Follow-up PR: flip `instance_size` to `"small"` (operator watches ~2 min
  resize); remove the `import` block post-apply (ADR-222 convention).
