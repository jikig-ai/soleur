---
title: Deferred re-decisions get superseded by events; SaaS bills are usually architecture-driven, not vendor-driven
date: 2026-10-29
category: workflow-patterns
related: [issue-4296, issue-4273, issue-6590, issue-7577]
---

# Deferred re-decisions + vendor-cost evaluation

## What happened

A 60-day vendor re-decision (#4296, target 2026-07-21) never ran — it was
superseded by a 49 h Better Stack quota outage and the forced paid upgrade. When
the operator re-asked the question ~130 days later (€157/mo combined bill), the
deferred criteria themselves were partly moot: "Sentry log-ingestion cost at
volume" no longer applied because logs had stayed on Better Stack, and the
"better vendor" framing hid the real cost drivers (monitor *count* at $0.78/seat,
log *volume* from multi-line container logs + host_metrics).

## Pattern

1. **A deferred re-decision issue is perishable.** Its criteria assume the world
   at deferral time; by execution time the load-bearing facts may have changed
   (vendors gained products, bills moved, prerequisites shipped or rotted).
   Re-derive each axis against live state before answering — don't just answer
   the letter of the deferral.
2. **Price the driver, not the vendor.** A vendor bill decomposes into
   plan-floor + per-unit seats + volume. At Soleur's scale both observability
   bills were seat/volume-driven, so migration could not save money — the same
   volumes would re-bill on the new vendor. The correct question was "which
   knob emits the bill," and both knobs already had filed issues (#6590, #7577).
3. **"Two systems" can be doctrine, not sprawl.** The Better Stack leg exists
   to page when Sentry's send path fails (ADR-218); consolidation would delete
   the watchdog-of-the-watchdog. Check ADRs for deliberate second-sourcing
   before treating vendor count as debt.
4. **Blast radius lives in IaC + guards, not SDK call sites.** ~370–450 files,
   ~185 TF resources, ~60 runbooks, ~55 drift-guard/test files — the emit layer
   was already funnel-shaped (~5 functions), so the true migration cost is
   alert-rule re-derivation, never call-site translation.

## Falsifiable rules

- Before pricing a vendor migration, decompose the current invoice into
  plan/seats/volume and name the emitting knob for each component.
- When executing a deferred re-decision, first mark which criteria are stale
  against live state and record the re-derivation in the verdict comment.
- Feature-gap checks for consolidation candidates must enumerate what the
  *departing* vendor uniquely expresses (e.g., Better Stack's
  `follow_redirects=false` — inexpressible on both Sentry and SigNoz).
