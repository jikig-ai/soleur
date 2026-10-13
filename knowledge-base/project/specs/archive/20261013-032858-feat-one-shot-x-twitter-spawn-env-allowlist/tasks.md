---
title: "Tasks — fix community-monitor X/Twitter spawn-env allowlist"
plan: knowledge-base/project/plans/2026-06-03-fix-community-monitor-x-twitter-spawn-env-allowlist-plan.md
lane: single-domain
---

# Tasks — forward X/Twitter credentials through community-monitor spawn-env allowlist

## Phase 1 — Test (RED)

- [x] 1.1 In `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts`, add `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` to the positive-class `it.each([...])` array in the `"buildSpawnEnv allowlist (PR-11 bucket-ii security surface)"` describe block.
- [x] 1.2 Add a negative assertion that `buildEnvBody` does NOT contain `X_ALLOW_POST` (read-only invariant). (Placed in the negative-class describe block per test-design review.)
- [x] 1.3 Run `./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts` (from `apps/web-platform/`); confirm the four new positive rows FAIL (RED) and the `X_ALLOW_POST`-absent assertion passes.

## Phase 2 — Core Implementation (GREEN)

- [x] 2.1 In `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, add the four `X_*` read credentials to the `buildSpawnEnv()` return object as `X_API_KEY: process.env.X_API_KEY` (and the other three). Do NOT add `X_ALLOW_POST`.
- [x] 2.2 Update the comment block above `buildSpawnEnv()` to list the four `X_*` additions alongside the existing Discord/Bluesky/LinkedIn entries, noting `X_ALLOW_POST` is deliberately excluded (read-only monitor).

## Phase 3 — Verify

- [x] 3.1 Re-run `./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts`; confirm all spawn-env allowlist tests pass (GREEN).
- [x] 3.2 Confirm `X_ALLOW_POST` is NOT forwarded by `buildSpawnEnv()` — body-scoped (the test slices the function body and asserts absence). A file-level `grep -c 'X_ALLOW_POST'` returns `1`: the intentional comment documenting the exclusion, not a forwarded key.
- [x] 3.3 Confirm `...process.env` spread is still absent from `buildSpawnEnv()`.
