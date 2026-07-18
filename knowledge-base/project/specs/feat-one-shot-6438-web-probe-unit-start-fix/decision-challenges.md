# Decision Challenges — feat-one-shot-6438-web-probe-unit-start-fix

Recorded per plan Step 4.5 (scoped strong-model advisor, ADR-084 User-Challenge). Headless pipeline:
these are persisted for `/ship` to render into the PR body + file as an `action-required` issue for
the operator to decide. The operator's stated direction is the default; these do NOT block.

## §1 — Split into two PRs (observability first, then unit fix)?

**Operator's stated direction:** ONE focused PR (`Ref #6438 #6548`), delivering unit fix +
observability + arming together.

**Challenge (plan-time advisor, model: fable):** Split into TWO PRs — PR 1 delivers only the
vector.toml Source-4 delivery (independently required regardless of the unit fix), and its merge is
verified by confirming probe-tagged stderr flows to Better Stack; PR 2 then delivers the unit
`HOME`/token fix. Rationale: within a single auto-applied PR both changes apply in the *same*
`terraform apply`, so the "measure the still-broken units' stderr before applying the fix" ordering
cannot actually be observed between them — it is internal-ordering fiction. Splitting makes the
observability channel provably live *before* the arm workflow re-runs, so a residual/differently-
failing unit is distinguishable from "fixed" (the #6536 failure mode: re-running the arm blind).

**Session-model assessment (kept as default = single PR):** The single-PR plan still preserves the
*essential* #6536 value — once the vector channel is live (same PR), ANY residual unit failure is
self-diagnosable off-box, and the diagnosis here is already strong from a unit-diff (not a dev-box
guess), so the pre-fix measurement is confirmatory, not load-bearing. The plan mitigates the advisor's
concern within one PR by sequencing the apply/verify (Phase 1 vector delivery + telemetry checkpoint →
Phase 2 unit fix + telemetry → Phase 3 separate `workflow_dispatch` arm run only after the channel is
confirmed live). The operator's single-PR direction is retained; the split is the cleaner-engineering
alternative for the operator to weigh.

**Disposition:** default = single PR (operator direction). Surface to operator via `/ship`.
