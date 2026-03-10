---
title: "refactor(community): unify get_request and x_request response handling"
type: refactor
date: 2026-03-10
semver: patch
---

# refactor(community): unify get_request and x_request response handling

## Overview

`get_request` and `x_request` in `x-community.sh` duplicate ~90 lines of response handling logic (HTTP status dispatch, 429 retry with clamping, JSON validation, error messages). The 403 handler has already diverged: `get_request` parses the `reason` field for richer error messages (`client-not-enrolled`, `official-client-forbidden`), while `x_request` gives a generic message. This refactor extracts the shared response handling into a `handle_response` function, renames `x_request` to `post_request` to enforce its POST-only contract, and ensures both helpers share identical error handling behavior.

## Problem Statement / Motivation

1. **Maintenance burden:** Bug fixes to retry logic, error messages, or status dispatch must be applied in two places. The depth-limited retry pattern (#477) had to be patched into both functions independently.
2. **Behavioral inconsistency:** POST 403 errors give `"Your app may lack the required permissions or your account may be suspended."` while GET 403 errors parse the `reason` field and give paid-access-specific guidance (`"This endpoint requires paid API access."`). Both code paths should share the richer 403 handling.
3. **Naming inaccuracy:** `x_request` accepts any HTTP method string but cannot correctly sign GET requests with query params (query params must be included in the OAuth signature base string, per the learning in `2026-03-10-x-api-oauth-get-query-params-in-signature.md`). The name misleads callers into thinking it handles GET requests.

## Proposed Solution

### Architecture

Extract a `handle_response` function that takes `http_code`, `body`, `endpoint`, and a retry callback, and handles the case/esac dispatch. Both `get_request` and `post_request` become thin wrappers that:

1. Build curl args (method-specific: query params for GET, JSON body for POST)
2. Execute curl with OAuth signing
3. Delegate to `handle_response` for status dispatch

#### Function Signatures

```bash
# Shared response handler
# Arguments: http_code body endpoint retry_callback
# retry_callback is the function name + args to invoke on 429
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  shift 3
  # Remaining args: retry command (function name + args)
  local -a retry_cmd=("$@")
  ...
}
```

```bash
# POST-only helper (renamed from x_request)
# Arguments: endpoint [json_body] [depth]
post_request() {
  local endpoint="$1"
  local json_body="${2:-}"
  local depth="${3:-0}"
  ...
  handle_response "$http_code" "$body" "$endpoint" \
    post_request "$endpoint" "$json_body" "$((depth + 1))"
}
```

```bash
# GET helper (signature unchanged)
# Arguments: endpoint query_params [depth]
get_request() {
  local endpoint="$1"
  local query_params="${2:-}"
  local depth="${3:-0}"
  ...
  handle_response "$http_code" "$body" "$endpoint" \
    get_request "$endpoint" "$query_params" "$((depth + 1))"
}
```

### What moves into `handle_response`

| Concern | Current location | After refactor |
|---------|-----------------|----------------|
| 2xx JSON validation | Both functions (identical) | `handle_response` |
| 401 error message | Both functions (near-identical) | `handle_response` |
| 403 error with reason parsing | `get_request` only | `handle_response` (unified) |
| 429 retry with float clamping | Both functions (identical) | `handle_response` |
| Default error extraction | Both functions (near-identical) | `handle_response` |
| Depth guard (>= 3) | Both functions (identical) | Stays in callers (checked before curl) |
| Connection failure message | Both functions (identical) | Stays in callers (checked after curl, before handle_response) |

### What stays in the callers

- **Depth guard:** Checked before making the HTTP request (early exit, no response to handle)
- **curl execution:** Method-specific curl args (POST with `-X POST -d`, GET with query string URL)
- **Connection failure:** Checked immediately after curl (no HTTP response to dispatch)
- **OAuth signing:** Method-specific param handling (GET includes query params in signature)

### Rename: `x_request` -> `post_request`

The only caller of `x_request` is `cmd_post_tweet` (line 552). Renaming to `post_request` enforces the POST-only contract and parallels `get_request`. The single call site means minimal churn.

## Non-goals

- **Platform adapter interface (#470):** That refactor is deferred until a 4th platform is added. This is a within-file DRY cleanup, not a cross-file abstraction.
- **New features or commands:** No new functionality. This is a pure refactor with identical observable behavior.
- **Discord script changes:** The discord scripts have their own `discord_request` function. Unifying across platforms is #470's scope.

## Acceptance Criteria

- [ ] A single `handle_response` function in `x-community.sh` handles HTTP status dispatch for both GET and POST requests (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] `x_request` is renamed to `post_request` with no callers using the old name (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] 403 errors from POST requests now parse the `reason` field and give paid-access-specific guidance (same behavior as current GET 403) (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] All existing tests pass without modification (`test/x-community.test.ts`)
- [ ] New tests verify `handle_response` behavior for each HTTP status code (`test/x-community.test.ts`)
- [ ] No behavioral change for any command (fetch-metrics, fetch-mentions, fetch-timeline, post-tweet)

## Test Scenarios

### Acceptance Tests

- Given a 2xx response with valid JSON, when `handle_response` is called, then the JSON body is echoed to stdout
- Given a 2xx response with malformed JSON, when `handle_response` is called, then it exits 1 with "malformed JSON" error to stderr
- Given a 401 response, when `handle_response` is called, then it exits 1 with credential regeneration instructions to stderr
- Given a 403 response with `reason: "client-not-enrolled"`, when `handle_response` is called, then it exits 1 with paid API access guidance to stderr
- Given a 403 response with `reason: "official-client-forbidden"`, when `handle_response` is called, then it exits 1 with permissions guidance to stderr
- Given a 403 response with no reason field, when `handle_response` is called, then it exits 1 with generic permissions/suspension message to stderr
- Given a 429 response with `retry_after: 5`, when `handle_response` is called with depth < 3, then it sleeps and invokes the retry callback
- Given a 429 response with `retry_after: 120`, when `handle_response` is called, then retry_after is clamped to 60
- Given a 429 response with `retry_after: 0.5`, when `handle_response` is called, then retry_after is clamped to 1 for arithmetic but the float is preserved for sleep
- Given a 500 response, when `handle_response` is called, then it exits 1 with the parsed error detail

### Regression Tests

- Given `post_request` is called (renamed from `x_request`), when it receives a 403 with `reason: "client-not-enrolled"`, then it gives the same rich guidance that `get_request` currently gives (fixes the divergence from #492)
- Given `cmd_post_tweet` calls `post_request`, when the tweet is posted successfully, then the output format is unchanged

## MVP

### handle_response (new function) in `x-community.sh`

```bash
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  shift 3
  local -a retry_cmd=("$@")

  case "$http_code" in
    2[0-9][0-9])
      if ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: X API returned malformed JSON for ${endpoint}" >&2
        exit 1
      fi
      echo "$body"
      ;;
    401)
      echo "Error: X API returned 401 Unauthorized for ${endpoint}." >&2
      echo "Your credentials may be expired or invalid." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Go to https://developer.x.com/en/portal/dashboard" >&2
      echo "  2. Regenerate your Access Token and Secret" >&2
      echo "  3. Update environment variables" >&2
      exit 1
      ;;
    403)
      local reason
      reason=$(echo "$body" | jq -r '.reason // "unknown"' 2>/dev/null || echo "unknown")
      echo "Error: X API returned 403 Forbidden for ${endpoint}." >&2
      if [[ "$reason" == "client-not-enrolled" ]]; then
        echo "This endpoint requires paid API access." >&2
        echo "Visit https://developer.x.com to purchase credits." >&2
      elif [[ "$reason" == "official-client-forbidden" ]]; then
        echo "Your app may lack the required permissions." >&2
      else
        echo "Your app may lack the required permissions or your account may be suspended." >&2
      fi
      exit 1
      ;;
    429)
      local retry_after
      retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null || echo "5")
      local retry_int
      retry_int=$(printf '%.0f' "$retry_after" 2>/dev/null || echo "5")
      if (( retry_int > 60 )); then
        retry_after=60
      elif (( retry_int < 1 )); then
        retry_after=1
      fi
      echo "Rate limited. Retrying after ${retry_after}s..." >&2
      sleep "$retry_after"
      "${retry_cmd[@]}"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.detail // .title // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: X API returned HTTP ${http_code} for ${endpoint}: ${message}" >&2
      exit 1
      ;;
  esac
}
```

### post_request (renamed from x_request) in `x-community.sh`

```bash
post_request() {
  local endpoint="$1"
  local json_body="${2:-}"
  local depth="${3:-0}"

  if (( depth >= 3 )); then
    echo "Error: X API rate limit exceeded after 3 retries." >&2
    exit 2
  fi

  local url="${X_API}${endpoint}"
  local auth_header
  auth_header=$(oauth_sign "POST" "$url")

  local -a curl_args=(
    -s -w "\n%{http_code}"
    -H "Authorization: ${auth_header}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$json_body" ]]; then
    curl_args+=(-X POST -d "$json_body")
  fi

  local response http_code body
  if ! response=$(curl "${curl_args[@]}" "$url" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" \
    post_request "$endpoint" "$json_body" "$((depth + 1))"
}
```

### get_request (simplified) in `x-community.sh`

```bash
get_request() {
  local endpoint="$1"
  local query_params="${2:-}"
  local depth="${3:-0}"

  if (( depth >= 3 )); then
    echo "Error: X API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${X_API}${endpoint}"

  local auth_header
  if [[ -n "$query_params" ]]; then
    local -a param_args=()
    local param
    while IFS= read -r param; do
      [[ -n "$param" ]] && param_args+=("$param")
    done <<< "${query_params//&/$'\n'}"
    auth_header=$(oauth_sign "GET" "$url" "${param_args[@]}")
  else
    auth_header=$(oauth_sign "GET" "$url")
  fi

  local request_url="$url"
  if [[ -n "$query_params" ]]; then
    request_url="${url}?${query_params}"
  fi

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: ${auth_header}" \
    "$request_url" 2>/dev/null); then
    echo "Error: Failed to connect to X API." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" \
    get_request "$endpoint" "$query_params" "$((depth + 1))"
}
```

## Dependencies & Risks

- **Low risk:** Pure internal refactor with no API contract changes. All existing callers (`cmd_fetch_metrics`, `cmd_fetch_mentions`, `cmd_fetch_timeline`, `cmd_post_tweet`) use the same interface.
- **Retry callback pattern:** Passing function name + args as positional params to `handle_response` is idiomatic bash. The `"${retry_cmd[@]}"` expansion correctly handles arguments with spaces. However, `set -euo pipefail` requires that the retry function is defined before `handle_response` (function ordering matters in bash).
- **429 attempt logging:** The current `(attempt N/3)` message includes the depth counter. After extracting to `handle_response`, the depth is not directly available. The retry callback already increments depth, so the caller's depth guard handles the limit. The log message can be simplified to omit the attempt counter, or the depth can be passed as an additional param to `handle_response`.

## References

- Issue: #492
- Parent feature: #471 (X monitoring commands, closed)
- Deferred adapter refactor: #470 (platform adapter interface, open)
- Learning: `knowledge-base/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning: `knowledge-base/learnings/2026-03-10-x-api-oauth-get-query-params-in-signature.md`
- Learning: `knowledge-base/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- File: `plugins/soleur/skills/community/scripts/x-community.sh`
- Tests: `test/x-community.test.ts`
