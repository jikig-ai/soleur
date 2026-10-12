# Sign-off lifecycle staging — who participates at which phase

Moved verbatim from `plan/SKILL.md` section 2.6 (byte-ceiling extraction; see `skill-body-budget.json`).

The set of mandatory leaders changes by lifecycle phase, and that is by design — different leaders weigh in at different decision points:

- **Brainstorm phase (framing time):** CPO + CLO + CTO are spawned in parallel when `USER_BRAND_CRITICAL=true`. Rationale: the approach has not been chosen yet, so all three lenses (product blast-radius framing, legal/compliance, architectural blast-radius) need to land before the plan exists. See `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` `## User-Brand-Critical Tag Processing`.
- **Plan phase (this gate):** CPO sign-off only. Rationale: the plan implements the approach already framed by all three brainstorm leaders; the plan-time sign-off is the single product-owner ack on the technical approach. CLO and CTO concerns from brainstorm should be reflected in the plan body (Risks section, Sharp Edges, Domain Review carry-forward) — they do not re-sign here.
- **Review phase (PR time):** CPO is not re-invoked; instead the `soleur:engineering:review:user-impact-reviewer` agent enumerates failure modes against the diff. Rationale: review-time concerns are diff-shaped, not approach-shaped.
- **Ship phase (preflight Check 6):** No human sign-off; mechanical gate that the section exists and the threshold is valid.

This tiered model is intentional — re-asking CPO/CLO/CTO at every phase would dilute the framing into ceremony. The framing question is asked once (brainstorm), the answer is locked in (plan), the diff is checked against the answer (review), the gate verifies the answer was given (ship).
