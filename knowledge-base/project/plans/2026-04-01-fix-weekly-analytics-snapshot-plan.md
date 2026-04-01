---
title: "fix: harden weekly analytics script against non-JSON API responses"
type: fix
date: 2026-04-01
semver: patch
---

# Fix Weekly Analytics Snapshot Workflow

## Overview

The "Scheduled: Weekly Analytics" workflow failed on 2026-03-30 ([run 23733883325](https://github.com/jikig-ai/soleur/actions/runs/23733883325)) with `jq: parse error: Invalid numeric literal at line 1, column 10`. The Plausible Stats API returned a non-JSON response that bypassed all existing error handling.

## Problem Statement / Motivation

Two distinct failures converged:

### Failure 1: Plausible subscription lost Stats API access

The Plausible API key (`PLAUSIBLE_API_KEY` in GitHub Actions secrets / Doppler `ci` config) now returns HTTP 402 on all Stats API endpoints (v1 and v2). This means the subscription plan no longer includes Stats API access. The March 23 snapshot succeeded; by March 30, access was gone.

### Failure 2: `api_get()` trusts HTTP status code but not response body

The existing `api_get()` function (lines 197-235 of `scripts/weekly-analytics.sh`) validates HTTP status codes (401, 402, 429, non-2xx) but never validates that the response body is valid JSON. When the API returned a non-JSON response with an HTTP status that passed the checks, `api_get` passed the raw content through to `jq`, which crashed.

The jq error `Invalid numeric literal at line 1, column 10` is consistent with a response body starting with `402 Payment Required` (a plain-text HTTP status line rather than JSON). This can happen when:

- A reverse proxy or CDN intercepts the request and returns a plain-text error
- The API server returns a non-JSON error body with an unexpected HTTP status code
- A transient API deployment issue serves plain-text instead of JSON

### Why the preflight check did not help

The script has a preflight check (lines 253-261) that catches HTTP 402 and exits gracefully. On March 30, this preflight passed (the script printed "Fetching Plausible analytics..." which is after the preflight). Then the actual `api_get` calls received a different response -- either the API behavior was inconsistent between the preflight and data-fetch calls, or a transient issue occurred.

## Proposed Solution

Three changes, in priority order:

### Change 1: Add JSON validation to `api_get()`

After the HTTP status check passes, validate the response body is valid JSON before returning it:

```bash
# After the existing HTTP status checks, before cat:
if ! jq -e '.' "$response_file" >/dev/null 2>&1; then
  echo "Plausible API returned non-JSON response for $url" >&2
  echo "Response (first 200 chars): $(head -c 200 "$response_file")" >&2
  rm -f "$response_file"
  exit 1
fi
```

This catches any response that passes HTTP checks but isn't parseable JSON -- the exact failure mode from March 30.

### Change 2: Migrate from API v1 to v2

Plausible's Stats API v1 is now [documented as legacy](https://plausible.io/docs/stats-api-v1), with the canonical API being [v2](https://plausible.io/docs/stats-api). While both v1 and v2 currently return 402 (subscription issue, not version issue), migrating to v2 prevents future v1 deprecation breakage.

**Key differences:**

| Aspect | v1 | v2 |
|--------|----|----|
| Method | GET with query params | POST with JSON body |
| Endpoint | `/api/v1/stats/aggregate`, `/api/v1/stats/breakdown` | `/api/v2/query` (single endpoint) |
| Compare | `compare=previous_period` parameter | Not available -- compute client-side |
| Response | `{"results": {"metric": {"value": N, "change": N}}}` | `{"results": [{"metrics": [N, N]}]}` |

**WoW comparison approach for v2:** Make two queries -- current 7d and previous 7d -- and compute percentage change in the script. This is more explicit and resilient than relying on the API's compare feature.

```bash
# Current period
CURRENT=$(api_post '{"site_id":"'"$PLAUSIBLE_SITE_ID"'","metrics":["visitors","pageviews"],"date_range":"7d"}')

# Previous period (7d before the current 7d)
PREV_END=$(date -u -d "$SNAPSHOT_DATE - 7 days" +%Y-%m-%d)
PREV_START=$(date -u -d "$SNAPSHOT_DATE - 13 days" +%Y-%m-%d)
PREVIOUS=$(api_post '{"site_id":"'"$PLAUSIBLE_SITE_ID"'","metrics":["visitors"],"date_range":["'"$PREV_START"'","'"$PREV_END"'"]}')

# Compute WoW change
CURRENT_VISITORS=$(echo "$CURRENT" | jq '.results[0].metrics[0]')
PREV_VISITORS=$(echo "$PREVIOUS" | jq '.results[0].metrics[0]')
if [[ "$PREV_VISITORS" -gt 0 ]]; then
  VISITORS_CHANGE=$(( (CURRENT_VISITORS - PREV_VISITORS) * 100 / PREV_VISITORS ))
else
  VISITORS_CHANGE=""
fi
```

**Breakdown queries** (top pages, top sources) use the `dimensions` parameter:

```bash
# Top pages
TOP_PAGES=$(api_post '{"site_id":"'"$PLAUSIBLE_SITE_ID"'","metrics":["visitors"],"date_range":"7d","dimensions":["event:page"],"order_by":[["visitors","desc"]],"pagination":{"limit":10}}')

# Top sources
TOP_SOURCES=$(api_post '{"site_id":"'"$PLAUSIBLE_SITE_ID"'","metrics":["visitors"],"date_range":"7d","dimensions":["visit:source"],"order_by":[["visitors","desc"]],"pagination":{"limit":10}}')
```

### Change 3: Improve preflight to match actual API calls

The current preflight (line 253) uses a different endpoint path and parameters than the actual data fetch. Align them:

- Use the same v2 POST endpoint that the data fetch uses
- Check both JSON validity and HTTP status
- Log the actual response on failure for debugging

## Technical Considerations

- **`api_post()` function:** The v2 API uses POST, so either rename `api_get` to `api_post` or add a new function. Since v2 uses a single endpoint with POST, a new `api_post()` that takes a JSON body is cleaner.
- **`set -euo pipefail` compliance:** The `$(...)` command substitution for `VISITORS_CHANGE` computation uses bash arithmetic. Guard against empty/null values from jq.
- **Backward compatibility:** The snapshot markdown format is unchanged -- same headings, same table structure. Only the data source (v2 vs v1) and internal computation (client-side WoW) change.
- **Preflight 402 graceful exit:** The existing behavior (exit 0 with informative message on 402) is correct and must be preserved. The script should not fail when the Plausible plan doesn't include Stats API.
- **Test script updates:** `scripts/test-weekly-analytics.sh` tests helper functions (`detect_phase`, `determine_status`, `append_trend_row`, `check_kpi_miss`). These are unaffected by the API migration. New tests should cover: (1) JSON validation in `api_post`, (2) WoW percentage computation edge cases (zero previous visitors, equal visitors, negative change).
- **jq response parsing:** v2 response format uses `results[0].metrics[N]` instead of `results.metric.value`. All jq expressions in the parse section must be updated.
- **Date range for previous period:** The v2 `date_range: "7d"` means "last 7 days including today." The previous period must not overlap. If today is April 1, current = March 26-April 1, previous = March 19-March 25. The `["start", "end"]` array format in v2 is inclusive on both ends. Verify this against the Plausible v2 docs during implementation.
- **Pageviews comparison:** The current script computes `PAGEVIEWS_CHANGE` for display. Either compute this client-side too (one additional jq extraction from the same query) or display pageviews without WoW change. The simpler approach: extract both visitors and pageviews from the same two queries and compute both changes.

## Acceptance Criteria

- [ ] `api_get()` (or `api_post()`) validates response body is valid JSON before returning
- [ ] Non-JSON responses produce a clear error message with the first 200 chars of the response body
- [ ] All API calls use Plausible Stats API v2 (`POST /api/v2/query`) instead of v1 GET endpoints
- [ ] WoW visitor change is computed client-side from two v2 queries (current 7d vs previous 7d)
- [ ] Preflight check uses the same v2 endpoint as data fetch calls
- [ ] HTTP 402 response still triggers graceful exit 0 with informative message (not a workflow failure)
- [ ] Snapshot markdown format is unchanged (same headings, tables, structure)
- [ ] `scripts/test-weekly-analytics.sh` passes with no regressions
- [ ] New test cases cover: JSON validation, WoW computation with zero previous visitors, WoW computation with negative change
- [ ] `set -euo pipefail` compliance maintained throughout

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CI/infrastructure script fix with no user-facing, marketing, legal, financial, or operational impact.

## Test Scenarios

- Given the API returns valid JSON with HTTP 200, when `api_post()` is called, then the JSON body is returned successfully
- Given the API returns non-JSON text (e.g., "402 Payment Required") with HTTP 200, when `api_post()` is called, then it exits 1 with an error message containing the first 200 chars of the response
- Given the API returns HTTP 402, when the preflight runs, then the script exits 0 with an informative message
- Given the API returns HTTP 401, when `api_post()` is called, then it exits 1 with an auth error message
- Given current week has 50 visitors and previous week had 40 visitors, when WoW is computed, then `VISITORS_CHANGE` is 25 (25% increase)
- Given current week has 30 visitors and previous week had 0 visitors, when WoW is computed, then `VISITORS_CHANGE` is empty (division by zero guard)
- Given current week has 10 visitors and previous week had 28 visitors, when WoW is computed, then `VISITORS_CHANGE` is -64 (64% decrease)
- Given the v2 aggregate query succeeds, when jq parses the response, then visitors and pageviews are extracted from `results[0].metrics[0]` and `results[0].metrics[1]`
- Given the v2 breakdown query for pages succeeds, when jq parses the response, then page paths are extracted from `results[].dimensions[0]` and visitor counts from `results[].metrics[0]`
- Given all existing `test-weekly-analytics.sh` tests, when the test script runs, then all pass without regression

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Plausible subscription does not include Stats API access | Preflight 402 check exits gracefully. Workflow succeeds with no snapshot. Manual action: restore Stats API access on the Plausible account. |
| v2 API response format changes | JSON validation catches non-JSON responses. jq expressions are explicit about the expected structure. |
| Client-side WoW computation introduces off-by-one in date ranges | Use explicit `["start", "end"]` date_range format for previous period. Test with known values. |
| v2 API does not support `compare=previous_period` | Already accounted for -- client-side computation replaces API comparison. |
| GitHub Actions secret `PLAUSIBLE_API_KEY` differs from Doppler | Both should be synchronized. Add a comment in the workflow noting the Doppler config source. |

## Files Modified

| File | Change |
|------|--------|
| `scripts/weekly-analytics.sh` | Replace `api_get()` with `api_post()` (POST + JSON body + JSON validation). Migrate all API calls from v1 GET to v2 POST. Compute WoW change client-side. Update jq expressions for v2 response format. Update preflight to use v2 endpoint. |
| `.github/workflows/scheduled-weekly-analytics.yml` | No changes needed (calls `bash scripts/weekly-analytics.sh` which handles everything). |
| `scripts/test-weekly-analytics.sh` | Add test cases for JSON validation, WoW computation edge cases. Existing tests remain unchanged. |

## References

- Failed workflow run: <https://github.com/jikig-ai/soleur/actions/runs/23733883325>
- Plausible Stats API v2 docs: <https://plausible.io/docs/stats-api>
- Plausible Stats API v1 (legacy): <https://plausible.io/docs/stats-api-v1>
- Original analytics plan: `knowledge-base/project/plans/2026-03-13-feat-weekly-analytics-improvements-plan.md`
- Script: `scripts/weekly-analytics.sh`
- Test script: `scripts/test-weekly-analytics.sh`
- Workflow: `.github/workflows/scheduled-weekly-analytics.yml`
