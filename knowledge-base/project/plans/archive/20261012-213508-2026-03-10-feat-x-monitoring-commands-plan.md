---
title: "feat: add X monitoring commands requiring paid API tier"
type: feat
date: 2026-03-10
semver: minor
deepened: 2026-03-10
---

# feat: add X monitoring commands requiring paid API tier

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5 (Endpoint Details, Error Handling, Implementation Phases, Test Scenarios, get_request design)
**Research sources:** X API v2 OpenAPI schema, project learnings corpus, plan review feedback

### Key Improvements

1. Corrected `max_results` range from 1-100 to **5-100** (per X API v2 schema `minimum: 5`)
2. Discovered empty-results edge case: `data` field may be **absent entirely** (schema: `minItems: 1`) rather than an empty array -- jq must use `// empty` or `.data // []`
3. Identified 403 `reason` field (`client-not-enrolled`) from X API error schema for richer error messages
4. Specified `get_request` retry depth parameter design (must mirror `x_request` pattern)
5. Added `resolve_user_id` bootstrap sequencing note (uses `get_request` which is being extracted simultaneously)

## Overview

Add `fetch-mentions` and `fetch-timeline` commands to `x-community.sh`. These were excluded from #127 because the Free tier does not support them. X API has migrated to pay-per-use credits; these endpoints require purchased credits.

**Issue:** #471
**Parent:** #127 (closed)

## Problem Statement

`x-community.sh` currently supports only `fetch-metrics` (GET /2/users/me) and `post-tweet` (POST /2/tweets). The community-manager agent cannot monitor X mentions or view timeline activity. Issue #471 tracks adding these read commands now that paid tier access is a prerequisite, not a blocker.

## Proposed Solution

Add two new commands to the existing `x-community.sh` script following the established patterns (case dispatch, `x_request` helper, JSON stdout, errors to stderr).

### New Commands

| Command | Endpoint | Purpose |
|---------|----------|---------|
| `fetch-mentions` | GET /2/users/{id}/mentions | Fetch recent @mentions of the authenticated user |
| `fetch-timeline` | GET /2/users/{id}/tweets | Fetch recent tweets by the authenticated user |

### What Is NOT In Scope

