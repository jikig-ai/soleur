# Decision Challenges — feat-one-shot-6902-encryption-posture-layer-b-reconcile

Headless plan-phase challenges to the operator's *stated direction* (issue #6902). The operator's
direction is the default; these are surfaced (not silently applied) per ADR-084. `ship` renders these
into the PR body + files an `action-required` issue.

## Challenge 1 — Dedicated Sentry cron-monitor deferred (not built this increment)

- **Operator's stated direction (issue #6902):** "Use the Sentry cron-monitor plane (NOT Better
  Stack) so `sentry-monitor-iac-parity.test.ts` covers it."
- **Challenge (architecture-strategist, agreed by plan):** `sentry-monitor-iac-parity.test.ts` is
  **workflow-step-granular** — it requires a `sentry_cron_monitor` resource only for a workflow that
  carries a `monitor-slug:` heartbeat step. The Layer B reconcile is added as a **job** in the
  already-monitored `scheduled-terraform-drift.yml`, so it triggers **no** parity requirement. Minting
  a NEW dedicated `failure_issue_threshold=1` cron-monitor on a twice-daily **disarmed** (near-no-op)
  probe is a **false-MISSED-page generator** (the parity test's own comment warns a crontab monitor
  "pages MISSED forever").
- **Plan default:** DEFER the dedicated Sentry monitor + `cron-monitors.tf` edit + parity coverage to
  the **armed reconcile** (when there is a real drift-SLO to protect). This increment's failures are
  still observable via `::error::` + `notify-ops-email` + a failed job, plus the workflow-level Sentry
  monitor that already pages if the whole workflow stops dispatching.
- **Operator override path:** if you want the dedicated monitor now, add the `sentry_cron_monitor`
  resource to `cron-monitors.tf` + a `monitor-slug: scheduled-encryption-posture-reconcile` heartbeat
  step to the job; the parity test will then require and cover it.

## Challenge 2 — No new Inngest fn / workflow (ride the existing one)

- **Operator's stated direction (issue #6902):** "a `cron-encryption-posture-reconcile.ts` owns the
  schedule and workflow_dispatch-es an `on: workflow_dispatch:`-only workflow."
- **Challenge (architecture-strategist, agreed by plan):** that mints a **second Inngest fn + second
  schedule** for an infra-drift-shaped concern that already has a living precedent —
  `heartbeat-live-reconcile` in the SAME file is literally the same shape (read live state → reconcile
  against a manifest → find-or-update issues) and is a **job**, not a workflow. A new substrate
  **violates ADR-033 single-substrate** and is costly to unwind once `cron-terraform-drift.ts` /
  IaC-parity wiring references it.
- **Plan default:** add the reconcile as a **job** in `scheduled-terraform-drift.yml` — no new `.ts`,
  no new schedule, no new Inngest fn. Accepts (consciously, recorded in ADR-141) that the reconcile
  cadence is coupled to terraform-drift's; both are infra-drift on the same substrate.
- **Operator override path:** if a distinct cadence/substrate is required later, split it out with the
  armed reconcile.
