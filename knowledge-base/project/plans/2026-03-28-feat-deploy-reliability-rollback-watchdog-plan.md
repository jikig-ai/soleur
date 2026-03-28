---
title: "Deploy Reliability: Rollback + Watchdog"
type: feat
date: 2026-03-28
---

# Deploy Reliability: Rollback + Watchdog

## Overview

Two complementary improvements to deploy reliability for the web-platform: Part A adds health-gated canary deployment with automatic rollback to `ci-deploy.sh`, preventing downtime from bad deploys. Part B adds a `deploy-watchdog.yml` GitHub Actions workflow that detects failed deploys, extracts diagnostic logs, and creates GitHub issues. Together they form a failure → rollback → investigation chain.

## Problem Statement

When a web-platform deploy fails after merge, the broken deploy causes downtime AND goes unnoticed. The current `ci-deploy.sh` kills the old container before verifying the new one works (hard-stop gap). 8 of the last 20 deploy runs failed (40%), with the #1235 failure going unnoticed until the founder manually checked.

## Proposed Solution

**Part A — Canary rollback in ci-deploy.sh:**
Restructure the web-platform deploy block (lines 97-126) to: pull new image → start canary on port 3001 → health-check canary → on success swap to production ports → on failure remove canary and keep old container.

**Part B — Deploy watchdog workflow:**
New `deploy-watchdog.yml` triggered by `workflow_run` on `Web Platform Release`. On failure: extract workflow step logs via `gh api`, pattern-match failure type, create GitHub issue with structured diagnosis. GitHub's built-in email notifications handle alerting.

## Technical Approach

### Architecture

```
ci-deploy.sh (server-side, async via webhook)
├── docker pull $IMAGE:$TAG
├── docker run --name soleur-web-platform-canary -p 3001:3000 ...
├── Health check: curl -sf http://localhost:3001/health (10 attempts, 3s)
├── SUCCESS PATH:
│   ├── docker stop soleur-web-platform
│   ├── docker rm soleur-web-platform
│   ├── docker run --name soleur-web-platform -p 80:3000 -p 3000:3000 ...
│   ├── docker stop soleur-web-platform-canary
│   ├── docker rm soleur-web-platform-canary
│   └── exit 0
└── FAILURE PATH:
    ├── docker logs soleur-web-platform-canary (last 30 lines to syslog)
    ├── docker stop soleur-web-platform-canary
    ├── docker rm soleur-web-platform-canary
    ├── log DEPLOY_ROLLBACK event to syslog
    └── exit 1 (old container untouched, serves traffic)

GHA deploy job polls app.soleur.ai/health for 120s:
├── Canary passed + swap succeeded → new version responds → GHA succeeds
└── Canary failed + rollback → old version responds → version mismatch → GHA fails
    └── workflow_run triggers deploy-watchdog.yml
        ├── gh api: pull workflow run logs, identify failed step
        ├── Pattern match: version-mismatch/timeout/crash/health-check
        ├── Better Stack API: pull container logs (graceful degradation if unavailable)
        └── gh issue create with structured diagnosis
```

**Port swap gap:** The swap sequence has a ~1-2s window where port 80 is unbound (between stopping old and starting new production container). This is acceptable: Cloudflare Tunnel retries, GHA polls at 10s intervals, and this is vastly better than the current 30s+ gap during failed deploys.

**Async model:** ci-deploy.sh runs via fire-and-forget webhook (HTTP 202). Its exit code goes to `journalctl -u webhook`, not GHA. The watchdog detects failure through the GHA health poll timeout/version mismatch — rollback is inferred from "old version still responding."

**Better Stack limitation:** Better Stack currently provides uptime monitoring only — no container log ingestion exists. The watchdog ships with graceful degradation: if `BETTER_STACK_API_TOKEN` is not set, the issue body notes "Server-side logs unavailable" and uses GHA workflow logs only. Better Stack log drain setup is a follow-up task.

### Implementation Phases

#### Phase 1: Canary rollback in ci-deploy.sh

