# Tasks: Fix Weekly Analytics Snapshot

## Phase 1: Setup and Test Infrastructure

- [ ] 1.1 Read existing `scripts/weekly-analytics.sh` and `scripts/test-weekly-analytics.sh`
- [ ] 1.2 Add test cases for JSON validation (non-JSON response produces error)
- [ ] 1.3 Add test cases for WoW percentage computation (positive change, negative change, zero previous visitors, equal visitors)
- [ ] 1.4 Run tests -- new tests should FAIL (TDD red phase)

## Phase 2: Core Implementation -- JSON Validation

- [ ] 2.1 Add JSON validation to `api_get()` -- validate response body with `jq -e '.'` before returning
- [ ] 2.2 Include first 200 chars of non-JSON response in error message for debugging
- [ ] 2.3 Run tests -- JSON validation tests should PASS

## Phase 3: Core Implementation -- API v2 Migration

- [ ] 3.1 Add `api_post()` function for v2 POST endpoint (`/api/v2/query`) with JSON body parameter
  - Include JSON validation from Phase 2
  - Handle HTTP 401, 402, 429, non-2xx status codes
- [ ] 3.2 Migrate preflight check from v1 GET to v2 POST (same endpoint as data fetch)
- [ ] 3.3 Migrate aggregate data fetch from v1 `api_get` to v2 `api_post`
  - Current period: `{"site_id":"...","metrics":["visitors","pageviews"],"date_range":"7d"}`
  - Previous period: `{"site_id":"...","metrics":["visitors","pageviews"],"date_range":["<start>","<end>"]}`
- [ ] 3.4 Implement client-side WoW computation for visitors and pageviews
  - Division by zero guard when previous period has 0 visitors/pageviews
  - Empty/null handling for `VISITORS_CHANGE` and `PAGEVIEWS_CHANGE`
- [ ] 3.5 Migrate top pages breakdown from v1 to v2
  - Use `dimensions: ["event:page"]` with `order_by` and `pagination`
- [ ] 3.6 Migrate top sources breakdown from v1 to v2
  - Use `dimensions: ["visit:source"]` with `order_by` and `pagination`
- [ ] 3.7 Update all jq parse expressions for v2 response format
  - `results[0].metrics[N]` for aggregate
  - `results[].dimensions[0]` and `results[].metrics[0]` for breakdowns
- [ ] 3.8 Remove old `api_get()` function (now unused)
- [ ] 3.9 Run full test suite -- all tests should PASS

## Phase 4: Verification

- [ ] 4.1 Run `scripts/test-weekly-analytics.sh` -- all tests pass
- [ ] 4.2 Run `npx markdownlint-cli2 --fix` on any changed markdown files
- [ ] 4.3 Verify snapshot markdown format is unchanged by diffing a sample output against existing `2026-03-23-weekly-analytics.md`
