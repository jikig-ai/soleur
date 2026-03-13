---
title: "feat: enrich fetch-mentions API data for engagement guardrail enforcement"
type: feat
date: 2026-03-13
---

# feat: enrich fetch-mentions API data for engagement guardrail enforcement

## Overview

Enrich the `fetch-mentions` API response in `x-community.sh` and update the `community-manager` agent workflow so that engagement guardrails added in #508 can be enforced by the agent directly, rather than relying solely on human reviewer fallback.

**Issue:** #510
**Depends on:** #508 (merged), #503 (merged)

## Problem Statement / Motivation

The engagement guardrails added in #508 identify skip criteria that require richer mention data than `fetch-mentions` currently provides. Three guardrails are scoped to observable data with human reviewer fallback -- this issue tracks enriching the API response so the agent can enforce them directly.

Current data gaps (from learning `2026-03-10-guardrails-must-match-observable-data.md`):

1. **Bot detection** relies on "no profile image, alphanumeric handle, zero followers" but `fetch-mentions` returns only `username`, `name`, `text`, `created_at`, `conversation_id`. No `profile_image_url`, no `followers_count`.
2. **Brand association risk** requires checking an author's recent content, but no command exists to fetch another user's timeline.
3. **Thread context** (rage-bait assessment, RT/QT detection) requires `referenced_tweets` data, which is not requested from the API.
4. **Conversation dedup** -- the agent receives `conversation_id` but has no guidance to group mentions by it.
5. **Cadence cross-reference** -- engagement guardrails exist in the brand guide but are not structurally referenced in the agent workflow.
6. **Approval prompt** -- the human reviewer sees mention text and author username but not follower count or profile image URL, limiting their ability to enforce skip criteria.

## Proposed Solution

Six changes across two files (`x-community.sh` and `community-manager.md`), plus test updates:

### 1. Bot detection: enrich user fields (x-community.sh)

Add `profile_image_url` and `public_metrics` to the `user.fields` parameter in `cmd_fetch_mentions()` (line 417). Propagate through the jq transform (lines 437-456) to expose `author_profile_image_url` and `author_followers_count` in the output JSON.

**Current query params (line 417):**
```text
user.fields=username,name
```

**Proposed query params:**
```text
user.fields=username,name,profile_image_url,public_metrics
```

**Updated jq output shape per mention:**
```json
{
  "id": "...",
  "text": "...",
  "author_username": "alice",
  "author_name": "Alice",
  "author_profile_image_url": "https://pbs.twimg.com/...",
  "author_followers_count": 1234,
  "created_at": "2026-03-10T00:00:00Z",
  "conversation_id": "...",
  "referenced_tweets": null
}
```

X API v2 confirms `profile_image_url` and `public_metrics` are valid `user.fields` values for GET /2/users/:id/mentions. The `public_metrics` object contains `followers_count`, `following_count`, `tweet_count`, and `listed_count`.

### 2. Brand association risk: add fetch-user-timeline command (x-community.sh)

Add a new `cmd_fetch_user_timeline()` function and `fetch-user-timeline` command that accepts a user ID parameter. This fetches another user's recent tweets so the agent can check an author's content before replying.

**Signature:**
```bash
x-community.sh fetch-user-timeline <user_id> [--max N]
```

**Implementation:** Uses the existing `get_request` helper to call `GET /2/users/<user_id>/tweets` with `tweet.fields=created_at,public_metrics,text&max_results=<N>`. Returns `jq '.data // []'` (same pattern as existing `cmd_fetch_timeline`).

**Key difference from `fetch-timeline`:** `fetch-timeline` resolves the authenticated user's ID via `resolve_user_id()`. `fetch-user-timeline` accepts an explicit user ID parameter, enabling the agent to inspect any author's recent posts.

**Validation:** `<user_id>` must be a positive integer (same pattern as `--since-id` validation). `--max` uses the same clamping logic as `cmd_fetch_timeline` (5-100 range).

### 3. Thread context: add referenced_tweets to tweet fields (x-community.sh)

Add `referenced_tweets` to the `tweet.fields` parameter in `cmd_fetch_mentions()` and propagate through the jq transform.

**Current tweet.fields:**
```text
tweet.fields=author_id,created_at,conversation_id
```

**Proposed tweet.fields:**
```text
tweet.fields=author_id,created_at,conversation_id,referenced_tweets
```

The `referenced_tweets` field is an array of objects with `type` (`retweeted`, `quoted`, `replied_to`) and `id`. This enables the agent to detect RT/QT mentions and assess thread context.

