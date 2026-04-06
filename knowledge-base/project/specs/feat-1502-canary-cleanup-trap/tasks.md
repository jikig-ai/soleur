# Tasks: fix canary crash leaks temp secrets file

Ref: `knowledge-base/project/plans/2026-04-06-fix-canary-crash-leaks-temp-secrets-file-plan.md`

## Phase 1: RED -- Write failing test

- [ ] 1.1 Add test to `apps/web-platform/infra/ci-deploy.test.sh` that verifies env file cleanup on canary crash path
  - Use `MOCK_DOCKER_RUN_FAIL_CANARY=1` to trigger canary crash
  - Verify the temp env file created by `resolve_env_file` does not persist after script exit
  - Test should FAIL against current code (canary crash path skips cleanup)

## Phase 2: GREEN -- Implement trap-based cleanup

- [ ] 2.1 Add EXIT trap to `apps/web-platform/infra/ci-deploy.sh` after `resolve_env_file` call (line 134)
  - `trap 'rm -f "$ENV_FILE"' EXIT`
- [ ] 2.2 Remove all 4 explicit `cleanup_env_file "$ENV_FILE"` calls (lines 170, 194, 202, 211)
- [ ] 2.3 Remove the `cleanup_env_file` function definition (lines 47-50)
- [ ] 2.4 Remove the comment on line 16 referencing `cleanup_env_file`

## Phase 3: VERIFY -- Run tests

- [ ] 3.1 Run `bash apps/web-platform/infra/ci-deploy.test.sh` -- all tests pass (including new test)
- [ ] 3.2 Verify test count is 36/36 (35 existing + 1 new)
