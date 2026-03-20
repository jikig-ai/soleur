---
title: "fix: discord-community.sh recursive 429 retry has no depth limit"
type: fix
date: 2026-03-09
semver: patch
---

# fix: discord-community.sh recursive 429 retry has no depth limit

## Overview

The `discord_request` function in `discord-community.sh` retries on HTTP 429 by recursively calling itself with no depth limit. Under sustained rate limiting, this causes unbounded recursion -- a stack overflow or infinite loop. The same bug exists in `discord-setup.sh`.

The reference implementation `x_request` in `x-community.sh` already solves this with a `depth` parameter and a max retry count of 3. This fix applies the same pattern to both Discord scripts.

Closes #472

## Affected Files

| File | Function | Bug |
|------|----------|-----|
| `plugins/soleur/skills/community/scripts/discord-community.sh:60` | `discord_request()` | Recursive 429 retry, no depth limit |
| `plugins/soleur/skills/community/scripts/discord-setup.sh:54` | `discord_request()` | Recursive 429 retry, no depth limit |

## Proposed Fix

Apply the `x_request` depth pattern to both `discord_request` functions:

1. Add a `depth` parameter (default `0`) to `discord_request()`
2. Guard: if `depth >= 3`, print error to stderr and `exit 2`
3. On 429 retry, pass `$((depth + 1))` to the recursive call
4. Include attempt count in the rate-limit log message for observability

### discord-community.sh

Current signature: `discord_request "$endpoint"` (1 arg)
New signature: `discord_request "$endpoint" "$depth"` (2 args, depth optional)

All callers pass only `$endpoint` today, so adding `depth` with a default is backward-compatible.

### discord-setup.sh

Current signature: `discord_request "$endpoint" "$method" "$data"` (3 args)
New signature: `discord_request "$endpoint" "$method" "$data" "$depth"` (4 args, depth optional)

All callers pass 1-3 args today, so adding `depth` as arg 4 with a default is backward-compatible.

## Non-goals

- Changing the retry-after sleep logic (existing `jq '.retry_after // 5'` is fine)
- Adding exponential backoff (out of scope; 429 responses include `retry_after`)
- Refactoring the two scripts to share a common request function (scope creep)
- Adding tests (no test infrastructure exists for these shell scripts yet)

## Acceptance Criteria

- [x] `discord-community.sh` `discord_request` accepts a `depth` parameter with default 0
- [x] `discord-community.sh` exits with code 2 when `depth >= 3`
- [x] `discord-community.sh` 429 handler passes incremented depth to recursive call
- [x] `discord-community.sh` 429 log message includes attempt count (e.g., "attempt 1/3")
- [x] `discord-setup.sh` `discord_request` accepts a `depth` parameter with default 0
- [x] `discord-setup.sh` exits with code 2 when `depth >= 3`
- [x] `discord-setup.sh` 429 handler passes incremented depth to recursive call
- [x] `discord-setup.sh` 429 log message includes attempt count
- [x] Exit code 2 (not 1) on exhaustion, matching `x_request` convention
- [x] Existing callers continue working without modification (backward-compatible)

## Test Scenarios

- Given a Discord API returning 429 once then 200, when `discord_request` is called, then it retries once and returns the 200 body
- Given a Discord API returning 429 three consecutive times, when `discord_request` is called, then it exits with code 2 after the third retry
- Given a Discord API returning 429 with `retry_after: 1`, when `discord_request` retries, then the log message shows "attempt N/3"
- Given an existing caller like `cmd_messages`, when it calls `discord_request "/channels/123/messages"`, then the function works identically (no depth arg needed)

## Context

- Reference implementation: `plugins/soleur/skills/community/scripts/x-community.sh:165-239` (`x_request` with depth)
- Issue origin: Noted during #127 implementation review (see learning `2026-03-09-external-api-scope-calibration.md`)
- Pre-existing bug, not a regression from #127

## MVP

### discord-community.sh (lines 60-105)

```bash
discord_request() {
  local endpoint="$1"
  local depth="${2:-0}"

  if (( depth >= 3 )); then
    echo "Error: Discord API rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  local response http_code body
  # ... existing curl logic unchanged ...

  case "$http_code" in
    # ... 2xx and 401 unchanged ...
    429)
      local retry_after
      retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null)
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
      sleep "$retry_after"
      discord_request "$endpoint" "$((depth + 1))"
      ;;
    # ... default unchanged ...
  esac
}
```

### discord-setup.sh (lines 54-111)

```bash
discord_request() {
  local endpoint="$1"
  local method="${2:-GET}"
  local data="${3:-}"
  local depth="${4:-0}"

  if (( depth >= 3 )); then
    echo "Error: Discord API rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  # ... existing curl logic unchanged ...

  case "$http_code" in
    # ... 2xx, 401, 400 unchanged ...
    429)
      local retry_after
      retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null)
      if [[ -z "$retry_after" ]] || [[ "$retry_after" == "null" ]]; then
        retry_after=5
      fi
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
      sleep "$retry_after"
      discord_request "$endpoint" "$method" "$data" "$((depth + 1))"
      ;;
    # ... default unchanged ...
  esac
}
```

## References

- Issue: #472
- Reference impl: `plugins/soleur/skills/community/scripts/x-community.sh:165` (`x_request`)
- Related PR: #466 (community skill that introduced these scripts)
- Learning: `knowledge-base/learnings/2026-03-09-external-api-scope-calibration.md`
