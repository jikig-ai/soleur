# Tasks: Deploy Reliability — Rollback + Watchdog

**Issue:** #1238
**Branch:** deploy-watchdog
**Plan:** `knowledge-base/project/plans/2026-03-28-feat-deploy-reliability-rollback-watchdog-plan.md`

## Phase 1: Canary Rollback in ci-deploy.sh

- [ ] 1.1 Read current `apps/web-platform/infra/ci-deploy.sh` (full file)
- [ ] 1.2 Restructure web-platform deploy block (lines 97-126):
  - [ ] 1.2.1 Move `resolve_env_file()` call and `sudo chown` before canary start
  - [ ] 1.2.2 Add canary `docker run` on port 3001 with `--restart no`
  - [ ] 1.2.3 Add canary health-check loop (`localhost:3001/health`, 10 attempts, 3s)
  - [ ] 1.2.4 Add success path: stop old → rm old → start production (80:3000, 3000:3000) → stop canary → rm canary
  - [ ] 1.2.5 Add failure path: dump canary logs → stop canary → rm canary → log DEPLOY_ROLLBACK → exit 1
  - [ ] 1.2.6 Ensure `{ ...; } || true` wrapping on all docker stop/rm calls
  - [ ] 1.2.7 Ensure env file cleanup runs on both paths (trap or explicit)

## Phase 2: Canary Rollback Tests

- [ ] 2.1 Read current `apps/web-platform/infra/ci-deploy.test.sh` (full file)
- [ ] 2.2 Enhance curl mock to support port-based routing (3001 for canary, 3000 for production)
- [ ] 2.3 Add test: canary success path — verify docker trace ordering
- [ ] 2.4 Add test: canary failure / rollback path — verify old container preserved
- [ ] 2.5 Add test: docker pull failure — no canary started
- [ ] 2.6 Add test: canary crash on start — no health check, old untouched
- [ ] 2.7 Run full test suite — all existing + new tests pass

## Phase 3: Deploy Watchdog Workflow

- [ ] 3.1 Create `.github/workflows/deploy-watchdog.yml` with workflow_run + workflow_dispatch triggers
- [ ] 3.2 Add run context resolution step (from event or inputs)
- [ ] 3.3 Add failure detail extraction step (gh api for jobs + step logs)
- [ ] 3.4 Add pattern matching step (version-mismatch, timeout, crash, webhook-rejected)
- [ ] 3.5 Add Better Stack log query step with graceful degradation
- [ ] 3.6 Add label pre-creation step (`deploy/crash`, `deploy/stale`, `deploy/timeout`, `deploy/health-check`, `deploy/webhook-rejected`, `deploy/unknown`)
- [ ] 3.7 Add issue dedup step (label + exact title match via jq)
- [ ] 3.8 Add issue creation step (printf to temp file + --body-file, milestone included)

## Phase 4: Verification

- [ ] 4.1 Run `ci-deploy.test.sh` — all tests pass
- [ ] 4.2 Manual `gh workflow run deploy-watchdog.yml` with simulated failure (after merge)
- [ ] 4.3 Verify issue format, labels, milestone, and Markdown rendering
- [ ] 4.4 Verify graceful degradation (no BETTER_STACK_API_TOKEN)
