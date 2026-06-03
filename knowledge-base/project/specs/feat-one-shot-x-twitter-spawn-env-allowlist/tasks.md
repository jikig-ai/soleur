---
title: "Tasks — fix community-monitor X/Twitter spawn-env allowlist"
plan: knowledge-base/project/plans/2026-06-03-fix-community-monitor-x-twitter-spawn-env-allowlist-plan.md
lane: single-domain
---

# Tasks — forward X/Twitter credentials through community-monitor spawn-env allowlist

## Phase 1 — Test (RED)

- [ ] 1.1 In `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`, add `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` to the positive-class `it.each([...])` array in the `"buildSpawnEnv allowlist (PR-11 bucket-ii security surface)"` describe block.
- [ ] 1.2 Add a negative assertion that `buildEnvBody` does NOT contain `X_ALLOW_POST` (read-only invariant).
- [ ] 1.3 Run `./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts` (from `apps/web-platform/`); confirm the four new positive rows FAIL (RED) and the `X_ALLOW_POST`-absent assertion passes.

## Phase 2 — Core Implementation (GREEN)

- [ ] 2.1 In `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, add the four `X_*` read credentials to the `buildSpawnEnv()` return object as `X_API_KEY: process.env.X_API_KEY` (and the other three). Do NOT add `X_ALLOW_POST`.
- [ ] 2.2 Update the comment block above `buildSpawnEnv()` to list the four `X_*` additions alongside the existing Discord/Bluesky/LinkedIn entries, noting `X_ALLOW_POST` is deliberately excluded (read-only monitor).

## Phase 3 — Verify

- [ ] 3.1 Re-run `./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts`; confirm all spawn-env allowlist tests pass (GREEN).
- [ ] 3.2 Confirm `grep -c 'X_ALLOW_POST' apps/web-platform/server/inngest/functions/cron-community-monitor.ts` returns `0`.
- [ ] 3.3 Confirm `...process.env` spread is still absent from `buildSpawnEnv()`.
