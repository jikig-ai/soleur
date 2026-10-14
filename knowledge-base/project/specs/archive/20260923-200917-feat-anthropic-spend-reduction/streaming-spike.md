# Streaming spike — Phase 0 evidence (#8611)

Run 2026-09-23 on a workstation. This decides Fix 1 Branch A (SDK streaming) vs Branch B
(detach-and-poll) per the plan's Phase 0. No tunnel hostname or key appears in this record.

## Setup

| Component | Version / shape |
|---|---|
| Inngest server | `inngest start` **v1.19.4** release binary (the pinned production version), bound to 127.0.0.1 |
| SDK | `inngest` **3.54.2** (the app's pinned version), `serve({ streaming: "force" })` |
| App | Next **16.3.1** production build (`next build` + `dev: false`), served by a minimal `http.createServer → next().getRequestHandler()` server that mirrors the transport of `apps/web-platform/server/index.ts` |
| Proxy | a Cloudflare **quick tunnel** (`cloudflared tunnel --url http://127.0.0.1:3000`) as the registered serve URL, so every step request crossed a real Cloudflare proxy |
| Keys | throwaway `signkey-test-<random hex>` and a random event key; both processes started under `env -i` with `INNGEST_DEV=0`; no Doppler |

**Deviation from the plan, and what it cost.** The plan asked for the app's own
`server/index.ts`. The spike used a minimal server that mirrors only its transport, so for S1–S6, S8
and S3 the app's `installCrashHandlers()` (`server/crash-handlers.ts`: `uncaughtException` → Sentry →
`process.exit(1)`) was **not** loaded — and that is the behaviour the spike's most important finding
depends on (see "Heartbeat leak" below). The S7 runs added the same two handlers to the spike server
and ran the app and the inngest server under restart loops (the production supervisor shape), which
measured the crash end-to-end.

The production path differs in one more way: `app.soleur.ai` reaches its origin through the
production Cloudflare edge, not a quick tunnel. Phase 6 closes that on the real edge.

## Results

Each row ran three times unless stated otherwise. Pass conditions are the plan's.

| # | Function | Result | Verdict |
|---|---|---|---|
| S1 | one 2s step | 3/3 completed in one attempt | pass |
| S2 | one 3-minute step | 3/3 completed in one attempt, **zero** `invalid status code: 524` | pass — streaming beats the ~100s origin timeout |
| S3 | one 70-minute step (`retries: 1`) | **2/3 completed in one attempt** (`function.finished` 16:53:32–33Z, 70 min); **1/3 stream dropped at ~20.5 min** (16:04:02Z) and its step re-ran | fail by the plan's letter; the drop is not a length limit (below) |
| S4 | throws a plain `Error` on attempt 0, succeeds on attempt 1 (`retries: 1`) | 3/3: attempt 1 scheduled and succeeded — a streamed error is read as an error | pass |
| S5 | throws `NonRetriableError` (`retries: 3`) | 3/3 failed once, no retry | pass |
| S6 | two steps with `step.sleep("1m")` between | 3/3: both ran, in order, once each | pass |
| S7 | see "S7 — stream cuts and kills" below | all rows as expected | pass with the wrapper |
| S8 | leader-loop shape: `cap-check` → `turn-1-claude` (20s) → `tool-0` (throws on attempt 0), `retries: 3`, `timeouts.finish: "10m"` | 3/3: `cap-check` and `claude` ran **once**; only `tool-0` re-ran (attempt 1), and the run completed | pass — no double billing |
| — | `throttle: { limit: 2, period: "1h" }`, 4 events | 2 ran, 2 queued | the pinned server honours `throttle` |
| — | unsigned POST through the tunnel | HTTP/2 **201** with `x-inngest-sdk` headers; the streamed envelope carried **401**; no function ran | signature still enforced, but the status line no longer shows it |

Other observations:

- **Heartbeat interval: 3 s**, a single space byte (`createStream` in `inngest/helpers/stream.js`).
- `streaming: "allow"` does not stream on a non-Vercel host (SDK source; the spike defaulted to `"force"`).
- The server accepted the response signature carried in the streamed body: every signed run above
  completed.
- Compression of the streamed response through the tunnel was **not recorded**.

### S3 — the dropped stream

- cloudflared: `ERR Request failed error="stream 25 canceled by remote with error code 0"`
  (`originService=http://127.0.0.1:3000`).
- Inngest server: `ERROR error handling queue item error="Your server reset the connection while we
  were reading the reply: Unexpected ending response" item_kind=start`.
