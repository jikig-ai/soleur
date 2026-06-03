---
title: "Tasks — Inngest --poll-interval + watchdog backstop demotion (#4652)"
plan: knowledge-base/project/plans/2026-05-30-feat-inngest-poll-interval-watchdog-simplification-plan.md
issue: 4652
branch: feat-one-shot-4652-inngest-poll-interval
lane: cross-domain
created: 2026-05-30
---

# Tasks — Adopt Inngest `--poll-interval`; demote watchdog to guarded backstop (#4652)

Derived from `2026-05-30-feat-inngest-poll-interval-watchdog-simplification-plan.md`. Execute with `skill: soleur:work`.

## Phase 0 — Preconditions (verify against live worktree)

- [ ] 0.1 Confirm app port 3000 published to host loopback: `grep -n "PORT=3000" apps/web-platform/Dockerfile` + `grep -n "0.0.0.0:3000:3000" apps/web-platform/infra/ci-deploy.sh`.
- [ ] 0.2 Confirm `/api/inngest` in `PUBLIC_PATHS`: `grep -n "api/inngest" apps/web-platform/lib/routes.ts` (makes loopback polling not 307→/login).
- [ ] 0.3 Re-run open-code-review-overlap `jq --arg` check against live `gh issue list --label code-review --state open`.
- [ ] 0.4 Confirm `--poll-interval` int-seconds + `--sdk-url`/`-u` app-serve-URL semantics (Context7 self-hosting docs already verified in plan; if `inngest` binary local, run `inngest start --help | grep -E 'poll-interval|sdk-url'`).

## Phase 1 — ExecStart change (`apps/web-platform/infra/inngest-bootstrap.sh`)

