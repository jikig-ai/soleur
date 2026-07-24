# Decision Challenges — feat-one-shot-6902-encryption-posture-layer-b-reconcile

Headless plan-phase challenges to the operator's *stated direction* (issue #6902). The operator's
direction is the default; these are surfaced (not silently applied) per ADR-084. `ship` renders these
into the PR body + files an `action-required` issue.

## Challenge 1 (LOAD-BEARING) — The Layer B live-reconcile cron is DEFERRED almost entirely

- **Operator's stated direction (issue #6902):** build an Inngest-dispatched, Sentry-cron-monitored
  live reconcile of `encryption-posture-ledger.json` against actual provider/host state
  (`cron-encryption-posture-reconcile.ts` → `workflow_dispatch` workflow, shelling out to
  `lint-encryption-posture.py --report --json`, positive-work floor over `live_verification:available`
  rows).
- **Challenge (code-simplicity/YAGNI, corroborated by architecture-strategist + verify-the-negative):**
  `lint-encryption-posture.py --json` emits the **committed ledger verbatim** and is **hermetic** (no
  network/host/SSH — `scripts/lint-encryption-posture.py:54, 1006-1012`). So `live_verification` is a
  **static committed string, not a measured live signal**, and the runner has **no independent live
  signal** for any store (the one measurable volume, `workspaces_luks`, is host-probe-backed via
  `luks-monitor.sh`, not runner-reconcilable — Hetzner API blind to guest LUKS, SSH forbidden). A
  twice-daily cron comparing two static committed files adds **zero detection value** over a single
  PR-time assertion and degrades it (bad commit → hours-later email vs blocked at PR time). It also
  violates the layering boundary the plan itself names (design-time checks belong in Layer A).
- **Plan default (near-total DEFER — the #6901 measure-then-arm pattern the mandate blessed):** ship
  **ADR-141** (the decision record), a small **Layer A** positive-work floor (`≥1
  live_verification:available` row, PR-time, no cron), and a **Layer B tracking issue** for the armed
  live reconcile gated on the per-volume emitters. Build the live reconcile only when an emitter gives
  the runner a real signal.
- **Operator override path:** if you want the cron now, it can be added as a job on the existing
  `scheduled-terraform-drift.yml` (ADR-033 single-substrate) — but understand it will re-read a static
  file and cannot detect anything a PR-time Layer A check doesn't already block.

## Challenge 2 — No new Inngest fn / workflow (if the reconcile is ever built, ride the existing job)

- **Operator's stated direction:** a new `cron-encryption-posture-reconcile.ts` + a new
  `workflow_dispatch` workflow.
- **Challenge (architecture-strategist):** that mints a second Inngest fn + schedule for an
  infra-drift-shaped concern that already has a precedent — `heartbeat-live-reconcile` in
  `scheduled-terraform-drift.yml` is the same shape (live read → manifest reconcile →
  find-or-update-by-title) and is a **job**, not a workflow. A new substrate violates ADR-033.
- **Plan default:** recorded in ADR-141 — if/when the armed reconcile is built, it rides the existing
  job. No new substrate.

## Challenge 3 — Dedicated Sentry cron-monitor deferred

- **Operator's stated direction:** "use the Sentry cron-monitor plane so
  `sentry-monitor-iac-parity.test.ts` covers it."
- **Challenge (architecture-strategist):** the parity guard is workflow-step-granular; with no cron
  built this increment, no monitor is required, and a `failure_issue_threshold=1` monitor on a
  static-input probe is a false-MISSED-page generator.
- **Plan default:** deferred with the armed reconcile (which is when a real drift-SLO exists).
