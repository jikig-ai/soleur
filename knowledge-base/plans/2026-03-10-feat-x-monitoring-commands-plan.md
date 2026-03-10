---
title: "feat: add X monitoring commands requiring paid API tier"
type: feat
date: 2026-03-10
semver: minor
---

# feat: add X monitoring commands requiring paid API tier

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

### Endpoint Details (from X API v2 docs)

**GET /2/users/{id}/mentions:**
- Scopes: `tweet.read`, `users.read`
- Parameters: `max_results` (1-100, default 10), `start_time`, `end_time`, `since_id`, `until_id`, `pagination_token`, `tweet.fields`, `expansions`, `user.fields`
- Returns: array of Tweet objects with metadata (result_count, next_token, newest_id, oldest_id)

**GET /2/users/{id}/tweets:**
- Scopes: `tweet.read`, `users.read`
- Parameters: same as mentions plus `exclude` (retweets, replies)
- Returns: same structure as mentions

### User ID Resolution

Both endpoints require the authenticated user's numeric ID (`{id}`), not the username. The existing `fetch-metrics` calls GET /2/users/me which returns the user's ID. Extract a `resolve_user_id` helper function that calls GET /2/users/me and returns the numeric ID via `jq -r '.data.id'`. Both new commands call this helper. This avoids three separate parsing locations for the /2/users/me response -- if the response format changes, only one location breaks. [Updated 2026-03-10 per plan review]

### Error Handling

Both endpoints may return:
- **401** -- credentials expired or invalid (existing handling in `x_request`)
- **403** -- insufficient API access level (endpoint requires paid credits)
- **429** -- rate limit (existing retry logic in `x_request`, depth-limited to 3)

The **403 case is critical** -- this is the expected failure when the user has Free tier without purchased credits. The existing `x_request` 403 handler says "Your app may lack the required permissions or your account may be suspended." For the new `get_request` helper, enhance the 403 message to include the endpoint path so the user knows which endpoint was rejected: "X API returned 403 Forbidden for {endpoint}. This endpoint may require paid API access (credit purchase). Visit https://developer.x.com to purchase credits." The endpoint path provides sufficient differentiation without parsing X API error codes. [Updated 2026-03-10 per plan review]

### Query Parameter Signing

The existing `cmd_fetch_metrics` manually constructs the OAuth signature with query params because `x_request` does not handle query parameters in GET requests. It also duplicates all error handling (401, 429, catch-all) that `x_request` already provides, minus retry logic and JSON validation.

Extract a `get_request` helper function that handles: (1) OAuth signing with query params, (2) curl with stderr suppression, (3) HTTP status dispatch with the same error handling as `x_request` (401, 403, 429 retry, JSON validation). Refactor `cmd_fetch_metrics` to use this helper. Both new commands use it too. This eliminates 3x code duplication and ensures all GET commands get retry logic and JSON validation consistently. [Updated 2026-03-10 per plan review -- all 3 reviewers converged on this]

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

1. Extract `resolve_user_id` helper function:
   - Call GET /2/users/me via `get_request` (or inline for bootstrap)
   - Return numeric user ID via `jq -r '.data.id'`
   - Exit with clear error if /2/users/me fails

2. Extract `get_request` helper function:
   - Arguments: `endpoint` `query_params_string`
   - Sign request via `oauth_sign` including query params
   - curl with stderr suppression, HTTP status capture
   - Error dispatch: 401 (auth error), 403 (paid access message with endpoint path), 429 (retry with depth limit), JSON validation on 2xx
   - Returns: JSON body on success

3. Refactor `cmd_fetch_metrics` to use `get_request` instead of inline curl/sign/parse. Verify output is identical.

### Phase 2: Add `fetch-mentions` and `fetch-timeline` Commands

**File modified:** `plugins/soleur/skills/community/scripts/x-community.sh`

**Tasks:**

1. Add `cmd_fetch_mentions` function:
   - Resolve user ID via `resolve_user_id`
   - Call `get_request` with `/2/users/{id}/mentions` and `tweet.fields=created_at,author_id,public_metrics,text`
   - Accept optional `--since` flag for `start_time` filtering
   - Accept optional `--max` flag for `max_results` (default: 10, clamp to 1-100)
   - Format output as JSON array via jq; handle empty results (null or empty `data` array) by outputting `[]`

2. Add `cmd_fetch_timeline` function:
   - Resolve user ID via `resolve_user_id`
   - Call `get_request` with `/2/users/{id}/tweets` and `tweet.fields=created_at,public_metrics,text`
   - Accept optional `--max` flag for `max_results` (default: 10, clamp to 1-100)
   - Format output as JSON array via jq; handle empty results

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

- [ ] `x-community.sh fetch-mentions` returns recent @mentions as JSON (with paid API access)
- [ ] `x-community.sh fetch-timeline` returns recent tweets as JSON (with paid API access)
- [ ] `x-community.sh fetch-mentions` returns clear 403 error with endpoint path and paid access guidance (without credits)
- [ ] `x-community.sh fetch-timeline` returns clear 403 error with endpoint path and paid access guidance (without credits)
- [ ] `--since` flag on `fetch-mentions` filters by start_time
- [ ] `--max` flag on both commands controls result count (1-100)
- [ ] Empty results (no mentions/tweets) return `[]` not an error
- [ ] Existing `fetch-metrics` and `post-tweet` commands unchanged (refactored `cmd_fetch_metrics` produces identical output)
- [ ] `get_request` helper handles 401, 403, 429 (retry), JSON validation consistently
- [ ] Community-manager agent doc notes paid access requirement
- [ ] Usage text and SKILL.md updated with new commands

## Test Scenarios

- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions` is called, then JSON array of recent mentions is returned with id, text, created_at, author_id, public_metrics fields
- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions --since 2026-03-01T00:00:00Z` is called, then only mentions after that timestamp are returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions --max 5` is called, then at most 5 mentions are returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-timeline` is called, then JSON array of recent tweets is returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-timeline --max 20` is called, then at most 20 tweets are returned
- Given X API credentials with Free tier (no credits) are configured, when `x-community.sh fetch-mentions` is called, then exit 1 with error mentioning the endpoint path and paid API access requirement
- Given X API credentials are invalid, when `x-community.sh fetch-mentions` is called, then exit 1 with 401 error
- Given `openssl` is not installed, when any command is called, then clear error about missing openssl (existing `require_openssl`)
- Given the user has zero mentions, when `x-community.sh fetch-mentions` is called, then output is `[]` (empty JSON array), not an error
- Given the user has zero tweets, when `x-community.sh fetch-timeline` is called, then output is `[]` (empty JSON array), not an error
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
- Parent plan: `knowledge-base/plans/2026-03-09-feat-community-agent-platform-adapter-plan.md`
- Spec: `knowledge-base/specs/feat-community-agent-x/spec.md`

### Learnings Applied

- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- jq fallback, curl stderr suppression, JSON validation
- `2026-03-09-depth-limited-api-retry-pattern.md` -- retry depth limit (already in x_request)
- `2026-03-09-external-api-scope-calibration.md` -- verify API tier before building commands
- `2026-03-10-require-jq-startup-check-consistency.md` -- startup dependency checks

### External

- X API v2 User Mentions: `https://docs.x.com/x-api/users/get-mentions`
- X API v2 User Tweets: `https://docs.x.com/x-api/users/get-posts`
- X API Pricing: `https://docs.x.com/x-api/getting-started/pricing`