**Files modified:** `apps/web-platform/infra/ci-deploy.sh`

Restructure the web-platform deploy block (lines 97-126):

1. **Pull image** (unchanged): `docker pull "$IMAGE:$TAG"`
2. **Resolve env file** (moved earlier): `ENV_FILE=$(resolve_env_file)` — shared by canary and production
3. **chown volumes** (once): `sudo chown 1001:1001 /mnt/data/workspaces`
4. **Start canary:**

   ```bash
   docker run -d --name soleur-web-platform-canary \
     --restart no \
     --env-file "$ENV_FILE" \
     -v /mnt/data/workspaces:/workspaces \
     -v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro \
     -p 0.0.0.0:3001:3000 \
     "$IMAGE:$TAG"
   ```

   Note: `--restart no` for canary (not `unless-stopped`) — canary is temporary.
5. **Health-check canary:** Poll `http://localhost:3001/health` (10 attempts, 3s sleep).
6. **Success path:** Stop old → remove old → start new production on 80:3000 and 3000:3000 with `--restart unless-stopped` → stop canary → remove canary → cleanup env → exit 0.
7. **Failure path:** Dump canary logs (last 30 lines) to syslog → stop canary → remove canary → cleanup env → log `DEPLOY_ROLLBACK` event → exit 1.

**Gotchas from learnings:**

- Wrap every `docker stop ... || true` and `docker rm ... || true` in `{ ...; }` to prevent bash operator precedence bugs (learning: bash-operator-precedence)
- Use `rm -f` under `set -euo pipefail` for TOCTOU safety (learning: toctou-race-fix)
- Health check uses `curl -sf` (existing pattern) — canary on port 3001 not 3000
- Env file cleanup must run on both success and failure paths — use trap or explicit cleanup in both branches
- The canary uses the same volumes and env as production — identical application environment

#### Phase 2: Canary rollback tests

**Files modified:** `apps/web-platform/infra/ci-deploy.test.sh`

Add test cases using existing mock infrastructure:

1. **Canary success path:** curl mock returns success → verify docker trace shows: prune → pull → canary-run → canary-health → old-stop → old-rm → prod-run → canary-stop → canary-rm
2. **Canary failure / rollback path:** curl mock returns failure for port 3001 → verify: canary-run → canary-health-fail → canary-stop → canary-rm → old container NOT stopped → exit 1
3. **Docker pull failure:** docker mock returns non-zero for `pull` → verify: no canary started, old container untouched, exit 1
4. **Canary crash (immediate exit):** docker mock returns non-zero for canary `run` → verify: no health check attempted, old container untouched, exit 1

**Testing pattern:** Use `run_deploy_traced()` (existing) which emits `DOCKER_TRACE:<subcommand>` markers. Add canary-specific trace markers. The `seq` mock returns `"1"` so health loops run once.

**Curl mock enhancement:** The existing curl mock always returns success. Add port-based routing: `localhost:3001` (canary) can be configured to return failure for rollback tests, while `localhost:3000` (production) returns success.

#### Phase 3: Deploy watchdog workflow

**Files created:** `.github/workflows/deploy-watchdog.yml`

```yaml
name: "Deploy Watchdog"

on:
  workflow_run:
    workflows: ["Web Platform Release"]
    types: [completed]
  workflow_dispatch:
    inputs:
      run_id:
        description: "Workflow run ID to investigate (for testing)"
        required: false
        type: string
      conclusion:
        description: "Simulated conclusion (for testing)"
        required: false
        type: choice
        options:
          - failure
          - success
        default: failure

permissions:
  issues: write
  actions: read

jobs:
  investigate:
    if: >-
      (github.event_name == 'workflow_dispatch') ||
      (github.event.workflow_run.conclusion == 'failure')
    runs-on: ubuntu-latest
    timeout-minutes: 5
    ...
```

**Steps:**

1. **Resolve run context:** From `workflow_run` event or `workflow_dispatch` inputs. Validate run ID format `^[0-9]+$`.

