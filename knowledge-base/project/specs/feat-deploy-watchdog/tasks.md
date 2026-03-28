# Tasks: Deploy Reliability — Canary Rollback

**Issue:** #1238
**Branch:** deploy-watchdog
**Plan:** `knowledge-base/project/plans/2026-03-28-feat-deploy-reliability-rollback-watchdog-plan.md`

## Phase 1: Canary Rollback in ci-deploy.sh

- [ ] 1.1 Read `apps/web-platform/infra/ci-deploy.sh` (full file)
- [ ] 1.2 Add `flock` serialization at top of script
- [ ] 1.3 Add stale canary cleanup before deploy block
- [ ] 1.4 Restructure web-platform deploy block (lines 97-126):
  - [ ] 1.4.1 Move `resolve_env_file()` and `sudo chown` before canary start
  - [ ] 1.4.2 Add canary `docker run` on port 3001 with `--restart no`
  - [ ] 1.4.3 Add canary health-check loop (`localhost:3001/health`, 10 attempts, 3s)
  - [ ] 1.4.4 Add success path: stop old → rm old → start production (80:3000, 3000:3000) → stop canary → rm canary
  - [ ] 1.4.5 Add failure path: dump canary logs (protected) → stop canary → rm canary → log DEPLOY_ROLLBACK → exit 1
  - [ ] 1.4.6 Handle production start failure after canary success (third path)
  - [ ] 1.4.7 Ensure `{ ...; } || true` wrapping on all docker stop/rm/logs calls
  - [ ] 1.4.8 Ensure env file cleanup runs on both paths

## Phase 2: Tests

- [ ] 2.1 Read `apps/web-platform/infra/ci-deploy.test.sh` (full file)
- [ ] 2.2 Enhance curl mock for port-based routing (3001 canary, configurable failure)
- [ ] 2.3 Add test: canary success path — verify docker trace ordering
- [ ] 2.4 Add test: canary failure / rollback — verify old container preserved
- [ ] 2.5 Add test: docker pull failure — no canary started
- [ ] 2.6 Add test: canary crash on start — no health check, old untouched
- [ ] 2.7 Add test: production start failure after canary success
- [ ] 2.8 Add test: stale canary cleanup
- [ ] 2.9 Add test: flock rejects concurrent deploy
- [ ] 2.10 Run full test suite — all existing + new tests pass
