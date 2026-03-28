# Deploy Watchdog Brainstorm

**Date:** 2026-03-28
**Issue:** #1238
**Branch:** deploy-watchdog

## What We're Building

A GitHub Actions workflow (`deploy-watchdog.yml`) that automatically detects failed web-platform deploys, investigates the root cause by pulling both workflow logs and server-side container logs, and creates a structured GitHub issue with diagnosis. GitHub's built-in email notifications handle alerting — no custom Discord or email integration needed.

The watchdog triggers via `workflow_run` on `web-platform-release.yml`. When the release workflow's deploy job fails, the watchdog:

1. Extracts workflow step logs via `gh api` to identify which step failed and why
2. Queries Better Stack Logs API for container logs from the deploy time window
3. Pattern-matches against known failure types (version mismatch, health 503, timeout, container crash)
4. Creates a GitHub issue with structured diagnosis including both log sources

## Why This Approach

- **Real pain point:** 4 of the last 10 deploy runs failed. The #1235 deploy failure went unnoticed until the founder manually checked.
- **New workflow, not extending post-merge-monitor:** The existing `post-merge-monitor.yml` is scoped to bot-fix commits on the CI workflow with an infinite-loop guard tied to that design. Different trigger, different scope, different concerns.
- **Better Stack for server-side logs:** GitHub Actions only sees the health poll timeout, not the actual container failure reason (OOM, crash, startup error). Better Stack is already integrated (#1235) and provides the missing observability layer.
- **GitHub email for alerting:** GitHub already emails repo watchers on issue creation. Adding custom alerting is unnecessary complexity. The watchdog's job is to create the issue with good diagnosis — notification is GitHub's job.
- **Single workflow:** All logic in one file. No premature abstractions (only web-platform deploys today). Testable via `workflow_dispatch`.

## Key Decisions

1. **Scope: Phase 1 + 2 only.** Detect + investigate + create issue. No auto-fix — deferred to a separate issue due to high risk (deploy secrets, infinite-loop potential, retry authority conflicts with server-side `ci-deploy.sh`).
2. **No custom alerting.** Rely on GitHub's built-in email notifications for issue creation. No Discord webhook, no transactional email service.
3. **Better Stack API for container logs.** Requires `BETTER_STACK_API_TOKEN` in GitHub secrets. Graceful degradation: if Better Stack query fails, issue is still created with workflow logs only.
4. **Pattern matching for known failures.** Version mismatch (expected X, got Y/empty), health 503, deploy verification timeout, container crash. Pattern match informs the issue title and labels but does not trigger automated remediation.
5. **`workflow_dispatch` for testing.** Include manual trigger inputs to simulate failure scenarios without needing an actual failed deploy.

## Open Questions

1. **Better Stack API token availability.** Does a token already exist in Doppler/GitHub secrets, or does it need to be created? (Actionable during implementation.)
2. **Log retention window.** How far back does Better Stack retain logs? Affects the query time window for the container logs.
3. **Issue deduplication.** If a deploy fails, gets investigated, then the same commit is re-deployed and fails again, should the watchdog update the existing issue or create a new one?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The existing `post-merge-monitor.yml` is not reusable — it monitors CI (not deploys) and is scoped to bot-fix commits. A new workflow is needed. The CTO strongly recommended phasing: detect+alert is small, investigation is medium (requires log access strategy), auto-fix is large with its own risk profile. Key risk: GitHub Actions only sees health poll timeouts, not actual container failures. Better Stack bridges this gap. No capability gaps identified — existing tooling (`gh` CLI, `workflow_run` triggers, Better Stack) covers all Phase 1+2 requirements.
