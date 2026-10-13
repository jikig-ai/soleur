---
title: Workspace Reconcile Push — "no workspace matched" Sentry noise
closes:
status: complete
---

# Plan: workspace-reconcile-push "no workspace matched" noise

## Problem

The `workspace-reconcile-on-push` Inngest function emits a Sentry warning
(`feature=workspace-reconcile-push`, `op=skip-no-workspace-match`,
"no workspace matched (installation_id, repo)") on every push whose
`(github_installation_id, repo_url)` matches zero workspaces. Recurring
operator email noise ("triggered by auth-per-user-loop" alert rule).

## Verified data (Sentry, project web-platform, org jikigai-eu, 2026-05-30)

Pulled via Discover API (`SENTRY_AUTH_TOKEN`, EU host `jikigai-eu.sentry.io`),
all HTTP 200:

- Event counts for `feature:workspace-reconcile-push op:skip-no-workspace-match`:
  **24h = 12**, **7d = 37**, 14d/30d/90d = 37 (all recent — entirely within 7d).
- Repo attribution: **11/11** sampled recent events had `targetRepoUrl` =
  `jikig-ai/soleur` (the platform's own dev repo, on which the GitHub App is
  installed but which is NOT a customer workspace).

## Root cause

Two compounding causes:

1. **The source.** The GitHub App is installed on `jikig-ai/soleur`. Every push
   there matches zero workspaces → benign skip → Sentry event. This is the
   dominant driver (100% of the sample).
2. **Ineffective suppression.** The prior fix routed the skip through
   `mirrorWarnWithDebounce`, whose dedup is an **in-process `Map`**
   (`observability.ts`). Across the platform's container churn each new worker
   resets the map, so the per-`(installationId, repoUrl)` 5-min TTL never bounds
   the cross-process repeat rate — the warning still creates Sentry issues and
   fires the alert rule.

The skip itself is by-design (app uninstalled, repo not onboarded, disconnected
fork, stale/replayed webhook). It carries no signal worth a Sentry issue.
Genuine workspace-resolution **errors** take a separate `reportSilentFallback`
path and are unaffected.

## Fix (implemented)

Operator decision: **drop the benign skip from Sentry + stop the source.**

1. **Stop the source** — `workspace-reconcile-on-push.ts`: short-circuit
   platform-internal repos before the DB query and before any emission. New
   `RECONCILE_IGNORED_REPO_SUBSTRINGS` (env `WORKSPACE_RECONCILE_IGNORE_REPOS`,
   default `jikig-ai/soleur`) → returns `{ ok: false, reason:
   "ignored-internal-repo" }` silently.
2. **Drop from Sentry** — the remaining `rows.length === 0` branch (genuinely
   un-onboarded customer repos) now logs via pino `logger.info` (Better Stack
   drain) instead of `mirrorWarnWithDebounce`. No Sentry mirror, no in-memory
   debounce. `reportSilentFallback` error path is untouched.
3. **Config doc** — `.env.example` documents `WORKSPACE_RECONCILE_IGNORE_REPOS`.

`mirrorWarnWithDebounce` remains exported (still used by
`lib/feature-flags/server.ts`).

## Tests

`test/server/inngest/workspace-reconcile-on-push.test.ts`:
- Replaced the two `mirrorWarnWithDebounce` assertions with a pino-only test
  (asserts `logger.info` called with the structured context + message; asserts
  neither `warnSilentFallback` nor `reportSilentFallback` fire).
- Added an ignored-internal-repo test (`jikig-ai/soleur` → fully silent: no
  `repo_url` query, no sync, no log, no Sentry).
- All other tests (happy fan-out, slug parity, schema gate, not-ready,
  sync-failure) unchanged and passing.

Verified: `tsc --noEmit` clean; vitest 11/11 passing (reconcile test file),
exit 0. Includes an over-match guard test (`jikig-ai/soleur-fork` must NOT be
short-circuited) since the ignored-repo match is exact `owner/repo` equality,
not a raw substring.

## Observability

- **Pino / Better Stack:** benign skips for real un-onboarded customer repos
  remain visible via `logger.info` (`op=skip-no-workspace-match`).
- **Sentry:** genuine resolution failures still surface via
  `reportSilentFallback` (`op=resolve-workspaces`, error level). Discoverable
  in Sentry by `feature:workspace-reconcile-push level:error`. No SSH required.

## Operator follow-up

After deploy, resolve/archive the existing Sentry issue
("no workspace matched (installation_id, repo)") so the historical events clear;
new events should stop arriving once the release is live.
