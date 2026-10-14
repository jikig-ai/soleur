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
[`streaming-spike.md`](../../../project/specs/archive/20260923-200917-feat-anthropic-spend-reduction/streaming-spike.md).
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
every 3 s, then one JSON envelope carrying the real status. The exception is a POST carrying a
non-empty `?probe=` query value, which the SDK does not stream and answers with its real status.
Spike S2 (3-minute step, real Cloudflare proxy): one attempt, zero 524s. S4/S5/S6/S8: streamed errors
are read as errors, `NonRetriableError` does not retry, sleeps work, and the leader-loop chain's
memoized `claude` step is **not** re-run.

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
bytes. The SDK controller never sees a cancel. The route passes `streamRequestInfo(request)`, so each
cancel is reported (warning level, op `inngest-stream-consumer-cancel`) with tags `signed:true|false`
and `fn:<fnId>` and extras `stepId` / `msSinceResponse`. The signed ones are the production drop rate;
unsigned callers aborting after the 201 are tagged so they can be filtered out. A source error while
draining reports op `inngest-stream-drain-error`. `inngest` is pinned **exactly** at `3.54.2`, and
`stream-detach.test.ts` pins `stream.js` by content hash: any SDK change re-opens this section.
`inngest@4.21.0` fixes `createStream` upstream; the wrapper is deleted with that upgrade (#8628).

### 2. At most one Claude child per (function, run), and a late retry gets the finished result

Every cron Claude spawn goes through `spawnClaudeEval` (the last two inline spawners,
`cron-daily-triage` and `cron-follow-through-monitor`, moved onto it). A `globalThis` map keyed
`${cronName}:${runId}` (runId validated as an Inngest ULID; a missing one is reported at error level
and never joins) holds the in-flight promise, set before the first `await`:

- a re-invocation while the child lives **joins** it (reported at warning level, op
  `claude-eval-singleflight-join`, tag `cron`);
- a re-invocation within **2 hours** (`SETTLED_TTL_MS`) after it fulfilled gets **the same result**.
  Two hours, not minutes: while a dropped step waits for its retry, the account-wide `cron-platform`
  concurrency slot (limit 1) is free, so another claude-eval cron (up to 70 minutes) can take it
  first. The window covers the longest `MAX_TURN_DURATION_MS` plus that queue; it is bounded at
  ≤ 2 starts/h × 18 functions × 2 h = 72 entries of ~16 KB;
- a rejection is not kept, so a transient setup failure can retry;
- the key carries no step identity, because every caller spawns once per run. A second spawn in the
  same run with a **different** prompt is refused (op `claude-eval-singleflight-key-collision`)
  rather than handed the first spawn's result.

**"Single chokepoint" means the spawn, not the sandbox.** The two migrated crons run in the server's
own working directory and do **not** go through `setupEphemeralWorkspace`, so they skip the
deploy-lease check and the containment hook. Their bash surface is bounded only by `--allowedTools`
(pinned to their `CRON_BASH_ALLOWLISTS` rows by test), and `Read`/`Glob`/`Grep` are unscoped inside
`/app` — both unchanged from before this PR.

**Process-local state (AP-013) is acceptable because one web host executes steps:** `dns.tf` points
`app` at web-1 only. A change that puts a second host behind `/api/inngest` step calls (ADR-068 load
balancing, ADR-143 web-2 serving weight) breaks this guard and must reopen this section (shared
state, or host affinity for `/api/inngest`). ADR-068 and ADR-143 carry the back-pointer.

### 3. Bound what a run and a function can spend

- **Per-run ceiling, owned by the substrate.** `spawnClaudeEval` appends
  `--max-budget-usd <CLAUDE_BUDGET_USD[cronName]>` itself (`server/inngest/cron-budgets.ts`), refuses a
  caller-supplied `--max-budget-usd` (the CLI takes the last value, so it could raise the cap), and
  throws before any side effect for a cron with no budget entry. Sites carry no budget flag. Verified
  on the pinned CLI (2.1.219 at design, 2.1.280 now): a capped run ends `is_error` with subtype
  `error_max_budget_usd`. `classifyEvalFatal` reports it as its own fatal class, `budget-capped`,
  checked before the clean-exit shortcut, so a best-effort cron goes red with a reason even on exit 0;
  `cron-daily-triage` and `cron-follow-through-monitor` report their heartbeat as failed on it.
- **Cap rule:** `ceil(max(3 × median, 1.25 × largest observed, $2))` from the markers' `cost_usd`,
  Opus 5 runs re-priced to Opus 5.5. A single sample is not data (it is often a run cut short by
  credit exhaustion), so n=1 sites and sites with no funded run take a tier default: $15 audit tier,
  $5 execution tier.
- `throttle: { limit: 2, period: "1h" }` on all 18 (the pinned server honours it: spike, 2 ran / 2
  queued). This is a **rate** limit, not a spend bound: Inngest queues the excess, which still runs and
  is still billed. It spreads a burst of manual `soleur:trigger-cron` fires out long enough for the
  hourly burn alert to page first. The dollar bound is the burn alert and, ultimately, a Console
  workspace spend limit (#8614).
- `AUDIT_MODEL` is `claude-opus-5-5` (cheaper than Opus 5 on every price axis). This PR planned the
  re-pin; #8601 landed the same change on main first, so it arrives here through the merge.
- Better Stack alerts: any `invalid status code: 524`, or either dropped-stream text, from
  inngest-server in 15 min; cron Claude spend above **$25 per trailing 24 h**
  (`local.claude_cost_daily_burn_usd`; a healthy Monday's medians already sum to ≈ $13 before the two
  newly metered crons, and the measured incident days read $28–34); and 24 h with no cost marker at all
  (credit-probe RED rows count, so an out-of-credit day stays quiet). The burn sum is a **floor**:
  null-cost markers (timeouts, killed runs, the HTTP-transport crons) count as $0, a killed process
  emits no marker, and `summarizeEmail` on the operator key emits none.

| Site | Cap ($/run) | Schedule (UTC) |
|---|---:|---|
| cron-agent-native-audit | 15 | 09:00 on the 15th |
| cron-architecture-diagram-sync | 9 | Sun 02:00 |
| cron-competitive-analysis | 15 | 09:00 on the 1st |
| cron-growth-audit | 16 | Mon 07:00 |
| cron-legal-audit | 15 | 11:00 on 1 Jan/Apr/Jul/Oct |
| cron-ux-audit | 15 | 09:00 on the 1st |
| cron-bug-fixer | 4 | daily 06:00 |
| cron-campaign-calendar | 4 | Mon 16:00 |
| cron-community-monitor | 6 | daily 08:00 |
| cron-content-generator | 14 | Tue, Thu 10:00 |
| cron-daily-triage | 5 | daily 04:00 |
| cron-follow-through-monitor | 5 | Mon–Fri 09:00 |
| cron-growth-execution | 5 | 10:00 on the 1st and 15th |
| cron-roadmap-review | 4 | Mon 09:00 |
| cron-seo-aeo-audit | 10 | Mon 11:00 |
| event-ship-merge | 5 | manual event only |
| oneshot-f2-defer-gate-review | 5 | one-shot event |
| oneshot-recheck-4217-calibration | 5 | one-shot event |

**Worst-case scheduled day** (every capped run hits its cap): daily crons $15 + weekday
follow-through $5 = $20 on an ordinary weekday; **$54 on a Monday** (+ growth-audit, seo-aeo,
roadmap, campaign-calendar); **$104 on a Monday that is the 1st of a quarter** (+ competitive,
ux and legal at 15 each, growth-execution 5); the 15th adds agent-native's 15. **Manual-trigger row:** the
throttle admits at most 48 starts per function per day, so the sum of caps (**$157**) × 48 is a
theoretical ceiling the per-run caps do not meaningfully bound — the daily burn alert is the dollar
bound, and a Console workspace spend limit (#8614) is the hard one. Caps and the alert threshold are
recalibrated after 14 funded days (#8613).

## Observability

| Signal | Where it lands | Visible as |
|---|---|---|
| `claude-eval-singleflight-join` | Sentry (warning), tag `cron` | the guard worked: a retry joined a live child or got its settled result |
| `claude-eval-singleflight-no-runid` | Sentry (error) | the guard was bypassed for that spawn — investigate |
| `claude-eval-singleflight-key-collision` | Sentry (error) | a second, different spawn in one run was refused |
| `inngest-stream-consumer-cancel` | Sentry (warning), tags `signed`, `fn` | a step stream dropped; `signed:true` rows are the production drop rate |
| `inngest-stream-drain-error` | Sentry (warning) | the SDK stream errored while being drained |
| `budget-capped` fatal class | Sentry cron monitor red + `routine_runs.error_summary` | a run stopped at its cap |
| `SOLEUR_CLAUDE_COST` (`subtype`, `num_turns`; leader-loop `turn`, `attempt`) | Better Stack (Vector Source 3) | cap hits per cron; a leader-loop marker with `attempt > 0` is a double-billed founder turn |
| inngest-server `invalid status code: 524` / dropped-stream texts | Better Stack (Vector Source 1) → `inngest_step_524` alert | the transport failed a step |

The 524 path relies on observed behaviour: inngest-server PRIORITY 6 rows ship although Source 1's
comment says INFO drops at source (#6551). Guard 2 pins the source shape; `vector.toml` was left
untouched because any edit to it re-hashes and reloads Vector on the production host.

## Consequences

- The signature 401 now travels in the streamed envelope; the HTTP status line of every non-probe POST
  is 201. `signature-verify.test.ts` asserts the envelope and pins the 201. Unsigned callers run no
  function (spike), and receive the SDK's headers: `x-inngest-sdk`, `x-inngest-framework`,
  `server-timing`, and an echo of their own `x-inngest-server-kind` as
  `x-inngest-expected-server-kind` (CR/LF cannot be injected). Accepted; no edge rule was added.
- A dropped stream is survivable once: the retry joins the live child (or gets its result). With
  `retries: 1`, a second drop in the same run fails it — spend wasted, not doubled. Raising `retries`
  was **not** done here: it applies to every step of these functions (clone, commit/PR, issue filing),
  whose idempotency is unverified. Decide it from the cancel telemetry (#8613).
- A web deploy kills running Claude children only when the ADR-078 cron drain times out (it waits up
  to 4200 s for a `claude` child); the retry then spawns a fresh child (correct, the in-process map died
  with the process).
- The account-wide `cron-platform` concurrency slot (limit 1) is now held for a whole claude-eval run
  instead of being released at the ~100 s 524. So a 06:00 `cron-email-ingress-probe` can wait behind
  `cron-bug-fixer` (up to ~50 min): delayed, not dropped.
- The Routines UI now shows live rows for `cron-daily-triage` and `cron-follow-through-monitor`
  (`routine_run_progress` SELECT is any-authenticated per ADR-077; system ids only, no personal data).
- The BYOK leader loop is not behind the guard. A drop during its `claude` step re-runs that step and
  bills the founder's key again — a risk that exists today, which streaming does not increase. It is
  now **detectable**: the leader-loop cost marker carries `turn` and `attempt`, and `attempt > 0` (or
  two markers for one `(id, turn)`) is a double bill. The plan's 72 h rollback trigger reads that.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Streaming without the wrapper | One dropped stream crashes the web process (§1), and an unsigned request can reach the same path. |
| Upgrade to `inngest@4` now | Fixes `createStream`, but is a major-version migration across ~70 functions and three middlewares, untested against server v1.19.4, and would need the whole spike re-run. Deferred to #8628. |
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

- #8611, plan `plans/archive/20260923-200917-2026-09-23-fix-anthropic-spend-cron-524-double-run-plan.md`, #5692 (burn alert),
  #8613 (turn/cap/threshold recalibration and the `retries` decision), #8614 (Console spend limit),
  #8628 (inngest v4 upgrade; deletes stream-detach), #8601 (the AUDIT_MODEL re-pin).
- ADR-033 (child-process spawn inside one `step.run`), ADR-030 (signing), ADR-108 (cost markers),
  ADR-218 (Terraform-managed Logs alerts), ADR-077 (routine run progress), ADR-078 (deploy cron
  drain), ADR-068 / ADR-143 (multi-host serving, which reopens §2).
