---
module: web-platform/infra
date: 2026-05-28
problem_type: infrastructure_observability
component: shell_script
symptoms:
  - "infra-config-apply.sh has no structured logging — errors blend into general webhook logs"
  - "push-infra-config.sh always sees HTTP 202 success (async) — no way to detect apply failures"
  - "self-restart can race with state file write"
root_cause: missing_observability_parity
severity: medium
tags: [observability, webhook, state-file, shell-script, multi-agent-review]
synced_to: []
---

# Learning: Infrastructure observability parity — state write guards and CI verification

## Problem

`infra-config-apply.sh` (the webhook handler for /hooks/infra-config) had zero structured logging: no `logger -t` tags, no per-file write confirmations, no persistent status file, and no way for CI to verify whether an apply actually succeeded. The sibling script `ci-deploy.sh` already had all of these patterns. Discovered during #4538 AC11 validation when `ci-deploy.sh` on the server was never updated despite 3 successful HTTP 202 responses.

## Solution

Brought `infra-config-apply.sh` to observability parity with `ci-deploy.sh`:

1. Added `readonly LOG_TAG="infra-config-apply"` + `logger -t` calls for all operations
2. Per-file error handling: `base64 -d` failures caught without aborting (`if ! ... ; then continue`)
3. SHA256 per written file, logged and persisted
4. Persistent state file at `/var/lock/infra-config-apply.state` with JSON structure
5. EXIT trap with `.final` sentinel pattern (precedent: `ci-deploy.sh:96-111`)
6. New `/hooks/infra-config-status` GET endpoint via `cat-infra-config-state.sh`
7. CI verification step in `apply-deploy-pipeline-fix.yml` polling the new endpoint

## Key Insight

Multi-agent review (8 agents) caught two issues that the implementation author missed:

**P1: State file `printf`/`mv` lack `|| true` guards.** Under `set -euo pipefail`, a disk-full condition during state file write would trigger the EXIT trap. But `.final` was already touched, so the trap would skip the "unhandled" fallback — leaving NO state file at all. The fix mirrors `ci-deploy.sh`'s `write_state()` pattern: every operation gets `2>/dev/null || { logger ...; return 0; }`.

**P2: CI verification step silently swallowed partial failures.** 6 of 8 agents independently flagged that the CI step would retry 3 times on `exit_code != 0` but then fall through without `exit 1`. The post-loop check only tested `HTTP_CODE`, not `EXIT_CODE`. A partial apply failure (one bad base64 file) would appear green in CI. Fixed by adding an explicit `exit_code` check after the retry loop.

**P2: `jq` stdout leak in cat-infra-config-state.sh.** The `elif ! jq -c . "$STATE_FILE"` pattern could emit partial stdout from jq before the sentinel JSON on certain malformed inputs. Fixed by capturing output in a variable: `elif output=$(jq -c . "$STATE_FILE" 2>/dev/null); then printf '%s\n' "$output"`.

## Session Errors

1. **CWD drift after terraform fmt** — Running `terraform -chdir=apps/web-platform/infra fmt -check .` left the Bash CWD inside the infra directory. The next `git add` with relative paths failed with "pathspec did not match any files". Recovery: used absolute paths. **Prevention:** Always use absolute paths for git commands in worktree pipelines, or avoid CWD-changing terraform invocations.

2. **Unbound variable crash in bash test** — Test assertion `[[ "$files_failed" -gt 0 ]]` crashed when `files_failed` was the string "MISSING" (jq fallback on nonexistent file). Bash's `-gt` can't compare non-numeric strings under `set -u`. Recovery: added `[[ "$files_failed" =~ ^[0-9]+$ ]]` regex guard before the integer comparison. **Prevention:** Always guard bash integer comparisons with a numeric regex check when the value comes from a fallback path.

## Tags
category: best-practices
module: web-platform/infra
