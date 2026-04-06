---
module: ci-deploy
date: 2026-04-06
problem_type: security_issue
component: tooling
symptoms:
  - "Temp env file /tmp/doppler-env.XXXXXX with production secrets persists on disk after canary docker run crash"
  - "cleanup_env_file not called on set -e exit path"
root_cause: missing_workflow_step
resolution_type: code_fix
severity: high
tags: [secrets-leak, trap-cleanup, shell-script, canary-deploy, exit-trap]
synced_to: [work]
---

# Troubleshooting: Canary crash leaks temp secrets file on disk

## Problem

When the canary `docker run` command fails under `set -e`, `ci-deploy.sh` exits immediately and the `cleanup_env_file` function is never called. The temp file at `/tmp/doppler-env.XXXXXX` containing production Doppler secrets persists on disk.

## Environment

- Module: ci-deploy (web-platform deploy pipeline)
- Affected Component: `apps/web-platform/infra/ci-deploy.sh`
- Date: 2026-04-06

## Symptoms

- Temp env file with production secrets persists on disk after canary crash
- 4 of 5 exit paths had explicit `cleanup_env_file` calls; the canary `docker run` crash path did not
- The `set -e` flag causes immediate script termination, bypassing all subsequent cleanup code

## What Didn't Work

**Direct solution:** The problem was identified and fixed on the first attempt. The anti-pattern (scattered explicit cleanup calls) was already documented in `knowledge-base/project/learnings/2026-03-13-shell-script-defensive-patterns.md`.

## Session Errors

**Wrong script path for setup-ralph-loop.sh**

- **Recovery:** Found correct path via `ls plugins/soleur/scripts/`
- **Prevention:** one-shot skill should reference `./plugins/soleur/scripts/` not `./plugins/soleur/skills/one-shot/scripts/`

**`replace_all` missed 1 of 4 cleanup_env_file occurrences**

- **Recovery:** Targeted Edit for the remaining occurrence at line 204
- **Prevention:** After any `replace_all` operation, grep the file to verify zero remaining matches before proceeding

**Bash tool tmpfs exhaustion from background agent output files**

- **Recovery:** Output files cleaned up, Bash tool recovered
- **Prevention:** Always pipe uncertain-length output through `| head -n 500` in subagents per AGENTS.md rule; limit parallel background agents on large files

## Solution

Replaced 4 scattered `cleanup_env_file()` calls with a single EXIT trap placed immediately after `resolve_env_file`:

```bash
# Before (broken): scattered cleanup calls, canary crash path missed
ENV_FILE=$(resolve_env_file)
# ... later, on each exit path:
cleanup_env_file "$ENV_FILE"  # missing on canary crash!

# After (fixed): single EXIT trap covers all paths
ENV_FILE=$(resolve_env_file)
trap 'rm -f "$ENV_FILE"' EXIT
```

Removed the `cleanup_env_file` function entirely (dead code elimination).

Added 2 new tests using the ENV_FILE_TRACKER pattern: a mock `mktemp` records the temp file path to a tracker directory outside the test subshell, allowing the test to verify the file was deleted after the deploy script exits.

## Why This Works

1. **Root cause:** The `cleanup_env_file` function relied on every exit path explicitly calling it. When `set -e` causes an exit (e.g., canary `docker run` failure), control flow jumps directly to process termination, bypassing any cleanup code between the failing command and the explicit call.

2. **EXIT trap fires on all exits:** The bash EXIT trap fires on `exit 0`, `exit 1`, `set -e` aborts, and signal delivery (SIGTERM/SIGINT). It is impossible to exit the process without the trap running.

3. **Composition with ERR trap:** The existing ERR trap (line 13) fires on failing commands. The new EXIT trap fires on process termination. These are different signals and compose correctly -- ERR fires first, then EXIT.

4. **Trap placement:** After `resolve_env_file` (not at script top) because `$ENV_FILE` is only populated inside the `web-platform)` case block. The trap references the variable, so it must be placed after assignment.

## Prevention

- Always pair `mktemp` with a `trap` on the next line -- this is the pattern from `2026-03-13-shell-script-defensive-patterns.md`
- Never use scattered explicit cleanup calls for temp files -- a single EXIT trap handles all paths
- When reviewing shell scripts, check that every `mktemp` has a corresponding `trap 'rm -f' EXIT`

## Related Issues

- See also: [shell-script-defensive-patterns](../2026-03-13-shell-script-defensive-patterns.md)
- See also: [canary-rollback-docker-deploy](../implementation-patterns/2026-03-28-canary-rollback-docker-deploy.md)
- See also: [doppler-secrets-manager-setup-patterns](../2026-03-20-doppler-secrets-manager-setup-patterns.md)
