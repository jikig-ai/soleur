---
title: "ADR-243: Inngest step requests cross the Cloudflare proxy, so long steps stream, and each Claude spawn is single-flight, capped and throttled"
status: Accepted
date: 2026-09-23
supersedes: []
amends:
  - ADR-033
  - ADR-030
tags: [inngest, cloudflare, streaming, claude-eval, cost, anthropic, single-flight]
---

# ADR-243: Inngest step requests cross the Cloudflare proxy, so long steps stream, and each Claude spawn is single-flight, capped and throttled

## Status

Accepted — 2026-09-23 (#8611). Evidence:
[`streaming-spike.md`](../../../project/specs/feat-anthropic-spend-reduction/streaming-spike.md).
Learning: `2026-09-23-cloudflare-524-made-every-long-inngest-step-run-twice-and-commit-nothing.md`.

## Context

`app/api/inngest/route.ts` pins `serveHost` to `https://app.soleur.ai` (#5159), a Cloudflare-proxied
record. The self-hosted Inngest server therefore calls **every step** through Cloudflare, which gives up
on an origin response after ~100 s with a 524. A claude-eval step holds its request for 5–70 minutes.
So the first attempt got a 524, `retries: 1` re-invoked the step (nothing memoized), a **second paid
Claude session** spawned beside the still-running first, the retry got a 524 too, and the run failed
before `verify-output` / `safe-commit-pr`. Measured from the cost markers' own `cost_usd` over 30 days:
duplicates were **51%** of cron spend ($82.04 of $159.81), 24 of 33 paid runs committed nothing, and a
$50 top-up lasted ~39 h.

The `serve()` handler is shared: the same transport change reaches the founder-facing BYOK leader loop
(`agent-on-spawn-requested`), so the change was held to the `single-user incident` threshold.

## Decision

### 1. Stream step responses, and never let the SDK stream see a disconnect

`serve({ streaming: "force" })`. Every POST answers **HTTP 201** at once and writes a heartbeat byte
every 3 s, then one JSON envelope carrying the real status. Spike S2 (3-minute step, real Cloudflare
proxy): one attempt, zero 524s. S4/S5/S6/S8: streamed errors are read as errors, `NonRetriableError`
does not retry, sleeps work, and the leader-loop chain's memoized `claude` step is **not** re-run.

**The SDK defect this has to route around.** In `inngest` 3.54.2, `helpers/stream.js` `createStream`
clears its heartbeat `setInterval` only in `finalize()`; the `ReadableStream` has no `cancel()` and its
`enqueue` calls are unguarded. When the consumer disconnects mid-step, every tick throws `Invalid state:
Controller is already closed` from a timer (measured: one every 3 s, 281 in 14 min after one drop), and
`finalize()`'s `.then` rejects the same way. Both are process-level fatals, and
`server/crash-handlers.ts` exits the process on the first one — one dropped step stream would restart
the web server, killing every in-flight request, WebSocket session and running Claude child. An
unsigned caller that resets its socket before `finalize` reaches the same path.

`server/inngest/stream-detach.ts` wraps the route's POST: it re-streams the SDK body through its own
stream and, when **its** consumer cancels, keeps draining the SDK stream to its end and discards the
bytes. The SDK controller never sees a cancel. Each cancel reports
`op: "inngest-stream-consumer-cancel"`, which is the only measurement of the production drop rate.
`inngest` is pinned **exactly** at `3.54.2`, and `stream-detach.test.ts` pins `stream.js` by content
hash: any SDK change re-opens this section. `inngest@4.21.0` fixes `createStream` upstream; the wrapper
is deleted with that upgrade.

### 2. At most one Claude child per (function, run), and a late retry gets the finished result

`spawnClaudeEval` is the single chokepoint for every Claude spawn (the last two inline spawners,
`cron-daily-triage` and `cron-follow-through-monitor`, moved onto it). A `globalThis` map keyed
`${cronName}:${runId}` (runId validated as an Inngest ULID; a missing one is reported and never joins)
holds the in-flight promise, set before the first `await`:

- a re-invocation while the child lives **joins** it;
- a re-invocation within **15 minutes** after it fulfilled gets **the same result** (a stream that
  dropped after the child finished but before Inngest read the result);
- a rejection is not kept, so a transient setup failure can retry.

**Process-local state (AP-013) is acceptable because one web host executes steps:** `dns.tf` points
`app` at web-1 only. Putting a second host behind the proxy breaks this guard — that change must reopen
this ADR (shared state, or host affinity for `/api/inngest`).

### 3. Bound what a run and a function can spend

- `--max-budget-usd` on all 18 spawn sites (`server/inngest/cron-budgets.ts`, verified on the pinned
  CLI 2.1.219; a capped run ends `is_error` with subtype `error_max_budget_usd`). Rule:
  `ceil(max(3 × median, 1.25 × largest observed, $2))` from the markers' `cost_usd`, Opus 5 runs
  re-priced to Opus 5.5; sites with no funded run take a tier default ($10 audit, $5 execution).
- `throttle: { limit: 2, period: "1h" }` on all 18 (the pinned server honours it: spike, 2 ran / 2
  queued). This bounds manual `soleur:trigger-cron` fires, each of which is a new run with a fresh cap.
- `AUDIT_MODEL` re-pinned `claude-opus-5` → `claude-opus-5-5` (cheaper on every price axis).
- Better Stack alerts: any `invalid status code: 524` from inngest-server in 15 min; cron Claude spend
  above **$15 per trailing 24 h** (≈ 2× the projected post-fix funded-day rate); and 24 h with no cost
  marker at all (credit-probe RED rows count, so an out-of-credit day stays quiet).

| Site | Cap ($/run) | Schedule (UTC) |
|---|---:|---|
| cron-agent-native-audit | 2 | 09:00 on the 15th |
| cron-architecture-diagram-sync | 9 | Sun 02:00 |
| cron-competitive-analysis | 10 | 09:00 on the 1st |
| cron-growth-audit | 16 | Mon 07:00 |
| cron-legal-audit | 10 | 11:00 on 1 Jan/Apr/Jul/Oct |
| cron-ux-audit | 10 | 09:00 on the 1st |
| cron-bug-fixer | 4 | daily 06:00 |
| cron-campaign-calendar | 4 | Mon 16:00 |
| cron-community-monitor | 6 | daily 08:00 |
| cron-content-generator | 14 | Tue, Thu 10:00 |
| cron-daily-triage | 5 | daily 04:00 |
| cron-follow-through-monitor | 5 | Mon–Fri 09:00 |
| cron-growth-execution | 4 | 10:00 on the 1st and 15th |
| cron-roadmap-review | 4 | Mon 09:00 |
| cron-seo-aeo-audit | 10 | Mon 11:00 |
| event-ship-merge | 5 | manual event only |
| oneshot-f2-defer-gate-review | 5 | one-shot event |
| oneshot-recheck-4217-calibration | 5 | one-shot event |

**Worst-case scheduled day** (every capped run hits its cap): daily crons $15 + weekday
follow-through $5 = $20 on an ordinary weekday; **$54 on a Monday** (+ growth-audit, seo-aeo,
roadmap, campaign-calendar); **$88 on a Monday that is the 1st of a quarter** (+ competitive, ux,
growth-execution, legal). **Manual-trigger row:** the throttle admits at most 48 starts per function per
day, so the sum of caps (**$128**) × 48 is a theoretical ceiling the per-run caps do not meaningfully
bound — the daily burn alert is the dollar bound, and a Console workspace spend limit (#8614) is the hard
one. Caps and the alert threshold are recalibrated after 14 funded days (#8613).

## Consequences

- The signature 401 now travels in the streamed envelope; the HTTP status line of every POST is 201.
  `signature-verify.test.ts` asserts the envelope and pins the 201. Unsigned callers learn the SDK
  version header, and run no function (spike). No edge rule was added.
- A dropped stream is survivable once: the retry joins the live child (or gets its result). With
  `retries: 1`, a second drop in the same run fails it — spend wasted, not doubled. Raising `retries`
  was **not** done here: it applies to every step of these functions (clone, commit/PR, issue filing),
  whose idempotency is unverified. Decide it from the cancel telemetry.
- A web deploy still kills running Claude children; the retry then spawns a fresh child (correct).
- The BYOK leader loop is not behind the guard. A drop during its `claude` step re-runs that step and
  bills the founder's key again — a risk that exists today, which streaming does not increase. The
  post-merge check and the 72 h rollback trigger in the plan watch it.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Streaming without the wrapper | One dropped stream crashes the web process (§1), and an unsigned request can reach the same path. |
| Upgrade to `inngest@4` now | Fixes `createStream`, but is a major-version migration across ~70 functions and three middlewares, untested against server v1.19.4, and would need the whole spike re-run. Deferred; its trigger is "delete stream-detach.ts". |
| Detach-and-poll (plan Fix 1B) | Plan review found nine defects, all caused by runs that sleep while a detached child works. |
| Cap every step below ~20 min | Sessions run 5–25 min, and the one observed drop (~20.5 min) looks random, not a limit. |
| Private `serveHost` | Breaks cron planning: only the public-host registration re-plans crons (#5159). |
| `step.waitForEvent` completion | Same sleeping-run defect class as detach-and-poll. |
| Inngest Connect | Switches every function's transport; self-hosted support on v1.19.4 unverified. |
| Raise Cloudflare's origin timeout | Enterprise only. |
| A separate serve handler for BYOK functions | Does not remove the cron problem, and doubles the registration surface. |

## Spike vs production differences

The spike used a Cloudflare **quick tunnel** (production: the proxied record) and a minimal server
mirroring `server/index.ts`'s transport (production also installs the crash handlers — the S7 rows
re-ran with them). Phase 6 of the plan closes the edge difference on production.

## References

- #8611, plan `2026-09-23-fix-anthropic-spend-cron-524-double-run-plan.md`, #5692 (burn alert),
  #8613 (turn/cap recalibration), #8614 (Console spend limit).
- ADR-033 (child-process spawn inside one `step.run`), ADR-030 (signing), ADR-108 (cost markers),
  ADR-218 (Terraform-managed Logs alerts).
