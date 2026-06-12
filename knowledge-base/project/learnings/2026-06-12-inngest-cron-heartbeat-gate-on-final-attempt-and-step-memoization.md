# Learning: Inngest cron Sentry-heartbeat must gate on the final attempt — and skip the whole `step.run`, not just the POST

## Problem

The Sentry Crons monitor `scheduled-stale-deferred-scope-outs` (Inngest function
`cron-stale-deferred-scope-outs`, `0 12 * * *`) fired a high-priority **"An error
check-in was detected"** page. It had succeeded 06-11 and failed once 06-12
(`failure_issue_threshold = 1`). The cron auto-closes stale `deferred-scope-out`
GitHub issues via the synthetic-probe Octokit.

## Root cause (two compounding bugs)

1. **The handler paged before Inngest's retry ran.** The function is registered
   `retries: 1` (2 attempts), but the handler posted the `status=error` Sentry
   heartbeat at the end of *every* failed attempt and only *then* rethrew to
   trigger the retry. So a transient GitHub fault (401-after-budget / 403
   secondary-rate-limit / 429 / 5xx) on attempt 0 paged the operator even though
   attempt 1 recovered. The "page before retry" timing was itself the bug.
2. **Only a *thrown* sweep flips the monitor.** `sweepFailed` is set solely by
   the `catch` wrapping `step.run("sweep…")`. Per-issue write 403s (missing
   `issues:write`) are caught *inside* the comment/close loop and never set
   `sweepFailed`. So the only paths that page are `createProbeOctokit()` and the
   bare `GET /search/issues` call — a transient on either, not a permission bug.

## Solution

Read Inngest's zero-indexed `ctx.attempt` / `ctx.maxAttempts` (added as optional
fields to the shared `HandlerArgs`) and gate the `error` heartbeat on the final
attempt: `isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`.

- **non-final failure** → `reportSilentFallback` (forensic breadcrumb) + **skip
  the heartbeat `step.run` entirely** + rethrow to trigger the retry;
- **final failure** → `error` heartbeat + rethrow;
- **success** → `ok` heartbeat (+ a `recovered_after_attempts` warn when
  `attempt > 0` so a daily transient flap is queryable as a trend).

Legacy callers/tests passing no `attempt` read `attempt=0 / maxAttempts=1` →
`isFinalAttempt=true` → identical to pre-fix behavior. The fix is path-agnostic:
Inngest's existing `retries: 1` is the recovery mechanism; the only bug was
paging before it ran.

## Key Insight

**Skip the whole `step.run`, not just the side effect inside it.** A completed
`step.run` is *memoized across retries* — Inngest replays its recorded result on
the next attempt instead of re-executing the callback. So if you keep
`step.run("sentry-heartbeat", …)` always-invoked with a conditional POST
*inside*, a non-final failed attempt completes the step (posting nothing), it
gets memoized, and the retry replays the memoized empty step — the recovered
`ok` is **never** posted and the monitor stays red. The fix must skip the entire
`step.run` call on the non-final failure path so the heartbeat step is first
executed (with the authoritative status) on the final attempt. A `step.run` that
*throws* is not memoized as terminal — it re-runs on retry — which is why the
sweep step correctly re-executes.

**A monitor "error check-in" narrows the root cause to a thrown function, not a
caught one.** Before theorizing (the first-pass hypothesis here was
`issues:write` consent drift), trace which code path actually sets the
error/`sweepFailed` flag. Per-issue `try/catch` that mirrors to Sentry and
*continues* never flips the monitor; only an uncaught throw out of the gated step
does. The failure *signal* (error check-in, single failure after a prior
success) is a stronger root-cause discriminator than a plausible-sounding
permission theory: a standing permission bug would have failed the day before
too.

**Fail-safe direction matters.** `maxAttempts` is *optional* on Inngest's
`BaseContext`. If a fire ever omits it, `?? 1` collapses `isFinalAttempt` to
always-true → the cron over-pages (the original bug) rather than masking a real
failure with a false `ok`. Ambiguous attempt data must default to paging.

## Session Errors

- **Near-miss: nearly fired the prod cron via `/soleur:trigger-cron` to
  "reproduce" the failure.** Recovery: recognized the trigger route is
  fire-and-forget — it dispatches the Inngest event and returns, so it cannot
  surface the cron's *thrown* error back to the caller (the error lands in
  Inngest run logs / Sentry, not the curl response). Reproduced in a hydrated
  worktree instead. **Prevention:** to *observe* a cron's failure, run/inspect
  its logic in a worktree or read Inngest/Sentry run detail — do NOT POST to the
  prod trigger route expecting the error back; it is for *firing* a cron, not
  diagnosing one. (No code fix — correct behavior, usage gotcha.)
- **One-off: first-pass root-cause hypothesis ("issues:write consent drift") was
  falsified by control-flow analysis.** Recovery: traced that per-issue 403s are
  caught and never set `sweepFailed`. **Prevention:** captured as the "error
  check-in ⇒ thrown function" key insight above.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
