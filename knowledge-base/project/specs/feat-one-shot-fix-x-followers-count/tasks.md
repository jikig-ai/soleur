# Tasks: fix X followers count showing 0

## Phase 1: Setup

- [x] 1.1 Investigate root cause of 0 followers in community digest
- [x] 1.2 Verify X API response returns 0 followers_count directly
- [x] 1.3 Confirm issue is X API side (pay-per-use migration), not script parsing

## Phase 2: Core Implementation

- [ ] 2.1 Add `_scrape_followers_count` function to `x-community.sh`
  - [ ] 2.1.1 Fetch public profile page at `https://x.com/<username>` using curl
  - [ ] 2.1.2 Parse HTML to extract follower count (grep/sed pattern)
  - [ ] 2.1.3 Validate extracted value is a positive integer
  - [ ] 2.1.4 Return extracted count or empty string on failure
- [ ] 2.2 Add detection heuristic to `cmd_fetch_metrics`
  - [ ] 2.2.1 After API call, extract followers_count and tweet_count from response
  - [ ] 2.2.2 If followers_count == 0 AND tweet_count > 0, trigger fallback
  - [ ] 2.2.3 Call `_scrape_followers_count` with username from API response
  - [ ] 2.2.4 If scrape succeeds, merge scraped value into JSON output
  - [ ] 2.2.5 If scrape fails, keep API value and warn on stderr
  - [ ] 2.2.6 Emit diagnostic warning to stderr when fallback triggers

## Phase 3: Testing

- [ ] 3.1 Run `cmd_fetch_metrics` with live API to verify fallback triggers
- [ ] 3.2 Verify JSON output schema is unchanged
- [ ] 3.3 Verify stderr diagnostic does not corrupt stdout JSON
- [ ] 3.4 Test edge case: account with 0 tweets and 0 followers (no fallback)
