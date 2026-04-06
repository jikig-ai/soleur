# Tasks: fix(infra) deploy health check version mismatch

Source: `knowledge-base/project/plans/2026-04-06-fix-deploy-health-check-version-mismatch-plan.md`

## Phase 1: Investigate server-side deploy failure

- [ ] 1.1 Check journald logs for ci-deploy.sh output during the failed deploy timeframe
- [ ] 1.2 Verify GHCR authentication -- check if `docker login ghcr.io` is configured on the server
- [ ] 1.3 Check running containers and images on the server (`docker ps -a`, `docker images`)
- [ ] 1.4 Check disk space (`df -h /`)
- [ ] 1.5 Identify root cause from investigation and document findings
- [ ] 1.6 Apply fix for root cause (if server-side issue found)

## Phase 2: Fix polling window and improve diagnostics

- [ ] 2.1 Update `.github/workflows/web-platform-release.yml` -- increase poll from 12 to 30 attempts
- [ ] 2.2 Replace `grep -q "ok"` with `jq -r '.status'` for robust status check
- [ ] 2.3 Add uptime to version mismatch log messages
- [ ] 2.4 Verify workflow YAML is valid (no heredoc/indentation issues per AGENTS.md)

## Phase 3: Verification

- [ ] 3.1 Trigger a deploy (merge to main or workflow_dispatch) and verify health check passes
- [ ] 3.2 Confirm email notification is not sent for the successful deploy
