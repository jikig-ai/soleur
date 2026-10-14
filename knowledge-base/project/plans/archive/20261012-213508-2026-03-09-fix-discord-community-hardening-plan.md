---
title: "fix: discord-community.sh missing jq fallback and curl stderr suppression"
type: fix
date: 2026-03-09
semver: patch
deepened: 2026-03-09
---

# fix: discord-community.sh missing jq fallback and curl stderr suppression

## Enhancement Summary

**Deepened on:** 2026-03-09
**Sections enhanced:** Fix 4 (critical bug found), Test Scenarios, Acceptance Criteria
**Review perspectives applied:** security-sentinel, code-quality, code-simplicity, spec-flow-analyzer

### Key Improvements

1. **Critical: Fix 4 float arithmetic bug** -- Discord returns `retry_after` as a float (e.g., `1.234`), and bash `(( ))` arithmetic fails on non-integers under `set -euo pipefail`. Changed to `printf '%.0f'` truncation.
2. Added negative `retry_after` clamping (floor at 1s) to prevent `sleep 0` or `sleep -1`.
3. Added three missing test scenarios for float, negative, and zero `retry_after` values.

### New Considerations Discovered

- The `set -euo pipefail` float trap is documented in `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- same class of bug (arithmetic on values that may not be pure integers).
- `sleep` accepts floats natively, so non-clamped float values like `1.5` work fine. Only the comparison/clamping code needs integer handling.

## Overview

Five pre-existing inconsistencies found during #472 review across `discord-community.sh`, `discord-setup.sh`, and `x-community.sh`. Two have security implications (token leakage via curl stderr, DoS via unsanitized `retry_after`). The fixes are mechanical -- each script already has the correct pattern implemented for some issues but not others.

Closes #476

## Affected Files

| File | Issue | Fix |
|------|-------|-----|
| `plugins/soleur/skills/community/scripts/discord-community.sh:107` | Missing `\|\| echo "Unknown error"` bash fallback on jq in catch-all | Add `\|\| echo "Unknown error"` after `2>/dev/null` |
| `plugins/soleur/skills/community/scripts/discord-community.sh:71` | `curl -s` without `2>/dev/null` -- stderr can leak token in debug output | Add `2>/dev/null` to curl, matching `discord-setup.sh:78` |
| `plugins/soleur/skills/community/scripts/discord-setup.sh:88-89` | No JSON validation on 2xx responses | Add `jq .` validation, matching `discord-community.sh:82-86` |
| All three scripts (429 handlers) | `retry_after` passed unsanitized to `sleep` -- malicious API response can set arbitrarily large value | Clamp `retry_after` to max 60s |
| `discord-community.sh` + `discord-setup.sh` | `channel_id` parameters not validated as numeric | Add numeric validation matching `DISCORD_GUILD_ID` pattern |

## Proposed Fixes

### Fix 1: jq fallback in catch-all error (discord-community.sh)

**Current** (line 107):

```bash
message=$(echo "$body" | jq -r '.message // "Unknown error"' 2>/dev/null)
```

**Fixed:**

```bash
message=$(echo "$body" | jq -r '.message // "Unknown error"' 2>/dev/null || echo "Unknown error")
```

The jq `// "Unknown error"` handles missing `.message` keys, but if jq itself fails (malformed body, not valid JSON), the bash command returns empty. The `|| echo "Unknown error"` bash fallback covers that case. `discord-setup.sh:113` already has this pattern.

### Fix 2: curl stderr suppression (discord-community.sh)

**Current** (lines 71-74):

```bash
response=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "${DISCORD_API}${endpoint}")
```

**Fixed:**

```bash
if ! response=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  "${DISCORD_API}${endpoint}" 2>/dev/null); then
  echo "Error: Failed to connect to Discord API (endpoint: ${endpoint})." >&2
  exit 1
fi
```

Matches `discord-setup.sh:78` and `x-community.sh:192`. This also adds a connection failure handler that the current code lacks.

### Fix 3: JSON validation on 2xx (discord-setup.sh)

**Current** (lines 88-89):

```bash
2[0-9][0-9])
  echo "$body"
  ;;
```

**Fixed:**

```bash
2[0-9][0-9])
  # Validate JSON
  if ! echo "$body" | jq . >/dev/null 2>&1; then
    echo "Error: Discord API returned malformed JSON for ${endpoint}" >&2
    exit 1
  fi
  echo "$body"
  ;;
```

Matches `discord-community.sh:82-86` and `x-community.sh:203-207`.

### Fix 4: Clamp retry_after to max 60s (all three scripts)

**Critical edge case:** Discord returns `retry_after` as a float (e.g., `1.234`). Bash `(( ))` arithmetic fails on non-integer values with `syntax error: invalid arithmetic operator`, which is fatal under `set -euo pipefail`. The `sleep` command accepts floats natively, so only the comparison needs integer handling.

**Pattern to apply in each 429 handler:**

```bash
# After extracting retry_after, clamp to sane range [1, 60]
# Use printf to truncate float to integer for arithmetic comparison
# (sleep accepts floats natively, but bash (( )) does not)
local retry_int
retry_int=$(printf '%.0f' "$retry_after" 2>/dev/null || echo "5")
if (( retry_int > 60 )); then
  retry_after=60
elif (( retry_int < 1 )); then
  retry_after=1
fi
```

