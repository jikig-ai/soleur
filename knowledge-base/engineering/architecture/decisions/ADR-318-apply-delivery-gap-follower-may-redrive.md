# ADR-318: The apply-delivery-gap follower may actuate a bounded re-dispatch

- Status: adopting
- Date: 2026-11-03
- Refs: #10033, #12001, #10879 (follower), ADR-189 (sense/adjudicate/actuate), ADR-006 (R2 has no state lock)

## Context

Both apply workflows share one concurrency group (`terraform-apply-web-platform-host`) — the only serializer, since the R2 backend has no lock. A group holds 1 running + 1 pending; a third arrival cancels the pending run even with `cancel-in-progress: false`. During merge-queue drains, `apply-deploy-pipeline-fix` push deliveries were silently evicted (#10033). The follower shipped in #10879 detects and files the gap issue but remediation stayed manual: during a storm the human is the queue — two manual dispatches were themselves evicted.

## Decision

The follower gains a `redrive` job that runs `gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason=...` when, and only when, `scripts/apply-delivery-gap.sh` emits `redrive_deploy_fix=true`: deploy-fix gap rows exist, every deploy-fix row is `evicted-before-start` (zero jobs ran — nothing partial on the lockless backend), and no non-stale deploy-fix run is in flight.

- Sense/adjudicate/actuate stay separate (ADR-189): `follow` keeps `actions: read`; `actions: write` is scoped to the `redrive` job alone.
- Merge-as-authorization is unchanged: a redrive applies main HEAD — exactly what the issue body's printed manual command already instructed. It cannot apply anything the merge did not authorize.
- `cancelled-mid-run` is never auto-redispatched (possibly-partial state stays human-only).
- One dispatch per reconcile; the dispatched run lands in the same group, so serialization is untouched and a re-eviction re-fires the follower on the next completion. The aged-issue escalation is the floor.

Rejected: native `concurrency.queue: max` (arriving-run-governs semantics require it on all ≥6 members and convert load-shedding into an unbounded stale-SHA backlog — re-evaluation filed); the `infra` key's redrive (deferred until deploy-fix redrive is observed — filed).

## Consequences

A standing `actions: write` grant exists that can autonomously dispatch a production apply into `infra-privileged` (branch_policy only — verified). The eligibility predicate is the control: it is asserted by `apply-delivery-gap-follower.test.sh` fixture rows and the script's `--self-test`, and the workflow's `if:` is the single dispatch chokepoint pinned by the W wiring assertions.
