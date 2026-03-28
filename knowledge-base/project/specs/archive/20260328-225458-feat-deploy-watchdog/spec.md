# Spec: Deploy Reliability — Rollback + Watchdog

**Issue:** #1238
**Branch:** deploy-watchdog
**Status:** Draft

## Problem Statement

When a web-platform deploy fails after merge, the broken deploy sits unresolved until a human notices. In #1235, the deploy failed because the health endpoint returned 503 — this went unnoticed until the founder manually checked. 8 of the last 20 deploy runs have failed (40%), with a cluster of 6 failures on 2026-03-27.

The current deploy has a hard-stop gap: the old container is killed before the new one is verified. Failed deploys cause downtime AND go unnoticed.

## Goals

- G1: Prevent downtime from failed deploys via health-gated container swapping with automatic rollback
- G2: Automatically detect when deploys fail (including rollbacks) and investigate root cause
- G3: Create a GitHub issue with structured diagnosis from workflow logs + server-side container logs
- G4: Leverage GitHub's built-in email notifications for alerting (no custom alerting infrastructure)

## Non-Goals

- Kamal migration (evaluated and rejected — SSH re-introduction dealbreaker)
- Custom alerting via Discord, Telegram, or transactional email
- Extending `post-merge-monitor.yml` (different trigger, scope, and purpose)
- Monitoring runtime failures after successful deploy (Better Stack uptime handles this)

## Architecture: The Failure → Rollback → Investigation Chain

```
Push to main → web-platform-release.yml → webhook → ci-deploy.sh
                                                       │
                                              ┌────────┴────────┐
                                              │ Start new        │
                                              │ container as     │
                                              │ canary           │
                                              └────────┬────────┘
                                                       │
                                              ┌────────┴────────┐
                                         PASS │ Health check?    │ FAIL
                                              └───┬─────────┬───┘
                                                  │         │
                                           Swap traffic   Remove canary
                                           Remove old     Keep old running
                                           Exit 0         Log rollback event
                                                          Exit 1
                                                            │
                                              ┌─────────────┴──────────────┐
                                              │ Deploy job fails            │
                                              │ workflow_run triggers       │
                                              │ deploy-watchdog.yml         │
                                              └─────────────┬──────────────┘
                                                            │
                                              ┌─────────────┴──────────────┐
                                              │ Pull workflow logs (gh API) │
                                              │ Pull container logs         │
                                              │   (Better Stack API)       │
                                              │ Pattern-match failure type  │
                                              │ Create GitHub issue         │
                                              │   → GitHub emails founder   │
                                              └────────────────────────────┘
```

## Part A: Rollback in ci-deploy.sh

### Functional Requirements

- **FR-A1:** Start new container under a temporary name (e.g., `soleur-web-platform-canary`) before stopping the old one
- **FR-A2:** Health-check the canary container (same logic as current: poll `localhost:<canary-port>/health` for N attempts)
- **FR-A3:** On health check pass: stop old container, rename canary to production name, update port bindings
- **FR-A4:** On health check fail: remove canary container, keep old container running (zero downtime)
- **FR-A5:** On rollback, write a structured `DEPLOY_ROLLBACK` event to stderr/syslog with: new image tag, old image tag, health check failure details, container logs snippet
- **FR-A6:** Exit non-zero on rollback so the deploy job in GitHub Actions fails and triggers the watchdog

### Technical Constraints

- The canary container needs a different host port (e.g., 3001) to avoid conflict with the running production container on port 3000
- After swap, the production container must be on port 3000 (or whatever port Cloudflare Tunnel routes to)
- Docker container naming: `soleur-web-platform` (production), `soleur-web-platform-canary` (during verification)
- Volume mounts must be identical between canary and production
- Environment variables (Doppler) must be identical
- The `{ ...; } || true` bash safety pattern applies (per learnings)

## Part B: Deploy Watchdog Workflow

### Functional Requirements

- **FR-B1:** New `deploy-watchdog.yml` workflow triggered by `workflow_run` on `web-platform-release.yml` with `types: [completed]`
- **FR-B2:** On `conclusion == failure`, extract failed job/step name, exit code, and last N lines of step output via `gh api repos/{owner}/{repo}/actions/runs/{id}/logs`
- **FR-B3:** Query Better Stack Logs API for container logs in a time window around the deploy (e.g., +/- 5 minutes of workflow start). Graceful degradation if query fails.
- **FR-B4:** Pattern-match failure against known types: version mismatch (expected X, got Y/empty), health endpoint non-200, deploy verification timeout, container crash/OOM, rollback event
- **FR-B5:** Create GitHub issue with structured body: failure type, affected commit/PR, workflow run link, workflow step logs, Better Stack container logs, rollback status, suggested investigation steps
- **FR-B6:** Apply labels based on failure type (e.g., `deploy/crash`, `deploy/stale`, `deploy/timeout`, `deploy/health-check`, `deploy/rollback`)
- **FR-B7:** Support `workflow_dispatch` with inputs for testing (simulated conclusion, optional run ID override)
- **FR-B8:** Issue deduplication: search for existing open issue with matching failure label before creating a new one. Update existing issue with a new comment if found.

### Technical Requirements

- **TR1:** Must not extend `post-merge-monitor.yml` — create a new workflow file
- **TR2:** Requires `BETTER_STACK_API_TOKEN` in GitHub secrets
- **TR3:** Heredoc body content in `run:` blocks must be left-aligned (AGENTS.md rendering rule)
- **TR4:** After merge, must trigger a manual run (`gh workflow run`) and verify the workflow produces correct output (AGENTS.md workflow verification gate)
- **TR5:** Issue body must use proper Markdown (no indentation that renders as code blocks)
- **TR6:** Issue must include `--milestone "Post-MVP / Later"` (AGENTS.md guardrail)

## Known Failure Patterns

| Pattern | Signature in Logs | Label | Part A Behavior |
|---------|------------------|-------|-----------------|
| Version mismatch (empty) | `expected X, got (empty)` | `deploy/crash` | Rollback — canary health check fails |
| Version mismatch (old) | `expected X, got Y` | `deploy/stale` | Rollback — canary returns wrong version |
| Health timeout | `Deploy verification timed out` | `deploy/timeout` | Rollback — canary health check times out |
| Health non-200 | `HTTP 503` or similar | `deploy/health-check` | Rollback — canary returns non-200 |
| Container crash/OOM | Container exits immediately | `deploy/crash` | Rollback — canary never starts |

## Dependencies

- `web-platform-release.yml` — the workflow whose deploy job triggers the watchdog
- `ci-deploy.sh` — the script being enhanced with rollback logic
- Better Stack API — for container log retrieval in the watchdog
- `gh` CLI — for workflow log extraction and issue creation
