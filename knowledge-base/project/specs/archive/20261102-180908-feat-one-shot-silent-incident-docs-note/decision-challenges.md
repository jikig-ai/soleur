# Decision challenges (plan phase, headless)

Rulings and findings persisted during planning of the docs-only follow-up on #11820. The operator's stated
direction (and the binding CTO ruling) is the default.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fate of the `inngest_cutover_flip_silent` and `egress_gw_probe_silent` alerts whose `lower_than` incidents stay open after data returns (leave, rewrite predicate, or pause) | technical | Ruled by CTO agent, 2026-11-02: leave the alert as is, document the class finding in the runbook entries and the `.tf` comment block, no predicate rewrite, no pause. |
| Manual resolve test of Better Stack incidents 1031046761 and 1045365287 (a Better Stack write) | operator (production-mutating) | Run the manual resolve test on the two incidents - not run in this PR; pending the owner's per-command go-ahead and named as pending in the PR body. |
| Reword the neighbouring statements that say the replace-window incident "clears on its own" (the flip runbook bullet parenthetical, the `.tf` comment line "That is expected; it clears on its own.", `incident_cause`, and `inngest-server.md` Silence alert bullet) | operator (scope) | Reword those four statements - not done in this PR, because the brief limits the edit to the added note and `incident_cause` is a resource attribute whose edit would change the Terraform plan; the added note sits beside them and states the exception. Awaiting the owner's decision to widen scope. |

## Notes

- The CTO row was copied from the ruling supplied with the task; no further technical fork arose. The placement of the
  note in each bullet, the comment-only proof, and the guard-anchor constraints are mechanical consequences of the brief.
