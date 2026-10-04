# Tasks: Inngest dispatch cron for the merge-queue stall check (#9482 follow-up (a))

Plan: knowledge-base/project/plans/2026-10-04-feat-merge-queue-stall-dispatch-cron-plan.md

## Phase 0: Setup
- 0.1 File the monitor-routing tracking issue (two-PR rule); note its number for the unrouted-map reason.

## Phase 1: Core (RED then GREEN)
- 1.1 Write apps/web-platform/test/server/inngest/cron-merge-queue-stall-dispatch.test.ts (RED): anchors, mint/request toEqual, dispatch failure with redaction, mint failure rethrow, replaying step fake, existsSync row.
- 1.2 Write apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts (GREEN): replay-safe step layout (mint try/rethrow with error heartbeat; dispatch step catches+reports inside; heartbeat as callback step), header comment (single authority for the timing story).

## Phase 2: Registration and parity
- 2.1 cron-manifest.ts (alphabetical insert)
- 2.2 execution-placement.ts (portable row)
- 2.3 routine-metadata.ts (confirm, Every 10 min)
- 2.4 app/api/inngest/route.ts (import + functions array)
- 2.5 function-registry-count.test.ts (71 -> 72)
- 2.6 cron-safe-commit-parity.test.ts (comment acknowledgement)
- 2.7 apps/web-platform/test/repo-wide-suites.ts: list the new test (it reads the workflow outside the app; repo-wide-containment.test.ts otherwise reds)

## Phase 3: Monitor, routing, counts
- 3.1 cron-monitors.tf: scheduled_merge_queue_stall_dispatch (*/10, margin 30, comment: green = dispatched)
- 3.2 cron-monitor-alerts.tf: unrouted entry citing the Phase 0 issue
- 3.3 infra/sentry/README.md and sentry-monitors-audit.sh counts 61 -> 62
- 3.4 Read model.c4, views.c4, spec.c4; edit C4 (61->62) and C6 (44->45) in model.c4; run scripts/regenerate-c4-model.sh

## Phase 4: Documentation
- 4.1 merge-queue-stall-check.yml: comment-only edits (keep S11/S12 literals; standalone fallback comment above on:; inline cron comment untouched)
- 4.2 ADR-270: one-clause amendment (multi-line span) + canary item 10 note

## Phase 5: Verify
- 5.1 vitest: test/server/inngest, test/lib/inngest, test/server/routines, test/repo-wide-containment.test.ts
- 5.1b python3 scripts/lint-encryption-posture.py --repo-sweep
- 5.2 bash: c4-count-parity, c4-model-freshness, sentry-monitors-audit.test.sh, merge-queue-stall-check.test.sh
- 5.3 Apply Guard 1 mutation rows 1-4 + harness row once each; confirm RED
- 5.4 Comment-only diff check on the workflow; PR body says "Ref #9482" not "Closes"
