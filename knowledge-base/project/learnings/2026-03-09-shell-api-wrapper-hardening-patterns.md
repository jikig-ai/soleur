# Learning: Shell API Wrapper Hardening Patterns

## Problem

Shell scripts wrapping REST APIs (Discord, X/Twitter) accumulate subtle failure modes that only surface under adversarial or degraded conditions. PR #477 identified five gaps across `discord-community.sh`, `discord-setup.sh`, and `x-community.sh`:

1. **jq fallback gap** -- The catch-all error branch used `jq -r '.message // "Unknown error"' 2>/dev/null` but had no fallback if jq itself failed (e.g., malformed body). Under `set -euo pipefail`, this crashes the script instead of producing a readable error.
2. **curl stderr token leakage** -- `curl` without `2>/dev/null` can print debug/error output containing `Authorization` headers when connections fail or redirect, leaking the bot token to logs.
3. **No JSON validation on 2xx** -- A 200 response was assumed to contain valid JSON. Truncated responses or proxy HTML pages would propagate garbage to callers silently.
4. **Float retry_after crashes bash arithmetic** -- Discord returns `retry_after` as a float (e.g., `1.234`). Bash `(( ))` arithmetic rejects non-integers, crashing the script under `set -euo pipefail`. This is the same class of bug documented in `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`.
5. **No input validation on IDs** -- Channel and guild IDs were passed directly into URL paths without validation, allowing path traversal or malformed API calls.

## Solution

### Fix 1: jq fallback chain

Always append `|| echo "fallback"` after `jq ... 2>/dev/null`:

```bash
message=$(echo "$body" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
```

The `2>/dev/null` suppresses jq's stderr; the `|| echo` catches jq exit code 1+ when the input is not valid JSON at all.

### Fix 2: curl stderr suppression

```bash
if ! response=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "${DISCORD_API}${endpoint}" 2>/dev/null); then
  echo "Error: Failed to connect to Discord API (endpoint: ${endpoint})." >&2
  exit 1
fi
```

The `if !` pattern also lets us provide a clear connection-failure message instead of silently falling through with an empty response.

### Fix 3: JSON validation on success responses

```bash
case "$http_code" in
  2[0-9][0-9])
    if ! echo "$body" | jq . >/dev/null 2>&1; then
      echo "Error: Discord API returned malformed JSON for ${endpoint}" >&2
      exit 1
    fi
    echo "$body"
    ;;
```

### Fix 4: Float-safe retry_after clamping

```bash
retry_after=$(echo "$body" | jq -r '.retry_after // 5' 2>/dev/null || echo "5")
# Clamp retry_after to sane range [1, 60]
# Use printf to truncate float to integer for arithmetic comparison
# (sleep accepts floats natively, but bash (( )) does not)
local retry_int
retry_int=$(printf '%.0f' "$retry_after" 2>/dev/null || echo "5")
if (( retry_int > 60 )); then
  retry_after=60
elif (( retry_int < 1 )); then
  retry_after=1
fi
sleep "$retry_after"
```

The key trick: `printf '%.0f'` converts the float to an integer for `(( ))` comparison, but the original float is kept for `sleep` (which accepts floats natively). This avoids both the arithmetic crash and unnecessary precision loss.

### Fix 5: Snowflake ID validation

```bash
validate_snowflake_id() {
  local id="$1"
  local label="$2"
  if [[ ! "$id" =~ ^[0-9]+$ ]]; then
    echo "Error: ${label} must be numeric. Got: ${id}" >&2
    exit 1
  fi
}
```

Applied at every entry point that interpolates an ID into a URL path. The `label` parameter gives actionable error messages (e.g., "channel_id must be numeric") without duplicating the function.

## Key Insight

Shell API wrappers need defense at five layers, and each layer has its own failure mode that only manifests under specific conditions:

| Layer | Defense | Fails without it when... |
|-------|---------|--------------------------|
| Input | Validate IDs/params before URL interpolation | Caller passes a typo or malicious string |
| Transport | Suppress curl stderr, check curl exit code | Network error or redirect leaks auth headers |
| Response parsing | Validate JSON before consuming | Proxy returns HTML 200 or response is truncated |
| Error extraction | Chain `jq ... \|\| echo "fallback"` | Response body is not JSON at all |
| Retry arithmetic | Convert floats with `printf '%.0f'` before `(( ))` | API returns float `retry_after` under `set -euo pipefail` |

The float arithmetic trap (layer 5) is the most insidious because it only triggers during rate limiting -- a condition that is hard to reproduce in manual testing but common in production. It is a specific instance of the broader `set -euo pipefail` pitfall class: code that works fine without strict mode silently becomes a crash under strict mode when edge-case values appear.

## Related Learnings

- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- the general class of bash strict-mode traps
- `2026-03-09-depth-limited-api-retry-pattern.md` -- unbounded recursion fix (same scripts, prior PR)
- `2026-02-18-token-env-var-not-cli-arg.md` -- token handling via env vars (mentions curl stderr as additional measure)

## Tags

category: security
module: community
symptoms: token-leakage, arithmetic-crash, malformed-response, input-validation
