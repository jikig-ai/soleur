# Decision Challenges — feat-one-shot-6258-inngest-pg-pool-cap

These are User-Challenges surfaced during plan/deepen-plan on the headless one-shot path. `ship` renders them into the PR body and files an `action-required` follow-up issue. The operator's stated direction is the default; each entry records where the plan diverges and why.

## Challenge 1 — Do NOT execute the #5562 `default_pool_size` 30→15 revert

**Issue #6258 remediation #3 asks:** reconcile the inngest project's Supavisor `default_pool_size` from 30 back to 15 per the #5562 decision.

**Plan diverges — keep `default_pool_size` at 30.**

- **Why:** #5562's premise was "the client cap `--postgres-max-open-conns 10` holds inngest's *total* connection count under 15." This plan establishes (via the per-pool footprint model — inngest opens ~P separate Postgres pools, each honouring the cap independently) that the cap is **per-pool, not total**. Lowering the upstream Supavisor pool to 15 while inngest's worst-case burst can approach ~20 would make `EMAXCONNSESSION` *guaranteed*, not fixed — the exact "most-capable-end-of-range" interaction.
- **What the plan does instead:** the low client-side per-pool cap (`--postgres-max-open-conns 5`) + idle drain is the sole lever; the upstream pool stays at 30 (ample headroom, no prod-write, no sequencing hazard).
- **Follow-up:** file an `action-required` issue re-scoping #5562's premise ("revisit `default_pool_size` only after the per-pool footprint P is confirmed and if a lower upstream cap is ever justified"). The #5562 decision as written is superseded by ADR-103.

**Convergence:** the scoped strong-model advisor (fable, Step 4.5) and spec-flow-analyzer (findings C1/C2) independently reached the same conclusion — decoupling the revert removes the plan's only prod-write and its entire sequencing-hazard surface.