- Attempt 1 of the step started 18 s later (16:04:20Z) while attempt 0's work was still running — the
  exact double-run shape of the production 524, now with a different transport error. In production the
  single-flight guard in `spawnClaudeEval` makes attempt 1 join the live child instead of spawning a
  second session; a second drop would still exhaust `retries: 1` and fail the run.
- The other two streams of the same batch stayed open for the full **70 minutes** and completed in one
  attempt, so the drop is a random fault on the path, not a length cap at the server or the edge.
  Whether the production edge drops long streams at a similar rate is unmeasured; the
  `inngest-stream-consumer-cancel` report counts it from the first deploy.

### Heartbeat leak → production crash (severe)

After the S3 drop the app logged `⨯ uncaughtException: TypeError: Invalid state: Controller is already
closed` from a timer, **once every 3 s** (281 between 16:04 and 16:18Z; 12 in a measured 35 s window),
and kept doing so until the dropped step's work finished (989 in total, stopping at the step's end
16:53:32Z — the throw lasts exactly as long as the step).

Cause, read in `node_modules/inngest/helpers/stream.js` (3.54.2): the heartbeat `setInterval` is cleared
only in `finalize()`. The `ReadableStream` has no `cancel()` handler and `enqueue` is unguarded, so when
the consumer disconnects the interval leaks and every tick throws. `inngest@4.21.0` adds `cancel()`, a
`closed` flag and a try/catch; **3.54.2 is the last 3.x release**, so no 3.x upgrade fixes it.

Under `next start` this is only log noise. The production server installs `installCrashHandlers()`,
which exits the process on the first `uncaughtException`. So on 3.54.2, `streaming: "force"` means
**any dropped step stream restarts the web server about 3 s later**, taking every in-flight request,
WebSocket session and running Claude child with it.

## S7 — stream cuts and kills

Second stack, same versions, with the production crash handlers installed in the spike server and both
the app and the inngest server under restart loops. A "cut" drops every live connection between the
Cloudflare tunnel and the app (a small TCP proxy in front of the app, destroyed on a signal) without
stopping either side. `s7c`/`s7e` use the production single-flight shape (join a live child; keep a
fulfilled result 15 min). The wrapper is the JS copy of `server/inngest/stream-detach.ts`, toggled per
request.

| Row | Setup | Result |
|---|---|---|
| control | `s7c` (3-min step), wrapper **off**, cut at 30 s | app **crashed** within the next heartbeat tick (exit logged in the same second as the cut): `FATAL uncaughtException Invalid state: Controller is already closed`, exit 1. After the restart the retry spawned a **second** child (the crash wiped the in-process guard); run completed |
| S7c | `s7c`, wrapper **on**, cut at 30 s | app **stayed up**; one `inngest-stream-consumer-cancel`; attempt 1 was invoked and **joined** the live child — **one spawn**; run completed |
| S7e | `s7e` (20 s step), wrapper on, cut at 17 s | app stayed up; attempt 1 arrived after the child ended and got the **settled result** — one spawn; run completed |
| S7a | `retries: 1`, app **killed** (SIGKILL) at 30 s | the step re-ran once after the restart (2 spawns, as for a deploy today); run completed |
| S7b | `retries: 3`, app killed at 30 s | same: one re-run, run completed — `retries` beyond 1 is not consumed by a single kill |
| S7d | 5 unsigned POSTs through the tunnel, client aborts at 0.3 s | app stayed up |

The inngest server's `error` text for a dropped step stream (all five cuts/kills):
`error parsing stream: error reading response body to check for status code: unexpected end of JSON
input` (msg `error parsing SDK response stream` / `error handling queue item`). It is the second needle
of the `inngest_step_524` alert, beside S3's `Your server reset the connection while we were reading the
reply`.

A first S7 attempt cut the stream by SIGKILLing the inngest server instead. That also crashed the
wrapper-less app, but no retry followed: `inngest start` without an external Redis keeps its queue in
memory, so the kill lost it. Production runs a durable Redis, so that variant was discarded as
unrepresentative and the cut moved to the network.

## Decision

**Branch A with the stream-detach wrapper ("A-wrap")**, reviewed by the CTO agent against this evidence.
S1, S2, S4–S6 and S8 pass; S3's one drop is random rather than a limit, and the single-flight guard plus
the settled result make one drop per run free (S7c, S7e). The SDK heartbeat leak makes raw streaming
unshippable on 3.54.2 (control row), and the wrapper removes it (S7c, S7d). `inngest` is pinned exactly;
the v4 upgrade that fixes `createStream` upstream is #8628. Recorded in ADR-243.
