---
title: "fix: canary crash leaks temp secrets file on disk"
type: fix
date: 2026-04-06
---

# fix: canary crash leaks temp secrets file on disk

Ref #1502

## Problem

If `docker run` for the canary fails under `set -e`, the script exits immediately and `cleanup_env_file "$ENV_FILE"` is never called. The temp file at `/tmp/doppler-env.XXXXXX` containing production secrets (Doppler download) persists on disk. The success, rollback, bwrap-failure, and prod-fail paths all call `cleanup_env_file`, but the canary crash path does not.

**Location:** `apps/web-platform/infra/ci-deploy.sh:134-147`

The current code flow after `ENV_FILE=$(resolve_env_file)` on line 134:

| Exit path | Cleanup called? | Lines |
|-----------|----------------|-------|
| Canary success, prod success | Yes | 194 |
| Canary success, prod failure | Yes | 202 |
| Canary health check failure (rollback) | Yes | 211 |
| Bwrap sandbox check failure | Yes | 170 |
| Canary `docker run` crash (`set -e`) | **No** | 139-147 |

## Proposed Solution

Add a `trap`-based cleanup for the env file immediately after `resolve_env_file` returns. This ensures cleanup on all exit paths (normal, error, signal). Then remove the four explicit `cleanup_env_file` calls since the trap handles all paths.

### ci-deploy.sh changes

```bash
# After line 134: ENV_FILE=$(resolve_env_file)
# Add:
trap 'rm -f "$ENV_FILE"' EXIT

# Remove: all 4 explicit cleanup_env_file "$ENV_FILE" calls (lines 170, 194, 202, 211)
# Remove: the cleanup_env_file function definition (lines 47-50)
```

### Key design decisions

1. **Single EXIT trap, not ERR trap.** EXIT fires on all exits (success, error, signal). ERR only fires on non-zero and does not fire on SIGTERM/SIGINT. EXIT is the correct choice for cleanup.

2. **Compose with existing ERR trap.** Line 13 has `trap '...' ERR`. The new EXIT trap is on a different signal (EXIT), so they do not conflict. Both can coexist.

3. **Remove `cleanup_env_file` function entirely.** With the trap, no caller needs to invoke cleanup manually. The function becomes dead code. Removing it eliminates the risk of future callers forgetting to call it.

4. **Trap placement: after `resolve_env_file`, not at script top.** The trap references `$ENV_FILE`, which is only set inside the `web-platform)` case block (line 134). Placing it at script top would reference an empty variable. Placing it immediately after `resolve_env_file` guarantees `ENV_FILE` is populated.

5. **No `trap -` reset needed.** The script always exits after the `web-platform)` block (all paths end with `exit 0` or `exit 1`), so the trap fires exactly once.

## Acceptance Criteria

- [ ] Temp env file is cleaned up on all exit paths including canary `docker run` crash
- [ ] No production secrets persist on disk after any deploy failure mode
- [ ] The `cleanup_env_file` function is removed (dead code elimination)
- [ ] All four explicit `cleanup_env_file` call sites are removed
- [ ] Existing ERR trap (line 13) continues to function
- [ ] All 35 tests still pass (current count verified: 35/35)
- [ ] New test added: canary crash path verifies env file cleanup

## Test Scenarios

- Given a successful deploy, when the script exits 0, then the temp env file does not exist on disk
- Given a canary `docker run` failure (`set -e` exit), when the script exits non-zero, then the temp env file does not exist on disk
- Given a canary health check failure (rollback), when the script exits 1, then the temp env file does not exist on disk
- Given a production `docker run` failure after canary success, when the script exits 1, then the temp env file does not exist on disk
- Given a docker pull failure (before `resolve_env_file`), when the script exits non-zero, then no temp env file was ever created (the EXIT trap was never registered because `set -e` exits before reaching the trap line)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Implementation Notes

### Files to modify

1. **`apps/web-platform/infra/ci-deploy.sh`** -- Add EXIT trap, remove `cleanup_env_file` function and all call sites
2. **`apps/web-platform/infra/ci-deploy.test.sh`** -- Add test verifying env file cleanup on canary crash path

### Terraform deployment

Changes to `ci-deploy.sh` trigger the `terraform_data.deploy_pipeline_fix` resource in `server.tf` (line 87-88: `triggers_replace` hashes the file content). After merge, `terraform apply` will push the updated script to the production server via SSH file provisioner.

### Test approach for env file cleanup

The test mock harness (`run_deploy_traced`) runs in a subshell with mocked commands. To verify env file cleanup, the test needs to:

1. Create a temp file to act as the mock `ENV_FILE`
2. Verify it is deleted after the deploy subshell exits (including on canary crash)
3. The existing `MOCK_DOCKER_RUN_FAIL_CANARY=1` mock already triggers the canary crash path

The mock `doppler` already writes `KEY=value` to a temp file via `resolve_env_file`. The test can check if that temp file persists after the deploy exits. However, since the deploy runs in a subshell, the temp file path needs to be captured. One approach: modify the mock doppler to write the temp file path to a known location (e.g., `$MOCK_DIR/env_file_path`), then check if the file at that path still exists after the subshell exits.

## References

- Issue: #1502
- Source: PR #1496 review finding
- Existing learning: `knowledge-base/project/learnings/implementation-patterns/2026-03-28-canary-rollback-docker-deploy.md`
- Existing learning: `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md`
- Terraform deploy mechanism: `apps/web-platform/infra/server.tf:86-101` (`deploy_pipeline_fix` resource)