**jq transform addition:** Map `referenced_tweets` as `(.referenced_tweets // null)` in the output object.

### 4. Conversation dedup: add grouping guidance to community-manager.md

Add guidance to community-manager.md Step 3 (Draft Replies) instructing the agent to group mentions by `conversation_id` and draft only one reply per conversation thread. This prevents multiple replies in the same thread, which the cadence guardrail already discourages.

**Location:** `community-manager.md`, Capability 4, Step 3 (Draft Replies), add before the existing bullet list.

**Content:**
```text
Before drafting individual replies, group mentions by `conversation_id`. When multiple mentions share the same `conversation_id`, select the most recent mention in the thread and skip the rest. Draft only one reply per conversation thread.
```

### 5. Cadence cross-reference: add guardrails reference to community-manager.md

Add an explicit reference to the engagement guardrails in community-manager.md so the behavioral constraints are structurally present in the agent workflow, not only inherited through the brand guide read.

**Location:** `community-manager.md`, Capability 4, between Step 2 (Read Brand Guide) and Step 3 (Draft Replies). Add a new step or extend Step 2.

**Content:** After reading the brand guide voice and X/Twitter sections, also read the `#### Engagement Guardrails` subsection. Apply skip criteria before drafting: for each mention, check whether it should be skipped based on the guardrails (bot signals, off-topic, rage-bait, brand association risk, RT/QT). Only proceed to draft for mentions that pass the skip check.

This makes the guardrails structurally present in the agent's decision flow rather than relying on the agent to organically apply rules from the brand guide text.

### 6. Approval prompt enrichment: surface author metadata (community-manager.md)

Update the approval prompt format in Step 4 to include author metadata so the human reviewer can meaningfully enforce skip criteria.

**Current format:**
```text
Mention from @<author_username> (<created_at>):
"<mention_text>"
```

**Proposed format:**
```text
Mention from @<author_username> (<created_at>):
  Followers: <author_followers_count> | Profile image: <yes/no>
  Type: <original/reply/retweet/quote_tweet>
"<mention_text>"
```

The follower count and profile image presence help the reviewer spot bot accounts. The mention type (derived from `referenced_tweets`) helps the reviewer assess thread context.

## Technical Considerations

### X API Field Availability

Confirmed via X API v2 documentation:
- `profile_image_url` is a valid `user.fields` value for GET /2/users/:id/mentions
- `public_metrics` is a valid `user.fields` value (returns `followers_count`, `following_count`, `tweet_count`, `listed_count`)
- `referenced_tweets` is a valid `tweet.fields` value (returns array of `{type, id}`)
- GET /2/users/:id/tweets supports fetching any user's tweets (not just authenticated user) with OAuth 1.0a

### Backward Compatibility

The jq transform adds new fields to the output JSON. Existing consumers that destructure specific fields are unaffected -- new fields are additive. The `community-manager` agent parses the `mentions` array by field name, so new fields are ignored until the agent instructions reference them.

### API Credit Impact

Adding `user.fields` and `tweet.fields` to the existing `fetch-mentions` request does not cost additional API credits -- these are query parameter expansions on the same request. The new `fetch-user-timeline` command is a separate API call per author. The agent should call it selectively (only for mentions that pass initial skip criteria), not for every mention.

### OAuth Signature

The `get_request` helper already handles query parameter inclusion in OAuth signatures (learning `2026-03-10-x-api-oauth-get-query-params-in-signature.md`). Adding fields to the query string works without changes to the signing logic.

### Free Tier Fallback

In manual mode (Free tier 403 fallback), the enriched fields are not available because mentions are pasted by the user, not fetched from the API. The agent must handle absent metadata gracefully -- the approval prompt should display "N/A" for missing fields. The `fetch-user-timeline` command may also return 403 on Free tier; if so, skip the brand association check and note it in the approval prompt.

## Non-Goals

- Automated enforcement without human approval -- the agent applies skip criteria and recommends skipping, but the human reviewer makes the final decision
- Modifying the brand guide guardrails text -- the guardrails were finalized in #508
- Adding new guardrail criteria beyond what #508 established
- Fetching user timeline for every mention -- selective use only for non-obvious cases
- Thread reply content fetching (getting the full thread) -- `referenced_tweets` provides type/ID metadata, not full thread content

## Acceptance Criteria

### x-community.sh Changes

