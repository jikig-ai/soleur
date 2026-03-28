# Spec: Deploy Watchdog

**Issue:** #1238
**Branch:** deploy-watchdog
**Status:** Draft

## Problem Statement

When a web-platform deploy fails after merge, the broken deploy sits unresolved until a human notices. In #1235, the deploy failed because the health endpoint returned 503 — this went unnoticed until the founder manually checked. 4 of the last 10 deploy runs have failed, making this a recurring pain point with no automated detection or diagnosis.

## Goals

- G1: Automatically detect when `web-platform-release.yml` deploy job fails
- G2: Extract structured diagnosis from both GitHub Actions workflow logs and server-side container logs (Better Stack)
- G3: Create a GitHub issue with categorized failure reason, relevant logs, and actionable next steps
- G4: Leverage GitHub's built-in email notifications for alerting (no custom alerting infrastructure)

## Non-Goals

- Auto-fixing deploy failures (deferred — requires deploy secrets, infinite-loop guards, retry authority decisions)
- Custom alerting via Discord, Telegram, or transactional email
- Extending `post-merge-monitor.yml` (different trigger, scope, and purpose)
- Monitoring runtime failures after successful deploy (Better Stack uptime handles this)

## Functional Requirements

- **FR1:** New `deploy-watchdog.yml` workflow triggered by `workflow_run` on `web-platform-release.yml` with `types: [completed]`
- **FR2:** On `conclusion == failure`, extract failed job/step name, exit code, and last N lines of step output via `gh api repos/{owner}/{repo}/actions/runs/{id}/logs`
- **FR3:** Query Better Stack Logs API for container logs in a time window around the deploy (e.g., ±5 minutes of workflow start). Graceful degradation if query fails.
- **FR4:** Pattern-match failure against known types: version mismatch (expected X, got Y/empty), health endpoint non-200, deploy verification timeout, container crash/OOM
- **FR5:** Create GitHub issue with structured body: failure type, affected commit/PR, workflow run link, workflow step logs, Better Stack container logs, suggested investigation steps
- **FR6:** Apply labels based on failure type (e.g., `deploy/version-mismatch`, `deploy/health-check`, `deploy/timeout`, `deploy/crash`)
- **FR7:** Support `workflow_dispatch` with inputs for testing (simulated conclusion, optional run ID override)

## Technical Requirements

- **TR1:** Must not extend `post-merge-monitor.yml` — create a new workflow file
- **TR2:** Requires `BETTER_STACK_API_TOKEN` in GitHub secrets
- **TR3:** Heredoc body content in `run:` blocks must be left-aligned (AGENTS.md rendering rule)
- **TR4:** After merge, must trigger a manual run (`gh workflow run`) and verify the workflow produces correct output (AGENTS.md workflow verification gate)
- **TR5:** Issue body must use proper Markdown (no indentation that renders as code blocks)

## Known Failure Patterns

| Pattern | Signature in Logs | Label |
|---------|------------------|-------|
| Version mismatch (empty) | `expected X, got (empty)` | `deploy/crash` |
| Version mismatch (old) | `expected X, got Y` | `deploy/stale` |
| Health timeout | `Deploy verification timed out` | `deploy/timeout` |
| Health non-200 | `HTTP 503` or similar | `deploy/health-check` |

## Dependencies

- `web-platform-release.yml` — the workflow being monitored
- Better Stack API — for container log retrieval
- `gh` CLI — for workflow log extraction and issue creation
