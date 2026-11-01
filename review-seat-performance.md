# Performance Oracle review — PR #11780 (feat-one-shot-11772-next-dev-server-crash)

Lens: `soleur:engineering:review:performance-oracle`. Scope: `git diff origin/main...HEAD` in
`/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-11772-next-dev-server-crash`.
Report-only; no git writes/edits performed.

## Verdict

**SHIP with one P2 advisory.** The diff's own-code delta is ~34 lines on a cold
per-fatal path (`isBenignClientAbort` is O(1) and runs only on process-level
exceptions). The dominant performance surface is not the predicate — it is the
*volume* of what the new non-fatal branch emits, and the unquantified serving-path
churn in next 16.3.8 → 16.4.3. Relative to the pre-fix state (unauthenticated
one-request restart-DoS) this change is a strict improvement even in the worst
case analyzed below.

## P1 — none

## P2

### P2-1: Undebounced warn emission on an unauthenticated-triggerable abort path

`server/crash-handlers.ts:85-89` and `:95-99` call `warnSilentFallback`
(`server/observability.ts:287`) for every inbound client abort that reaches the
process handlers. `warnSilentFallback` has **no rate limit**: each call emits one
pino `logger.warn` line plus one `Sentry.captureException` (`level: "warning"`),
each preceded by `redactErrorForEmit` (`server/pii-redact.ts:173` — recursive walk
over message/stack/own props) and `sanitizeLogMessage`, and followed by
`beforeSend` → `scrubSentryEvent` (`server/sentry-scrub.ts:178` — recursive event
walk) plus envelope serialization and transport egress.

The trigger is unauthenticated and cheap: `next-server.js:1213-1231` (installed
16.4.3) runs `cloneBodyStream()` + `finalize()` for **every non-GET/HEAD request
with a body** that passes Node middleware; `middleware.ts:887` matcher covers all
non-asset paths including public ones (`/login` POSTs, public `/api/*`). A client
that opens a connection, sends a partial body, and RSTs mints exactly the
`Error: aborted` + `code: ECONNRESET` pair — verified still present in
`node_modules/next/dist/server/body-streams.js` (`replaceRequestBody` still copies
`_events` onto the `IncomingMessage`; `p2` carries no `'error'` listener). Confirmed
the upstream fix is NOT in 16.4.3, so the classifier remains necessary.

Back-of-envelope: at 100 aborts/s sustained ≈ **8.6M Sentry warning events/day**
(grouped to one issue but every envelope counts against quota before grouping;
spike protection may throttle, org-config dependent) + ~3–5 GB/day of pino warn
egress at ~400 B/line. CPU per event is bounded (~0.1–0.3 ms for redact + scrub +
envelope build) — at 100/s that is ~1–3% of a core; the cost driver is quota +
log volume, not CPU. This converts a restart-DoS into a quota/log amplification —
strictly better, but the amplification is unbounded.

`mirrorWarnWithDebounce` (`server/observability.ts:588`) exists for exactly this
shape: a constant key (`"client-abort"`, no request context is available at the
process-handler level) collapses a flood to ≤1 warn / 5 min / process while still
routing through `warnSilentFallback` — i.e., it does NOT contradict the settled
`warnSilentFallback` ruling. The tension is with the plan's stated observability
property (`2026-11-01-fix-next-16-4-1-e2e-dev-server-crash-plan.md:398`: "grouped;
burst readable as event count") — coalescing loses per-abort counts. Options, in
ascending effort: (a) keep undebounced and accept quota/log spend, relying on
Sentry spike protection — an explicit accepted-cost ruling is warranted; (b)
wrap in `mirrorWarnWithDebounce` with a constant key — cheapest bound, loses
burst counts; (c) local counter flushed periodically as one warn carrying
`extra.count` — preserves burst sizing at ~20 lines. Recommend (b) or (c) if the
security lens wants the flood bounded in-process; otherwise record (a) as a
decision-challenges row rather than leaving it implicit.

## P3

### P3-1: Next 16.3.8 → 16.4.3 serving-path churn is broad and unmeasured

v16.4.0 alone is ~500 commits touching the serving path: "Separate App Route/Page
render and prerender pipelines" (#96662/#96659), "Remove WorkStore execution
mode" (#96674), client Router-Cache/prefetch unification (#96876, #96439,
#96583, #96727), and two bundled-React canary bumps (#96550, #96735). These
interact with the app's `experimental.staleTimes.dynamic: 30`
(`next.config.ts:139-141`) — prefetch/RSC-reuse behavior may shift request
volume to the server in either direction. Post-deploy watch: p95 latency, RSC
fetch rate, RSS (the 25 MB `proxyClientMaxBodySize` clone buffers are
pre-existing). One upstream change is directly complementary: "Don't report a
client-aborted RSC stream as a render error" (#96715) reduces downstream
error noise from the same abort class.

### P3-2: 16.4.3 backports are mildly net-positive on this app's path

"Don't load the app-page runtime in proxy.ts" (#100423) and "Avoid loading
standalone React in server bootstrap" (#100610) reduce proxy/bootstrap module
load; "Keep OpenTelemetry request traces together" (#100542) is tracing
correctness. 16.4.1 is the three security fixes; 16.4.2 is Turbopack/GC —
mostly dev/build. `images.localPatterns` already scopes the optimizer to
`/icons/**`, and `experimental.serverActions` is configured so the
GHSA-p3m5-59mp-jv5r DoS fix lands on a live surface — both upstream-fixed, no
repo action.

### P3-3: Non-findings recorded for completeness

- `isBenignClientAbort` (crash-handlers.ts:74-80): O(1), two string compares —
  negligible even on the abort path.
- warn path does not touch the `handling` re-entrancy flag — correct; the fatal
  arm stays armed.
- Lockfile delta is clean: only `next` + `@next/*` scope + `sharp` optional-dep
  floor; no transitive churn. `warnSilentFallback` is also called in dev/e2e where
  `SENTRY_DSN` is unset — captureException short-circuits; cost there is one pino
  line per abort.
- `assert-dependabot-drain.py` rows/floors and `.test.sh` arms are CI-time
  Python/bash — no runtime cost; MIN_ROWS/MIN_RESOLVED/MIN_ASSERTIONS bumps are
  internally consistent (36/36/34).

## Settled rulings — checked, not contradicted

exact-pair scope (verified: in-repo `Error("aborted")` producers carry no `.code`);
prod-wide (`installCrashHandlers` at `server/index.ts:83` in the single bundle);
`warnSilentFallback` helper choice (P2-1 concerns the wrapper, not the helper);
team_names deferral and defense-in-depth stance — no contradiction found.