Apply to:

- `discord-community.sh:100` (after `retry_after` extraction)
- `discord-setup.sh:102-106` (after `retry_after` extraction and null check)
- `x-community.sh:227` (after `retry_after` extraction)

60 seconds is the ceiling -- Discord's documented rate limits are typically 1-5s. Anything higher is either a bug or adversarial. Floor of 1s prevents `sleep 0` (immediate retry loop) or `sleep` with negative values.

### Fix 5: Validate channel_id as numeric (discord-community.sh + discord-setup.sh)

Add validation function and call it in commands that accept `channel_id`:

```bash
validate_channel_id() {
  local channel_id="$1"
  if [[ ! "$channel_id" =~ ^[0-9]+$ ]]; then
    echo "Error: channel_id must be numeric. Got: ${channel_id}" >&2
    exit 1
  fi
}
```

Apply to:

- `discord-community.sh:cmd_messages` (line 117, after extracting `channel_id`)
- `discord-setup.sh:cmd_list_channels` (line 154, `guild_id` parameter -- already validated at env level but not at command level)
- `discord-setup.sh:cmd_create_webhook` (line 162, `channel_id` parameter)

Discord snowflake IDs are always numeric. Validating early prevents injection via malformed endpoint paths.

## Non-goals

- Refactoring scripts to share a common request function (scope creep, tracked separately)
- Adding tests (no shell test infrastructure exists yet)
- Changing retry logic beyond clamping (exponential backoff, jitter -- YAGNI)
- Modifying x-community.sh beyond the retry_after clamp (it already has the correct patterns for other items)

## Acceptance Criteria

- [x] `discord-community.sh` catch-all error extraction has `|| echo "Unknown error"` bash fallback
- [x] `discord-community.sh` curl call suppresses stderr with `2>/dev/null`
- [x] `discord-community.sh` curl failure produces a clear error message and exits 1
- [x] `discord-setup.sh` validates JSON on 2xx responses before returning body
- [x] `discord-community.sh` 429 handler clamps `retry_after` to range [1, 60]
- [x] `discord-setup.sh` 429 handler clamps `retry_after` to range [1, 60]
- [x] `x-community.sh` 429 handler clamps `retry_after` to range [1, 60]
- [x] `retry_after` clamping handles float values (e.g., `1.234`) without bash arithmetic errors
- [x] `discord-community.sh` `cmd_messages` validates `channel_id` as numeric
- [x] `discord-setup.sh` `cmd_list_channels` validates `guild_id` parameter as numeric
- [x] `discord-setup.sh` `cmd_create_webhook` validates `channel_id` as numeric
- [x] All existing callers continue to work without modification

## Test Scenarios

- Given `discord-community.sh` receives a non-JSON body on a non-2xx response, when the catch-all handler runs, then the error message contains "Unknown error" (not empty)
- Given `discord-community.sh` with `DISCORD_BOT_TOKEN` set, when curl writes to stderr (e.g., TLS warning), then stderr output is suppressed
- Given `discord-community.sh` with an unreachable API endpoint, when curl fails to connect, then it exits 1 with "Failed to connect" error
- Given `discord-setup.sh` receives valid HTTP 200 with malformed body `{not json`, when the 2xx handler runs, then it exits 1 with "malformed JSON" error
- Given any script receives a 429 with `retry_after: 3600`, when the retry handler runs, then `sleep` is called with 60 (clamped to max)
- Given any script receives a 429 with `retry_after: 3`, when the retry handler runs, then `sleep` is called with 3 (no clamping needed)
- Given any script receives a 429 with `retry_after: 1.234` (float), when the retry handler runs, then no bash arithmetic error occurs and `sleep` is called with the float value
- Given any script receives a 429 with `retry_after: 0`, when the retry handler runs, then `sleep` is called with 1 (clamped to floor)
- Given any script receives a 429 with `retry_after: -5`, when the retry handler runs, then `sleep` is called with 1 (clamped to floor)
- Given `cmd_messages` is called with `channel_id="abc"`, when validation runs, then it exits 1 with "must be numeric" error
- Given `cmd_messages` is called with `channel_id="123456789"`, when validation runs, then it passes and proceeds to API call
- Given `cmd_create_webhook` is called with `channel_id="../../admin"`, when validation runs, then it exits 1 (path traversal blocked by numeric check)

## Context

- Origin: #472 review, filed as #476
- Prior fix: #475 addressed the recursive retry depth limit (item already resolved)
- Reference patterns: Each fix already exists in at least one of the three scripts -- this is a cross-pollination task
- Learning: `knowledge-base/project/learnings/2026-03-09-depth-limited-api-retry-pattern.md`
- Learning: `knowledge-base/project/learnings/2026-03-09-external-api-scope-calibration.md`
- Learning: `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` (float arithmetic trap in Fix 4)
- Learning: `knowledge-base/project/learnings/2026-02-18-token-env-var-not-cli-arg.md` (curl stderr suppression rationale)

## References

- Issue: #476
- Prior PR: #475 (depth-limited retries -- already merged)
- `plugins/soleur/skills/community/scripts/discord-community.sh`
- `plugins/soleur/skills/community/scripts/discord-setup.sh`
- `plugins/soleur/skills/community/scripts/x-community.sh`
