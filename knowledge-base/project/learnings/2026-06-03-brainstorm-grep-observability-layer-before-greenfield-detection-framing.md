# Learning: PIR-follow-up "build detection" framing is often already-shipped — grep the observability layer + check sibling-PR merge dates first

## Problem

Issue #4882, a KB-sync-stale PIR follow-up, proposed building a "liveness/age
alert (Sentry rule or scheduled probe)" for diverged/stale workspace KB clones,
asserting "detection still depends on a user noticing a missing file." Accepting
that greenfield framing would have spawned a domain-leader fan-out to design a
detection system that already existed.

## Investigation

Pre-worktree premise probe (Phase 0 / 1.1) surfaced the contradiction:

1. `git grep -l "kb_sync_history"` returned
   `server/inngest/functions/cron-workspace-sync-health.ts` — a daily probe with
   **three arms** already shipped:
   - Arm 1 — `ready` + `github_installation_id IS NULL` → `op=ready-null-installation`
   - Arm 2 (#4712) — latest `kb_sync_history` row `ok:false` → `op=stale-sync-failed`
   - Arm 3 (#4717) — went-quiet → `op=went-quiet`
2. `gh pr view 4712/4717 --json mergedAt` + `gh issue view 4882 --json createdAt`:
   both arms merged **2026-06-01**, the issue was filed **2026-06-03** — the
   detection arms shipped two days *before* the issue claimed detection was absent.
3. Row-shape check (`kb-route-helpers.ts:307-309` + reconcile writer): the issue's
   bullet-1 case (`non_fast_forward`, `recovered != true`) writes
   `{ok:false, error_class:'non_fast_forward'}`, and Arm 2 fires on *any*
   `latest.ok === false` — so it was already caught.
4. `git grep` in `infra/sentry/issue-alerts.tf` for `workspace-sync-health`:
   **zero matches**. That was the real gap — the probe's `reportSilentFallback`
   events landed in Sentry with no alert rule to notify on them.

## Solution

Scope narrowed from "build detection" to "add one `sentry_issue_alert` mirroring
`chat_message_save_failure`." No app-code change. Deferred refinements
(error_class severity, age gate, scan-failure-op alerts) kept as conditional
Open Questions, not speculative backlog issues.

## Key Insight

A PIR follow-up is frequently authored while its author is focused on the
*recovery* PR in flight (#4878 here), and discounts or is unaware of *detection*
work that sibling PRs shipped between the incident and the issue-filing date.
Before accepting a "build detection / build a probe" framing:

1. **Grep the observability layer for the proposed mechanism** — `cron-*.ts`
   Inngest functions + `infra/sentry/*.tf` — not just app code. The probe may
   already exist; the gap may be only the *alert rule* on top of its events
   (`hr-no-dashboard-eyeball-pull-data-yourself`).
2. **Diff the sibling-PR merge dates against the issue createdAt.** Detection
   arms that merged *before* the issue was filed invalidate an "X doesn't exist"
   premise even when the issue is brand-new.
3. **Verify the row/event shape** the proposed condition would produce, to
   confirm whether an existing blanket check already covers it.

## Session Errors

Session error inventory: none detected. The pre-worktree premise probe worked as
designed — the contradiction was caught before worktree creation and leader spawn.

## Tags
category: workflow-patterns
module: brainstorm
