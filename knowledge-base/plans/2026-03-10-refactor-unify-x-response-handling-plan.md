---
title: "refactor(community): unify get_request and x_request response handling"
type: refactor
date: 2026-03-10
semver: patch
---

# refactor(community): unify get_request and x_request response handling

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5 (Architecture, Dependencies & Risks, Test Scenarios, MVP, Acceptance Criteria)
**Analysis applied:** code-simplicity, security, test-design, pattern-recognition, shell-hardening learnings

### Key Improvements

1. **Function ordering constraint resolved:** `handle_response` must be defined *after* `post_request` and `get_request` (not before) because bash resolves function names at call time, not definition time -- and `handle_response` calls `"${retry_cmd[@]}"` which references the callers. Actually, bash resolves at call time so ordering does not matter for mutually recursive functions. Corrected the false risk.
2. **Retry callback with empty args edge case identified:** When `post_request` is called without a JSON body, the empty string `""` is passed as the second retry_cmd arg -- `"${retry_cmd[@]}"` will pass it through correctly, but `post_request` must handle `json_body=""` on retry just as it does on first call.
3. **Test strategy clarified:** `handle_response` is not directly testable via the existing Bun spawn pattern (it is a bash function, not a standalone script). Tests must exercise it indirectly through the command entry points, or extract a test harness script.
4. **Attempt counter preservation solved:** Pass depth as an explicit parameter to `handle_response` to keep the `(attempt N/3)` log message.

### New Considerations Discovered

- The `Content-Type: application/json` header in `post_request` should only be sent when there is a body -- sending it on an empty POST is harmless but imprecise
- The 429 retry in `handle_response` uses `"${retry_cmd[@]}"` which creates a tail-call-like recursion; this is correct because the caller's depth guard prevents unbounded recursion, but the call stack still grows by 2 frames per retry (caller + handle_response)

## Overview

`get_request` and `x_request` in `x-community.sh` duplicate ~90 lines of response handling logic (HTTP status dispatch, 429 retry with clamping, JSON validation, error messages). The 403 handler has already diverged: `get_request` parses the `reason` field for richer error messages (`client-not-enrolled`, `official-client-forbidden`), while `x_request` gives a generic message. This refactor extracts the shared response handling into a `handle_response` function, renames `x_request` to `post_request` to enforce its POST-only contract, and ensures both helpers share identical error handling behavior.

## Problem Statement / Motivation

