# Decision Challenges — feat-one-shot-8079-registry-probe-dark-gate

Persisted headless per `soleur:plan-review`'s classifier routing. `ship` Phase 6 renders these into
the PR body and files them as an `action-required` issue. Nothing here was auto-applied.

## UC1 — Two reviewers argue the mechanism the issue asks for is the expensive half, and not the valuable half

**Class:** user-challenge (drops operator-requested scope — never auto-decided)

**The operator's stated direction (the default, and what the plan implements):** #8079 says "route the
`registry-probe)` arm's non-200 branch through `inngest_execute_registry_gate`". The plan does exactly
that.

**The challenge.** `soleur:engineering:cto` (devex lens) and `soleur:engineering:review:dhh-rails-reviewer`
independently proposed a smaller shape:

- Keep D4 (the `<step>` parameter), D6 (`op=inventory` instead of a self-referential remedy), D9 (the two
  stale strings inside 2.0) and D8's `silent` clause — all small, independent, high-value.
- Replace the imported eleven-token `case` with a short non-200 branch: the `webhook_path`
  discrimination, then ONE `::error::` naming the three dispatchable reads with their discrimination
  rules.

**What it would buy.** It drops the duplicated plumbing, both drift guards, the `RPG_*` scheme and —
crucially — **most of the assertion collisions, which are caused by importing the gate, not by fixing
the message.** The CTO costs the plan as written at "large (week+), suite-dominated" versus "medium
(1-2 days)" for this shape.

**What it would cost.** P1 weakens from "a graded verdict naming what is and is not established" to
"named next reads". P3 and P4 — the properties the Premise Correction says are the point — are fully
met either way.

**Why it is NOT auto-applied.** It drops scope the operator asked for by name. Per ADR-084 /
decision-principles.md, dropping operator-requested scope is never Mechanical.

**What would decide it:** whether the operator wants `op=registry-probe` to *grade* the host (the
issue's ask) or merely to *route them to the instruments that grade it* (the cheaper shape).

## UC2 — Make `scripts/inngest-host-state.sh` dispatchable (orthogonal, not a substitute)

**Class:** user-challenge (adds scope)

`soleur:engineering:cto` verified — and this session re-verified — that **no workflow wraps
`scripts/inngest-host-state.sh`** (`grep -rln inngest-host-state .github/workflows/` → no match).
Running it needs a local checkout plus the `doppler` CLI plus `prd_terraform` access.

That matters because it is the instrument the plan's highest-stakes remedy points at. A ~40-line
`workflow_dispatch` wrapper would give the operator the host's own verdict from one `gh workflow run`,
from a phone, with no cutover-arm change and no new assertions. `DOPPLER_TOKEN` is already injected
unconditionally.

It does **not** close #8079 and is not a substitute for it. The plan mitigates the gap inline instead
(D8 reorders the remedy so the dispatchable read is step 1 and states the local script's
prerequisites), so this is an additive suggestion, not a blocker.

**If accepted:** file as its own issue rather than growing this PR.

## UC3 — The `_EXACT_FLOOR` convention itself

**Class:** taste (challenges a repo-wide convention, not this change)

`soleur:engineering:cto` measured the floor's history as `556 → 628 → 630 → 648 → 649 → 665` — six
bumps in five days, one already resolved from a documented merge conflict — and argues the exact
integer plus its ten-line itemised delta comment is a guaranteed merge conflict on every concurrent
PR, while (by the plan's own Guard 1 Anchor) buying no anti-substitution property over `-ge`.

Proposal: move the integer to a sibling one-line file (`cutover-inngest-workflow.floor`), keep `-ne`,
and let git log carry the history instead of a comment block every PR appends to.

**Not adopted in this plan** — it is a change to a shared convention that reaches far beyond this
arm, and adopting it here would widen a P2 diagnostic fix into a suite-wide refactor. The two
narrow parts WERE adopted (see the plan's Phase 4): re-measure the floor after the final rebase
onto `main`, not at authoring time; and stop growing the itemised delta comment.
