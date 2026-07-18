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

**Corroboration (deepen-plan review):** two independent reviewers (spec-flow-analyzer + architecture-
strategist) CONFIRMED the advisor's structural point — on merge, `apply-web-platform-infra.yml` runs a
SINGLE apply job that delivers vector + the unit fix together AND runs the arm step in the same job, so
the "measure the still-broken units' stderr BEFORE fixing" checkpoint is **structurally unreachable**
in one PR (not merely inelegant). The plan was revised accordingly: that checkpoint is demoted from an
acceptance criterion to best-effort.

**Session-model assessment (kept as default = single PR):** The single-PR plan still preserves the
*essential* #6536 value — once Source 4 is live (same merge), ANY residual unit failure is
self-diagnosable off-box, and the diagnosis here is already CONFIRMED from a unit-diff (not a dev-box
guess), so the pre-fix measurement is confirmatory, not load-bearing. The plan also adds a positive-
control canary so a future Source-4 regression is detectable. **The two-PR split is the ONLY way to
capture the true pre-fix broken-state reading** — a real (if marginal, given the strong diagnosis)
engineering benefit for the operator to weigh against the ARGUMENTS' single-PR deliverable. Retained
as default = single PR; surfaced for the operator to decide.

**Disposition:** default = single PR (operator direction). Surface to operator via `/ship`.
