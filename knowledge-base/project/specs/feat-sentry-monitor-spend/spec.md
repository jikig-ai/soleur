---
title: Sentry monitor spend — raise cap, fix the IaC delete path, detect drift
feature: feat-sentry-monitor-spend
date: 2026-07-17
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-17-sentry-monitor-spend-brainstorm.md
issue: 6589
pr: 6582
status: draft
---

# Spec — Sentry monitor spend

## Problem Statement

Sentry alerted that cron + uptime monitors consumed **$42.22 / $50.00 (84%)** of the
monthly pay-as-you-go budget for org `jikigai-eu`. Investigation found the bill is a
**fixed per-monitor seat charge** (`49 × $0.78 + 4 × $1.00 = $42.22` exactly), not an
accruing burn — but it sits **9 monitors** from an **all-or-nothing cliff**: at the next
billing period, if PAYG cannot cover all active monitors, *every* monitor deactivates and
check-ins are silently dropped (precedent: **#3958**, 7/8 monitors disabled).

The root cause of the growth is that **the IaC delete path is a silent no-op**.
`apply-sentry-infra.yml` runs `terraform plan` scoped to a hand-maintained `-target=`
allowlist, so removing a resource block from `cron-monitors.tf` never destroys the live
monitor. Monitor count has gone **8 → 49 in two months, monotonically, never once
decreasing** — not because nobody retires monitors, but because retiring one does not work.
This footgun has fired at least twice (#4929's alert rule; #6034/#6074's monitor, which is
live today and has carried an unresolved incident for 12 days).

Separately, `knowledge-base/operations/expenses.md:37` understates Sentry by
**$31.22/mo (~$375/yr)** — recorded `$40.00`, actual `$71.22` ($29 base + $42.22 PAYG).

## Goals

- **G1** — Remove the all-or-nothing deactivation cliff at zero recurring cost.
- **G2** — Make the ledger truthful about the largest single product-COGS line.
- **G3** — Make Sentry resource deletion actually delete, so monitor count can go down.
- **G4** — Make live↔IaC drift detectable, so a leak surfaces within a day instead of never.
- **G5** — Reclaim the identified dead spend ($3.34/mo) and kill the 12-day false incident.

## Non-Goals

- **NG1** — Buying reserved volume. **It does not exist** for monitors
  ([getsentry/sentry#73359](https://github.com/getsentry/sentry/issues/73359), closed
  unshipped). $0.78/$1.00 PAYG are the only rates.
- **NG2** — Migrating crons to Better Stack. Costs **2.5×** ($2.00/heartbeat) with only
  ~4 free slots left in a shared 10-unit pool. Sentry is the cheaper venue.
- **NG3** — Deep prune to ~16 monitors. Reverses **ADR-031**'s deliberate monitor-per-cron
  decision. Deferred (see Deferred Work).
- **NG4** — Amending ADR-031's "monitor every cron" policy. Deferred.
- **NG5** — Touching `scheduled_github_app_drift_guard`. Register-cited Art. 33 primitive.

## Functional Requirements

- **FR1** — Raise the Sentry PAYG cap (`onDemandMaxSpend`) from **$50 → $75** for org
  `jikigai-eu`. Must draw **$0** while undrawn. Ships first, independently of FR3–FR6.
- **FR2** — Correct `knowledge-base/operations/expenses.md:37`: `Amount` `40.00` → `71.22`;
  replace the stale "~$11 expected PAYG (estimate: 14 backfilled × ~$0.78)" note with the
  verified arithmetic (`49 × $0.78 + 4 × $1.00 = $42.22`, monitor-count-driven, fixed) and
  close the row's unresolved "verify actual draw on the 2026-06-17 invoice" TODO.
  Row format (`expenses.md:9`): `| Service | Provider | Category | Amount | Status | Renewal Date | Notes |`.
- **FR3** — Replace the hand-maintained `-target=` allowlist in `apply-sentry-infra.yml`
  with a full-root `terraform plan`/`apply`, keeping the `[ack-destroy]` gate and the
  `[skip-sentry-apply]` kill switch intact. After FR3, removing a resource block destroys
  the live resource.
- **FR4** — Reconcile latent state orphans surfaced by the first non-targeted plan. Known:
  `kb_tenant_mint_silent_fallback` (`apply-sentry-infra.yml:186-192`). The plan output must
  be reviewed and every proposed destroy explicitly accounted for before apply.
- **FR5** — Add **Class D orphan** detection to `apps/web-platform/scripts/sentry-monitors-audit.sh`:
  a live monitor (cron or uptime) whose slug has no corresponding `sentry_cron_monitor` /
  `sentry_uptime_monitor` resource in `infra/sentry/*.tf`. Must report slug, creation date,
  last check-in, and monthly cost.
- **FR6** — Destroy the 4 identified dead monitors via the FR3 path:
  `scheduled-ghcr-token-minter` (orphan, unresolved incident 12d),
  `Uptime Monitoring for https://app.soleur.ai` (id `1422253`, orphan),
  `scheduled-ux-audit` and `scheduled-architecture-diagram-sync` (IaC-declared, **zero
  check-ins ever**). Before destroying the latter two, confirm their producers are dead
  rather than unwired (Open Question 4) — destroying the monitor of a broken producer
  treats the symptom.

## Technical Requirements

- **TR1** — `sentry-monitor-iac-parity.test.ts` asserts slug parity **and** `-target=`
  allowlist membership. FR3 removes the allowlist, so the test's allowlist assertion must
  be removed in the same PR or CI goes red on every change.
- **TR2** — The audit script's existing 4-gate token check and DSN residency guard must be
  preserved. Class D uses the same `SENTRY_IAC_AUTH_TOKEN` (Doppler `soleur/prd`) and
  org-wide `GET /organizations/{org}/monitors/` enumeration already present.
- **TR3** — Live liveness must be read from `environments[].lastCheckIn`, **not** the list
  endpoint's `lastCheckIn` (which does not exist as a field and yields a false "never
  checked in" for every monitor).
- **TR4** — FR3 must not weaken the destroy guard. `[ack-destroy]` remains required for any
  plan containing a destroy; the anchoring posture (own-line regex) must be preserved so it
  cannot fire from a quoted block or code fence.
- **TR5** — Per `hr-observability-as-plan-quality-gate`, Class D findings must be reachable
  without SSH: emit a monitored `SOLEUR_*` stdout marker so the next occurrence self-reports.
- **TR6** — FR1 is an ops/vendor action, not a code change. It must not block FR2–FR6 in CI.
- **TR7** — Per `wg-record-recurring-vendor-expense-before-ready`, FR2 must land before the
  PR is marked ready.

## Acceptance Criteria

- **AC1** — Sentry `onDemandMaxSpend` reads `$75` for `jikigai-eu`; invoice draw unchanged
  at $42.22 (proving the cap is usage-billed).
- **AC2** — `expenses.md:37` reads `71.22` with the verified arithmetic in Notes.
- **AC3** — A test proves that removing a `sentry_cron_monitor` block produces a `destroy`
  in the plan (the behaviour #6074 wrongly assumed it already had).
- **AC4** — `sentry-monitors-audit.sh` reports exactly the 2 known orphans as Class D on
  the current live state, and reports zero after FR6.
- **AC5** — Live monitor count drops 50 → 46 cron-equivalent; next-period PAYG ≈ $38.88.
  (No in-cycle refund — savings begin next period.)
- **AC6** — `scheduled-ghcr-token-minter`'s 12-day unresolved incident is closed.
- **AC7** — `scheduled_github_app_drift_guard` remains active (CLO hard constraint).

## Deferred Work

- **D1** — Deep prune to ~16 monitors (~$26/mo). Requires reversing ADR-031. Re-evaluate
  if monitor spend exceeds burn-rate tolerance or the count re-accretes past ~60.
- **D2** — ADR: *"Sentry cron monitors only where silence is undetectable"* — the CTO's
  framing, sound but out of scope. The keep/drop dividing line is a durable observability
  policy, not a cleanup.
- **D3** — Monitor-value telemetry: which monitors have ever caught a real miss. This gap
  is why the CTO/CPO prune disagreement could not be settled on data (Capability Gap 3).
- **D4** — Trace the creation mechanism of uptime monitor id `1422253`.

## Adjacent Decision

**#4296** (60-day observability re-decision, target **2026-07-21** — 4 days out) is
adjacent but distinct: its four criteria concern **log ingestion** (Sentry Logs vs Better
Stack Logs), and Sentry Logs read **0 B / 5 GB**, so criterion 1 is unmeasurable without
first routing logs to Sentry. This brainstorm's finding is nonetheless material evidence
for it: **Sentry's true cost is $71.22/mo, not the $29/mo that #4273's CFO ledger lookup
recorded** — it is now the largest product-COGS line. That correction should be threaded
into the #4296 re-decide rather than re-derived there.
</content>
</invoke>
