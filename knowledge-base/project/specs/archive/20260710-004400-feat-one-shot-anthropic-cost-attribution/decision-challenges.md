# Decision Challenges — feat-one-shot-anthropic-cost-attribution

Recorded during deepen-plan (headless / one-shot path). `ship` renders these into
the PR body and files an `action-required` issue for operator visibility.

## Challenge 1 — Phase 3 (Admin cost-report cron) is reconciliation, not attribution

**Raised by:** code-simplicity-reviewer (deepen-plan panel, 2026-07-09).

**The challenge:** All four downstream optimizations the feature exists to make
measurable — Opus→Sonnet tier audit (per-model), prompt caching (cache tokens),
spawn-only-when-work-exists (per-cron), per-surface key split (session-vs-cron) —
are measurable from the **Phase 1 (session) + Phase 2 (cron) markers alone**. Phase 3
(the Anthropic Admin Cost/Usage API cron) serves **none** of the four directly; it
adds authoritative billed-$ reconciliation ground-truth, which the plan's own
Overview names as the *deferred* half of `Ref #5674`. Deferring Phase 3 would remove
the only new secret, the only console mint, the only new Terraform, the only
merge-sequencing hazard, ADR-103, the C4 edge, and ~6 ACs — with zero loss of the
stated measurable outcome.

**Disposition:** KEPT per stated scope. The operator's task explicitly scoped it
(Scope item 2: "wire the Anthropic Admin Usage & Cost API … as a new low-frequency
cron … so per-key/per-model spend is self-servable from Better Stack"). The stated
direction is the default; the source markers can drift or miss, and the Admin API is
the authoritative reconciliation the markers cannot self-check against. Trimmed within
Phase 3 per the sub-recommendation: `usage_report` is now pulled ONLY if Phase 0 shows
`cost_report`'s `description` grouping does not already carry per-model detail.

**Operator decision requested:** if authoritative daily reconciliation is NOT wanted
in this PR, Phase 3 can be deferred to the `Ref #5674` spend-vs-budget follow-up and
the PR ships as Phases 0/1/2/4 (pure code, no infra, no secret, no operator mint).
Default (no response) = keep Phase 3 as scoped.
