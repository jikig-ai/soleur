# Learning: Plausible API JSON response validation bypass

## Problem

The weekly analytics GitHub Actions workflow failed on 2026-03-30 with `jq: parse error: Invalid numeric literal at line 1, column 10`. The Plausible Stats API returned a non-JSON response (plain-text "402 Payment Required") that bypassed all error handling in `api_get()` and crashed `jq`.

Two converging failures:

1. **Plausible subscription lost Stats API access** — API started returning HTTP 402
2. **`api_get()` validated HTTP status but not response body** — a 200-series response with non-JSON body would pass all checks and crash `jq`
3. **Preflight check used different parameters** than the actual data fetch (`period=day&metrics=visitors` vs `period=7d&metrics=visitors,pageviews&compare=previous_period`), so preflight passed while the actual fetch failed

## Solution

1. Added `validate_json_response()` shared function (outside `main()`, testable by test script) that uses `jq -e '.'` to validate response files and reports first 200 chars on failure
2. Integrated JSON validation into `api_get()` after HTTP status checks
3. Aligned preflight parameters to match actual data fetch
4. Added JSON validation to preflight response (not just HTTP status check)
5. 6 new test cases covering valid JSON, non-JSON text, empty files, HTML error pages, and error message content

## Key Insight

HTTP 200 does not guarantee JSON. Reverse proxies, WAF filters, and API gateways can return HTML/text error pages with 2xx status codes. Always validate response body structure independently from HTTP status. Preflight checks must use identical parameters as the calls they guard — parameter mismatch defeats the purpose.

## Prevention Strategies

- Validate response content structure (not just HTTP status) before parsing in all API integrations
- Align preflight checks with production call parameters — version them together
- Extract validation logic into shared, testable functions rather than inline checks
- Test with realistic error responses: plain-text errors, HTML proxy pages, empty bodies

## Related Documentation

- `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md`
- `knowledge-base/project/learnings/2026-03-13-plausible-goals-api-provisioning-hardening.md`
- `knowledge-base/project/plans/2026-03-13-feat-weekly-analytics-improvements-plan.md`
- GitHub issue #1360 — Migrate Plausible Stats API from v1 to v2 (deferred)

## Tags

category: runtime-errors
module: ci/weekly-analytics
