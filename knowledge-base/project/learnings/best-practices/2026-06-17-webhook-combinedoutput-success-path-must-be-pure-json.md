# Learning: when a webhook returns CombinedOutput and the consumer parses the response as JSON, the SUCCESS path must be pure-JSON on BOTH streams — and the success path must be the thing you test

category: best-practices
module: apps/web-platform/infra (adnanh/webhook host ops), .github/workflows, #5503

## Problem

#5492 fixed the epoch-`from` 500 in `inngest-enumerate-reminders.sh`, so `op=enumerate` finally queried prod and returned the armed reminders. But the cutover stayed blocked: the workflow step failed with `enumerate did not return a JSON array`. The script succeeded; the **consumer** rejected the body.

## Root cause

`adnanh/webhook` v2.8.2 returns `cmd.CombinedOutput()` — stdout **and** stderr — even on a 200. `cutover-inngest.yml` parses that body with `jq -e 'type == "array"'`. The enumerate **success** path wrote an observability summary to **stderr** (`echo "...N armed reminder(s)..." >&2`), which `CombinedOutput()` merged ahead of the stdout JSON array → the array parse failed.

The merge happens **only at the webhook boundary**. Internal shell consumers (`records=$(enumerate)`, `post=$(enumerate 2>/dev/null)`) capture stdout only, so they were never affected — which is exactly why the bug hid: every internal path and every test saw clean stdout.

## Solution / durable rule

For a host script whose **webhook response is parsed as JSON** by the consumer: on the success path, write **nothing** non-JSON to **either** stream. stdout = the JSON only; route the observability summary to `logger`/journald (NOT stderr). The failure path is the opposite — it may (should) write the cause to both streams, because failure → non-2xx → the consumer dumps the body as an `::error::` cause, never parses it as JSON.

Audit rule for the whole op set: the bug exists only where BOTH (a) the webhook returns CombinedOutput AND (b) the workflow `jq`-parses that response body. Map every op: enumerate (jq array → broken), rearm (body only `cat`'d + HTTP-code-checked → safe), verify (polls a pure-JSON cat-state with no stderr → safe).

## Key Insight

**Test the SUCCESS path's COMBINED stream, not just the failure path's.** #5492 added a no-leak test — but it only captured the *failure*-path combined stream. Three review agents + preflight + the no-leak test all passed because none of them exercised the *success*-path combined stdout+stderr the way the webhook actually returns it. The bug was caught only by the **post-merge read-only `op=enumerate` dry-run against prod** — which is also the payoff of #5492's observability fix: the failure was now diagnosable (`enumerate did not return a JSON array` + the data), where before it was an opaque 500. The regression test now captures `bash "$TARGET" 2>&1` and asserts it parses as a pure JSON array (RED with the stderr echo restored, GREEN without).

## Session Errors

1. **#5492's no-leak test and 3-agent review covered only the FAILURE-path combined stream; the SUCCESS-path combined-stream pollution passed every pre-merge gate.** **Recovery:** caught by the post-merge read-only prod verification; fixed in #5503 (drop the success-path stderr echo) with a test that asserts the success-path COMBINED stream is pure JSON. **Prevention:** for any CombinedOutput-webhook whose body is JSON-parsed, the canonical test is "combined stdout+stderr on the SUCCESS path parses as the expected JSON" — assert it for the happy path, not only the error path.
2. **The justification comment over-claimed the observability layer** (`→ Vector → Better Stack`). **Recovery:** review (observability-coverage-reviewer, `hr-observability-layer-citation`) verified the `logger` line lands in on-host journald under `webhook.service` at notice priority, which no `vector.toml` source captures; comment corrected to on-host journald, broader Vector-source gap routed to #5495. **Prevention:** cite an observability layer only after confirming the signal's unit + priority actually matches a live Vector source filter.

## Tags
category: best-practices
module: webhook, observability, no-ssh, combinedoutput, #5503
related: [[2026-06-17-synchronous-webhook-consumer-must-dump-response-body]], [[2026-06-17-inngest-eventsv2-raw-payload-and-receivedat-filter]]
