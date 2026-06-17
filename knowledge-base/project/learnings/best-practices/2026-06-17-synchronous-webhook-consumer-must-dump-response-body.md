# Learning: a no-SSH webhook op is only diagnosable if the SYNCHRONOUS consumer dumps the response body

category: best-practices
module: apps/web-platform/infra (adnanh/webhook host ops), .github/workflows, #5492

## Problem

The #5450 Inngest cutover orchestration exposed host ops through HMAC webhook hooks so the operator could run them with no SSH. The first live `op=enumerate` returned an **opaque HTTP 500 with an empty body** — the host script had failed, but the cause was invisible, and the cutover stalled. The whole point of the no-SSH design (`hr-no-ssh-fallback-in-runbooks`) was defeated at the moment it mattered.

## Two corrected facts (the initial diagnosis was partly wrong)

1. **adnanh/webhook (pinned v2.8.2) captures BOTH streams.** `include-command-output-in-response[-on-error]: true` returns the command's output via Go `cmd.CombinedOutput()` — stdout **and** stderr. The earlier hypothesis "include-command-output is stdout-only, so the script must echo errors to stdout" was **factually wrong** (verified against the upstream source). A fatal cause reaching *either* stream is captured by the webhook.

2. **The bug was a CONSUMER discarding the response body, not a stream-capture gap.** The script's error reached the webhook response fine; the calling GitHub Actions step (`cutover-inngest.yml` `enumerate` branch) never `cat`'d `/tmp/enum-body` on the non-200 path — it did `echo "::error::enumerate returned HTTP $CODE"; exit 1` and threw the body away. The sibling `rearm` branch *did* cat its body, which is why only enumerate was blind.

## Solution / durable rule

For any host script invoked by a webhook hook with `include-command-output-in-response-on-error: true`, the **synchronous consumer (the workflow step) MUST `cat` the response-body file on the non-2xx branch before `exit 1`**, and echo it (CR/LF-stripped) into an `::error::` annotation. The script must emit a cause to **either** stream (stream-agnostic — do not encode "stdout-only"). Echoing a cause-only line to stdout before `exit` is fine as *defensive portability* (works under any output-capturing harness), but it is NOT the fix for *this* harness, which already captures stderr.

A fatal cause that reaches ONLY an asynchronous layer (Vector journald → Better Stack, Sentry ingest) with no synchronous-consumer dump does NOT satisfy no-SSH diagnosability for a synchronous webhook op. "Eventually queryable in Better Stack" ≠ "visible in the failing request."

## Key Insight

When a workflow can't be pre-merge-validated (R4 — a new `workflow_dispatch` 404s on a feature branch) AND a script carries runtime-only default args, **the first prod action must be a read-only dry-run whose failure path is visible.** Running `op=enumerate` (read-only) first is exactly what surfaced the 500 before any quiesce/deploy/wipe touched prod — but it only helped because (after this fix) the failure is diagnosable. Build the synchronous-error surface BEFORE you need it.

(Root-cause aside, same PR: the enumerate script defaulted its `eventsV2 filter:{from}` bound to the 1970 epoch, which inngest v1.19.4 rejects as out-of-range → no `.data.eventsV2` → exit 1 → the 500. Clamped to a 365-day lookback; `ENUMERATE_FROM` overrides. The default-value path was untested because the mocked fixtures + the docker schema probe both used a recent `from` — a runtime-only default never exercised by the suite. See `2026-06-17-inngest-eventsv2-raw-payload-and-receivedat-filter`.)

## Session Errors

1. **`readonly NOW_MS` inherited by a `$()` subshell broke the new `source`-based unit test** (`line 57: NOW_MS: readonly variable`). The test file marks `NOW_MS` readonly; a same-process `$(source "$TARGET"; …)` inherits it, and the script's top-level `NOW_MS=` then fails. **Recovery:** source via a fresh `bash -c 'source "$1"; …' _ "$TARGET"` (a new process does not inherit the parent's readonly; `BASH_SOURCE[0] != $0` still skips the network loop). **Prevention:** to unit-test a function in a script that assigns top-level vars the harness froze readonly, source in a fresh `bash -c`, never an in-process command-substitution subshell.
2. **The issue's stated mechanism ("adnanh/webhook include-command-output is stdout-only") was factually wrong** — it's `CombinedOutput()` (stdout+stderr). **Recovery:** deepen-plan dogfooded the observability-coverage-reviewer, verified the upstream source, and re-framed the fix (consumer discards the body) + authored the learning stream-agnostically. **Prevention:** verify a third-party tool's stream/capture behavior against its pinned-version source before encoding it as a durable rule (this learning + the reviewer Step 2.5 now state the corrected fact).
3. **The plan's `/work MUST confirm the malformed-response stderr doesn't echo event `.data`` was not executed on the first work pass** — the raw `echo "$resp" >&2` shipped, and AC4's body-dump made it leak into the synchronous run log. **Recovery:** two review agents (code-quality + observability) concurred; fixed inline (dump only error messages + data key names; combined-stream no-leak test). **Prevention:** treat plan `## Sharp Edges` "/work MUST" items as explicit checklist tasks during work, not assumptions; the multi-agent review is the safety net that caught the miss here.

## Tags
category: best-practices
module: webhook, observability, no-ssh, #5492
related: [[2026-06-17-inngest-eventsv2-raw-payload-and-receivedat-filter]], [[2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim]]
routed-from: plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md (Step 2.5)
