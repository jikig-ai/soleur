# Decision Challenges — feat-one-shot-12001-10033-suite-times

Headless pipeline (Devin CLI subagent): no Task/Agent tool available, so technical rulings that the workflow would route to `soleur:engineering:cto` are recorded here as `pending - assumed:` per the technical-ruling-delegation rule.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| #10033 mechanism: bounded auto-redrive via the shipped `apply-delivery-gap-follower` vs native `concurrency.queue: max` on all group members vs issue options (b)/(c) | technical | pending - assumed: bounded auto-redrive (second job, `actions: write` scoped, class-gated to `evicted-before-start`, never `cancelled-mid-run`). Rationale: detection already ships there (#10879); `queue: max` is effective only on every member of `terraform-apply-web-platform-host` (the arriving run's declaration governs eviction) and converts the infra apply's supersede load-shedding into an unbounded serialized backlog whose 100-cap recreates the same hole; (b) is infeasible (the POST lives inside the state-mutating apply), (c) is impossible (an evicted pending run executes zero jobs). |
| `track.sh` disposition (declare edge vs accept row) | technical | pending - assumed: declare — `terraform-target-parity.test.ts:3456-3480` asserts workflow run-steps contain `dispatch-web-redeploy/track.sh`, so the file's name-state feeds the suite's verdict (widened doctrine, PR #11955). Verify at work with `audit --all-refs`; the doctrine, not the table, governs on contradiction. |
| Item-2 median source: last ≥4 green `merge_group` runs vs PR runs | technical | pending - assumed: merge_group — canonical full-matrix run per `watch-shard-balance-11564.sh:18-21`; PR-event medians are a different distribution (Oct-29 learning) and noted as a caveat in the report. |
| CPO sign-off (`requires_cpo_signoff: true`, threshold `single-user incident`) | operator (authorization) | pending - assumed: recorded in plan frontmatter; CPO consult not spawnable on this harness — flag for operator review at ship time. |
| Brand-survival threshold `single-user incident` (challengeable per template) | taste | pending - assumed: matches the Oct-12 path-aware-gating brainstorm's rating on the same affected-selection surface + the prod-delivery channel touch. |
