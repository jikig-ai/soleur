# Tasks: Enrich fetch-mentions API data for engagement guardrail enforcement

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/skills/community/scripts/x-community.sh` to confirm current `cmd_fetch_mentions` query params and jq transform
- [ ] 1.2 Read `plugins/soleur/agents/support/community-manager.md` to confirm Capability 4 structure (Steps 1-7)
- [ ] 1.3 Read `test/x-community.test.ts` to confirm existing jq transform test structure and assertion patterns
- [ ] 1.4 Read `knowledge-base/marketing/brand-guide.md` engagement guardrails section to confirm skip criteria

## Phase 2: Core Implementation -- x-community.sh

- [ ] 2.1 Enrich `cmd_fetch_mentions` query params
  - [ ] 2.1.1 Add `profile_image_url,public_metrics` to `user.fields` parameter (line 417)
  - [ ] 2.1.2 Add `referenced_tweets` to `tweet.fields` parameter (line 417)
- [ ] 2.2 Update jq transform (lines 437-456) to propagate new fields
  - [ ] 2.2.1 Add `author_profile_image_url: ($user.profile_image_url // null)` to output object
  - [ ] 2.2.2 Add `author_followers_count: (($user.public_metrics.followers_count) // 0)` to output object
  - [ ] 2.2.3 Add `referenced_tweets: (.referenced_tweets // null)` to output object
- [ ] 2.3 Add `cmd_fetch_user_timeline` function
  - [ ] 2.3.1 Accept required `<user_id>` positional argument with positive integer validation
  - [ ] 2.3.2 Accept optional `--max N` flag with same clamping logic as `cmd_fetch_timeline` (5-100)
  - [ ] 2.3.3 Call `get_request "/2/users/${user_id}/tweets"` with `tweet.fields=created_at,public_metrics,text`
  - [ ] 2.3.4 Return `jq '.data // []'` (same pattern as `cmd_fetch_timeline`)
- [ ] 2.4 Update script header comment to include `fetch-user-timeline <user_id> [--max N]` command
- [ ] 2.5 Update `main()` dispatch case to route `fetch-user-timeline` to `cmd_fetch_user_timeline`

## Phase 3: Core Implementation -- community-manager.md

- [ ] 3.1 Add conversation dedup guidance to Step 3 (Draft Replies)
  - [ ] 3.1.1 Insert grouping instruction before the existing bullet list: group by `conversation_id`, select most recent, skip rest
- [ ] 3.2 Add guardrails cross-reference between Step 2 and Step 3
  - [ ] 3.2.1 Add step or extend Step 2 to explicitly read `#### Engagement Guardrails` subsection
  - [ ] 3.2.2 Add skip criteria application: for each mention, check bot signals, off-topic, rage-bait, brand association risk, RT/QT before drafting
  - [ ] 3.2.3 For brand association risk checks, instruct agent to call `fetch-user-timeline <author_id>` selectively (not for every mention)
- [ ] 3.3 Enrich Step 4 approval prompt format
  - [ ] 3.3.1 Add follower count line (`Followers: <N>`)
  - [ ] 3.3.2 Add profile image presence indicator (`Profile image: yes/no`)
  - [ ] 3.3.3 Add mention type derived from `referenced_tweets` (`Type: original/reply/retweet/quote_tweet`)
  - [ ] 3.3.4 Handle absent metadata gracefully (display "N/A" for manual mode or missing data)

## Phase 4: Testing

- [ ] 4.1 Update jq transform test constant to include new fields in assertions
- [ ] 4.2 Add jq transform test: `author_profile_image_url` populated from `includes.users[].profile_image_url`
- [ ] 4.3 Add jq transform test: `author_followers_count` populated from `includes.users[].public_metrics.followers_count`
- [ ] 4.4 Add jq transform test: `referenced_tweets` populated when present in API response
- [ ] 4.5 Add jq transform test: `author_followers_count` defaults to 0 when `public_metrics` absent
- [ ] 4.6 Add jq transform test: `referenced_tweets` defaults to null when absent
- [ ] 4.7 Add jq transform test: `author_profile_image_url` defaults to null when absent
- [ ] 4.8 Add `fetch-user-timeline` argument validation tests
  - [ ] 4.8.1 Missing user_id exits 1 with usage error
  - [ ] 4.8.2 Non-numeric user_id exits 1 with error
  - [ ] 4.8.3 `--max` with non-numeric value exits 1
  - [ ] 4.8.4 `--max` out of range clamps with warning (reuse pattern from `cmd_fetch_timeline`)

## Phase 5: Verification

- [ ] 5.1 Run `bun test test/x-community.test.ts` to verify all tests pass
- [ ] 5.2 Verify `x-community.sh` help text includes `fetch-user-timeline`
- [ ] 5.3 Verify jq transform output shape matches documented JSON in plan
- [ ] 5.4 Run `skill: soleur:compound` to capture learnings
