---
name: post-ship-autonomous-monitor
lane: single-domain
brand_survival_threshold: none
---

# Post-Ship Autonomous Monitor

## Problem Statement

The shipping pipeline stops at "auto-merge enabled." CI failures block merge silently, Sentry regressions go unnoticed, and `/soleur:postmerge` is never invoked automatically. The operator must manually monitor merge status, fix CI failures, and verify production health — defeating the purpose of autonomous shipping.

## Goals

1. Ship Phase 7 autonomously fixes CI failures that block merge (1 attempt, then escalate)
2. Ship Phase 7 auto-chains to `/soleur:postmerge` after merge + release workflows pass
3. Postmerge verifies Sentry cron monitor health post-deploy

## Non-Goals

- Automated rollback on production regression (out of scope — surface the problem, don't auto-revert)
- Cross-app deployment coordination (single-app deploy pipeline only)
- Real-time alerting infrastructure (this is session-scoped monitoring, not a persistent monitoring system)

## Functional Requirements

- FR1: When a required CI check fails during ship Phase 7 merge poll, the agent attempts to diagnose and fix the failure (run tests locally, identify issue, commit fix, push, re-queue auto-merge)
- FR2: CI auto-fix is capped at 1 attempt. After failure, escalate to the operator with diagnosis.
- FR3: After ship Phase 7 confirms merge + all release workflows pass, automatically invoke `/soleur:postmerge <PR#>`
- FR4: Postmerge includes a new Sentry verification phase that checks cron monitors report `ok` or `active`

## Technical Requirements

- TR1: Sentry API token available via Doppler `prd` (`SENTRY_AUTH_TOKEN`, with `SENTRY_API_TOKEN` fallback)
- TR2: Monitor tool loops emit state-change events (not every-tick noise)

## Acceptance Criteria

- AC1: Ship Phase 7 detects a failing required check, delegates to test-fix-loop, pushes, and merge completes — all without operator intervention
- AC2: After merge + release workflows pass, postmerge runs automatically and reports production health
- AC3: Postmerge Sentry phase verifies cron monitors are healthy post-deploy
