# Decision challenges: feat-one-shot-9927-item7-hetzner-project-deletion

Plan run (2026-10-23). Every row below is a technical fork ruled by the CTO agent per
`hr-technical-fork-is-not-an-operator-question`; none drops or changes the operator's stated scope, so there is no
operator-facing User-Challenge. Rows are recorded so `ship` can render them into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Wording of the ADR-282 residual on Hetzner project deletion or account loss when the documentation read is silent | technical | Ruled by CTO agent, 2026-10-23: state the planning posture "plan as if project deletion or account loss destroys the volume regardless of delete protection" and label the underlying fact "not established; Hetzner docs read 2026-10-23 are silent", in the reworded residual plus a dated addendum - rationale: docs-silent evidence does not separate the options, so the stricter one wins; assuming protection survives risks sole-copy data loss, assuming it does not costs no data, only a pending mitigation decision (amended the same day on quality and security seat dissent; the CTO upheld the posture); delete protection must never be cited as cover against project or account loss |
| Whether the addendum names a way to settle the fact | technical | Ruled by CTO agent, 2026-10-23: name one non-binding route, a written Hetzner support question as an owner-side read-only act, not the only route and not a gate; say a live test is out of scope because project deletion is irreversible, and that the first sanctioned inngest-host-replace proves detach under protection only - rationale: stops the replace being misread as settling the residual |
| Runbook edit | technical | Ruled by CTO agent, 2026-10-23: no runbook edit - rationale: the ADR-282 residual on Hetzner project deletion is the only place the question is open (grep re-run; the loss-mode rows already read no recovery), and open PR 10874 edits the inngest-server runbook for an unrelated reason |
| Seat dissent: the rationale `costs nothing` is an unsourced universal and conflicts with the no-backup residual | technical | Ruled by CTO agent, 2026-10-23: amend the rationale to `assuming protection survives risks sole-copy data loss; assuming it does not costs no data, only a pending mitigation decision`, and state in the addendum, unranked, that no off-project backup exists today and that adding one is a separate spend and effort decision this item does not make - rationale: planning for volume loss points toward an off-project copy, and the posture and the `not established` labels stay unchanged |

## Not Yet Specified candidates

None.
