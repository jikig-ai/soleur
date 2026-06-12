---
feature: stale-bot-pr-watchdog
issue: 5138
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-12-chore-stale-bot-pr-watchdog-plan.md
---

# Tasks — stale `ci/*` bot-PR watchdog (#5138)

## Phase 1 — Pure helpers (test-first)

- [ ] 1.1 Add tests (RED) for `scheduledLabelFromHead` (Scenario 1) and `isStaleBotPr` (Scenarios 2–3, incl. malformed `created_at` → false) to `apps/web-platform/test/server/inngest/cron-cloud-task-heartbeat.test.ts`.
- [ ] 1.2 Add constants (`STALE_BOT_PR_THRESHOLD_MS`, `BOT_PR_HEAD_PREFIXES`, `STALE_BOT_PR_WARN_OP`) + exported `scheduledLabelFromHead`, `isStaleBotPr`, `BotPrLite` to `cron-cloud-task-heartbeat.ts` (GREEN).

## Phase 2 — Scan step

- [ ] 2.1 Add `step.run("check-stale-bot-prs", …)` after `check-task-silence`, reusing `installationToken`: paginate `GET …/pulls` (`state:open, sort:created, direction:asc, per_page:100`), ascending-created early-exit (comment the invariant at the `break`), no page cap. Filter via `isStaleBotPr`.
- [ ] 2.2 try/catch → `reportSilentFallback(op: "stale-bot-pr-scan-failed")`, return `[]` on error (no throw, no monitor flip).
- [ ] 2.3 Tests: scan failure (Scenario 7), pagination early-exit (Scenario 9).

## Phase 3 — Handling step

- [ ] 3.1 Add `step.run("stale-bot-pr-handling", …)` before `sentry-heartbeat`: per stale PR → `warnSilentFallback(op: "stale-bot-pr")` (stable message, per-PR detail in `extra`).
- [ ] 3.2 Best-effort deduped comment on `scheduled-<name>` issue via the `commentOnScheduledIssue` shape + `<!-- stale-bot-pr:<n> -->` marker dedup; Sentry-only when label null / no open issue; failures → `reportSilentFallback(op: "stale-bot-pr-comment-failed")`.
- [ ] 3.3 Tests: warn emission (4), comment dedup (5), no-labeled-issue Sentry-only (6), heartbeat orthogonality (8), source-shape anchors (10).

## Phase 4 — Sentry alert (IaC)

- [ ] 4.1 Add `resource "sentry_issue_alert" "stale_bot_pr"` to `apps/web-platform/infra/sentry/issue-alerts.tf`, mirroring `kb_db_error` (apply-created real body): `filter_match = "all"`, `tagged_event` on `feature == cron-cloud-task-heartbeat` AND `op == stale-bot-pr`, `notify_email { target_type = "IssueOwners", fallthrough_type = "ActiveMembers" }`, `frequency = 14` (with the dedup-collision `.tf` comment).
- [ ] 4.2 `cd apps/web-platform/infra/sentry && terraform validate`.
- [ ] 4.3 Wire scoped `-target=sentry_issue_alert.stale_bot_pr apply` into `apply-sentry-infra.yml` (terraform-architect; no manual apply).

## Phase 5 — Docs

- [ ] 5.1 Add `## Stale bot PR` section to `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` (meaning + operator action, no-SSH).
- [ ] 5.2 1-line "Resolved by PR #<this> (#5138)" annotation in ADR-054 Consequences.

## Phase 6 — Verify

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 6.2 `./node_modules/.bin/vitest run test/server/inngest/cron-cloud-task-heartbeat.test.ts` + `function-registry-count.test.ts` green.
- [ ] 6.3 Re-run Phase 1.7.5 code-review overlap query; PR body `Closes #5138`.