2. **Extract failure details:** Use `gh api repos/{owner}/{repo}/actions/runs/{id}/jobs` to find the failed job and step. Extract step name, conclusion, and the last 50 lines of step log output.

3. **Pattern match failure type:**
   - `"Deploy via webhook"` step failed → label `deploy/webhook-rejected`
   - `"Verify deploy health"` step failed + `expected .*, got (empty)` → label `deploy/crash`
   - `"Verify deploy health"` step failed + `expected .*, got .*` → label `deploy/stale` (rollback inferred)
   - `"Verify deploy health"` step failed + `timed out` → label `deploy/timeout`
   - Default → label `deploy/unknown`

4. **Better Stack log query (graceful degradation):**

   ```bash
   if [[ -n "${BETTER_STACK_API_TOKEN:-}" ]]; then
     # Query Better Stack Logs API for container logs ±5min of deploy
     # ... (future: when log drain is configured)
   else
     BETTERSTACK_LOGS="Server-side container logs unavailable (Better Stack log drain not configured)."
   fi
   ```

5. **Issue dedup:** Use label + exact title match (terraform-drift pattern):

   ```bash
   TITLE="deploy: ${FAILURE_TYPE} on ${SHORT_SHA}"
   EXISTING=$(gh issue list --label "$LABEL" --state open \
     --limit 50 --json number,title \
     --jq ".[] | select(.title == \"${TITLE}\") | .number" \
     | head -1)
   ```

   If existing: add comment with new failure details. If new: create issue.

6. **Create issue:** Write body to temp file with `printf`, use `--body-file`. Include:
   - Failure type heading and label
   - Affected commit SHA and PR link
   - Workflow run URL
   - Failed step name and output (in collapsible `<details>`)
   - Better Stack logs (in collapsible) or "unavailable" note
   - Suggested investigation steps based on pattern
   - `--milestone "Post-MVP / Later"`

7. **Label management:** Pre-create labels with `gh label create "deploy/..." ... 2>/dev/null || true`.

**Key implementation rules (from learnings):**

- Every `gh` CLI step needs `GH_TOKEN: ${{ github.token }}` in `env:`
- Use `printf` to temp file + `--body-file` (never heredoc in YAML `run: |`)
- Left-align all content in `run:` blocks
- Sanitize GITHUB_OUTPUT writes with `tr -d '\n\r'`
- Suppress curl stderr with `2>/dev/null` to prevent token leakage
- Use exact title match via `jq select`, not fuzzy `--search`

#### Phase 4: Verification

1. Run `ci-deploy.test.sh` — all existing + new tests pass
2. Manual `gh workflow run deploy-watchdog.yml` with simulated failure
3. Verify issue created with correct labels, formatting, and milestone
4. Verify graceful degradation when `BETTER_STACK_API_TOKEN` is unset

## Acceptance Criteria

### Functional

- [ ] Canary container starts on port 3001 with identical config before old container is touched
- [ ] On canary health-check pass: old container stopped, new production started on ports 80/3000
- [ ] On canary health-check fail: canary removed, old container untouched, exit 1
- [ ] `DEPLOY_ROLLBACK` event logged to syslog on rollback with image tags and failure details
- [ ] `deploy-watchdog.yml` triggers on `web-platform-release.yml` failure
- [ ] Watchdog creates GitHub issue with structured diagnosis (failure type, logs, commit, PR link)
- [ ] Watchdog applies correct label based on pattern match
- [ ] Watchdog deduplicates issues (comments on existing instead of creating duplicate)
- [ ] Watchdog degrades gracefully when `BETTER_STACK_API_TOKEN` is unset
- [ ] `workflow_dispatch` allows manual testing with simulated failure

### Testing

