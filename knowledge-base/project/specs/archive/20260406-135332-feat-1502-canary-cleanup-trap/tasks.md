# Tasks: fix canary crash leaks temp secrets file

Ref: `knowledge-base/project/plans/2026-04-06-fix-canary-crash-leaks-temp-secrets-file-plan.md`

## Phase 1: RED -- Write failing test

- [x] 1.1 Add `assert_env_file_cleanup` helper to `apps/web-platform/infra/ci-deploy.test.sh`
  - Create `ENV_FILE_TRACKER` dir outside mock dir (survives deploy process exit)
  - Mock `mktemp` to record created file path to tracker via `/usr/bin/mktemp` (not `command mktemp` -- mktemp is external, not a builtin)
  - After deploy exits, check if the tracked env file still exists on disk
- [x] 1.2 Add test: canary crash cleans up env file (`MOCK_DOCKER_RUN_FAIL_CANARY=1`)
  - Test should FAIL against current code (canary crash path skips cleanup)
- [x] 1.3 Add test: successful deploy cleans up env file (verify trap cleanup on success path too)

## Phase 2: GREEN -- Implement trap-based cleanup

- [x] 2.1 Add EXIT trap to `apps/web-platform/infra/ci-deploy.sh` after `resolve_env_file` call (line 134)
  - `trap 'rm -f "$ENV_FILE"' EXIT`
- [x] 2.2 Remove all 4 explicit `cleanup_env_file "$ENV_FILE"` calls (lines 170, 194, 202, 211)
- [x] 2.3 Remove the `cleanup_env_file` function definition (lines 47-50)
- [x] 2.4 Remove the comment on line 16 referencing `cleanup_env_file`

## Phase 3: VERIFY -- Run tests

- [x] 3.1 Run `bash apps/web-platform/infra/ci-deploy.test.sh` -- all tests pass (including new test)
- [x] 3.2 Verify test count is 37/37 (35 existing + 2 new cleanup tests)
