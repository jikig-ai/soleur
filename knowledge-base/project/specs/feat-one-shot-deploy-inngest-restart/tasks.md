# Tasks: feat(deploy): add inngest-server restart to deploy pipeline

Source plan: `knowledge-base/project/plans/2026-05-27-feat-deploy-inngest-server-restart-pipeline-plan.md`
Issue: #4538

## Phase 1: Sudoers entry

- [ ] 1.1 Add `INNGEST_RESTART` Cmnd_Alias to `apps/web-platform/infra/deploy-inngest-bootstrap.sudoers`
  - `Cmnd_Alias INNGEST_RESTART = /usr/bin/systemctl restart inngest-server.service`
  - `deploy ALL=(root) NOPASSWD: INNGEST_RESTART`
- [ ] 1.2 Add matching entry to `apps/web-platform/infra/cloud-init.yml` inline sudoers block (lines 54-64) for fresh-host parity

## Phase 2: ci-deploy.sh restart action

- [ ] 2.1 Widen action validation to accept `restart` alongside `deploy`
- [ ] 2.2 Add `restart` action validation: component must be `inngest`, reject others with `component_not_restartable`
- [ ] 2.3 Add `verify_inngest_functions()` helper function
  - Health check loop: 10 attempts x 3s at `127.0.0.1:8288`
  - Function count: `curl -s http://127.0.0.1:8288/v1/functions | jq length`
  - Floor check: count >= 1 (not exact match)
  - Returns 0 on success, 1 on health failure or zero functions
- [ ] 2.4 Add `restart inngest` case handler
  - `sudo systemctl restart inngest-server.service`
  - Call `verify_inngest_functions()`
  - Write state on success/failure via `final_write_state`

## Phase 3: Post-deploy inngest function log

- [ ] 3.1 Add lightweight function count log to web-platform handler
  - Placement: BEFORE `final_write_state 0 "ok"` / `exit 0`
  - Wait 5s, single curl to `/v1/functions | jq length`
  - Log count via `logger -t "$LOG_TAG" "INNGEST_FUNCTION_COUNT: $count"`
  - If count == 0, log warning suggesting restart workflow
  - Strictly informational, no state writes, no auto-restart

## Phase 4: GitHub Actions workflow

- [ ] 4.1 Create `.github/workflows/restart-inngest-server.yml`
  - `workflow_dispatch` trigger (no inputs needed)
  - Send `restart inngest _ latest` to deploy webhook
  - HMAC-sign payload with `WEBHOOK_DEPLOY_SECRET`
  - Include CF Access headers (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`)
  - Poll deploy-status endpoint until terminal state
  - Report success/failure via annotations

## Phase 5: Tests

- [ ] 5.1 Add restart test cases to `apps/web-platform/infra/ci-deploy.test.sh`
  - Successful restart with health check pass
  - Inngest health check failure after restart
  - Restart of non-inngest component rejected
  - Zero functions after restart returns non-zero

## Phase 6: Runbook update

- [ ] 6.1 Update H9 Restore section in `cloud-scheduled-tasks.md`
  - Add `gh workflow run restart-inngest-server.yml` as primary automated restore path
  - Keep SSH path as fallback reference
