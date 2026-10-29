---
title: Right-size observability spend — execute the 2026-05 re-decision (Sentry prune + Better Stack ingest cut)
feature: feat-observability-vendor-eval
date: 2026-10-29
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-29-observability-vendor-eval-brainstorm.md
issue: 4296
status: draft
---

# Spec — Right-size observability spend

## Problem Statement

Combined observability spend reached **€156.67/mo** (Sentry €75.53 + Better Stack
€81.14) for a product with ~1 active user — ~40% of product COGS. The 60-day
re-decision deferred from #4273 (#4296, target 2026-07-21) never ran and was
superseded by events; evaluating Datadog and SigNoz fresh confirms **migration
does not pay**: the bills are driven by *monitor count* (67 PAYG cron seats) and
*log ingest volume* (post-mortem-measured, unchanged), not by vendor choice, and
the migration blast radius is ~370–450 files / ~185 Terraform resources for a
~20–38-month payback. The fix is already filed as **#6590** (Sentry deep prune)
and **#7577** (Vector ingest cut) but was never sequenced as a spend initiative.

## Goals

- **G1** — Record the #4296 re-decision: stay multi-provider; Datadog remains
  dead; SigNoz logged as the durable direction with explicit revisit criteria.
- **G2** — Reduce Sentry spend to ≲ $35/mo by executing the deep monitor prune
  in #6590 (~67 → ~15–20 live-producer-backed monitors) and amending ADR-031's
  monitor-per-cron policy.
- **G3** — Reduce Better Stack spend toward the Nano tier (~$30/mo EU) or lower
  by executing #7577's ingest cuts (multi-line container log compaction,
  host_metrics sampling/drop).
- **G4** — Preserve every launch-critical capability: error triage, cron-dark
  detection, uptime/redirect-health checks, DB-readiness pager, log query, and
  the Better Stack → Slack/push/GitHub-issue wake path (ADR-218/260/298).

## Non-Goals

- **NG1** — Vendor migration of any kind (Datadog, SigNoz Cloud, self-hosted
  SigNoz, Sentry-only Path A, Better Stack-only). All priced and rejected in the
  brainstorm; Path A's own prerequisites (#3814/#3815/#3865/#3866/#4297) remain
  its blockers.
- **NG2** — Removing monitors whose silence is undetectable elsewhere without
  the #6591 monitor-value evidence pass.
- **NG3** — Executing the Better Stack DPA (#7529) or the missing Sentry Vendor
  DPA row — tracked compliance debt, listed as follow-ups.
- **NG4** — Re-pointing or rewriting any emit path (`reportSilentFallback`,
  `postSentryHeartbeat`, the sentry-heartbeat composite action, host scripts).
- **NG5** — Status page. None exists on either vendor today; out of scope.

## Functional Requirements

- **FR1** — Comment the re-decision verdict on #4296 (stay multi-provider +
  right-size; revisit criteria), linking this spec + brainstorm, then leave
  closure to the operator.
- **FR2** — Enumerate live-vs-declared Sentry cron monitors via
  `sentry-monitors-audit.sh` and `heartbeat-live-reconcile.ts`; the ~23 declared
  monitors with no Inngest producer are first-pass prune candidates for #6590.
- **FR3** — Execute #6590 (deep prune + ADR-031 amendment). Target ~15–20
  retained monitors: any cron whose silence is not otherwise detectable
  (dead-man/self-watch), plus monitors #6591 shows have caught real misses.
- **FR4** — Execute #7577 (Vector chokepoint): compact/join multi-line
  container log lines before ingest and drop or sample `host_metrics` to the
  minimum the 19 `logtail_exploration_alert` rules consume — enumerate which
  metrics each alert reads before cutting.
- **FR5** — Verify the unnamed ~$68 Better Stack plan/tier in the ledger
  (`knowledge-base/operations/expenses.md:50`) and update the row after the
  ingest cut lands (downgrade or Nano-tier fit check).
- **FR6** — Confirm the Sentry PAYG cap stays above post-prune spend and the
  all-or-nothing deactivation cliff cannot re-arm (post-prune monitor count ×
  $0.78 + uptime × $1.00 must sit well under the $75 cap).

## Technical Requirements

- **TR1** — Terraform-first: all monitor/alert changes through
  `apps/web-platform/infra/sentry/` and `apps/web-platform/infra/` TF roots +
  `apply-sentry-infra.yml` / `apply-web-platform-infra.yml` paths; no
  console edits (drift gates pin live-vs-declared).
- **TR2** — Every pruned monitor must be verified silent-safe: either its cron
  still exists and has a surviving independent signal, or the cron itself is
  retired. A prune that orphans detection is a regression, not savings.
- **TR3** — The `vector.toml` ingest cuts must not break any of the 19
  `logtail_exploration_alert` rules or the send-failed pager; grep each
  exploration's SQL before touching a source.
- **TR4** — No wake-path change: Better Stack email/push + incident-mirror →
  GitHub issues stays byte-identical through both cuts.
- **TR5** — All changes pass the existing drift/parity gates
  (`sentry-audit-gate`, `scheduled-sentry-alert-drift`,
  `reconcile-live-heartbeats`).

## Deferred Work

- SigNoz/OTel migration — revisit when real multi-user traffic exists AND
  (error triage outgrows Sentry OR post-prune bill still > ~€100/mo). Tracker:
  #4296.
- Path A (Sentry-only) — deferred with prerequisites #3814, #3815, #3865,
  #3866, #4297.
- #7529 Better Stack DPA execution; missing Sentry Vendor DPA row —
  compliance/critical follow-ups independent of this scope.

## Acceptance Criteria

- AC1 — Sentry monthly invoice projection ≤ ~$35–40/mo (Team base + retained
  monitors + uptime) after prune.
- AC2 — Better Stack monthly invoice ≤ ~$40/mo (or Nano tier) after ingest cut.
- AC3 — Zero coverage regressions: every retained detection property
  (cron-dark, uptime, redirect-health, DB-readiness, the 19 log alerts,
  send-failed pager, incident mirror) demonstrably fires post-change.
- AC4 — #4296 carries the recorded re-decision verdict with artifact links.
