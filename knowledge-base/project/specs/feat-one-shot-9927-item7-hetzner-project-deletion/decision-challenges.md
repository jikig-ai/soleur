# Decision challenges: feat-one-shot-9927-item7-hetzner-project-deletion

Plan run (2026-10-23). Every row below is a technical fork ruled by the CTO agent per
`hr-technical-fork-is-not-an-operator-question`; none drops or changes the operator's stated scope, so there is no
operator-facing User-Challenge. Rows are recorded so `ship` can render them into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Wording of the ADR-282 residual on Hetzner project deletion or account loss when the documentation read is silent | technical | Ruled by CTO agent, 2026-10-23: state the planning posture "plan as if project deletion or account loss destroys the volume regardless of delete protection" and label the underlying fact "not established; Hetzner docs read 2026-10-23 are silent", in an in-place parenthetical plus a dated addendum - rationale: docs-silent evidence does not separate the options, so the stricter one wins; assuming protection survives costs sole-copy data loss, assuming it does not costs nothing; delete protection must never be cited as cover against project or account loss |
| Whether the addendum names a way to settle the fact | technical | Ruled by CTO agent, 2026-10-23: name one non-binding route, a written Hetzner support question as an owner-side read-only act, not the only route and not a gate; say a live test is out of scope because project deletion is irreversible, and that the first sanctioned inngest-host-replace proves detach under protection only - rationale: stops the replace being misread as settling the residual |
| Runbook edit | technical | Ruled by CTO agent, 2026-10-23: no runbook edit - rationale: ADR-282 line 193 is the only live statement of the residual (grep re-run), and open PR 10874 edits the inngest-server runbook for an unrelated reason |

## Not Yet Specified candidates

None.