- [ ] `cmd_fetch_mentions` query params include `user.fields=username,name,profile_image_url,public_metrics`
- [ ] `cmd_fetch_mentions` query params include `tweet.fields=author_id,created_at,conversation_id,referenced_tweets`
- [ ] jq transform outputs `author_profile_image_url` (string or null) per mention
- [ ] jq transform outputs `author_followers_count` (number or 0) per mention
- [ ] jq transform outputs `referenced_tweets` (array or null) per mention
- [ ] New `fetch-user-timeline <user_id> [--max N]` command exists
- [ ] `fetch-user-timeline` validates `<user_id>` as a positive integer
- [ ] `fetch-user-timeline` validates `--max` with same clamping as `fetch-timeline` (5-100)
- [ ] Script header comment updated with new command
- [ ] `main()` dispatch case updated for `fetch-user-timeline`

### community-manager.md Changes

- [ ] Step 3 includes conversation dedup guidance (group by `conversation_id`, one reply per thread)
- [ ] Explicit guardrails cross-reference added between Step 2 and Step 3 (or extending Step 2)
- [ ] Step 4 approval prompt format includes follower count, profile image presence, and mention type
- [ ] Absent metadata handled gracefully (display "N/A" when data unavailable, e.g., manual mode)

### Tests (test/x-community.test.ts)

- [ ] jq transform test updated to verify `author_profile_image_url` field
- [ ] jq transform test updated to verify `author_followers_count` field
- [ ] jq transform test updated to verify `referenced_tweets` field
- [ ] jq transform test covers missing `public_metrics` (fallback to 0)
- [ ] jq transform test covers missing `referenced_tweets` (fallback to null)
- [ ] `fetch-user-timeline` argument validation tests (missing user_id, non-numeric user_id)
- [ ] `fetch-user-timeline --max` validation tests (non-numeric, out of range)

## Test Scenarios

- Given a mention with a user who has `public_metrics` in the API response, when the jq transform runs, then `author_followers_count` equals the user's `followers_count`
- Given a mention with a user whose `public_metrics` is absent from the API response, when the jq transform runs, then `author_followers_count` defaults to 0
- Given a mention that is a retweet, when the jq transform runs, then `referenced_tweets` contains an object with `type: "retweeted"`
- Given a mention with no `referenced_tweets` in the API response, when the jq transform runs, then `referenced_tweets` is null
- Given `fetch-user-timeline` called with a non-numeric user_id, when the command runs, then it exits 1 with an error
- Given `fetch-user-timeline` called with `--max 200`, when the command runs, then the max is clamped to 100 with a warning
- Given two mentions with the same `conversation_id`, when the agent applies conversation dedup, then only the most recent mention is drafted for reply
- Given a mention from a likely bot (0 followers, no profile image), when the agent applies skip criteria, then it recommends skipping with the reason displayed in the approval prompt
- Given manual mode (Free tier 403 fallback), when the approval prompt renders, then missing metadata fields display "N/A"

## Semver Intent

`semver:minor` -- new `fetch-user-timeline` command added to `x-community.sh`, enriched API response shape (additive), updated agent workflow.

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/community/scripts/x-community.sh` | Add `profile_image_url`, `public_metrics` to user.fields; add `referenced_tweets` to tweet.fields; update jq transform; add `cmd_fetch_user_timeline` function; update header and dispatch |
| `plugins/soleur/agents/support/community-manager.md` | Add conversation dedup in Step 3; add guardrails cross-reference between Steps 2-3; enrich Step 4 approval prompt format |
| `test/x-community.test.ts` | Update jq transform tests for new fields; add `fetch-user-timeline` validation tests |

## References

- Issue: #510
- PR #508 (merged) -- engagement guardrails added to brand guide
- Issue #503 (closed) -- original guardrails issue
- `plugins/soleur/skills/community/scripts/x-community.sh` -- target script, `cmd_fetch_mentions` at line 367
- `plugins/soleur/agents/support/community-manager.md` -- target agent, Capability 4 at line 247
- `test/x-community.test.ts` -- existing tests for jq transform and argument validation
- `knowledge-base/marketing/brand-guide.md` -- engagement guardrails at line 167
- `knowledge-base/features/learnings/2026-03-10-guardrails-must-match-observable-data.md` -- motivation
- `knowledge-base/features/learnings/2026-03-10-x-api-oauth-get-query-params-in-signature.md` -- OAuth signing for GET query params
- `knowledge-base/features/learnings/2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- Free tier constraints
- X API v2 GET /2/users/:id/mentions -- confirmed field availability
- X API v2 GET /2/users/:id/tweets -- confirmed supports arbitrary user_id with OAuth 1.0a
