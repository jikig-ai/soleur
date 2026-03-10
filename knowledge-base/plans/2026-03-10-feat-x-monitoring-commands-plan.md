---
title: "feat: add X monitoring commands requiring paid API tier"
type: feat
date: 2026-03-10
semver: patch
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
- Agent changes -- the community-manager agent already has X/Twitter data collection; it just needs the new commands to exist
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

Both endpoints require the authenticated user's numeric ID (`{id}`), not the username. The existing `fetch-metrics` calls GET /2/users/me which returns the user's ID. The new commands should:

1. Call GET /2/users/me to resolve the user ID first
2. Then call the target endpoint with that ID

This can be done via the existing `x_request` helper. Alternatively, cache the user ID in a local variable within the main dispatch to avoid repeated lookups if multiple commands are chained -- but for now, a per-command lookup is simpler and follows the existing pattern.

### Error Handling

Both endpoints may return:
- **401** -- credentials expired or invalid (existing handling in `x_request`)
- **403** -- insufficient API access level (endpoint requires paid credits)
- **429** -- rate limit (existing retry logic in `x_request`, depth-limited to 3)

The **403 case is critical** -- this is the expected failure when the user has Free tier without purchased credits. The error message should explicitly mention that these endpoints require X API paid access (credit purchase).

### Query Parameter Signing

The existing `cmd_fetch_metrics` manually constructs the OAuth signature with query params because `x_request` does not handle query parameters in GET requests. Two options:

1. **Follow the `cmd_fetch_metrics` pattern** -- manually sign and curl in each command function (duplicates ~20 lines but keeps each command self-contained)
2. **Extend `x_request` to accept query params** -- cleaner but modifies a working function

Option 1 is preferred to avoid regressions in `x_request`. The duplication is manageable for two commands.

### Shell Script Conventions

Per constitution.md and existing patterns:
- `set -euo pipefail` already declared
- `local` for all function variables
- Errors to stderr
- `jq` fallback chains: `jq ... 2>/dev/null || echo "fallback"`
- JSON validation on 2xx responses
- `${N:-}` guards for optional args

## Implementation

### Phase 1: Add `fetch-mentions` command

**File modified:** `plugins/soleur/skills/community/scripts/x-community.sh`

**Tasks:**

1. Add `cmd_fetch_mentions` function:
   - Resolve user ID via GET /2/users/me
   - Call GET /2/users/{id}/mentions with fields: `tweet.fields=created_at,author_id,public_metrics,text`
   - Accept optional `--since` flag for `start_time` filtering
   - Accept optional `--max` flag for `max_results` (default: 10, max: 100)
   - Format output as JSON array of mentions with id, text, created_at, author_id, public_metrics
   - Handle 403 with explicit "requires paid API access" message

2. Add `fetch-mentions` to the case dispatch in `main()`

3. Update the usage text in `main()` to list the new command

### Phase 2: Add `fetch-timeline` command

**File modified:** `plugins/soleur/skills/community/scripts/x-community.sh`

**Tasks:**

1. Add `cmd_fetch_timeline` function:
   - Resolve user ID via GET /2/users/me
   - Call GET /2/users/{id}/tweets with fields: `tweet.fields=created_at,public_metrics,text`
   - Accept optional `--max` flag for `max_results` (default: 10, max: 100)
   - Accept optional `--exclude` flag for excluding retweets/replies
   - Format output as JSON array of tweets
   - Handle 403 with explicit "requires paid API access" message

2. Add `fetch-timeline` to the case dispatch in `main()`

3. Update the usage text in `main()` to list the new command

### Phase 3: Update Community Agent

**File modified:** `plugins/soleur/agents/support/community-manager.md`

**Tasks:**

1. Update the Scripts section to list the new commands (`fetch-mentions`, `fetch-timeline`)
2. Update digest data collection (Step 1) to call `fetch-mentions` and `fetch-timeline` when X is enabled and paid access is available
3. Add graceful fallback: if `fetch-mentions` or `fetch-timeline` returns 403, log a warning and continue with `fetch-metrics` only (do not fail the digest)
4. Update Health Metrics (Capability 2) to include mention count and recent timeline activity when available

### Phase 4: Update SKILL.md Script Reference

**File modified:** `plugins/soleur/skills/community/SKILL.md`

**Tasks:**

1. Update the script reference for `x-community.sh` to include the new commands in the parenthetical: `(fetch-metrics, fetch-mentions, fetch-timeline, post-tweet)`

## Acceptance Criteria

- [ ] `x-community.sh fetch-mentions` returns recent @mentions as JSON (with paid API access)
- [ ] `x-community.sh fetch-timeline` returns recent tweets as JSON (with paid API access)
- [ ] `x-community.sh fetch-mentions` returns clear 403 error mentioning paid access requirement (without credits)
- [ ] `x-community.sh fetch-timeline` returns clear 403 error mentioning paid access requirement (without credits)
- [ ] `--since` flag on `fetch-mentions` filters by start_time
- [ ] `--max` flag on both commands controls result count
- [ ] Existing `fetch-metrics` and `post-tweet` commands unchanged
- [ ] Community-manager agent gracefully degrades when paid endpoints return 403
- [ ] Usage text updated with new commands

## Test Scenarios

- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions` is called, then JSON array of recent mentions is returned with id, text, created_at, author_id, public_metrics fields
- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions --since 2026-03-01T00:00:00Z` is called, then only mentions after that timestamp are returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-mentions --max 5` is called, then at most 5 mentions are returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-timeline` is called, then JSON array of recent tweets is returned
- Given X API credentials with paid access are configured, when `x-community.sh fetch-timeline --max 20 --exclude retweets` is called, then at most 20 tweets excluding retweets are returned
- Given X API credentials with Free tier (no credits) are configured, when `x-community.sh fetch-mentions` is called, then exit 1 with error message: "X API returned 403 Forbidden. This endpoint requires paid API access (credit purchase). Visit https://developer.x.com to purchase credits."
- Given X API credentials are invalid, when `x-community.sh fetch-mentions` is called, then exit 1 with 401 error (handled by existing `x_request`)
- Given `openssl` is not installed, when any command is called, then clear error about missing openssl (existing `require_openssl`)
- Given community-manager agent runs digest with X configured but no paid access, when `fetch-mentions` returns 403, then the digest continues with `fetch-metrics` only and logs a warning

## Rollback Plan

All changes are additive within existing files:
- `x-community.sh`: two new functions and two case dispatch entries -- revert with `git revert`
- `community-manager.md`: additional script references and fallback logic -- revert with `git revert`
- `SKILL.md`: parenthetical text update -- revert with `git revert`

No new files created. No existing behavior modified.

## Non-Goals

- New scripts or files
- OAuth 2.0 support (sticking with OAuth 1.0a User Context)
- Pagination support beyond `max_results` (no cursor-based pagination for MVP)
- Caching user ID across commands
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
