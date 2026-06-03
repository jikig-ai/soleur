# Learning: every-run healthy-path outcomes need a durable Sentry event, not just `logger.info`

## Problem

`cron-workspace-gc` computed a full disk-reclaim payload (`freeMbBefore`,
`freeMbAfter`, `freedMb`, `sweptCount`, `root`) on every run but only emitted a
**durable** Sentry signal on the degraded branches: the payload-less Crons
heartbeat (liveness only) and the low-disk `warnSilentFallback` (gated on
`freeMbAfter < floorMb`). On a HEALTHY reclaim — the common case — the numbers
went to `logger.info` (pino stdout) ONLY. Vector does not ship app stdout to
Better Stack/Sentry by design, so during the 2026-06-02 ENOSPC incident there
was no no-SSH way to confirm a manual GC fire actually reclaimed disk. This
violates the spirit of `hr-no-dashboard-eyeball-pull-data-yourself`: the
load-bearing OUTCOME (disk freed) must be verifiable from a durable, pulled
signal — not just the fact that the job ran.

## Solution

Added `infoSilentFallback` to `apps/web-platform/server/observability.ts` — an
`level: "info"` sibling of `warn`/`reportSilentFallback`, a verbatim mirror with
the level swapped on BOTH the `captureException` and `captureMessage` branches and
`art33Breach` intentionally dropped (info is never a breach). Then **replaced**
(not duplicated) the cron's success-path `logger.info` with an `infoSilentFallback`
call — the helper re-emits the pino mirror internally, so no stdout signal is lost,
while adding a queryable `Sentry.captureMessage` event on every run. A no-SSH
operator now pulls `extra.freedMb` from the latest Sentry event after firing
`cron/workspace-gc.manual-trigger`.

## Key Insight

When a periodic job's **healthy-path outcome** is itself load-bearing (disk
reclaimed, rows backfilled, queue drained), a bare `logger.info` is invisible
without SSH. Emit it as an info-level Sentry event via the centralized
`infoSilentFallback` helper — NOT a raw inline `Sentry.captureMessage` (which
bypasses the `hashExtraUserId` pseudonymization boundary + shim-safe try/catch)
and NOT a breadcrumb (not independently queryable) and NOT the heartbeat
(payload-less check-in URL). Keep `level:info` (informational/throughput) distinct
from `level:warning` (actionable/paging) so on-call can filter them apart.

**Cross-check when adding a new severity level to an existing `feature` emit:**
verify the new `level:info` event does not match a `filter_match="all"` Sentry
rule in `infra/sentry/issue-alerts.tf` that previously only saw the
`level:warning` event for that feature — a feature-only filter would over-fire on
the new informational events. (Confirmed safe here: no `cron-workspace-gc`
feature filter and no `level` filter exists in the rule config.)

## Tags
category: best-practices
module: apps/web-platform/server/observability
issue: 4897
refs: [4882, 4886]

## Session Errors

1. **Monitor tool called without its schema loaded** — `InputValidationError`
   (the tool was deferred and not in the discovered-tool set). Recovery:
   `ToolSearch "select:Monitor"` to load the schema, then retried.
   **Prevention:** fetch a deferred tool's schema via ToolSearch before the first
   invocation — the surfaced name alone is not callable.
2. **Plan-file Edit rejected with "modified since read"** — a `sed -i` AC-checkoff
   mutated the plan file after it had been Read, so a later `Edit` on a different
   region rejected. Recovery: re-Read the region, retried the Edit.
   **Prevention:** already covered by `hr-always-read-a-file-before-editing-it`
   (re-read a file after any out-of-band mutation — including your own `sed`/Bash
   writes — before Editing it).