- New scripts or files -- both commands go into the existing `x-community.sh`
- OAuth changes -- the existing OAuth 1.0a signing already supports GET requests with query params (see `cmd_fetch_metrics`)
- Community SKILL.md changes -- the skill already delegates to the community-manager agent which calls x-community.sh
- Major agent changes -- the community-manager agent already has X/Twitter data collection; a single sentence noting paid access suffices
- Adapter pattern refactor (#470) -- deferred
- Engage sub-command (#469) -- separate issue

## Technical Considerations

### Authentication

Both endpoints support OAuth 1.0a User Context (already implemented in `oauth_sign`). The existing `cmd_fetch_metrics` demonstrates the pattern for GET requests with query parameters -- the query params must be included in the OAuth signature.

### Endpoint Details (from X API v2 OpenAPI schema)

**GET /2/users/{id}/mentions:**

- Scopes: `tweet.read`, `users.read`
- Parameters: `max_results` (**5-100**, no documented default), `start_time`, `end_time`, `since_id`, `until_id`, `pagination_token`, `tweet.fields`, `expansions`, `user.fields`
- Returns: `data` array of Tweet objects (schema: `minItems: 1` -- **field is absent when zero results**, not an empty array) + `meta` object (result_count, next_token, newest_id, oldest_id)
- 403 error body: `{"type": "...client-forbidden", "reason": "client-not-enrolled", "title": "..."}`

**GET /2/users/{id}/tweets:**

- Scopes: `tweet.read`, `users.read`
- Parameters: same as mentions plus `exclude` (retweets, replies); `max_results` also **5-100**
- Returns: same structure as mentions (data absent when zero results)
- 403 error body: same schema as mentions

### Research Insights: Empty Results Handling

The X API v2 schema specifies `minItems: 1` on the `data` array for both endpoints. This means when there are zero results, the `data` field is **not present** in the response JSON -- it is not `null` and not `[]`. The jq filter must handle this:

```bash
# WRONG -- crashes on absent data field
echo "$body" | jq '.data'

# CORRECT -- defaults to empty array when data is absent
echo "$body" | jq '.data // []'
```

This matches the constitution.md rule: "jq '.[0].field' returns the literal string `null` (not empty) when the array is empty -- always use `// empty`."

### User ID Resolution

Both endpoints require the authenticated user's numeric ID (`{id}`), not the username. The existing `fetch-metrics` calls GET /2/users/me which returns the user's ID. Extract a `resolve_user_id` helper function that calls GET /2/users/me and returns the numeric ID via `jq -r '.data.id'`. Both new commands call this helper. This avoids three separate parsing locations for the /2/users/me response -- if the response format changes, only one location breaks. [Updated 2026-03-10 per plan review]

### Error Handling

Both endpoints may return:

- **401** -- credentials expired or invalid (existing handling in `x_request`)
- **403** -- insufficient API access level (endpoint requires paid credits)
- **429** -- rate limit (existing retry logic in `x_request`, depth-limited to 3)

The **403 case is critical** -- this is the expected failure when the user has Free tier without purchased credits. The existing `x_request` 403 handler says "Your app may lack the required permissions or your account may be suspended." For the new `get_request` helper, enhance the 403 handling:

1. Extract the `reason` field from the 403 response body: `jq -r '.reason // "unknown"'`
2. If `reason` is `client-not-enrolled`, include paid access guidance: "X API returned 403 for {endpoint}: client not enrolled. This endpoint requires paid API access. Visit <https://developer.x.com> to purchase credits."
3. If `reason` is `official-client-forbidden`, use existing message about permissions
4. Always include the endpoint path for differentiation

The `reason` field is part of the X API v2 `ClientForbiddenProblem` schema and provides machine-readable error differentiation. [Updated 2026-03-10 per plan review + deepened with API schema research]

### Query Parameter Signing

The existing `cmd_fetch_metrics` manually constructs the OAuth signature with query params because `x_request` does not handle query parameters in GET requests. It also duplicates all error handling (401, 429, catch-all) that `x_request` already provides, minus retry logic and JSON validation.

Extract a `get_request` helper function that handles: (1) OAuth signing with query params, (2) curl with stderr suppression, (3) HTTP status dispatch with the same error handling as `x_request` (401, 403 with reason parsing, 429 retry, JSON validation). Refactor `cmd_fetch_metrics` to use this helper. Both new commands use it too. This eliminates 3x code duplication and ensures all GET commands get retry logic and JSON validation consistently.

### Research Insights: `get_request` Design

**Signature:** `get_request endpoint query_params [depth]`

```bash
# Arguments:
#   $1 - endpoint (e.g., /2/users/me)
#   $2 - query params string (e.g., "user.fields=public_metrics,description")
#   $3 - retry depth (default: 0, max: 3) -- per depth-limited-api-retry-pattern learning
get_request() {
  local endpoint="$1"
  local query_params="${2:-}"
  local depth="${3:-0}"
  # ...
}
```

**Bootstrap sequencing:** `resolve_user_id` calls `get_request`, so `get_request` must be defined first. Since `resolve_user_id` uses `/2/users/me` which needs `user.fields=` as query params, `get_request` must handle the case where `query_params` is empty (for endpoints with no query string). Use `${2:-}` guard per set-euo-pipefail learning.

**Retry depth propagation:** `get_request` calls itself recursively on 429, incrementing depth. The `depth` param follows the exact pattern from `x_request` (lines 165-174 of the existing script). Per the depth-limited-api-retry-pattern learning: "Any function that handles transient errors by calling itself must accept a depth parameter with an explicit ceiling."

[Updated 2026-03-10 per plan review + deepened with learnings research]

### Shell Script Conventions

Per constitution.md and existing patterns:

- `set -euo pipefail` already declared
- `local` for all function variables
- Errors to stderr
- `jq` fallback chains: `jq ... 2>/dev/null || echo "fallback"`
- JSON validation on 2xx responses
- `${N:-}` guards for optional args

## Implementation

### Phase 1: Extract Shared Helpers

**File modified:** `plugins/soleur/skills/community/scripts/x-community.sh`

**Tasks:**

1. Extract `get_request` helper function (must be defined first -- `resolve_user_id` depends on it):
   - Arguments: `endpoint` `query_params_string` `depth` (all with `${N:-}` guards)
   - Sign request via `oauth_sign` including query params (split on `&` to pass as varargs)
   - curl with stderr suppression (`2>/dev/null`), HTTP status capture (`-w "\n%{http_code}"`)
   - Error dispatch: 401 (auth error), 403 (parse `reason` field -- `client-not-enrolled` vs `official-client-forbidden`), 429 (retry with depth limit, max 3), JSON validation on 2xx
   - Returns: JSON body on success

2. Extract `resolve_user_id` helper function:
   - Call `get_request "/2/users/me" ""` (empty query params)
   - Return numeric user ID via `jq -r '.data.id'`
   - Validate returned ID is numeric (`[[ "$user_id" =~ ^[0-9]+$ ]]`) -- per shell-api-wrapper-hardening-patterns learning
   - Exit with clear error if /2/users/me fails or returns non-numeric ID

3. Refactor `cmd_fetch_metrics` to use `get_request` instead of inline curl/sign/parse. Verify output is identical (same jq filter, same JSON structure).

### Phase 2: Add `fetch-mentions` and `fetch-timeline` Commands

**File modified:** `plugins/soleur/skills/community/scripts/x-community.sh`

**Tasks:**

1. Add `cmd_fetch_mentions` function:
   - Resolve user ID via `resolve_user_id`
   - Call `get_request` with `/2/users/{id}/mentions` and `tweet.fields=created_at,author_id,public_metrics,text`
   - Accept optional `--since` flag for `start_time` filtering (ISO 8601: `YYYY-MM-DDTHH:mm:ssZ`)
   - Accept optional `--max` flag for `max_results` (default: 10, clamp to **5-100** per API schema)
   - Format output via `jq '.data // []'` -- `data` field is **absent** (not empty array) when zero results

2. Add `cmd_fetch_timeline` function:
   - Resolve user ID via `resolve_user_id`
   - Call `get_request` with `/2/users/{id}/tweets` and `tweet.fields=created_at,public_metrics,text`
   - Accept optional `--max` flag for `max_results` (default: 10, clamp to **5-100** per API schema)
   - Format output via `jq '.data // []'` -- same absent-data handling as mentions

3. Add both commands to the case dispatch in `main()`

4. Update the usage text in `main()` and the file header comment to list the new commands

### Phase 3: Update Agent and Skill Docs

**Files modified:**

- `plugins/soleur/agents/support/community-manager.md`
- `plugins/soleur/skills/community/SKILL.md`

**Tasks:**

1. Update community-manager Scripts section to list new commands: `fetch-mentions`, `fetch-timeline`
2. Add a single note to X/Twitter data collection: "The `fetch-mentions` and `fetch-timeline` commands require X API paid access (credit purchase). If these return 403, continue with `fetch-metrics` only."
3. Update SKILL.md script reference parenthetical: `(fetch-metrics, fetch-mentions, fetch-timeline, post-tweet)`

## Acceptance Criteria

- [x] `x-community.sh fetch-mentions` returns recent @mentions as JSON (with paid API access)
- [x] `x-community.sh fetch-timeline` returns recent tweets as JSON (with paid API access)
- [x] `x-community.sh fetch-mentions` returns clear 403 error with endpoint path and paid access guidance (without credits)
- [x] `x-community.sh fetch-timeline` returns clear 403 error with endpoint path and paid access guidance (without credits)
- [x] `--since` flag on `fetch-mentions` filters by start_time
- [x] `--max` flag on both commands controls result count (5-100 per API schema)
- [x] Empty results (no mentions/tweets) return `[]` not an error
- [x] Existing `fetch-metrics` and `post-tweet` commands unchanged (refactored `cmd_fetch_metrics` produces identical output)
- [x] `get_request` helper handles 401, 403, 429 (retry), JSON validation consistently
- [x] Community-manager agent doc notes paid access requirement
- [x] Usage text and SKILL.md updated with new commands

## Test Scenarios

- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions` is called, then JSON array of recent mentions is returned with id, text, created_at, author_id, public_metrics fields
- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions --since 2026-03-01T00:00:00Z` is called, then only mentions after that timestamp are returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions --max 5` is called, then at most 5 mentions are returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-timeline` is called, then JSON array of recent tweets is returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-timeline --max 20` is called, then at most 20 tweets are returned
- Given X API credentials with Free tier (no credits) are configured, when `x-community.sh fetch-mentions` is called, then exit 1 with error mentioning the endpoint path and paid API access requirement
- Given X API credentials are invalid, when `x-community.sh fetch-mentions` is called, then exit 1 with 401 error
- Given `openssl` is not installed, when any command is called, then clear error about missing openssl (existing `require_openssl`)
- Given the user has zero mentions, when `x-community.sh fetch-mentions` is called, then output is `[]` (empty JSON array) -- the API response has no `data` field (absent, not null or empty array); the jq filter `.data // []` handles this
- Given the user has zero tweets, when `x-community.sh fetch-timeline` is called, then output is `[]` (empty JSON array) -- same absent-data handling
- Given `--max 3` is passed (below API minimum of 5), when the command is called, then the value is clamped to 5 with a warning to stderr
- Given GET /2/users/me succeeds but GET /2/users/{id}/mentions returns 403, when `x-community.sh fetch-mentions` is called, then the error references the mentions endpoint, not /2/users/me
- Given `cmd_fetch_metrics` is refactored to use `get_request`, when called, then output JSON is identical to the pre-refactor output

## Rollback Plan

All changes are within existing files -- revert with `git revert`:

- `x-community.sh`: new helper functions (`get_request`, `resolve_user_id`), two new command functions, refactored `cmd_fetch_metrics`. Note: `cmd_fetch_metrics` refactor changes implementation but not behavior -- verify output equivalence before shipping.
- `community-manager.md`: additional script references and paid access note
- `SKILL.md`: parenthetical text update

No new files created.

## Non-Goals

- New scripts or files
- OAuth 2.0 support (sticking with OAuth 1.0a User Context)
- Pagination support beyond `max_results` (no cursor-based pagination for MVP)
- `--exclude` flag for filtering retweets/replies (agent can filter raw results)
- Rate limit tracking or credit usage monitoring
- Automated testing with mock API (manual testing with real credentials)
- Adapter pattern refactor (#470)
- Engage sub-command (#469)

## Dependencies and Prerequisites

| Dependency | Type | Status |
|------------|------|--------|
| X API paid access (credit purchase) | Manual, blocking for testing | Per issue #471 |
| #127 merged | Code dependency | Closed |
| x-community.sh exists | Code dependency | Present |

## References

### Internal

- Existing script: `plugins/soleur/skills/community/scripts/x-community.sh`
- Community-manager agent: `plugins/soleur/agents/support/community-manager.md`
- Community SKILL.md: `plugins/soleur/skills/community/SKILL.md`
- Parent plan: `knowledge-base/project/plans/2026-03-09-feat-community-agent-platform-adapter-plan.md`
- Spec: `knowledge-base/project/specs/feat-community-agent-x/spec.md`

### Learnings Applied

- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- jq fallback, curl stderr suppression, JSON validation, snowflake ID validation
- `2026-03-09-depth-limited-api-retry-pattern.md` -- retry depth limit pattern for `get_request` (mirrors `x_request`)
- `2026-03-09-external-api-scope-calibration.md` -- verify API tier before building commands
- `2026-03-10-require-jq-startup-check-consistency.md` -- startup dependency checks
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- `${N:-}` guards for optional args in `get_request`; `|| true` for grep pipelines under pipefail
- `2026-02-27-parameterized-shell-install-eliminates-duplication.md` -- parameterized helper extraction pattern (same principle as `get_request`)

### External

- X API v2 User Mentions: `https://docs.x.com/x-api/users/get-mentions`
- X API v2 User Tweets: `https://docs.x.com/x-api/users/get-posts`
- X API Pricing: `https://docs.x.com/x-api/getting-started/pricing`
