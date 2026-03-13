---
title: "feat: enrich fetch-mentions API data for engagement guardrail enforcement"
type: feat
date: 2026-03-13
---

# feat: enrich fetch-mentions API data for engagement guardrail enforcement

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 6
**Research sources:** X API v2 docs (GET /2/users/:id/mentions, GET /2/users/:id/tweets), 7 institutional learnings, constitution.md, codebase pattern analysis (x-community.sh, community-manager.md, x-community.test.ts)

### Key Improvements
1. Added jq INDEX fallback pattern guidance -- new fields must follow the established `// null` / `// 0` fallback chain to prevent silent data loss (learning `2026-03-10-jq-generator-silent-data-loss.md`)
2. Added 5-layer shell hardening checklist for `cmd_fetch_user_timeline` -- input validation, transport safety, JSON validation, error extraction fallback, float-safe arithmetic (learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`)
3. Added API credit conservation guidance -- `fetch-user-timeline` is a separate API call and must be gated behind initial skip criteria, not called per-mention (learning `2026-03-09-external-api-scope-calibration.md`)
4. Added agent prompt sharp-edges-only principle -- community-manager.md updates should include only what the agent would get wrong without instruction, not general engagement best practices (learning `2026-02-13-agent-prompt-sharp-edges-only.md`)
5. Added headless mode handling for the new guardrails screening step -- headless mode must skip `fetch-user-timeline` calls since it skips all mentions anyway (learning `2026-03-03-headless-mode-skill-bypass-convention.md`)
6. Added `author_id` propagation to output JSON -- the agent needs `author_id` to call `fetch-user-timeline`, but the current jq transform drops it

### Applied Learnings
- `2026-03-10-guardrails-must-match-observable-data.md` -- primary motivation; this plan closes the gap between guardrail criteria and observable data
- `2026-03-10-jq-generator-silent-data-loss.md` -- new jq fields must use INDEX + `// fallback` pattern, not generator-style joins
- `2026-03-09-shell-api-wrapper-hardening-patterns.md` -- new command needs 5-layer defense (input, transport, response, error, retry)
- `2026-03-09-external-api-scope-calibration.md` -- avoid overscoping; `fetch-user-timeline` adds API calls, must be selective
- `2026-02-13-agent-prompt-sharp-edges-only.md` -- community-manager updates should be sharp edges only, not general knowledge
- `2026-03-03-headless-mode-skill-bypass-convention.md` -- new screening step must respect `--headless` flag
- `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- `fetch-user-timeline` may 403 on pay-per-use with $0 balance; handle gracefully

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

### Research Insights: Motivation

**Institutional Learnings:**
- Learning `2026-03-10-guardrails-must-match-observable-data.md` identifies two failure modes when guardrails exceed the data pipeline: (1) the agent silently ignores criteria it cannot evaluate, (2) the agent hallucinates judgments from insufficient signals. Both modes are currently active for bot detection, brand association risk, and thread context checks.
- Learning `2026-03-09-external-api-scope-calibration.md` warns against overscoping API integrations. This plan adds only the minimal fields needed to close the guardrail gaps -- no speculative enrichments.

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
  "author_id": "100",
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

### Research Insights: Bot Detection Fields

**jq Transform Pattern (learning `2026-03-10-jq-generator-silent-data-loss.md`):**
- The existing jq transform uses `INDEX(.id)` to build a user lookup map -- this is the correct pattern. New fields must follow the same `// fallback` chain:
  - `($user.profile_image_url // null)` -- null when user has no profile image or user is missing from includes
  - `(($user.public_metrics.followers_count) // 0)` -- 0 when public_metrics is absent (e.g., suspended accounts)
- Do NOT use generator-style access like `(.includes.users[] | select(...))` which silently drops unmatched records

**Edge Cases:**
- X API may omit `profile_image_url` for default-avatar accounts (the field is absent, not an empty string). The `// null` fallback handles this correctly.
- Suspended or deleted accounts may appear in `data[]` but be absent from `includes.users[]`. The existing INDEX pattern handles this -- the user lookup returns `{}`, and all field accesses fall through to defaults.
- `public_metrics` is an object, not a scalar. Access the nested `followers_count` field: `$user.public_metrics.followers_count`, not `$user.public_metrics`.

**Critical addition -- `author_id` propagation:**
- The current jq transform does NOT include `author_id` in the output. The agent needs `author_id` to call `fetch-user-timeline <user_id>` for brand association risk checks. Add `author_id: .author_id` to the output object.

### 2. Brand association risk: add fetch-user-timeline command (x-community.sh)

Add a new `cmd_fetch_user_timeline()` function and `fetch-user-timeline` command that accepts a user ID parameter. This fetches another user's recent tweets so the agent can check an author's content before replying.

**Signature:**
```bash
x-community.sh fetch-user-timeline <user_id> [--max N]
```

**Implementation:** Uses the existing `get_request` helper to call `GET /2/users/<user_id>/tweets` with `tweet.fields=created_at,public_metrics,text&max_results=<N>`. Returns `jq '.data // []'` (same pattern as existing `cmd_fetch_timeline`).

**Key difference from `fetch-timeline`:** `fetch-timeline` resolves the authenticated user's ID via `resolve_user_id()`. `fetch-user-timeline` accepts an explicit user ID parameter, enabling the agent to inspect any author's recent posts.

**Validation:** `<user_id>` must be a positive integer (same pattern as `--since-id` validation). `--max` uses the same clamping logic as `cmd_fetch_timeline` (5-100 range).

### Research Insights: fetch-user-timeline

**Shell API Wrapper Hardening (learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`):**
The new command must implement all 5 defense layers:

| Layer | Implementation |
|-------|---------------|
| Input | Validate `<user_id>` as `^[0-9]+$` before URL interpolation (prevents path traversal) |
| Transport | Uses existing `get_request` which suppresses curl stderr (`2>/dev/null`) |
| Response | Uses existing `handle_response` which validates JSON on 2xx |
| Error extraction | Uses existing `handle_response` jq fallback chain |
| Retry | Uses existing `get_request` depth-limited retry on 429 |

Since `cmd_fetch_user_timeline` reuses `get_request` and `handle_response`, layers 2-5 are inherited. Only layer 1 (input validation) needs new code.

**API Credit Conservation (learning `2026-03-09-external-api-scope-calibration.md`):**
- Each `fetch-user-timeline` call costs API credits (separate request per author)
- X API rate limit for GET /2/users/:id/tweets: 900 requests per 15 minutes per user token
- The agent must call this selectively -- only for mentions that pass the initial bot/spam/off-topic skip checks and have ambiguous brand association risk
- If the agent calls `fetch-user-timeline` for all 10 mentions in a session, that is 10 additional API requests -- acceptable, but unnecessary. Most mentions can be evaluated from the enriched mention data alone.

**Pay-per-use Billing (learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`):**
- `fetch-user-timeline` may return 403 (`client-not-enrolled`) on accounts with $0 credits
- Unlike `fetch-mentions` (which has a manual-mode fallback), there is no meaningful fallback for `fetch-user-timeline` -- the agent simply cannot check the author's timeline
- When `fetch-user-timeline` fails, the agent should note "Unable to check author timeline (API access required)" in the approval prompt and delegate the brand association risk check entirely to the human reviewer

**Default max_results:**
- Default to `--max 5` (not 10). The agent only needs a quick scan of recent content, not a deep history. 5 tweets is sufficient to detect obvious brand association risks while conserving API credits.

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

### Research Insights: Thread Context

**X API v2 `referenced_tweets` structure:**
```json
{
  "referenced_tweets": [
    {"type": "retweeted", "id": "12345"},
    {"type": "quoted", "id": "67890"}
  ]
}
```

Valid `type` values: `retweeted`, `quoted`, `replied_to`. A single tweet can have multiple entries (e.g., a quote-tweet of a retweet).

**Edge Cases:**
- A mention with `referenced_tweets` containing `type: "retweeted"` is a retweet of Soleur content. The brand guide guardrail says "the RT is sufficient engagement" -- the agent should auto-skip these.
- A mention with `referenced_tweets` containing `type: "quoted"` is a quote-tweet. The original content is the author's commentary, which may need a reply. Do NOT auto-skip quote-tweets -- they require human review.
- A mention with `referenced_tweets` containing only `type: "replied_to"` is a reply in a thread. The `conversation_id` field handles dedup for these (see section 4).
- Absent `referenced_tweets` (null after fallback) indicates an original tweet mentioning Soleur -- the most common case and highest priority for engagement.

**Guardrail mapping:**
| `referenced_tweets` state | Agent action |
|---------------------------|-------------|
| `null` (original mention) | Proceed to draft |
| `[{type: "retweeted"}]` | Auto-skip (guardrail: "RT is sufficient engagement") |
| `[{type: "quoted"}]` | Proceed to draft (author's commentary needs review) |
| `[{type: "replied_to"}]` | Proceed, but apply conversation dedup |

### 4. Conversation dedup: add grouping guidance to community-manager.md

Add guidance to community-manager.md Step 3 (Draft Replies) instructing the agent to group mentions by `conversation_id` and draft only one reply per conversation thread. This prevents multiple replies in the same thread, which the cadence guardrail already discourages.

**Location:** `community-manager.md`, Capability 4, Step 3 (Draft Replies), add before the existing bullet list.

**Content:**
```text
Before drafting individual replies, group mentions by `conversation_id`. When multiple mentions share the same `conversation_id`, select the most recent mention in the thread and skip the rest. Draft only one reply per conversation thread.
```

### Research Insights: Conversation Dedup

**Edge Cases:**
- When multiple mentions in the same conversation come from different authors, the "most recent" heuristic may not be optimal. The agent should prefer the mention that is most directly addressable (e.g., a question over a casual mention). However, "most recent" is simpler and avoids subjective ranking. Keep "most recent" as the rule.
- If a conversation has both a retweet and an original reply, the retweet should be skipped per the RT guardrail (section 3), and the reply should be the candidate for drafting. The RT skip runs before conversation dedup.
- `conversation_id` may be null for some mentions (e.g., API inconsistency). Treat null `conversation_id` as unique -- each null-conversation mention is its own group.

**Agent prompt wording (learning `2026-02-13-agent-prompt-sharp-edges-only.md`):**
- The dedup instruction is a sharp edge -- the agent would not group by `conversation_id` without being told. Keep it concise.
- Do NOT add general advice about thread etiquette or multi-party conversations -- the agent handles that correctly from training data.

### 5. Cadence cross-reference: add guardrails reference to community-manager.md

Add an explicit reference to the engagement guardrails in community-manager.md so the behavioral constraints are structurally present in the agent workflow, not only inherited through the brand guide read.

**Location:** `community-manager.md`, Capability 4, between Step 2 (Read Brand Guide) and Step 3 (Draft Replies). Add as Step 2b (not a separate numbered step, to avoid renumbering Steps 3-7).

**Content:** After reading the brand guide voice and X/Twitter sections, also read the `#### Engagement Guardrails` subsection. Apply skip criteria before drafting: for each mention, check whether it should be skipped based on the guardrails (bot signals, off-topic, rage-bait, brand association risk, RT/QT). Only proceed to draft for mentions that pass the skip check.

This makes the guardrails structurally present in the agent's decision flow rather than relying on the agent to organically apply rules from the brand guide text.

### Research Insights: Guardrails Cross-Reference

**Agent context blindness (learning `2026-02-22-agent-context-blindness-vision-misalignment.md`):**
- Agents that produce content must read canonical sources before making decisions. The existing Step 2 reads `## Voice` and `## Channel Notes > ### X/Twitter`, which already includes the guardrails subsection. However, reading and applying are different actions.
- The cross-reference adds an explicit "apply skip criteria" instruction. Without it, the agent reads the guardrails but treats them as general context rather than a decision gate.

**Sharp edges only (learning `2026-02-13-agent-prompt-sharp-edges-only.md`):**
- The guardrails screening step should be terse: "For each mention, apply the skip criteria from `#### Engagement Guardrails`. Skip mentions that match any criterion. For mentions requiring brand association risk assessment, call `fetch-user-timeline` with the mention's `author_id`."
- Do NOT duplicate the guardrail criteria in the agent prompt -- the agent reads them from the brand guide. The prompt should only say "apply the criteria from that section."

**Headless mode (learning `2026-03-03-headless-mode-skill-bypass-convention.md`):**
- In headless mode, all mentions are already skipped ("engage requires interactive approval"). The guardrails screening step should be skipped in headless mode -- there is no point evaluating skip criteria if no replies will be posted.
- Avoid calling `fetch-user-timeline` in headless mode since it consumes API credits for zero benefit.

**Implementation choice -- Step 2b vs. new Step 2.5:**
- Use Step 2b (sub-step) rather than inserting a new Step 3 that renumbers all subsequent steps. The community-manager agent's Step numbers are referenced by the community SKILL.md and the guardrails plan. Renumbering would require updating cross-references. Step 2b avoids this.

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

### Research Insights: Approval Prompt

**Mention type derivation logic:**
- `referenced_tweets` is null -> "original"
- `referenced_tweets` contains `type: "replied_to"` -> "reply"
- `referenced_tweets` contains `type: "retweeted"` -> "retweet" (should have been auto-skipped in Step 2b; display as informational if it reaches Step 4)
- `referenced_tweets` contains `type: "quoted"` -> "quote_tweet"
- Multiple types present -> show the most relevant (prefer "quoted" > "replied_to" > "retweeted")

**Absent metadata handling (manual mode):**
- In Free tier 403 fallback (manual mode), the agent has no API data for the mention author. The approval prompt should display:
  ```text
  Mention from @<author_username> (<created_at>):
    Followers: N/A | Profile image: N/A
    Type: N/A (manual mode)
  "<mention_text>"
  ```
- The agent should note: "Author metadata unavailable in manual mode. Apply skip criteria based on mention text and author handle."

**Bot signal thresholds:**
- The guardrails say "alphanumeric handle pattern, generic or empty display name" -- these are text-based checks the agent can already do.
- With enriched data, the agent can also check: followers_count == 0 AND profile_image_url == null as a strong bot signal. But avoid hardcoding a followers_count threshold (e.g., <10) -- new legitimate accounts also have low follower counts. The 0-followers + no-profile-image combination is the strongest signal.

## Technical Considerations

### X API Field Availability

Confirmed via X API v2 documentation (GET /2/users/:id/mentions):
- `profile_image_url` is a valid `user.fields` value
- `public_metrics` is a valid `user.fields` value (returns `followers_count`, `following_count`, `tweet_count`, `listed_count`)
- `referenced_tweets` is a valid `tweet.fields` value (returns array of `{type, id}`)
- GET /2/users/:id/tweets supports fetching any user's tweets (not just authenticated user) with OAuth 1.0a

### Research Insights: X API Fields

**Full list of valid `user.fields` for GET /2/users/:id/mentions:**
`affiliation, confirmed_email, connection_status, created_at, description, entities, id, is_identity_verified, location, most_recent_tweet_id, name, parody, pinned_tweet_id, profile_banner_url, profile_image_url, protected, public_metrics, receives_your_dm, subscription, subscription_type, url, username, verified, verified_followers_count, verified_type, withheld`

**Full list of valid `tweet.fields` for GET /2/users/:id/mentions:**
`article, attachments, author_id, card_uri, community_id, context_annotations, conversation_id, created_at, display_text_range, edit_controls, edit_history_tweet_ids, entities, geo, id, in_reply_to_user_id, lang, media_metadata, non_public_metrics, note_tweet, organic_metrics, possibly_sensitive, promoted_metrics, public_metrics, referenced_tweets, reply_settings, scopes, source, suggested_source_links, suggested_source_links_with_counts, text, withheld`

**Rate limits for GET /2/users/:id/mentions:** 450 per app / 300 per user per 15 minutes. The existing `fetch-mentions` call with additional fields does not increase rate limit consumption.

**Rate limits for GET /2/users/:id/tweets:** 10,000 per app / 900 per user per 15 minutes. Generous limits, but each call costs API credits on pay-per-use plans.

### Backward Compatibility

The jq transform adds new fields to the output JSON. Existing consumers that destructure specific fields are unaffected -- new fields are additive. The `community-manager` agent parses the `mentions` array by field name, so new fields are ignored until the agent instructions reference them.

### API Credit Impact

Adding `user.fields` and `tweet.fields` to the existing `fetch-mentions` request does not cost additional API credits -- these are query parameter expansions on the same request. The new `fetch-user-timeline` command is a separate API call per author. The agent should call it selectively (only for mentions that pass initial skip criteria), not for every mention.

### Research Insights: API Credit Impact

**Selective invocation strategy:**
1. Fetch mentions with enriched fields (single API call -- no additional cost)
2. Apply automated skip criteria (bot detection via followers/profile image, RT detection via referenced_tweets, conversation dedup)
3. For remaining mentions (those that passed automated checks), call `fetch-user-timeline` ONLY when the mention text or author handle does not provide enough signal for brand association risk
4. Expected calls per session: 0-3 `fetch-user-timeline` calls out of 10 mentions (most will be resolved by enriched mention data alone)

### OAuth Signature

The `get_request` helper already handles query parameter inclusion in OAuth signatures (learning `2026-03-10-x-api-oauth-get-query-params-in-signature.md`). Adding fields to the query string works without changes to the signing logic.

### Free Tier Fallback

In manual mode (Free tier 403 fallback), the enriched fields are not available because mentions are pasted by the user, not fetched from the API. The agent must handle absent metadata gracefully -- the approval prompt should display "N/A" for missing fields. The `fetch-user-timeline` command may also return 403 on Free tier; if so, skip the brand association check and note it in the approval prompt.

### Research Insights: Free Tier Fallback

**HTTP 402 vs. 403 (learning `2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md`):**
- X API may return HTTP 402 (Payment Required) when the account has $0 credits, in addition to 403 (client-not-enrolled).
- The `handle_response` function in `x-community.sh` currently handles 403 but not 402. The new `fetch-user-timeline` command should handle 402 the same as 403 for the agent's purposes -- skip the timeline check and delegate to human reviewer.
- Note: the existing `handle_response` falls through to the default `*` case for 402, which reports "HTTP 402" and exits 1. This is acceptable for `fetch-user-timeline` failures since the agent catches the non-zero exit and proceeds without timeline data.

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
- [ ] jq transform outputs `author_id` (string) per mention
- [ ] jq transform outputs `author_profile_image_url` (string or null) per mention
- [ ] jq transform outputs `author_followers_count` (number or 0) per mention
- [ ] jq transform outputs `referenced_tweets` (array or null) per mention
- [ ] New fields follow INDEX + `// fallback` pattern (not generator-style joins)
- [ ] New `fetch-user-timeline <user_id> [--max N]` command exists
- [ ] `fetch-user-timeline` validates `<user_id>` as a positive integer (`^[0-9]+$`)
- [ ] `fetch-user-timeline` validates `--max` with same clamping as `fetch-timeline` (5-100)
- [ ] `fetch-user-timeline` defaults to `--max 5` (not 10) to conserve API credits
- [ ] Script header comment updated with new command
- [ ] `main()` dispatch case updated for `fetch-user-timeline`

### community-manager.md Changes

- [ ] Step 2b added: explicit guardrails screening with skip criteria application before drafting
- [ ] Step 2b instructs selective `fetch-user-timeline` calls for brand association risk
- [ ] Step 2b skipped in headless mode (no API credit consumption for zero benefit)
- [ ] Step 3 includes conversation dedup guidance (group by `conversation_id`, one reply per thread)
- [ ] Step 3 auto-skips retweets (`referenced_tweets` type "retweeted")
- [ ] Step 4 approval prompt format includes follower count, profile image presence, mention type
- [ ] Absent metadata handled gracefully (display "N/A" when data unavailable, e.g., manual mode)
- [ ] Step numbering preserved (2b, not renumbered 3-7)

### Tests (test/x-community.test.ts)

- [ ] jq transform test JQ_TRANSFORM constant updated with new fields
- [ ] jq transform test updated to verify `author_id` field
- [ ] jq transform test updated to verify `author_profile_image_url` field
- [ ] jq transform test updated to verify `author_followers_count` field
- [ ] jq transform test updated to verify `referenced_tweets` field
- [ ] jq transform test covers missing `public_metrics` (fallback to 0)
- [ ] jq transform test covers missing `profile_image_url` (fallback to null)
- [ ] jq transform test covers missing `referenced_tweets` (fallback to null)
- [ ] jq transform test covers `referenced_tweets` with retweet type
- [ ] `fetch-user-timeline` argument validation tests (missing user_id, non-numeric user_id)
- [ ] `fetch-user-timeline --max` validation tests (non-numeric, out of range clamping)

## Test Scenarios

- Given a mention with a user who has `public_metrics` in the API response, when the jq transform runs, then `author_followers_count` equals the user's `followers_count`
- Given a mention with a user whose `public_metrics` is absent from the API response, when the jq transform runs, then `author_followers_count` defaults to 0
- Given a mention with a user who has `profile_image_url` in the API response, when the jq transform runs, then `author_profile_image_url` equals the URL string
- Given a mention with a user whose `profile_image_url` is absent, when the jq transform runs, then `author_profile_image_url` is null
- Given a mention that is a retweet, when the jq transform runs, then `referenced_tweets` contains an object with `type: "retweeted"`
- Given a mention that is a quote-tweet, when the jq transform runs, then `referenced_tweets` contains an object with `type: "quoted"`
- Given a mention with no `referenced_tweets` in the API response, when the jq transform runs, then `referenced_tweets` is null
- Given a mention whose author is missing from `includes.users`, when the jq transform runs, then `author_profile_image_url` is null and `author_followers_count` is 0 (INDEX fallback)
- Given `fetch-user-timeline` called without a user_id, when the command runs, then it exits 1 with a usage error
- Given `fetch-user-timeline` called with a non-numeric user_id, when the command runs, then it exits 1 with an error
- Given `fetch-user-timeline` called with `--max 200`, when the command runs, then the max is clamped to 100 with a warning
- Given `fetch-user-timeline` called with `--max 3`, when the command runs, then the max is clamped to 5 with a warning
- Given two mentions with the same `conversation_id`, when the agent applies conversation dedup, then only the most recent mention is drafted for reply
- Given a mention from a likely bot (0 followers, no profile image), when the agent applies skip criteria, then it recommends skipping with the reason displayed in the approval prompt
- Given a mention that is a retweet (`referenced_tweets` type "retweeted"), when the agent applies skip criteria in Step 2b, then it auto-skips with reason "RT is sufficient engagement"
- Given manual mode (Free tier 403 fallback), when the approval prompt renders, then missing metadata fields display "N/A"
- Given headless mode, when Step 2b runs, then `fetch-user-timeline` is NOT called

## Semver Intent

`semver:minor` -- new `fetch-user-timeline` command added to `x-community.sh`, enriched API response shape (additive), updated agent workflow.

## Files Changed

| File | Change |
|------|--------|
| `plugins/soleur/skills/community/scripts/x-community.sh` | Add `profile_image_url`, `public_metrics` to user.fields; add `referenced_tweets` to tweet.fields; update jq transform (add `author_id`, `author_profile_image_url`, `author_followers_count`, `referenced_tweets`); add `cmd_fetch_user_timeline` function; update header and dispatch |
| `plugins/soleur/agents/support/community-manager.md` | Add Step 2b (guardrails screening with selective `fetch-user-timeline`); add conversation dedup in Step 3; add RT auto-skip in Step 3; enrich Step 4 approval prompt format |
| `test/x-community.test.ts` | Update jq transform tests for new fields; add fallback coverage; add `fetch-user-timeline` validation tests |

## References

- Issue: #510
- PR #508 (merged) -- engagement guardrails added to brand guide
- Issue #503 (closed) -- original guardrails issue
- `plugins/soleur/skills/community/scripts/x-community.sh` -- target script, `cmd_fetch_mentions` at line 367
- `plugins/soleur/agents/support/community-manager.md` -- target agent, Capability 4 at line 247
- `test/x-community.test.ts` -- existing tests for jq transform and argument validation
- `knowledge-base/marketing/brand-guide.md` -- engagement guardrails at line 167
- `knowledge-base/features/learnings/2026-03-10-guardrails-must-match-observable-data.md` -- motivation
- `knowledge-base/features/learnings/2026-03-10-jq-generator-silent-data-loss.md` -- jq INDEX pattern requirement
- `knowledge-base/features/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md` -- 5-layer defense for new command
- `knowledge-base/features/learnings/2026-03-09-external-api-scope-calibration.md` -- selective API call strategy
- `knowledge-base/features/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` -- terse agent prompt updates
- `knowledge-base/features/learnings/2026-03-03-headless-mode-skill-bypass-convention.md` -- headless mode handling
- `knowledge-base/features/learnings/2026-03-10-x-api-oauth-get-query-params-in-signature.md` -- OAuth signing for GET query params
- `knowledge-base/features/learnings/2026-03-10-x-api-pay-per-use-billing-and-web-fallback.md` -- Free tier and 402 constraints
- X API v2 GET /2/users/:id/mentions -- confirmed field availability (profile_image_url, public_metrics, referenced_tweets)
- X API v2 GET /2/users/:id/tweets -- confirmed supports arbitrary user_id with OAuth 1.0a, 900 req/15min per user