- [ ] 1.1 Append `--poll-interval 60 --sdk-url http://127.0.0.1:3000/api/inngest` to the `inngest start` command at line 147, inside the `'/usr/bin/bash -c '...''` wrapper. Keep `$${INNGEST_SIGNING_KEY#signkey-prod-}` and `$${INNGEST_EVENT_KEY}` exactly. Add inline comment (#4652; port 3000 = app serve route per Dockerfile + #4017 PUBLIC_PATHS).
- [ ] 1.2 **DECISION (highest-risk):** resolve the `SKIP_BINARY_INSTALL` same-version-redeploy gap. Prefer option (a): move the inngest-server unit write + an explicit `enable` + restart OUTSIDE the `if [[ -z "$SKIP_BINARY_INSTALL" ]]` guard (reconcile-always, matching the heartbeat-unit precedent at `:64-73`). Replace `enable --now inngest-server.service` (`:279`) with `enable inngest-server.service` + restart, mirroring the Vector pattern at `:399-408`. Preserve upgrade-drain pause (`:88-96`) and resume (`:287-291`). Document chosen option in the PR body.

## Phase 2 — Deploy gate (`apps/web-platform/infra/ci-deploy.sh`)

- [ ] 2.1 In the `deploy inngest` success path (after the bootstrap-run block returns 0, `:784-788`, before `final_write_state 0 "success"`), call `verify_inngest_health` (the existing function at `:201-246`); on non-zero RC: `rm -rf "$INNGEST_EXTRACT_DIR"`, `final_write_state 1 "inngest_health_failed"`, exit 1.
- [ ] 2.2 Ensure `rm -rf "$INNGEST_EXTRACT_DIR"` runs on both success and the new failure branch.

## Phase 3 — Watchdog demotion to guarded backstop (`apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts`)

- [ ] 3.1 Introduce `POLL_RECOVERY_GRACE_TICKS` (suggested 2). Re-document/rename `UNPLANNED_RESTART_THRESHOLD`; meaning changes to "polling failed to recover".
- [ ] 3.2 Apply the grace-tick gate to BOTH H9a (MISSING) and escalated-H9b (UNPLANNED): MISSING accrues a per-fnId streak and only escalates to restart after `POLL_RECOVERY_GRACE_TICKS` consecutive ticks. Extend `nextUnplannedStreaks`/`escalatedUnplannedFnIds` to a unified MISSING ∪ UNPLANNED defect streak (or add `missingStreaks`). Keep pure-helper structure.
- [ ] 3.3 Retain the cooldown (`RESTART_COOLDOWN_MS`) as a second backstop guard. Do not remove.
- [ ] 3.4 Keep D1-A → D1-B restart body INTACT (`postRestartWebhook`, `fileRestartEscalationIssue`, `RESTART_ESCALATION_LABEL`, `inngest-watchdog-restart-dispatch.yml`); only the trigger changes.
- [ ] 3.5 Keep H9b manual-trigger heal (`:414-437`); add comment that polling re-plans within one interval so it is now a latency optimization.
- [ ] 3.6 Keep the Sentry heartbeat step (`:531-539`) EXACTLY as-is (`ok = defectCount === 0`).
- [ ] 3.7 Rewrite the header comment (`:1-34`, esp. RE-SYNC ASYMMETRY `:19-23`) + inline `:368-370` for the polling-backstop model. Remove all "no `--poll-interval`" claims.

## Phase 4 — Runbook H9 (`knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`)

- [ ] 4.1 Update H9a entry (`:272-275`): poll re-syncs a dropped function within ≤60s; restart is the backstop only.
- [ ] 4.2 Update "Distinguishing"/"Restore" framing: primary restore is "wait one poll interval (≤60s) and re-query `/v1/functions`".
- [ ] 4.3 Rewrite "Self-healing" step 3 (`:368-379`) for the grace-tick backstop model. Keep steps 1, 2, 4 accurate.
- [ ] 4.4 Keep SSH manual-fallback as last-resort.

## Phase 5 — Tests

- [ ] 5.1 `apps/web-platform/infra/inngest.test.sh` — extract the `UNITEOF` server-unit block; assert ExecStart contains `--poll-interval 60` and `--sdk-url http://127.0.0.1:3000/api/inngest` (each token independently). Assert the bootstrap restarts inngest-server on the unit-write path (AC2). Verify the awk extraction is non-empty before asserting.
- [ ] 5.2 `apps/web-platform/infra/ci-deploy.test.sh` — assert `deploy inngest <valid-image> <valid-tag>` invokes `verify_inngest_health` (reuse `8288/v1/functions` mock router at `:265-277`: default → success; H9b-deplaned → `inngest_health_failed`). Mock docker-extract as existing deploy-inngest tests (`:501-513`).
- [ ] 5.3 `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` — confirm still green (no ExecStart literal in cloud-init.yml); add server-unit assertions only if the suite is extended.
- [ ] 5.4 `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog.test.ts` — rename/extend streak tests for the unified grace-tick model; assert MISSING does NOT escalate on tick 1; escalates at `POLL_RECOVERY_GRACE_TICKS`. Keep cooldown tests.
- [ ] 5.5 `apps/web-platform/test/server/inngest/cron-inngest-cron-watchdog-handler.test.ts` — split the H9a-restart test: single tick → no restart, `ok=false`, no webhook fetch (AC4); sustained ≥grace ticks (seed `readFileMock` with prior streak) → restartRequested, webhook 202 (AC5). Keep D1-B non-202 + clean-registry tests.
- [ ] 5.6 `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — confirm still green (`EXPECTED_CRON_FUNCTIONS` unchanged). No edit expected.

## Phase 6 — Verify & ship

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-inngest-cron-watchdog.test.ts test/server/inngest/cron-inngest-cron-watchdog-handler.test.ts test/server/inngest/function-registry-count.test.ts` (do NOT use `bun test`).
- [ ] 6.2 `bash apps/web-platform/infra/inngest.test.sh && bash apps/web-platform/infra/ci-deploy.test.sh && bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`.
- [ ] 6.3 `tsc --noEmit` clean.
- [ ] 6.4 `grep -rn "no .--poll-interval" apps/web-platform/server/inngest/ knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` returns zero (AC8).
- [ ] 6.5 PR body uses `Closes #4652`. Document the Phase 1.2 decision. Note AC11 post-merge: verify whether inngest bootstrap image auto-builds+deploys on merge or is tag-gated (`hr-tagged-build-workflow-needs-initial-tag-push`); if tag-gated, prescribe `gh workflow run` in ship, NOT SSH.
