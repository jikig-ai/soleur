---
module: Inngest substrate
date: 2026-05-30
problem_type: integration_issue
component: inngest_cron
symptoms:
  - "Sentry cron monitors scheduled-gh-pages-cert-state + scheduled-community-monitor flagged Regressed"
  - "cert-state last OK 2026-05-26T06:48:18Z (incident 5032155); community last OK 2026-05-25T11:56:14Z (incident 5010688)"
root_cause: inngest_cron_trigger_desync_after_deploy_churn_recurred
severity: high
tags: [inngest, sentry, cron, deploy-churn, self-healing, regression, watchdog]
synced_to: []
---

# Learning: an Inngest cron-trigger desync needs a runtime self-heal, not a build-time CI guard

## Problem

Two Sentry cron monitors regressed on 2026-05-30: `scheduled-gh-pages-cert-state`
(incident 5032155, last OK 2026-05-26T06:48:18Z) and `scheduled-community-monitor`
(incident 5010688, last OK 2026-05-25T11:56:14Z). Both are Inngest cron functions
on the self-hosted Hetzner server. They stopped checking in within ~1 day of each
other → shared-substrate failure: the server drops (H9a) or de-plans (H9b) cron
triggers after deploy churn (`web-platform-release.yml` redeploys the container on
every `apps/web-platform/**` merge; each restart fires an SDK function-sync PUT).

This was a **regression** of the 2026-05-27 community-monitor incident
(`2026-05-27-sentry-cron-community-monitor-missed-checkin.md`). The
`auth-callback-no-code-burst` line in the Sentry emails was a red-herring
alert-routing artifact (same as the prior incident).

## Why the prior remediation was insufficient

The prior fix (issue #4533, closed COMPLETED 2026-05-27, PR #4531) shipped **only**
`function-registry-count.test.ts` — a *build-time source-parity* check (route.ts
count, cron-file↔route parity, slug↔terraform parity) — and **deferred** the
operational restart. A source-parity test proves the *source* is internally
consistent; it says nothing about the *running server's scheduler state*. H9 is
precisely "source consistent, running scheduler de-planned". The guard was green
throughout the outage. The failure recurred.

The other existing guards have the same blind spot:
- `inngest-heartbeat.timer` → Better Stack (`/health` 200) proves only that the
  **process is alive**. H9 = "process alive, cron de-planned" → green throughout.
- `restart-inngest-server.yml`'s verify step curled `/health`, not `/v1/functions`
  — it reported "healthy" even when triggers were still missing.

## Key Insight

**Liveness ≠ plan integrity.** Any check that probes `/health` proves the process
is up, never that its cron schedule is planned. A desync that survives a restart's
function-resync but not its cron-replan (H9b) passes every `/health` gate while
every monitored cron stays dead. The only honest signal is asserting the running
server's `/v1/functions` registry lists each expected function **with a cron
trigger**. A build-time test can never observe this; it requires a runtime probe.

**Re-sync asymmetry (load-bearing).** The server's `inngest start` ExecStart
(`inngest-bootstrap.sh`) sets no `--poll-interval` / `--sdk-url`, so function
discovery is bound to container restart, not polling. Consequence: H9a (dropped)
genuinely needs a restart/redeploy to re-sync; H9b (de-planned) is recoverable by
a manual-trigger event alone. A correct self-heal must implement BOTH paths — a
single mechanism is wrong for one of the two modes.

## Solution (this PR)

**(a) Immediate restoration:** dispatched `restart-inngest-server.yml` (run
26682039359, success) — re-syncs all functions + re-plans cron triggers at the
substrate level. Baseline + recovery recorded on issue #4650 via the Sentry Crons
API (no dashboard eyeballing).

**(b) Durable self-healing watchdog** (`cron-inngest-cron-watchdog.ts`, every 4h):
- Queries the running `/v1/functions` registry over the container's loopback
  bridge (`host.docker.internal:8288`, no SSH); classifies an
  `EXPECTED_CRON_FUNCTIONS` manifest as OK / MISSING (H9a) / UNPLANNED (H9b). A
  parity test (`function-registry-count.test.ts (e)`) keeps the manifest in
  lockstep with the cron-file set.
- H9b → fires `cron/<name>.manual-trigger` via `sendInngestWithRetry`.
- H9a → POSTs the deploy webhook restart (D1-A), falling back to a label-dispatched
  restart (D1-B, `inngest-watchdog-restart-dispatch.yml`); gated by a
  restart-survivable cooldown (`/var/lib/inngest/cron-watchdog/`, 6h > the 4h
  interval) so a persistent desync cannot restart-loop.
- Posts an `ok`/`error` Sentry heartbeat; `ok=false` pages on any defect.
- Closed the verify gap: `ci-deploy.sh verify_inngest_health` now asserts
  `/v1/functions` has ≥1 cron-triggered function after restart, not just `/health`.

The operational/automation piece is shipped this cycle — NOT deferred (unlike
#4533). Soleur operators are non-technical and cannot SSH
(never-defer-operator-actions, `hr-no-ssh-fallback-in-runbooks`).

## Sharp edges encountered

- The watchdog rides the substrate it monitors — a full-substrate H9a can drop the
  watchdog itself. Defended by (a) restart re-syncs ALL functions including the
  watchdog, (b) the watchdog's own Sentry monitor catches a watchdog miss.
- A manual-trigger RUNS the handler but does NOT re-plan the cron schedule; a
  recurring H9b keeps surfacing as a recurring `ok=false` heartbeat → escalate to
  restart. Do not treat one manual-trigger as a permanent H9b fix.
- Cooldown state must live on the host-bind-mounted `/var/lib/inngest/`, not in
  process memory — an in-memory cooldown is cleared by the very restart it gates.

## Cross-References

- Runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` (H9 → "Self-healing (automated)")
- Prior incident: `knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md`
- Plan: `knowledge-base/project/plans/2026-05-30-fix-inngest-cron-trigger-self-heal-watchdog-plan.md`
- Issue: #4650 · Sentry incidents 5032155, 5010688
