---
name: post-ship-autonomous-monitor
lane: single-domain
brand_survival_threshold: none
---

# Post-Ship Autonomous Monitor

## Problem Statement

The shipping pipeline stops at "auto-merge enabled." CI failures block merge silently, Sentry regressions go unnoticed, and `/soleur:postmerge` is never invoked automatically. The operator must manually monitor merge status, fix CI failures, and verify production health — defeating the purpose of autonomous shipping.

## Goals

1. Ship Phase 7 autonomously fixes CI failures that block merge (up to 2 attempts)
2. Ship Phase 7 auto-chains to `/soleur:postmerge` after merge + release workflows pass
3. Postmerge verifies Sentry health post-deploy (cron monitors + error count spike detection)
4. All polling uses Monitor tool instead of bash `while`/`sleep` loops

## Non-Goals

- Automated rollback on production regression (out of scope — surface the problem, don't auto-revert)
- Cross-app deployment coordination (single-app deploy pipeline only)
- Real-time alerting infrastructure (this is session-scoped monitoring, not a persistent monitoring system)

## Functional Requirements

- FR1: When a required CI check fails during ship Phase 7 merge poll, the agent attempts to diagnose and fix the failure (run tests locally, identify issue, commit fix, push, re-queue auto-merge)
- FR2: CI auto-fix is capped at 2 attempts. After 2 failures, escalate to the operator with diagnosis.
- FR3: After ship Phase 7 confirms merge + all release workflows pass, automatically invoke `/soleur:postmerge <PR#>`
- FR4: Postmerge includes a new Sentry verification phase that: (a) checks Sentry cron monitors report `ok`, (b) compares error count 15-min post-deploy vs 15-min pre-deploy baseline, flags >2x spike
- FR5: All polling loops (merge status, CI status, release workflows, deploy health, Sentry) use the Monitor tool, not bash `while`/`sleep`

## Technical Requirements

- TR1: Sentry API token available via Doppler `prd` (`SENTRY_API_TOKEN`)
- TR2: Sentry release tag format matches CI workflow output (`web-platform@X.Y.Z+<sha>`)
- TR3: Monitor tool loops emit state-change events (not every-tick noise)
- TR4: Ship Phase 7 poll block refactored from bash loop to Monitor tool invocation

## Acceptance Criteria

- AC1: Ship Phase 7 detects a failing required check, runs tests locally, fixes the issue, pushes, and merge completes — all without operator intervention
- AC2: After merge + release workflows pass, postmerge runs automatically and reports production health
- AC3: Postmerge Sentry phase catches a >2x error spike and reports it
- AC4: Postmerge Sentry phase verifies cron monitors are healthy post-deploy
- AC5: No bash `while`/`sleep` polling loops remain in ship Phase 7 or postmerge
