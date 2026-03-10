# Tasks: X Monitoring Commands (Paid API Tier)

## Phase 1: Add fetch-mentions Command

- [ ] 1.1 Add `cmd_fetch_mentions` function to `x-community.sh`
  - [ ] 1.1.1 Resolve user ID via GET /2/users/me using existing `x_request`
  - [ ] 1.1.2 Build query params: `tweet.fields=created_at,author_id,public_metrics,text`
  - [ ] 1.1.3 Parse `--since` flag for `start_time` filtering
  - [ ] 1.1.4 Parse `--max` flag for `max_results` (default 10, clamp to 1-100)
  - [ ] 1.1.5 Sign GET request with query params (follow `cmd_fetch_metrics` pattern)
  - [ ] 1.1.6 Handle 403 with paid-access-required error message
  - [ ] 1.1.7 Format output as JSON array via jq
- [ ] 1.2 Add `fetch-mentions` to case dispatch in `main()`
- [ ] 1.3 Update usage text with `fetch-mentions` entry

## Phase 2: Add fetch-timeline Command

- [ ] 2.1 Add `cmd_fetch_timeline` function to `x-community.sh`
  - [ ] 2.1.1 Resolve user ID via GET /2/users/me
  - [ ] 2.1.2 Build query params: `tweet.fields=created_at,public_metrics,text`
  - [ ] 2.1.3 Parse `--max` flag for `max_results` (default 10, clamp to 1-100)
  - [ ] 2.1.4 Parse `--exclude` flag for excluding retweets/replies
  - [ ] 2.1.5 Sign GET request with query params
  - [ ] 2.1.6 Handle 403 with paid-access-required error message
  - [ ] 2.1.7 Format output as JSON array via jq
- [ ] 2.2 Add `fetch-timeline` to case dispatch in `main()`
- [ ] 2.3 Update usage text with `fetch-timeline` entry

## Phase 3: Update Community Agent and Skill

- [ ] 3.1 Update `community-manager.md` Scripts section with new commands
- [ ] 3.2 Update digest data collection to call `fetch-mentions` and `fetch-timeline`
- [ ] 3.3 Add 403 graceful fallback in digest workflow (warn and continue with fetch-metrics only)
- [ ] 3.4 Update health metrics to include mention count and timeline activity
- [ ] 3.5 Update `SKILL.md` script reference parenthetical

## Phase 4: Verification

- [ ] 4.1 Verify existing `fetch-metrics` and `post-tweet` commands unchanged
- [ ] 4.2 Test `fetch-mentions` with paid API access (manual)
- [ ] 4.3 Test `fetch-timeline` with paid API access (manual)
- [ ] 4.4 Verify 403 error message clarity without paid access
- [ ] 4.5 Run compound before commit