- [ ] ci-deploy.test.sh: canary success path verified via docker trace ordering
- [ ] ci-deploy.test.sh: rollback path verified (canary removed, old preserved)
- [ ] ci-deploy.test.sh: docker pull failure handled (no canary started)
- [ ] ci-deploy.test.sh: all existing tests still pass (no regressions)
- [ ] Watchdog: manual `workflow_dispatch` run succeeds and creates test issue

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** New workflow required (post-merge-monitor.yml not reusable). Recommended phased approach: rollback + watchdog over Kamal migration. SSH re-introduction is a dealbreaker. The rollback logic replicates Kamal's core value in ~30 lines of bash. Port swap has ~1-2s gap, acceptable given Cloudflare retry and GHA poll interval. No capability gaps.

### Operations (COO)

**Status:** reviewed
**Assessment:** 40% failure rate clusters on 2026-03-27 (6 failures), suggesting specific incident. Pipeline hardened over 7+ sessions. Kamal costs $0 but reverses SSH→webhook migration. Recommended: diagnose failure cluster alongside building fixes. Flagged stale Plausible entry in expenses.md. No capability gaps.

## Test Scenarios

### Part A — ci-deploy.sh

- Given a valid deploy command, when canary health check passes, then old container is stopped and new production container runs on ports 80:3000 and 3000:3000
- Given a valid deploy command, when canary health check fails, then canary is removed and old container continues serving traffic on ports 80:3000
- Given a valid deploy command, when docker pull fails, then no canary is started and old container is untouched
- Given a valid deploy command, when canary docker run fails (crash on start), then no health check runs and old container is untouched
- Given a valid deploy command, when canary succeeds but old container was already dead, then new production container starts normally (no stop/rm errors — guarded by `{ ... || true; }`)

### Part B — deploy-watchdog.yml

- Given web-platform-release.yml completes with failure, when deploy-watchdog.yml triggers, then a GitHub issue is created with failure diagnosis
- Given an existing open issue with matching label and title, when a new failure occurs, then the existing issue receives a comment (no duplicate)
- Given BETTER_STACK_API_TOKEN is unset, when watchdog runs, then issue is created with "Server-side logs unavailable" note
- Given workflow_dispatch with simulated failure, when run manually, then issue creation logic executes correctly
- Given web-platform-release.yml completes with success, when deploy-watchdog.yml triggers, then no action is taken (job skipped)

## Dependencies & Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Port swap gap (~1-2s) | Brief 502/503 during swap | Cloudflare Tunnel retry, GHA 10s poll interval absorbs it |
| Concurrent deploys during canary | Second deploy races with first | GHA concurrency group `deploy-web-platform` already prevents this |
| Better Stack log drain not configured | Watchdog issue lacks server-side logs | Graceful degradation built in; GHA logs provide step-level detail |
| Disk space during canary (two containers + images) | Docker pull or run fails | `docker system prune -f --filter "until=48h"` runs before pull (existing) |
| Canary port 3001 conflicts with another service | Canary fails to start | No other service uses 3001 on this server |

## References & Research

### Internal References

- `apps/web-platform/infra/ci-deploy.sh:97-126` — current deploy block to restructure
- `apps/web-platform/infra/ci-deploy.test.sh:14-82` — mock infrastructure for testing
- `.github/workflows/web-platform-release.yml:49-93` — deploy job (webhook + health poll)
- `.github/workflows/scheduled-terraform-drift.yml:120-186` — issue creation + dedup pattern to follow
- `.github/workflows/scheduled-cf-token-expiry-check.yml:88-140` — alternate issue creation pattern
- `.github/workflows/post-merge-monitor.yml` — workflow_run trigger pattern (NOT to extend)
- `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` — critical: `{ ...; } || true` pattern
- `knowledge-base/project/learnings/2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md` — critical: printf to temp file, not heredoc in YAML
- `knowledge-base/project/learnings/2026-03-19-docker-restart-does-not-apply-new-images.md` — critical: stop/rm/run, never restart

### Related Issues

- #1238 — parent issue (this plan implements it)
- #1235 — production observability (Better Stack integration, triggered this work)
- #1237 — health endpoint fix (immediate 503 fix)
- #749, #963, #967, #968 — SSH→webhook migration (why Kamal was rejected)
