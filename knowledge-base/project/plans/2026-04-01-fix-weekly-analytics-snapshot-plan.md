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

Two changes, targeted at the exact failure mode:

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

### Change 2: Align preflight with actual API calls

The current preflight (line 253) uses a different endpoint path and parameters than the actual data fetch. Align them:

- Use the same `/api/v1/stats/aggregate` endpoint with the same parameters as the actual data fetch
- Add JSON validity check to the preflight response
- Log the actual response on failure for debugging

### Deferred: Migrate from API v1 to v2

Plausible's Stats API v1 is [documented as legacy](https://plausible.io/docs/stats-api-v1), with the canonical API being [v2](https://plausible.io/docs/stats-api). However, v1 still works and has no announced sunset date. Migrating now would add significant complexity (new POST function, new response parsing, client-side WoW computation with date arithmetic) without fixing the actual bug. A tracking issue will be created to migrate when v1 is sunset.

## Technical Considerations

- **`validate_json_response()` function:** Extract JSON validation into a shared function (outside `main()`) so it can be tested independently by `test-weekly-analytics.sh`. The function takes a file path and context string, returns 0 for valid JSON, 1 for invalid.
- **`set -euo pipefail` compliance:** `validate_json_response` uses `return` (not `exit`) so callers control flow. `api_get()` calls `exit 1` on validation failure since it runs in `$()` subshells.
- **Preflight 402 graceful exit:** The existing behavior (exit 0 with informative message on 402) is correct and must be preserved. The script should not fail when the Plausible plan doesn't include Stats API.
- **Preflight alignment:** Current preflight uses `period=day&metrics=visitors` while actual fetch uses `period=7d&metrics=visitors,pageviews&compare=previous_period`. Align the preflight to use the same parameters as the actual fetch to catch the exact same failure modes.
- **Test script updates:** `scripts/test-weekly-analytics.sh` tests helper functions. New tests cover `validate_json_response`: valid JSON, non-JSON text, empty file, error message content.

## Acceptance Criteria

- [x] `api_get()` validates response body is valid JSON before returning
- [x] Non-JSON responses produce a clear error message with the first 200 chars of the response body
- [x] Preflight check uses the same v1 endpoint and parameters as the actual data fetch
- [x] Preflight check validates JSON response (not just HTTP status)
- [x] HTTP 402 response still triggers graceful exit 0 with informative message (not a workflow failure)
- [x] Snapshot markdown format is unchanged (same headings, tables, structure)
- [x] `scripts/test-weekly-analytics.sh` passes with no regressions
- [x] New test cases cover: JSON validation (valid, invalid, empty file, error message content)
- [x] `set -euo pipefail` compliance maintained throughout

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- CI/infrastructure script fix with no user-facing, marketing, legal, financial, or operational impact.

## Test Scenarios

- Given a file with valid JSON content, when `validate_json_response()` is called, then it returns 0
- Given a file with non-JSON text (e.g., "402 Payment Required"), when `validate_json_response()` is called, then it returns 1 with an error message containing the context string and the first 200 chars of the response
- Given an empty file, when `validate_json_response()` is called, then it returns 1
- Given the API returns HTTP 402, when the preflight runs, then the script exits 0 with an informative message
- Given the API returns HTTP 401, when `api_get()` is called, then it exits 1 with an auth error message
- Given all existing `test-weekly-analytics.sh` tests, when the test script runs, then all pass without regression

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Plausible subscription does not include Stats API access | Preflight 402 check exits gracefully. Workflow succeeds with no snapshot. Manual action: restore Stats API access on the Plausible account. |
| API response format changes | JSON validation catches non-JSON responses before jq parsing. |
| GitHub Actions secret `PLAUSIBLE_API_KEY` differs from Doppler | Both should be synchronized. Add a comment in the workflow noting the Doppler config source. |

## Files Modified

| File | Change |
|------|--------|
| `scripts/weekly-analytics.sh` | Add `validate_json_response()` shared function. Add JSON validation to `api_get()`. Align preflight parameters with actual fetch and add JSON validation. |
| `scripts/test-weekly-analytics.sh` | Add test cases for `validate_json_response()`. Existing tests remain unchanged. |

## References

- Failed workflow run: <https://github.com/jikig-ai/soleur/actions/runs/23733883325>
- Plausible Stats API v2 docs: <https://plausible.io/docs/stats-api>
- Plausible Stats API v1 (legacy): <https://plausible.io/docs/stats-api-v1>
- Original analytics plan: `knowledge-base/project/plans/2026-03-13-feat-weekly-analytics-improvements-plan.md`
- Script: `scripts/weekly-analytics.sh`
- Test script: `scripts/test-weekly-analytics.sh`
- Workflow: `.github/workflows/scheduled-weekly-analytics.yml`
