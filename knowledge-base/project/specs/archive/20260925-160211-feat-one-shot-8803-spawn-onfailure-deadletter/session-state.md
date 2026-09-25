# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-25-fix-spawn-onfailure-deadletter-and-429-label-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- gh issue create guard hook blocked two filing attempts (body file written in same command; missing User-Impact line). Resolved by writing the body first and adding User-Impact:/Mandated-By: lines.

### Decisions
- Inngest cancellation and timeouts.finish emit only inngest/function.cancelled, never onFailure. onFailure (kept) forwards agent.spawn.orphaned to a new agent-on-spawn-settle function (retries: 3, idempotency on run_id) that also triggers on the cancel event.
- New paged reason leader_internal_error threaded through union, PAGES_OPERATOR, founder copy, TF reason list, contract pins, regenerated alert-reference.json. The six existing paged reasons are unchanged.
- #8783 fixed by a string cause tag set on the live error inside the step (instanceof APIConnectionError; SDK name is "Error" at runtime). Classifier becomes cause-only with a paged catch-all.
- Settle write is user-scoped, conditional UPDATE, reports only on rows written; 2-min grace for cancels; Stop+timeout pages; lifecycle in Sentry message.
- leader-429-label-8758.sh follow-through rewritten in same PR. Filed #8839, #8840, #8841, #8845.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan; research, domain-leader, plan-review and deepen-plan agent panels.
