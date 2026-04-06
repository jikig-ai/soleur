---
title: "fix: canary crash leaks temp secrets file on disk"
type: fix
date: 2026-04-06
deepened: 2026-04-06
---

# fix: canary crash leaks temp secrets file on disk

Ref #1502

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 3 (Proposed Solution, Test Scenarios, Implementation Notes)
**Research sources:** institutional learnings, ci-deploy.test.sh mock architecture analysis

### Key Improvements

1. Concrete test implementation pattern with `ENV_FILE_TRACKER` for verifying cleanup across subshell boundaries
2. Documented trap-subshell interaction edge case (EXIT trap fires in the `bash "$DEPLOY_SCRIPT"` process, not the test subshell)
3. Applied institutional learning from shell-script-defensive-patterns: "Any `rm -f "$tmpfile"` that is not inside a `trap` is a cleanup gap waiting to happen"

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

### Research Insights

**Institutional learning (shell-script-defensive-patterns, 2026-03-13):** This fix implements the exact pattern documented in `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md` section 2: "Pair every `mktemp` with a `trap` on the next line." The learning states: "Any `rm -f "$tmpfile"` that is not inside a `trap` is a cleanup gap waiting to happen." The current `cleanup_env_file` pattern is the anti-pattern -- scattered `rm -f` calls at each exit path with the predictable outcome that one path was missed.

**Trap-subshell interaction:** The `bash "$DEPLOY_SCRIPT"` invocation from the test harness starts a new process. The EXIT trap registered inside `ci-deploy.sh` fires when that bash process exits -- it does not leak into the parent test subshell. This means the test harness's own `trap 'rm -rf "$MOCK_DIR"' EXIT` and the deploy script's `trap 'rm -f "$ENV_FILE"' EXIT` operate in separate process trees and cannot conflict. Verified by inspection of the test harness in `ci-deploy.test.sh:113` (`bash "$DEPLOY_SCRIPT" 2>&1`).

**`set -e` interaction with trap:** When `set -e` triggers an exit (e.g., canary `docker run` fails at line 139), bash runs EXIT traps before terminating. This is specified in POSIX (the EXIT trap executes "when the shell terminates"). The ERR trap on line 13 fires first (on the failing command), then the EXIT trap fires (on process termination). Both fire in sequence -- the ERR trap does not prevent the EXIT trap from running.

## Acceptance Criteria

- [x] Temp env file is cleaned up on all exit paths including canary `docker run` crash
- [x] No production secrets persist on disk after any deploy failure mode
- [x] The `cleanup_env_file` function is removed (dead code elimination)
- [x] All four explicit `cleanup_env_file` call sites are removed
- [x] Existing ERR trap (line 13) continues to function
- [x] All 37 tests pass (35 existing + 2 new cleanup tests)
- [x] New test added: canary crash path verifies env file cleanup

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

**Problem:** The deploy script runs inside `bash "$DEPLOY_SCRIPT"` (a child process). The EXIT trap fires inside that child process and deletes `$ENV_FILE`. But the test harness (parent process) needs to verify the file was deleted. The `MOCK_DIR` created by the test is cleaned up by the test's own EXIT trap, so checking inside `MOCK_DIR` after the subshell exits is not possible -- `MOCK_DIR` itself is gone.

**Solution: ENV_FILE_TRACKER pattern.** Create a shared tracking directory outside the mock dir that survives both the deploy process exit and the test subshell exit. The mock `mktemp` inside the deploy script writes the created file path to this tracker. The test assertion checks if the file still exists after the deploy completes.

**Concrete implementation:**

```bash
assert_env_file_cleanup() {
  local description="$1"
  local extra_env="${2:-}"

  TOTAL=$((TOTAL + 1))

  # Tracker dir survives both the deploy process and test subshell
  local tracker_dir
  tracker_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export SSH_ORIGINAL_COMMAND="deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT
    export CI_DEPLOY_LOCK="$MOCK_DIR/ci-deploy.lock"
    export ENV_FILE_TRACKER="$tracker_dir/env_file_path"

    # Standard mocks (logger, docker, curl, sudo, chown, seq, flock, df)
    # ... [same as existing run_deploy pattern]

    # Mock doppler: write secrets AND record the env file path
    # The deploy script calls mktemp then doppler writes to that file.
    # We need mktemp to record its output path to the tracker.
    cat > "$MOCK_DIR/mktemp" << 'MOCK'
#!/bin/bash
# Create a real temp file, but record its path to the tracker
tmpfile=$(command mktemp "$@")
if [[ -n "${ENV_FILE_TRACKER:-}" ]]; then
  echo "$tmpfile" > "$ENV_FILE_TRACKER"
fi
echo "$tmpfile"
MOCK
    chmod +x "$MOCK_DIR/mktemp"

    # Standard doppler mock
    cat > "$MOCK_DIR/doppler" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "secrets" ]]; then echo "KEY=value"; exit 0; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/doppler"

    eval "$extra_env"
    export DOPPLER_TOKEN="dp.st.prd.mock-token"
    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Check: does the env file still exist?
  local env_file_path
  if [[ -f "$tracker_dir/env_file_path" ]]; then
    env_file_path=$(cat "$tracker_dir/env_file_path")
    if [[ ! -f "$env_file_path" ]]; then
      PASS=$((PASS + 1))
      echo "  PASS: $description"
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL: $description (env file still exists: $env_file_path)"
      rm -f "$env_file_path"  # clean up leaked file
    fi
  else
    # No env file was ever created (e.g., docker pull failure before resolve_env_file)
    PASS=$((PASS + 1))
    echo "  PASS: $description (no env file created)"
  fi

  rm -rf "$tracker_dir"
}
```

**Why mock `mktemp` instead of `doppler`:** The env file is created by `mktemp` (line 31 of ci-deploy.sh), not by `doppler`. The `resolve_env_file` function calls `mktemp`, writes the Doppler output to it, and returns the path via `echo`. Mocking `mktemp` to record its output path is the most precise interception point.

**Edge case: `command mktemp` inside the mock.** The mock `mktemp` needs to call the real `mktemp`. Using `command mktemp` bypasses PATH lookup and calls the built-in/original. However, `mktemp` is not a shell builtin -- it is an external binary at `/usr/bin/mktemp`. The mock should use the full path `/usr/bin/mktemp "$@"` instead of `command mktemp "$@"` to avoid recursion.

**Test cases to add:**

1. `assert_env_file_cleanup "canary crash cleans up env file" "export MOCK_DOCKER_RUN_FAIL_CANARY=1"` -- the main bug fix
2. `assert_env_file_cleanup "successful deploy cleans up env file" ""` -- verify trap cleanup on success path too

## References

- Issue: #1502
- Source: PR #1496 review finding
- Existing learning: `knowledge-base/project/learnings/implementation-patterns/2026-03-28-canary-rollback-docker-deploy.md`
- Existing learning: `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md`
- Terraform deploy mechanism: `apps/web-platform/infra/server.tf:86-101` (`deploy_pipeline_fix` resource)
