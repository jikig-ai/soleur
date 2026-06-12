# Learning: a detector cron must route its OWN self-failure ops, and a new sentry_issue_alert must be registered in the apply `-target` set

## Problem

Building the #5138 stale-`ci/*` bot-PR watchdog (a daily scan added to
`cron-cloud-task-heartbeat` that flags open bot PRs >48h). Two non-obvious gaps —
both caught by gates before merge, both reusable for any new detector + Sentry
issue alert:

1. **A detector whose own failure is invisible recreates the gap it closes.** The
   scan emits `warnSilentFallback(op: "stale-bot-pr")` on a finding but deliberately
   does NOT flip the cron monitor (`ok`/`silentCount`) — found-work ≠ liveness
   (`2026-06-01-best-effort-cron-monitor-liveness-not-success...`). Its self-failure
   paths emit `reportSilentFallback(op: "stale-bot-pr-scan-failed" | "...-comment-failed")`.
   The first-draft alert filtered `op EQUAL "stale-bot-pr"` only. Net: if the
   `GET …/pulls` call failed every day, the scan returned `[]`, the monitor stayed
   green, and the self-failure ops were *searchable but not routed* — the watchdog
   could silently stop, recreating the exact silent-stale failure mode it exists to
   detect.

2. **An apply-created `sentry_issue_alert` needs `conditions_v2` to fire AND must be
   added to `apply-sentry-infra.yml`'s `-target=` set.** The first-draft `.tf`
   omitted the `conditions_v2` lifecycle triple (a rule with filters but no condition
   never fires) and the new resource was not in the workflow's `-target=` allow-list,
   so `terraform apply` would never create it.

## Solution

1. Route the detector's self-failure ops through the SAME alert via `op IS_IN`:
   ```hcl
   { tagged_event = { key = "op", match = "IS_IN",
       value = "stale-bot-pr,stale-bot-pr-scan-failed,stale-bot-pr-comment-failed" } }
   ```
   `feature` is shared (the cron also emits unrelated `task-pending-first-run` /
   `check-task` ops), so op-scoping is mandatory — feature-only would over-page
   (`2026-06-03-sentry-alert-match-feature-only-when-feature-is-dedicated`).

2. Mirror an **apply-created** sibling (`egress_blocked` / `kb_db_error`) VERBATIM,
   not the import-only `auth_*` placeholders: `action_match="any"` +
   `conditions_v2 = [{first_seen_event={}},{reappeared_event={}},{regression_event={}}]`
   (the firing trigger) + a distinct `frequency` (dedup is on action+filter+frequency,
   not conditions — `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions`)
   + `lifecycle { ignore_changes = [environment] }`. Then add
   `-target=sentry_issue_alert.<name> \` to the `terraform plan`/`apply` block in
   `.github/workflows/apply-sentry-infra.yml` (its `-target` set already lists
   `sentry_issue_alert.*` alongside the cron monitors — a new alert NOT in the list
   is never applied; the `test-destroy-guard-sentry-scope-guard.sh` type-check still
   passes because the *type* is allowed, so it won't catch the omission).

## Key Insight

**Checklist for adding a new operator-facing detector + its Sentry alert:**
- Does every code path the detector can fail on emit a routed op (not just the
  happy-path "found something" signal)? If the detector's found-work is orthogonal
  to its cron monitor, its SELF-failure must page some other way — `op IS_IN` the
  alert filter is the cheapest route.
- Is the alert apply-created (real `conditions_v2`) or import-only (placeholder)?
  Copy the matching cohort.
- Is the new resource address in `apply-sentry-infra.yml`'s `-target=` list?
  Validation + scope-guard are green without it; only the missing live rule reveals it.
- Warn-level events DO satisfy `first_seen_event`
  (`2026-05-27-sentry-warning-level-still-triggers-alert-rules`) — a `warnSilentFallback`
  signal is routable; no need to escalate to error level for paging.

Related: [[2026-06-01-silence-detector-needs-out-of-band-liveness-signal]] ·
[[2026-06-03-sentry-alert-match-feature-only-when-feature-is-dedicated]] ·
[[2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions]] ·
[[2026-04-21-cloud-task-silence-watchdog-pattern]]

## Session Errors

- **Ran `vitest` from the bare-repo root (`/soleur/apps/web-platform`) before the
  worktree path.** 31 stale committed tests passed and masked the worktree's RED
  edits; a re-run from `.worktrees/<feat>/apps/web-platform` showed the real 25
  failures. **Recovery:** re-ran from the worktree. **Prevention:** already covered
  by the work-skill Sharp Edge ("chain `cd <worktree-abs-path> && <cmd>` in one Bash
  call") — the bare-root working copy is a stale synced snapshot; never trust a green
  run whose CWD isn't the worktree.
- **`Edit` on ADR-054 rejected with "File has not been read yet."** I had read it via
  `git show`/`sed`, not the `Read` tool, which is what the harness tracks.
  **Recovery:** `Read` the target section, then `Edit`. **Prevention:** one-off — when
  an Edit must follow a prior `git show`/`grep` inspection, `Read` the file region
  first; shell inspection does not satisfy the read-before-edit gate.

## Tags
category: integration-issues
module: inngest-crons, sentry-infra
