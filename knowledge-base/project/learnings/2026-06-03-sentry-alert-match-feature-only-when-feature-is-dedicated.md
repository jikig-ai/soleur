# Learning: Sentry alert op-scoping can silently drop self-failure signals — match feature-only when the feature tag is dedicated to one emitter

## Problem

Planning the `workspace_sync_health` Sentry issue-alert (#4882), I scoped it to
the 3 user-actionable "finding" ops (`ready-null-installation`,
`stale-sync-failed`, `went-quiet`) and excluded the 4 "probe-failure" ops
(`scan`, `scan-stale`, `scan-went-quiet`, `went-quiet-probe`) to honor the
operator's alert-fatigue concern. Plan-review (Kieran + DHH, HIGH) showed the
exclusion was wrong.

## Investigation

The feeding cron (`cron-workspace-sync-health.ts`) has 3 arms. Arms 2 and 3
**swallow their own scan errors** — on a failed Supabase query they call
`reportSilentFallback(..., {op: "scan-stale"|"scan-went-quiet"})` and then
`return {reported:0}` / `{wentQuiet:0}`. The Sentry cron **heartbeat** keys only
on arm-1's `scan` result (`postSentryHeartbeat({ok: scan.ok, ...})`). So when
arm 2 or 3's query breaks, the heartbeat stays green AND the arm reports zero
findings — the workspace looks healthy while the detector is blind. The
probe-failure op is the *only* signal for that state. An alert scoped to finding
ops drops it, reintroducing the exact silent-failure class the PIR is about.

## Solution

Match `feature = "workspace-sync-health"` ONLY (drop the `op` filter). Every
event the cron emits carries this feature and all are operator-actionable
(finding OR broken-probe), so feature-only covers them all, is future-proof
(a new arm's op is auto-covered), and is simpler.

## Key Insight

The `chat_message_save_failure` precedent scopes by op because its feature
(`cc-dispatcher`) spans many unrelated ops — op-scoping is required there to
avoid paging on noise. That is NOT a universal pattern. **When a feature tag is
dedicated to a single emitter whose every event is operator-actionable, match
feature-only — op-scoping then only adds brittleness and risks silently dropping
self-failure ops.** Two checks before op-scoping any alert:

1. Does the feature span ops you do NOT want to page on? If no → feature-only.
2. Do any sibling code paths **swallow** their errors (catch + return
   success-shaped result)? If yes, the error-op is the only signal — never
   exclude it, and confirm what the heartbeat actually keys on (it may cover
   only one of several arms).

Alert fatigue from repeated *findings* is handled by lifecycle conditions
(`first_seen`/`reappeared`/`regression` fold repeats into one issue), NOT by
narrowing the op set — so op-scoping buys no fatigue protection here anyway.

## Session Errors

Session error inventory: one design error, caught at plan-review (not shipped):
the initial op-scoping that would have dropped probe-failure detection.
**Prevention:** the two checks above, now also added to the brainstorm skill is
out of scope — the durable carrier is this learning + the plan's Research
Reconciliation row.

## Tags
category: observability
module: web-platform/infra/sentry
