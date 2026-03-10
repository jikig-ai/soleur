# Tasks: X Monitoring Commands (Paid API Tier)

## Phase 1: Extract Shared Helpers

- [ ] 1.1 Extract `resolve_user_id` helper function in `x-community.sh`
  - [ ] 1.1.1 Call GET /2/users/me, return numeric ID via `jq -r '.data.id'`
  - [ ] 1.1.2 Exit with clear error if /2/users/me fails
- [ ] 1.2 Extract `get_request` helper function in `x-community.sh`
  - [ ] 1.2.1 Arguments: endpoint, query_params_string
  - [ ] 1.2.2 OAuth signing with query params via `oauth_sign`
  - [ ] 1.2.3 curl with stderr suppression and HTTP status capture
  - [ ] 1.2.4 Error dispatch: 401, 403 (with endpoint path in message), 429 (retry with depth limit), JSON validation on 2xx
- [ ] 1.3 Refactor `cmd_fetch_metrics` to use `get_request`
  - [ ] 1.3.1 Verify output is identical to pre-refactor

## Phase 2: Add fetch-mentions and fetch-timeline Commands

- [ ] 2.1 Add `cmd_fetch_mentions` function
  - [ ] 2.1.1 Resolve user ID via `resolve_user_id`
  - [ ] 2.1.2 Call `get_request` with `/2/users/{id}/mentions` and `tweet.fields=created_at,author_id,public_metrics,text`
  - [ ] 2.1.3 Parse `--since` flag for `start_time` filtering
  - [ ] 2.1.4 Parse `--max` flag for `max_results` (default 10, clamp to 1-100)
  - [ ] 2.1.5 Format output as JSON array; handle empty results as `[]`
- [ ] 2.2 Add `cmd_fetch_timeline` function
  - [ ] 2.2.1 Resolve user ID via `resolve_user_id`
  - [ ] 2.2.2 Call `get_request` with `/2/users/{id}/tweets` and `tweet.fields=created_at,public_metrics,text`
  - [ ] 2.2.3 Parse `--max` flag for `max_results` (default 10, clamp to 1-100)
  - [ ] 2.2.4 Format output as JSON array; handle empty results as `[]`
- [ ] 2.3 Add `fetch-mentions` and `fetch-timeline` to case dispatch in `main()`
- [ ] 2.4 Update usage text and file header comment with new commands

## Phase 3: Update Agent and Skill Docs

- [ ] 3.1 Update `community-manager.md` Scripts section with new commands
- [ ] 3.2 Add paid access note to X data collection section
- [ ] 3.3 Update `SKILL.md` script reference parenthetical

## Phase 4: Verification

- [ ] 4.1 Verify refactored `cmd_fetch_metrics` output is identical
- [ ] 4.2 Verify `post-tweet` unchanged
- [ ] 4.3 Test `fetch-mentions` with paid API access (manual)
- [ ] 4.4 Test `fetch-timeline` with paid API access (manual)
- [ ] 4.5 Verify 403 error includes endpoint path
- [ ] 4.6 Verify empty results return `[]`
- [ ] 4.7 Run compound before commit
