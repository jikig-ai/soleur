# Streaming spike v4 — inngest@4 re-run record (feat-one-shot-8628-inngest-4-upgrade)

**Re-run of:** `knowledge-base/project/specs/archive/20260923-200917-feat-anthropic-spend-reduction/streaming-spike.md` (S1–S8) plus new checkpointing row S9.

**Versions:** SDK `inngest@4.26.0` (npm-resolved under `^4.26.0` — 4.26.1 was inside the repo's `min-release-age=3` floor on 2026-10-28) · server `inngest start` **v1.45.1** (`apps/web-platform/infra/inngest.tf` pin; `inngest version` → `1.45.1-9059f14a7`) · Cloudflare quick tunnel (`cloudflared` 2026.10.5 linux-amd64).

Run 2026-10-28 on the pipeline work host. No tunnel hostname or key appears in this record.

## Setup

| Component | Version / shape |
|---|---|
| Inngest server | `inngest start` **v1.45.1** fetched release binary, `--host 127.0.0.1 -p 8288 --sqlite-dir <tmp> --event-key <hex> --signing-key <hex>` (bare hex — the CLI rejects the `signkey-*` prefix; production strips it the same way, `inngest-bootstrap.sh:1731`) |
| SDK | `inngest` **4.26.0** from this branch's `node_modules`; `serve({ streaming: true })` |
| App | Next **16.x** production build of this branch (`next build`, placeholders for `NEXT_PUBLIC_SUPABASE_*`), served by a minimal `http.createServer → next().getRequestHandler()` server mirroring `server/index.ts` transport. `next.config.mjs` was precompiled with the Dockerfile's own esbuild line (`next.config.ts` cannot load outside `next build`) |
| Fixture mounts | the spike server intercepts `/api/spike-inngest` (client `spike-v4`, `checkpointing: false` — the shipped config) and `/api/spike-inngest-ck` (client `spike-v4-ck`, checkpointing left at the v4 default — S9 arm) before Next; **every other path, including the real `/api/inngest` route with all 74 `soleur-runtime` functions, is served by the actual app build** |
| Crash handlers | the same two handlers as `server/crash-handlers.ts` (`uncaughtException`/`unhandledRejection` → exit 1); Sentry capture is a no-op under `env -i`, the load-bearing exit semantic is identical. The app ran under a supervisor restart loop (the production shape) |
| Proxy | Cloudflare **quick tunnel** → a TCP **cut-proxy** on 127.0.0.1:3100 → app :3000. SIGUSR1 destroys all live sockets — the "cut" drops every live connection between tunnel and app without stopping either side |
| Keys | throwaway `signkey-test-<64hex>` / bare-hex event key; app booted under `env -i PATH=… HOME=… INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_BASE_URL=http://127.0.0.1:8288 INNGEST_DEV=0` — no Doppler |
| `NODE_ENV` | deliberately **unset**, so the `route.ts` `SERVE_HOST` pin (`NODE_ENV === "production" → serveOrigin https://app.soleur.ai`) does not fire — same as the 2026-09-23 run, the tunnel URL is what registers. The pin itself is unchanged by this diff |

**Deviations from the archived run, honestly recorded.** (a) Fixture functions
(s1–s8, s7a–e, throttle) live on spike-only serve mounts, not the app's registry —
the SDK code under test is the same `inngest@4.26.0` the branch ships; the real
route is still exercised by the unsigned-POST and registration-PUT rows.
(b) S3 ran twice, not three times, and the first run's stream was dropped
deliberately (see the row). (c) In v3 the spike ran `streaming: "force"`; v4's
equivalent is `streaming: true`.

## Results

Pass conditions are the plan's. Times UTC.

| # | Function | Result | Verdict |
|---|---|---|---|
| S1 | one 2s step | 3/3 completed in one attempt (`function.finished` ~2 s after dispatch) | pass |
| S2 | one 3-min step | 3/3 completed in one attempt, **zero** `invalid status code: 524`; each streamed response held ~180 s through the Cloudflare tunnel | pass — streaming still beats the ~100 s origin timeout on v4 |
| S3 | one 70-min step (`retries: 1`) | run 1: attempt-0 stream held ~6.5 min, then dropped by the deliberate S7 cut (server: `error parsing SDK response stream`); attempt-1 re-ran at +29 s, dropped again ~7 min in by the s7a/b app-SIGKILL row → FAILED, retries exhausted. Run 2 (re-fired, uninterrupted): **see S3 note below** | the drop is transport, not a length cap — see note |
| S4 | throws plain `Error` on attempt 0, `retries: 1` | 3/3: attempt-1 scheduled (at +2 s/+5 s/+15 s backoff) and succeeded | pass |
| S5 | throws `NonRetriableError`, `retries: 3` | 3/3 failed once, no retry (`function.failed` on attempt 0 only) | pass |
| S6 | two steps with `step.sleep("1m")` between | 3/3: `step-a` and `step-b` each ran once, in order | pass |
| S7 | see "S7 — stream cuts and kills" below | all rows as expected | **pass — kill-proof verified** |
| S8 | leader-loop: `cap-check` → `turn-1-claude` (20 s) → `tool-0` throws attempt-0, `retries: 3`, `timeouts.finish: "10m"` | 3/3: `cap-check` and `claude` ran **once**; only `tool-0` re-ran (attempt 1); run completed | pass — no double billing |
| — | `throttle: { limit: 2, period: "1h" }`, 4 events | 2 ran at once, 2 stayed QUEUED — then released and ran at ~30-min spacing (09:52:26, 10:22:26) | the pinned server honours `throttle` |
| — | unsigned POST through the tunnel | HTTP/2 **201** with `x-inngest-sdk: inngest-js:v4.26.0`, `x-inngest-sdk-handled: true`, `x-inngest-framework: nextjs`; streamed envelope `{"status":401,…,"body":"{\"message\":\"Unauthorized\"}"}`; no function ran; app logged `Signature validation failed` (handled, no crash) | signature still enforced; status line still 201 |
| — | registration `PUT https://<tunnel>/api/inngest` (real route) | `{"message":"Successfully registered","modified":true}` HTTP 200; server GraphQL registry: `soleur-runtime` app with **74 functions, 55 CRON triggers planned** | `modified:true` + crons planned — the #5159 invariant holds under `serveOrigin` |

### S3 — the 70-minute row

- Run 1 (fired 09:22): attempt 0's streamed step ran from 09:22:26 until the
  deliberate S7 cut at 09:28:30.947Z — **~6.5 minutes through the tunnel, no
  drop, no 524** before the cut (the cut is a forced fault, not a spontaneous
  drop). Server retried → attempt 1 invoked at 09:28:59; the app was then
  SIGKILLed for the s7a/s7b rows at 09:30:25, dropping attempt 1's stream →
  `retries: 1` exhausted → run FAILED.
- Run 2 (re-fired 09:31:59, uninterrupted): **COMPLETED** — step ran
  09:31:59.061Z → `function.finished` 10:41:59.37Z, the full **70-minute**
  streamed step through the tunnel in a single attempt, zero 524s and zero
  drops. Verdict: **pass** (the archived run's 2/3 rate was random-fault
  drops, and this run adds the clean full-length datapoint the first run's
  deliberate cuts could not).

### Heartbeat-leak scan (the load-bearing negative)

`grep -cE "Invalid state|Controller is already closed" app.log` → **0** across
the entire run — including every stream cut and abort below. The 48 `FATAL`
lines in the log are all the pre-fix `Cannot find module './lib/security-headers'`
boot failures from before `next.config.mjs` existed (config transpile gap, not
runtime). The app never restarted except on the deliberate SIGKILL.

## S7 — stream cuts and kills

Same supervisor shape as 2026-09-23: production crash-handler semantics
(uncaughtException → exit 1) installed, app under a restart loop. **No
stream-detach wrapper anywhere** — `export const { GET, POST, PUT } = handlers`.

| Row | Setup | Result |
|---|---|---|
| cut | `s7c` (3-min step) + `s7e` (20-s step) fired together; SIGUSR1 at ~16 s destroyed **6 sockets = all 3 live streams** (s7c, s7e, and S3's 70-min step) at 09:28:30.947Z | **app stayed up.** Server logged one `error parsing SDK response stream` + `error handling queue item` per dropped run (`error reading response body to check for status code: unexpected end of JSON input`) — the v4 `cancel()` handler fired instead of the leaked-heartbeat `Invalid state` throws. Retries invoked: s7c attempt-1 at +17 s, s3 attempt-1 at +29 s, s7e attempt-1 at +34 s |
| s7e | as above | attempt-1 re-ran and the run **COMPLETED** at 09:29:24 |
| s7c | as above | attempt-1 re-ran, then the stream was dropped a second time by the s7a/b app kill at ~98 s in → `retries: 1` exhausted → run FAILED. Retry-exhaustion on two deliberate drops, **not a crash** — the kill-proof mechanism (app survives the cut) verified |
| s7a | `retries: 1`, app **SIGKILLed** at ~30 s into the step (09:30:25) | supervisor restarted the app (~1 s); step re-ran on attempt 1 (09:30:56, 2 spawns — same as a deploy today); run **COMPLETED** 09:33:56 |
| s7b | `retries: 3`, app killed at ~30 s | same: one re-run (09:31:08), run **COMPLETED** 09:34:08 — `retries` beyond 1 is not consumed by a single kill |
| s7d | 5 unsigned POSTs through the tunnel, client aborts at 0.3 s | app stayed up (no restart; each abort produced the expected `Signature validation failed` handled log) |

## S9 — checkpointing matrix (measurement-only)

The shipped client config is `checkpointing: false` (CTO ruling 2026-10-28) —
unchanged by this measurement. S2's shape (one 3-min step) run once per arm.

| Arm | Client | Result |
|---|---|---|
| off (shipped) | `spike-v4`, `checkpointing: false` | S2 row above: 3/3 COMPLETED in one attempt, streamed >100 s through the tunnel |
| on (v4 default) | `spike-v4-ck`, flag absent | 1/1 **COMPLETED** in one attempt — root span 09:22:26.344Z → 09:25:26.425Z (~180 s). No checkpoint-related errors in the server log at info level; no app-side errors. The "expected degraded/fail on pinned self-hosted" hypothesis was **not** observed for this single-step shape — the run survived the >100 s step through Cloudflare. Whether the SDK negotiated the checkpoint transport or fell back to the streamed path is not visible in these logs (the server logs no `/v1/checkpoint*` lines at info); the completion is the measurement |

Inter-step latency: single-step functions — no inter-step gap to measure.
Heartbeat through >100 s step: confirmed on both arms (both crossed the
Cloudflare ~100 s origin timeout without a 524).

Other observations:

- After the real-route PUT, the throwaway server **armed the 55 real crons
  against the tunnel URL** — every `*/5`-minute cron fired into the `env -i`
  app and failed on missing runtime env (Supabase et al.), producing a
  `function.failed` per fire. Expected noise on a throwaway server; contained
  to this run and torn down with it. It doubles as live evidence that cron
  planning + dispatch works end-to-end on the registered URL.
- Heartbeat interval: not re-measured (the SDK's 3 s space-byte heartbeat is
  unchanged in v4's `createStream`; what changed is `cancel()`/`closed`
  cleanup — the property under test).

## Decision support

- The kill-proof for the `stream-detach.ts` deletion is **positive**: three live
  streams cut at once on `inngest@4.26.0` + server v1.45.1 produced zero
  `Invalid state`/`Controller is already closed` throws and the app stayed up.
  The upstream `cancel()`/`closed`/try-catch fix in `helpers/stream.js` holds on
  the pinned server.
- Streaming (`streaming: true`) still crosses the ~100 s Cloudflare origin
  timeout on v4 (S2, S3 run-1's 6.5 min, S9 both arms).
- Signature enforcement, registration/cron planning, retries, `NonRetriableError`,
  `step.sleep` scheduling, throttle, and per-attempt step re-invocation all match
  the v3 evidence.
