# Tasks: X Monitoring Commands (Paid API Tier)

## Phase 1: Extract Shared Helpers

- [ ] 1.1 Extract `get_request` helper function in `x-community.sh` (define before `resolve_user_id`)
  - [ ] 1.1.1 Arguments: `endpoint` `query_params` `depth` (all with `${N:-}` guards)
  - [ ] 1.1.2 OAuth signing: split query_params on `&`, pass as varargs to `oauth_sign`
  - [ ] 1.1.3 curl with stderr suppression (`2>/dev/null`) and HTTP status capture (`-w "\n%{http_code}"`)
  - [ ] 1.1.4 Error dispatch: 401, 403 (parse `reason` field: `client-not-enrolled` vs `official-client-forbidden`), 429 (retry with depth limit max 3), JSON validation on 2xx
  - [ ] 1.1.5 Handle empty query_params gracefully (no `?` appended to URL)
- [ ] 1.2 Extract `resolve_user_id` helper function
  - [ ] 1.2.1 Call `get_request "/2/users/me" ""`
  - [ ] 1.2.2 Return numeric ID via `jq -r '.data.id'`
  - [ ] 1.2.3 Validate returned ID is numeric (`[[ "$user_id" =~ ^[0-9]+$ ]]`)
  - [ ] 1.2.4 Exit with clear error if /2/users/me fails or returns non-numeric ID
- [ ] 1.3 Refactor `cmd_fetch_metrics` to use `get_request`
  - [ ] 1.3.1 Verify output JSON is identical to pre-refactor

## Phase 2: Add fetch-mentions and fetch-timeline Commands

- [ ] 2.1 Add `cmd_fetch_mentions` function
  - [ ] 2.1.1 Resolve user ID via `resolve_user_id`
  - [ ] 2.1.2 Call `get_request` with `/2/users/{id}/mentions` and `tweet.fields=created_at,author_id,public_metrics,text`
  - [ ] 2.1.3 Parse `--since` flag for `start_time` filtering (ISO 8601)
  - [ ] 2.1.4 Parse `--max` flag for `max_results` (default 10, clamp to **5-100** per API schema)
  - [ ] 2.1.5 Format output via `jq '.data // []'` (data field absent when zero results)
- [ ] 2.2 Add `cmd_fetch_timeline` function
  - [ ] 2.2.1 Resolve user ID via `resolve_user_id`
  - [ ] 2.2.2 Call `get_request` with `/2/users/{id}/tweets` and `tweet.fields=created_at,public_metrics,text`
  - [ ] 2.2.3 Parse `--max` flag for `max_results` (default 10, clamp to **5-100**)
  - [ ] 2.2.4 Format output via `jq '.data // []'`
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
- [ ] 4.5 Verify 403 error includes endpoint path and `reason` field
- [ ] 4.6 Verify empty results (absent `data` field) return `[]`
- [ ] 4.7 Verify `--max` below 5 is clamped with warning
- [ ] 4.8 Verify `resolve_user_id` validates numeric ID
- [ ] 4.9 Run compound before commit
