---
title: gdpr-gate as preflight Check 10 — Q1 re-evaluation
date: 2026-05-10
status: deferred-pending-data
issue: 3516
related_pr: 3501
related_adr: ADR-026
brand_survival_threshold: single-user incident
---

# gdpr-gate as preflight Check 10 — Q1 re-evaluation

## What We're Deciding

Whether to add `/soleur:gdpr-gate` as preflight Check 10 (third tier of enforcement, after `/soleur:plan` Phase 2.7 and `/soleur:work` Phase 2 exit).

## Decision

**Keep deferred. Do not implement preflight integration today.** Set a calendar-based
re-evaluation on **2026-08-10** (90 days post-ship).

## Why This Approach

The Q1 deferral criterion in #3516 is data-dependent:

> ≥3 Critical findings post-merge that escaped both `/soleur:plan` Phase 2.7 and `/soleur:work` Phase 2 exit gates.

PR #3501 (which introduced gdpr-gate as a plan/work-phase skill) merged at
**2026-05-10T13:42:03Z** — hours before this brainstorm. The criterion is
literally unmeasurable today: there is no post-merge window in which Critical
findings could have escaped, accumulated to 3, and been observed.

Implementing preflight Check 10 now would:

1. Bypass the criterion the spec deliberately set, treating the gate's
   plan/work coverage as insufficient by assumption rather than evidence.
2. Add a third tier of enforcement on top of two unproven tiers, increasing
   token cost on every preflight run for unknown marginal coverage.
3. Pre-commit context to a design (where in preflight, what trigger paths,
   what failure UX) before we know what *kind* of Critical findings escape —
   and the right Check 10 design depends on that distribution.

## Alternative Considered: Calendar Re-Evaluation Without Count

The criterion is "≥3 Critical findings". A purely count-based criterion can
silently never fire if usage is low. We pair the count with a calendar
checkpoint (90 days) so the question gets re-asked even if the count is 0.
At 2026-08-10, three outcomes are possible:

| Observed (90d) | Action |
|----------------|--------|
| ≥3 Critical findings escaped both gates | Implement Check 10. Brainstorm reopens with real failure data shaping the design. |
| 1-2 Critical findings escaped | Keep deferred 90 more days; document the cases. |
| 0 Critical findings escaped, OR plan/work gates caught everything | Close #3516 as "criterion settled — preflight tier not needed." |

90 days is a balance: long enough that low-frequency PII surfaces (auth
flows, schema changes, API routes) get hit by ordinary work; short enough
that the issue doesn't drift indefinitely.

## Key Decisions

- **Defer:** No code changes today. Issue #3516 stays open; draft PR #3520 closes without merge.
- **Re-eval mechanism:** One-time scheduled agent task on 2026-08-10 via `/soleur:schedule`, which posts to #3516 with the 90-day data and a recommendation.
- **Data source for re-eval:** `incidents.sh` telemetry on the gdpr-gate Critical-finding rule (`cq-gdpr-gate-critical-finding`, planned at gate-implementation time per the spec's TR8) — plus a manual scan of merged PRs in the 90-day window for compliance regressions that escaped review.

## Open Questions (deferred to re-eval)

- Does the gdpr-gate Critical-finding telemetry actually exist by 2026-08-10? If TR8's `cq-gdpr-gate-critical-finding` rule was never wired up, we have no count and the re-eval falls back to a manual sweep.
- If preflight Check 10 ships, is it a hard gate (block ship on Critical) or advisory (annotate ship message)? Plan/work tiers are advisory; a third advisory tier may be lower-value than a hard tier.

## User-Brand Impact

**Artifact:** Regulated user data (Art. 9 categories, PII, payment data) flowing through Soleur-generated code paths.

**Vector:** A Critical-severity GDPR/CCPA/HIPAA violation slips past plan-time and work-time advisory gates and reaches production, exposing real user data to non-compliant processing or storage.

**Threshold:** `single-user incident`. One user's regulated data leaked or mis-processed is a brand-survival event for an EU-targeting platform.

**Mitigation premise of this brainstorm:** The two existing tiers (plan + work) cover the design-time and implementation-time generation paths. Preflight Check 10 would catch only the residual case where (a) a Critical finding appears in a diff and (b) both upstream tiers missed it. We cannot size that residual without operational data.

## Domain Assessments

**Assessed:** none — the decision is "wait for data," not a feature design. CPO/CLO/CTO will be re-engaged at the 2026-08-10 re-evaluation if the count threshold is reached or if calendar review surfaces a design choice.

## Next Action

1. Comment on #3516 with this decision and the 2026-08-10 re-eval date.
2. Schedule a one-time agent task via `/soleur:schedule` to re-open this brainstorm on 2026-08-10.
3. Close draft PR #3520 (no implementation needed in this branch).
4. Leave #3516 OPEN with milestone unchanged so the scheduled task has something to comment on.
