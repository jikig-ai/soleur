# Deploy Watchdog Brainstorm

**Date:** 2026-03-28
**Issue:** #1238
**Branch:** deploy-watchdog

## What We're Building

Two complementary improvements to deploy reliability:

**Part A — Rollback in ci-deploy.sh (prevention):** Enhance the server-side deploy script with health-gated container swapping. Before killing the old container, start the new one under a temporary name, health-check it, then swap. On failure, remove the new container and keep the old one running. This replicates Kamal's core zero-downtime deploy value in ~30 lines of bash without changing the deploy architecture.

**Part B — Deploy watchdog workflow (visibility):** New `deploy-watchdog.yml` GitHub Actions workflow that detects failed deploys, investigates root cause using workflow logs + Better Stack container logs, and creates a GitHub issue with structured diagnosis. When Part A rolls back, the watchdog ensures the rollback event is visible and investigated.

## Why This Approach

- **Real pain point:** 8 of the last 20 deploy runs failed (40%). The #1235 deploy failure went unnoticed until the founder manually checked.
- **Kamal evaluated and rejected:** CTO and COO independently recommended against Kamal migration. Key reasons: (1) Kamal deploys via SSH, reversing the deliberate SSH→Cloudflare Tunnel webhook migration across 4 issues (#749, #963, #967, #968); (2) no native Doppler adapter; (3) kamal-proxy conflicts with Cloudflare SSL termination; (4) 1-2 week migration vs. 3-5 days for targeted fixes. See Domain Assessments below.
- **Rollback solves the acute problem:** The current deploy has a hard-stop gap — old container is killed before new one is verified. This is the root cause of downtime during failed deploys. Health-gated swapping eliminates this gap.
- **Watchdog provides visibility:** Even with rollback, you want to know when deploys fail and why. The watchdog creates a GitHub issue with diagnosis, and GitHub's built-in email notifications alert the founder.
- **New workflow, not extending post-merge-monitor:** `post-merge-monitor.yml` is scoped to bot-fix commits on the CI workflow. Different trigger, scope, and concerns.
- **Better Stack for server-side logs:** GitHub Actions only sees the health poll timeout. Better Stack (already integrated per #1235) provides container-level failure details.

## Key Decisions

1. **Two-part approach: prevention + visibility.** Part A (ci-deploy.sh rollback) prevents downtime. Part B (watchdog) provides investigation and alerting. Neither alone is sufficient.
2. **Kamal rejected.** SSH re-introduction is a dealbreaker. The custom pipeline is already hardened over 7+ sessions. Adding rollback to ci-deploy.sh replicates Kamal's core value without the migration cost.
3. **No custom alerting.** Rely on GitHub's built-in email notifications for issue creation. No Discord webhook, no transactional email service.
4. **Better Stack API for container logs.** Requires `BETTER_STACK_API_TOKEN` in GitHub secrets. Graceful degradation: if query fails, issue is created with workflow logs only.
5. **Pattern matching for known failures.** Version mismatch (expected X, got Y/empty), health 503, deploy verification timeout, container crash. Pattern match informs the issue title and labels.
6. **`workflow_dispatch` for testing.** Watchdog includes manual trigger inputs to simulate failure scenarios.

## Open Questions

1. **Better Stack API token availability.** Does a token already exist in Doppler/GitHub secrets, or does it need to be created?
2. **Log retention window.** How far back does Better Stack retain logs?
3. **Issue deduplication.** Should the watchdog update an existing issue or create a new one on repeated failures?
4. **Rollback container naming.** What temporary name should the new container use during health verification? (e.g., `soleur-web-platform-canary`)
5. **Rollback notification.** Should ci-deploy.sh write a structured event to syslog when rollback occurs, so Better Stack can surface it?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary (initial):** `post-merge-monitor.yml` is not reusable — it monitors CI (not deploys) and is scoped to bot-fix commits. A new workflow is needed. Recommended phasing: detect+alert (small), investigation (medium), auto-fix (large/risky).

**Summary (Kamal evaluation):** Kamal's SSH requirement is a dealbreaker given 4 issues documenting the deliberate migration away from SSH. Recommended Option C (rollback in ci-deploy.sh) + Option B Phase 1 (watchdog) over Kamal migration. The rollback logic replicates Kamal's core value (health-gated traffic cutover) in ~30 lines of bash. Estimated 3-5 days vs. 1-2 weeks for Kamal with higher risk. No capability gaps.

### Operations (COO)

**Summary:** The 40% failure rate (8/20 runs) clusters on 2026-03-27 (6 failures in one day), suggesting a specific incident rather than chronic fragility. The custom pipeline has been hardened over 7+ sessions with significant investment. Kamal has zero cost impact ($0) but re-introduces SSH, reversing a deliberate architectural decision. Migration effort: 8-12 hours. Recommended: diagnose failure cluster before committing to any solution. Flagged stale Plausible entry in expenses.md. No capability gaps.
