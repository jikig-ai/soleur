# Learning: a green run-log / cron monitor can mask a claude-eval failure — pull stdout before assigning a cause

category: integration-issues
module: inngest-cron-substrate
date: 2026-06-29
refs: #5674, #5680, ADR-033 I8

## Problem

Operator asked "did this week's crons recover after the egress fix (#5413)?" The
investigation twice reached a WRONG conclusion before the real cause surfaced:

1. **`routine_runs.status = "completed"` is not "succeeded".** The durable run-log
   middleware recorded `completed` for crons that had actually FAILED, because the
   Inngest function returns `{ ok: false }` *without throwing* on its failure paths
   — and the pre-#5674 middleware only treated a thrown error as `failed`. So the
   run-log said "completed" while the claude-eval inside the cron never did its work.
   Reading `routine_runs` alone produced a confident "5/6 recovered ✅" that was false.

2. **Even the Sentry cron-monitor heartbeat was masked.** Some crons posted a GREEN
   check-in on a non-zero claude-eval exit (logging literally `"cron monitor stays
   green (liveness, not success)"`), while others posted `error`. So the monitor
   colour was an unreliable success signal too — `agent-native-audit` showed `ok`
   at the same minute its claude-eval failed with `Credit balance is too low`.

3. **The failure cause was invisible and got misattributed.** The cron substrate
   discarded claude's stdout (ADR-033 I5) and wrote `error_summary = null`, so the
   Sentry issue was a generic `"spawn exited non-zero AND created no … issue"`.
   Meanwhile an unrelated `egress-blocked` Sentry issue was firing continuously
   (Cloudflare `104.16.x.34` drops). The two concurrent signals composed into a
   plausible-but-wrong story: "the #5413 egress fix is incomplete and is breaking
   the crons." It was not — the crons reached Anthropic fine and got a **billing**
   error. The egress drops were real but **non-causal** and on a different host set.

## Solution / what actually found it

Pulled claude's **stdout tail from Better Stack** (`scripts/betterstack-query.sh`
under `doppler run -p soleur -c prd_terraform`, table
`t520508_soleur_inngest_vector_prd_3_logs`). One line settled it:

```
{ fn: 'cron-agent-native-audit', stream: 'stdout' } Credit balance is too low
→ claude-eval exited non-zero (best-effort); cron monitor stays green (liveness, not success)
```

Root cause = **Anthropic operator-key credit exhaustion** (started ~10:36Z that day),
not egress. Confirmed by a direct minimal call to the exact operator
`ANTHROPIC_API_KEY` (HTTP 200 after top-up) rather than waiting on a cron.

The #5674 fix makes this self-diagnosing going forward: capture the scrubbed
failure reason into Sentry + `routine_runs.error_summary`; classify-fatal so a
credit/auth/spawn-fault non-zero flips the monitor RED (benign max-turns stays
green per #4727); and an hourly canary probe pages on credit exhaustion directly
from the HTTP body.

## Key Insight

When diagnosing autonomous-cron health, **the green status layer you read first is
the one most likely to be lying.** Rank the signals by authority:

- `routine_runs.status` / a green cron monitor = **liveness**, NOT success — a
  non-throwing `return { ok:false }` and a "liveness-green" heartbeat both look
  identical to a healthy run.
- The **claude-eval stdout tail** (Better Stack) is the only layer that carries the
  actual cause (`Credit balance is too low`, `invalid x-api-key`, a traceback).
- For an external dependency (the Anthropic key), **probe it directly** — a 1-token
  API call validated the top-up in seconds; re-firing a heavy cron raced a ~2-min
  billing-propagation lag and produced a false "still broken."

And: **two concurrent error signals are not one cause.** A still-firing
`egress-blocked` issue + a `spawn-exited-non-zero` cron is two problems, not a
causal chain — verify the link by reading the actual failure cause, don't infer it
from temporal coincidence. (Here egress, credit exhaustion, AND a separate
`follow-through` NULL-installation_id bug were all live at once; filed as #5676 /
#5674 / #5675 respectively.)

## Session Errors

- **Read `routine_runs.completed` as "recovered" (twice).** Recovery: cross-checked
  the Sentry cron-monitor heartbeats, then the Better Stack stdout. Prevention:
  treat run-log/monitor green as liveness; confirm success from the eval stdout or a
  reason field (now shipped via #5674).
- **Misattributed the failures to the egress fix.** Recovery: the stdout named the
  real cause (billing). Prevention: read the captured failure cause before assigning
  a causal story when multiple error signals overlap.
- **Scanned Doppler config `prd` for the Better Stack query token** and concluded
  "no query access." Recovery: the creds are in `prd_terraform` (see
  `runbooks/betterstack-log-query.md`). Prevention: read the betterstack-log-query
  runbook first; the ingest token (`prd`) is write-only, the ClickHouse query creds
  live in `prd_terraform`.
- **Credit-propagation race:** a post-top-up cron re-fire still hit credit-balance
  for ~2 min. Prevention: validate an external-credential fix with a direct probe of
  the credential, not by waiting on a downstream consumer.
- Two one-off process slips: scratchpad dir needed `mkdir` before writes; an `Edit`
  failed because the file was only `sed`-viewed, not Read first.

## Tags
category: integration-issues
module: inngest-cron-substrate
