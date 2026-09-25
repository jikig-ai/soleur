---
title: Inngest functions that must leave a terminal record handle both lifecycle signals
status: active
date: 2026-09-25
related: [8803, 8783]
related_adrs: [ADR-030, ADR-042]
---

# ADR-251: Inngest functions that must leave a terminal record handle both lifecycle signals

## Context

Some Inngest functions owe a user-visible terminal record. The leader loop (`agent-on-spawn-requested`, ADR-042) is one: the founder's Today card reads "Working" until `action_sends` carries a terminal state. A function's body can only write that record for failures it catches. Runs that end outside the body wrote nothing (#8803).

Inngest reports those runs through two separate system events. This was measured on 2026-09-25 against a local `inngest-cli` 1.19.4-2c8385ba8 (the version pinned in `apps/web-platform/infra/inngest.tf`), using SDK 3.54.2:

- A run that fails past its retries fires `onFailure` (`inngest/function.failed`). It does not emit `inngest/function.cancelled`.
- A run cut off by `timeouts.finish`, or cancelled with `DELETE /v1/runs/<id>`, emits only `inngest/function.cancelled`. `onFailure` never fires for either. The payload carries `data.event` (the original event, with a numeric `ts`), `data.run_id`, `data.function_id` and no `data.error`. Nothing in it tells a timeout apart from a manual cancel.
- The server rejects a hand-sent `inngest/function.cancelled` with HTTP 400 (the name is reserved), so outside callers cannot forge that trigger.

A second constraint: the SDK registers `onFailure` as its own `<id>-failure` function, pinned to `retries: { attempts: 1 }` and without idempotency. Settling the record inside that function would give the database write a single retry.

## Decision

An Inngest function that owes a terminal record handles BOTH lifecycle signals and does the settling in ONE function:

1. The owning function declares `onFailure`. That handler only forwards the failed run as an app event (for the leader loop, `agent.spawn.orphaned`, carrying `data.event` and `data.run_id` from the failure envelope). It does no database work.
2. A dedicated settle function (for the leader loop, `agent-on-spawn-settle`) triggers on both that forwarded event and `inngest/function.cancelled`. The cancelled trigger's `if` is the literal expression the SDK generates for the owner's failure trigger, so it can never match the `-failure` id. The settle function has retries (`3`) and idempotency on the orphaned run id (`event.data.run_id`).
3. The settle write is conditional. It applies only to a row with no terminal state, it is scoped to the owning user, and it reports only on rows it actually wrote. For a cancel, a grace `step.sleep` comes first, because Inngest does not abort a step request already in flight.
4. Handlers read `event.data.event` and `event.data.run_id`, never the ctx `runId`, which belongs to the handler's own run.

Known pre-existing gap, not changed here: `cronGhPagesCertReissueOnFailure` (`server/inngest/functions/cron-gh-pages-cert-reissue.ts`) handles `onFailure` only, so a timeout or cancel of that function is not seen by its failure path. This ADR is a sibling of ADR-030, which covers Inngest as the durable trigger layer.

## Consequences

- Every exit of such a run now leaves a terminal record: a caught failure, a retry-exhausted throw, a finish timeout and an API or dashboard cancel. The one exception is a run Inngest loses entirely, which fires no lifecycle event (tracked in #8839).
- Every function covered by this pattern adds one extra served Inngest function, and each is pinned in `function-registry-count.test.ts`.
- A cancel settles after the grace sleep, not immediately. For the leader loop, a timed-out card can show "Working" for up to about 12 minutes.
- The pattern depends on server behaviour measured on 1.19.4. An Inngest server upgrade should re-run the measurement (the plan's I-1 recipe) before relying on it.
