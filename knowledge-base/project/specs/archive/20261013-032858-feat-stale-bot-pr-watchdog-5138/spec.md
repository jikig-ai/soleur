---
feature: stale-bot-pr-watchdog
issue: 5138
lane: cross-domain
brand_survival_threshold: none
status: planned
created: 2026-06-12
---

# Spec — stale `ci/*` bot-PR watchdog (#5138)

## Problem Statement

Bot cron PRs on `mergeMode: "auto"` (ADR-054) rely on GitHub `enablePullRequestAutoMerge`, which **silently disarms on merge conflict** — the PR stays open with no Sentry signal and no comment. This is the only *invisible*-stale mode. Exposure spans the 7 dormant `auto` crons (opens at Tier-2 restoration) AND the live `direct`-fallback window (a `direct` pipeline whose immediate merge fails arms auto-merge → same disarmable state today, per ADR-054 Consequences). #5138 gates Tier-2 restoration of the PR-flow crons on this watchdog landing first.

## Goals

- FR1: Extend `cron-cloud-task-heartbeat` with a daily open-bot-PR age scan over heads `ci/*` and `self-healing/auto-*`.
- FR2: Flag PRs created >48h ago (strictly), excluding `draft && labels∋"self-healing/auto"` (compound-promote human-review drafts).
- FR3: For each stale PR → `warnSilentFallback(op: "stale-bot-pr")` + best-effort deduped comment on the owning cron's `scheduled-<name>` issue (reuse `commentOnScheduledIssue` shape; Sentry-only fallback when no labeled issue).
- FR4: Route the warn to the operator via `sentry_issue_alert.stale_bot_pr` (`notify_email` IssueOwners, `frequency = 14`).
- TR1: Bot-PR staleness is orthogonal to the heartbeat `ok`/`silentCount` — never flips the cron monitor.
- TR2: No new Inngest function, `EXPECTED_CRON_FUNCTIONS` entry, or cron monitor (extend in place).

## Non-Goals

- No change to merge semantics of any cron (`auto`/`direct`/`none` modes unchanged).
- No new GitHub-App scope or secret (reuses the existing installation token).

## Reference

Full design, file list, test scenarios, IaC, and observability schema: `knowledge-base/project/plans/2026-06-12-chore-stale-bot-pr-watchdog-plan.md`.