1. **Maintenance burden:** Bug fixes to retry logic, error messages, or status dispatch must be applied in two places. The depth-limited retry pattern (#477) had to be patched into both functions independently.
2. **Behavioral inconsistency:** POST 403 errors give `"Your app may lack the required permissions or your account may be suspended."` while GET 403 errors parse the `reason` field and give paid-access-specific guidance (`"This endpoint requires paid API access."`). Both code paths should share the richer 403 handling.
3. **Naming inaccuracy:** `x_request` accepts any HTTP method string but cannot correctly sign GET requests with query params (query params must be included in the OAuth signature base string, per the learning in `2026-03-10-x-api-oauth-get-query-params-in-signature.md`). The name misleads callers into thinking it handles GET requests.

## Proposed Solution

### Architecture

Extract a `handle_response` function that takes `http_code`, `body`, `endpoint`, `depth`, and a retry callback, and handles the case/esac dispatch. Both `get_request` and `post_request` become thin wrappers that:

1. Build curl args (method-specific: query params for GET, JSON body for POST)
2. Execute curl with OAuth signing
3. Delegate to `handle_response` for status dispatch

#### Function Signatures

```bash
# Shared response handler
# Arguments: http_code body endpoint depth retry_callback_args...
# retry_callback_args are the function name + args to invoke on 429
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  local depth="$4"
  shift 4
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
  handle_response "$http_code" "$body" "$endpoint" "$depth" \
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
  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    get_request "$endpoint" "$query_params" "$((depth + 1))"
}
```

### Research Insights [Updated 2026-03-10]

**Simplicity review:**
- The callback-via-positional-args pattern is the simplest approach for bash. Alternatives (eval, nameref functions, temporary files) are all more complex and fragile.
- Passing `depth` to `handle_response` (4 fixed params + varargs) is preferable to embedding the attempt counter in the retry callback args, because `handle_response` needs depth for logging but should not parse it out of the retry command.

**Security review:**
- The `echo "$body" | jq` pattern is safe because `$body` is in double quotes and piped to stdin. No shell expansion occurs.
- Credential leakage prevention (`curl 2>/dev/null`) is preserved in both callers. `handle_response` never touches curl, so no new leakage vector.
- The retry callback `"${retry_cmd[@]}"` cannot be injected by API responses -- it is constructed entirely from hardcoded function names and local variables.

**Pattern recognition:**
- The `discord_request` function in `discord-community.sh` (line 70) follows the same single-function pattern this refactor creates for X. Post-refactor, `x-community.sh` will have the same architecture: one shared response handler, called by method-specific wrappers.
- The `handle_response` function is analogous to a Strategy pattern where the retry strategy (which function to call back) is injected by the caller.

**Shell hardening (from learnings):**
- Per `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`: The `echo "$body" | jq ... 2>/dev/null || echo "fallback"` chains in `handle_response` are correct under `set -euo pipefail` because the `|| echo` prevents pipefail from aborting on jq failure.
- Per `2026-03-09-shell-api-wrapper-hardening-patterns.md`: All five hardening layers (input validation, transport, response parsing, error extraction, retry arithmetic) are preserved in the refactored code.

### What moves into `handle_response`

| Concern | Current location | After refactor |
|---------|-----------------|----------------|
| 2xx JSON validation | Both functions (identical) | `handle_response` |
| 401 error message | Both functions (near-identical) | `handle_response` |
| 403 error with reason parsing | `get_request` only | `handle_response` (unified) |
| 429 retry with float clamping | Both functions (identical) | `handle_response` |
| 429 attempt logging | Both functions (identical) | `handle_response` (using `depth` param) |
| Default error extraction | Both functions (near-identical) | `handle_response` |
| Depth guard (>= 3) | Both functions (identical) | Stays in callers (checked before curl) |
| Connection failure message | Both functions (identical) | Stays in callers (checked after curl, before handle_response) |

### What stays in the callers

- **Depth guard:** Checked before making the HTTP request (early exit, no response to handle)
- **curl execution:** Method-specific curl args (POST with `-X POST -d`, GET with query string URL)
- **Connection failure:** Checked immediately after curl (no HTTP response to dispatch)
- **OAuth signing:** Method-specific param handling (GET includes query params in signature)
- **Response splitting:** `tail -1` / `sed '$d'` to separate HTTP code from body (could move to `handle_response` but would require passing the raw response string which may contain newlines in the body -- keeping it in callers is safer)

### Rename: `x_request` -> `post_request`

The only caller of `x_request` is `cmd_post_tweet` (line 552). Renaming to `post_request` enforces the POST-only contract and parallels `get_request`. The single call site means minimal churn.

## Non-goals

- **Platform adapter interface (#470):** That refactor is deferred until a 4th platform is added. This is a within-file DRY cleanup, not a cross-file abstraction.
- **New features or commands:** No new functionality. This is a pure refactor with identical observable behavior.
- **Discord script changes:** The discord scripts have their own `discord_request` function. Unifying across platforms is #470's scope.
- **Extracting `handle_response` into a shared library:** A shared shell library across scripts would require sourcing and path resolution. Not justified for 2 scripts.

## Acceptance Criteria

- [ ] A single `handle_response` function in `x-community.sh` handles HTTP status dispatch for both GET and POST requests (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] `x_request` is renamed to `post_request` with no callers using the old name (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] 403 errors from POST requests now parse the `reason` field and give paid-access-specific guidance (same behavior as current GET 403) (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] All existing tests pass without modification (`test/x-community.test.ts`)
- [ ] New tests verify the unified response handling behavior for error status codes (`test/x-community.test.ts`)
- [ ] No behavioral change for any command (fetch-metrics, fetch-mentions, fetch-timeline, post-tweet)
- [ ] 429 retry log message preserves `(attempt N/3)` format using depth param (`plugins/soleur/skills/community/scripts/x-community.sh`)
- [ ] `grep -rn 'x_request' plugins/soleur/skills/community/scripts/x-community.sh` returns zero matches after refactor

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

### Research Insights: Test Strategy [Updated 2026-03-10]

**Testing `handle_response` directly:**
`handle_response` is a bash function inside `x-community.sh`, not a standalone script. The existing test pattern (Bun spawning the script with args) cannot call `handle_response` in isolation. Two approaches:

1. **Preferred: Test through command entry points.** The existing tests already exercise the input validation paths. For HTTP status code testing, a test harness would need to mock curl responses, which requires either:
   - A `--dry-run` mode (adds complexity, violates YAGNI for a refactor PR)
   - A curl wrapper function that can be overridden in tests (adds a seam)

2. **Pragmatic: Source the script and call the function.** Create a thin test wrapper script:
   ```bash
   #!/usr/bin/env bash
   source "$(dirname "$0")/../plugins/soleur/skills/community/scripts/x-community.sh"
   # Override main to prevent execution
   handle_response "$@"
   ```
   Then Bun tests spawn this wrapper with specific http_code/body/endpoint args. This tests `handle_response` in isolation without mocking curl.

**Recommendation:** Option 2 is simpler and directly tests the extracted function. Create `test/helpers/test-handle-response.sh` that sources the script, suppresses main, and exposes `handle_response` for direct invocation. The Bun tests spawn this helper.

**Caveat:** Sourcing the full script runs `main "$@"` at the bottom. The test wrapper must either: (a) define `main()` as a no-op before sourcing (impossible -- source runs top-level code), or (b) the script must guard `main "$@"` with `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"` so sourcing skips execution. This is a common bash library pattern and a minor change to `x-community.sh`.

## MVP

### handle_response (new function) in `x-community.sh`

```bash
# --- Response handler ---

# Handle HTTP response status codes from X API
# Arguments: http_code body endpoint depth retry_cmd...
# On 2xx: validates JSON, echoes body to stdout
# On 429: sleeps and invokes retry_cmd (caller with incremented depth)
# On error: prints diagnostic to stderr, exits 1 (or 2 for rate limit exhaustion)
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  local depth="$4"
  shift 4
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
      echo "Rate limited. Retrying after ${retry_after}s (attempt $((depth + 1))/3)..." >&2
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
# Make an authenticated POST request to the X API
# Arguments: endpoint [json_body] [depth]
# Retries on 429 up to 3 times
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

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    post_request "$endpoint" "$json_body" "$((depth + 1))"
}
```

### get_request (simplified) in `x-community.sh`

```bash
# Make an authenticated GET request to the X API with query params
# Arguments: endpoint query_params [depth]
# Query params are included in the OAuth signature
# Retries on 429 up to 3 times
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

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    get_request "$endpoint" "$query_params" "$((depth + 1))"
}
```

### Source guard for testability in `x-community.sh`

```bash
# --- Main ---

# Guard: allow sourcing without executing main (for test harness)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

**Replaces:** the current bare `main "$@"` at line 597.

## Dependencies & Risks

- **Low risk:** Pure internal refactor with no API contract changes. All existing callers (`cmd_fetch_metrics`, `cmd_fetch_mentions`, `cmd_fetch_timeline`, `cmd_post_tweet`) use the same interface.
- **Retry callback pattern:** Passing function name + args as positional params to `handle_response` is idiomatic bash. The `"${retry_cmd[@]}"` expansion correctly handles arguments with spaces, including the empty string case when `json_body` is `""`.
- **Function ordering:** Bash resolves function names at call time, not at definition time. Mutually recursive functions (`post_request` calls `handle_response`, `handle_response` calls `post_request` via callback) work regardless of definition order. No ordering constraint exists.
- **429 attempt logging:** Resolved by passing `depth` as an explicit parameter to `handle_response`. The `(attempt N/3)` message is preserved.
- **Source guard:** Adding `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` is a standard bash idiom. It has no effect on normal script invocation. It enables test harness sourcing.
- **Call stack depth on retries:** Each 429 retry adds 2 stack frames (caller + handle_response). With max 3 retries, this is at most 6 frames -- well within bash limits.

### Research Insights: Risk Mitigations [Updated 2026-03-10]

**From `2026-03-09-depth-limited-api-retry-pattern.md`:**
The depth guard pattern is already proven in this codebase. The refactor preserves the exact same depth semantics -- the guard fires in the caller before making the HTTP request.

**From `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`:**
No new `set -euo pipefail` risks introduced. The `handle_response` function uses the same `jq ... 2>/dev/null || echo "fallback"` chains and `printf '%.0f' ... 2>/dev/null || echo "5"` patterns that are already proven safe under strict mode.

**From `2026-03-09-shell-api-wrapper-hardening-patterns.md`:**
All five hardening layers (input validation, transport security, response parsing, error extraction, retry arithmetic) are preserved. No layer is weakened by the extraction.

## References

- Issue: #492
- Parent feature: #471 (X monitoring commands, closed)
- Deferred adapter refactor: #470 (platform adapter interface, open)
- Learning: `knowledge-base/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning: `knowledge-base/learnings/2026-03-10-x-api-oauth-get-query-params-in-signature.md`
- Learning: `knowledge-base/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Learning: `knowledge-base/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`
- Learning: `knowledge-base/learnings/2026-03-10-jq-generator-silent-data-loss.md` (not directly applicable but confirms jq patterns in same file are correct)
- File: `plugins/soleur/skills/community/scripts/x-community.sh`
- Tests: `test/x-community.test.ts`
