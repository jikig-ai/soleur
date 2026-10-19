# Learning: fixtures written from a model of the tool agree with the model, not the tool

## Problem

PR #10349 (#9545 PR1, dark egress audit rollup) passed its own suites and a plan-time review, then a 13-seat panel
found four P1s and about 26 P2s. The recurring shape: a claim or fixture about an external system was written from the
author's model of it and never measured against the real thing, so the tests agreed with the model by construction.

- The ingest route rejected every `x-forwarded-*` header as a proxy signal. Next.js adds all four to EVERY request it
  serves (measured on 16.3.8), so every legitimate Vector batch got 401. Unit tests used a bare `Request`.
- The throttle marker filter read `component_discarded_events_total` with a `key` tag. In Vector 0.43.1 the per-key
  counter is `events_discarded_total`; the component-wide one has no key. The test metrics were hand-written.
- The "global cap of 10,000" assumed a fixed window. A Vector throttle is a leaky bucket (threshold 100 / 10 s over a
  20 s flood passed 299 events), so the memory bound was 2x optimistic.
- The probe's status pattern was validated in Python and used a backslash inside a ClickHouse string literal.
- A runbook step (switch the per-organisation flag off) named a precondition the SQL guard did not check (`web_egress`).

## Solution

Capture the real shape first and make that the fixture: a real Vector run for the metric names and the throttle
behaviour, a real Squid run for what is logged before authentication, the real engine for a pattern
(`betterstack-query.sh` ran the final regex in ClickHouse), a real Next server's headers. Keep a pin test on the version
the measurement was taken on. Mutation-check each new guard (revert the line, see a test go red).

## Key Insight

A fixture authored from your own model of a tool is a restatement of the model. It can only fail where the model
fails to match itself. The measurement has to come from the tool, in the engine that will run the thing, before the
fixture exists.

## Session Errors

1. **Route rejected `x-forwarded-*`, 401 for every batch** — Recovery: measured Next's injected headers, narrowed the proxy markers, added a pin test on the Next minor. **Prevention:** measure the framework's injected request headers in Phase 0 before writing an allow/deny rule over them.
2. **Marker filter used a metric name that carries no key** — Recovery: captured a real 0.43.1 run, rebuilt the fixtures from it. **Prevention:** capture a real metric/log shape from the pinned binary and use it as the fixture.
3. **Throttle assumed to be a fixed window** — Recovery: measured the leaky bucket, global threshold 5,000. **Prevention:** a memory or rate bound derived from a limiter must be measured over a sustained flood on the real component.
4. **Status regex validated in Python, backslash in a ClickHouse literal** — Recovery: bracket class with no backslash, run in ClickHouse via Better Stack (read-only). **Prevention:** run a query pattern in the engine that will execute it.
5. **Runbook precondition did not match the SQL guard** — Recovery: runbook names `web_egress`. **Prevention:** when a runbook says "do X first", the guard that depends on X must check exactly X; grep the guard.
6. **DSAR runbook used `erase_egress_audit_rollup` for an open account, which the new member guard turns into a no-op** — Recovery: added `erase_egress_audit_rollup_for_requester`. **Prevention:** after tightening an RPC's precondition, re-walk every caller's flow (saga and runbook), not only the one that motivated the change.
7. **Uppercase nil-UUID test row was unchanged by `toUpperCase()`** — Recovery: used a UUID with letters. **Prevention:** a negative fixture must be shown to differ from the positive one.
8. **A hand-set `verify` LIKE pattern did not match `pg_get_constraintdef` output (escapes, array form)** — Recovery: read the rendered definitions first. **Prevention:** print the catalog's rendering before writing a match against it.
9. **`docker run | tail` capture hung until timeout; first `git push` failed once (transient); the pii-scrub suite needed an env var and a Vector binary** — Recovery: detached container + `docker logs`; retry; extracted the binary from the pinned image. **Prevention:** (one-off) capture container output via `docker logs`, never a pipe that waits for EOF.
10. **Affected-test gate queued for 45+ minutes behind other sessions** — one-off (shared runner contention); the `LOCK_WAIT_HEARTBEAT` banner made it attributable.
11. **Stop hook fired on a closing sentence that promised an action** — Recovery: ended with a `Paused:` line naming the wait. **Prevention:** end a waiting turn with the label and the one thing awaited.

## Tags
category: workflow-issues
module: egress-audit, vector, ingest-route, review
