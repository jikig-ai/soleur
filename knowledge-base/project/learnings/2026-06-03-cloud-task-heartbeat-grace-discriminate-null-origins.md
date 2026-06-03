---
title: "Cloud-task silence watchdog — a never-produced grace must discriminate among the THREE origins of daysSince:null"
date: 2026-06-03
category: observability
tags: [cron, watchdog, inngest, false-positive, silent-fallback, cloud-task-silence]
refs: [4873, 4874, 4875, 4876, 4877, 2714, 4770, 4870, 4708]
---

# Watchdog grace: discriminate the three origins of `daysSince === null`

## Context

On 2026-06-03 the `cron-cloud-task-heartbeat` Inngest watchdog filed **five**
`[cloud-task-silence]` issues (#4873–#4877). Diagnosis (Sentry cron monitors +
Sentry issue events, reached via `SENTRY_AUTH_TOKEN` / `SENTRY_ISSUE_RW_TOKEN`
in Doppler `soleur/prd` + `prd_scheduled`, org `jikigai-eu`):

- **3 genuine** (content-generator, community-monitor, roadmap-review): the
  freshly TR9-migrated Inngest crons fired but **failed mid-run on the 256 MB
  `/tmp` tmpfs** (`git clone exit 128` / `spawn cwd … no longer exists`). Root
  cause already fixed by **#4770** (`CRON_WORKSPACE_ROOT=/workspaces` — the code
  shipped an env override falling back to `tmpdir()`; the fix only takes effect
  once the container is redeployed with the `-e`/`-v` flags) and **#4870**
  (community max-turns). They self-heal on next scheduled fire — the watchdog
  auto-closes silence issues on recovery.
- **2 false positives** rooted in the watchdog itself (this PR).

## The two false-positive classes (and the fix)

1. **Never-yet-run producer (legal-audit, #4875).** Quarterly, migrated
   2026-05-25, first real fire 2026-07-01 → has produced ZERO `scheduled-legal-audit`
   issues. The watchdog's `daysSince === null → silent: true` flagged it.
2. **Conditional producer (strategy-review, #4874).** Its Sentry monitor checked
   in OK (it ran) but it only opens an issue per KB-file-needing-review — quiet
   weeks legitimately yield zero issues. Issue-presence is the wrong silence
   signal — same class as the already-excluded daily-triage/ux-audit/bug-fixer.
   Fix = remove from `TASK_INVENTORY` (liveness via its Sentry monitor).

## Key insight — `daysSince === null` has THREE distinct origins; grace fits ONE

The highest-risk way to "fix" class 1 is to flip *every* `daysSince === null` to
`silent: false`. That is wrong. In `cron-cloud-task-heartbeat.ts` the null has
three structurally distinct origins:

| Origin | Meaning | Correct verdict |
|---|---|---|
| `issues.length === 0` (query succeeded, zero rows) | never produced → pending-first-run | `silent: false` + `warnSilentFallback(op: task-pending-first-run)` |
| in-band `Date.parse(created_at)` → `NaN` (issues exist) | corrupt/unparseable timestamp | **`silent: true`** (real anomaly) |
| `catch (err)` | GitHub API error | **`silent: true`** + `reportSilentFallback` (error) |

The grace's discriminator is **"the query returned zero rows"**, NOT "`daysSince`
happens to be null." Only the zero-rows arm changes.

## Severity discipline

Pending-first-run is *expected*, not an error → use `warnSilentFallback`
(warning level, non-paging), not `reportSilentFallback` (error). It still
mirrors to Sentry + pino (`cq-silent-fallback-must-mirror-to-sentry`), so a task
stuck pending past its first-fire date stays continuously queryable in Sentry by
`op:task-pending-first-run` — and the firing question is owned by the task's own
per-function Sentry cron monitor, not this watchdog.

## Diagnostic reusable

A Sentry `error`-status cron check-in does **not** mean the work failed:
`competitive-analysis` checked in `error` on 2026-06-01 yet produced #4747 — the
status reflects the spawned claude's non-zero exit, decoupled from work success
(#4732/#4727). Always cross-check the output artifact, not just the check-in
status. Sentry liveness is reachable headless via the Doppler-stored token +
`https://<org>.sentry.io/api/0/organizations/<org>/monitors/<slug>/checkins/`
(monitor list/check-ins) and `…/issues/<SHORT-ID>/events/latest/` (error events,
needs `SENTRY_ISSUE_RW_TOKEN` — the plain `SENTRY_AUTH_TOKEN` lacks issue:read).
