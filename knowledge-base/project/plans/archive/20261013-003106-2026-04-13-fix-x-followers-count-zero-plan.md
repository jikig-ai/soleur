---
title: "fix: X followers count showing 0 in community monitor"
type: fix
date: 2026-04-13
deepened: 2026-04-13
---

# fix: X followers count showing 0 in community monitor

The community monitor daily digest has been reporting 0 X/Twitter followers since
April 11, 2026. Previous digests showed 3 followers (April 6-9), then 1 (April 10),
then 0 (April 11 onward). The Bluesky follower count (5) is correct and growing
normally.

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** Root cause, proposed fix, acceptance criteria, test scenarios
**Research agents used:** WebSearch, WebFetch, Playwright MCP, X API live testing, GraphQL endpoint testing

### Key Improvements

1. Root cause corrected from "API returning bad data" to "account genuinely has 0 followers" -- verified via 3 independent sources (API v2, GraphQL, Playwright page snapshot)
2. Proposed fix changed from web scraping fallback (would not help) to detection heuristic with warning annotation in digest output
3. Added staleness detection for all zeroed-out metrics to catch silent API degradation in the future

### New Considerations Discovered

- X profile page shows "0 Followers" visually (verified via Playwright snapshot)
- X GraphQL endpoint (guest token, UserByScreenName) also returns `followers_count: 0`
- The profile page shows `@soleur_ai hasn't posted` despite `statuses_count: 67` in API -- posts exist but are not visible to unauthenticated viewers, which is normal X behavior for logged-out page views
- X migrated to pay-per-use pricing in Feb 2026 -- free-tier apps were migrated with a $10 voucher; this may or may not be related to the follower loss
- Web scraping cannot solve this since the web page itself shows 0

## Root Cause Analysis

### Investigation Method

Three independent verification paths were tested:

1. **X API v2 (authenticated):** `GET /2/users/me?user.fields=public_metrics` via
   production Doppler credentials (`prd_scheduled` config) -- returns `followers_count: 0`
2. **X GraphQL (guest token):** `UserByScreenName` endpoint with guest bearer token --
   returns `followers_count: 0` and `normal_followers_count: 0`
3. **X profile page (Playwright):** Navigated to `https://x.com/soleur_ai` and captured
   accessibility snapshot -- page displays "0 Followers" in the profile section

All three sources agree: the account has 0 followers. The API is returning accurate data.

### Conclusion

The community monitor is **correctly** reporting 0 followers. The account genuinely
lost its followers between April 9-11. Possible causes:

- **Spam account cleanup:** X periodically removes spam/bot accounts, which can reduce
  follower counts for small accounts disproportionately
- **Pay-per-use migration side effect:** X migrated free-tier API users to pay-per-use
  in February 2026. Unclear if this affects follower visibility
- **Organic unfollows:** With only 3 followers previously, all 3 unfollowing is plausible

**Timeline of the decline:**

| Date | X Followers | Bluesky Followers | Notes |
|------|-------------|-------------------|-------|
| Apr 6-9 | 3 | 3-4 | Normal |
| Apr 10 | 1 | 5 | Two unfollows in one day |
| Apr 11-13 | 0 | 5 | Last follower gone |

The script `plugins/soleur/skills/community/scripts/x-community.sh` function
`cmd_fetch_metrics` (lines 369-379) is working correctly.

## Proposed Fix

Since the API data is accurate, the fix is not about correcting the data but about
making the community monitor resilient to suspect metrics and providing better
diagnostics when metrics look anomalous.

### Approach: Anomaly Detection + Warning Annotation

1. **Anomaly detection in `cmd_fetch_metrics`:** After the API call, check if
   `followers_count` is 0 AND `tweet_count` is > 0 AND `following_count` is > 0.
   This combination (active account with zero followers) is unusual and worth flagging.
   When detected, emit a warning to stderr so the community monitor agent can
   include a diagnostic note in the digest.

2. **Add `_check_metrics_anomaly` function:** A pure detection function that takes
   the metrics JSON and returns 0 (anomaly detected) or 1 (normal). The function
   writes the anomaly description to stderr when triggered.

3. **Existing behavior preserved:** The `cmd_fetch_metrics` JSON output schema
   remains unchanged. The anomaly check is informational only (stderr) and does
   not modify stdout. This ensures the community monitor agent receives the data
   and can decide how to present it.

4. **Future-proofing:** The anomaly check also detects if ALL `public_metrics`
   values are 0 (which would indicate a genuine API degradation rather than
   organic unfollows). This catches the "soft degradation" scenario where X
   silently zeroes out metrics.

### Research Insights

**Best Practices (from learnings):**

- **Truncate API error responses** (`2026-03-26-truncate-api-error-responses`):
  Any warning or diagnostic output to stderr should truncate variable data to
  avoid leaking large responses in CI logs. Use `head -c 200` for safety.
- **Shell script defensive patterns** (`2026-03-13-shell-script-defensive-patterns`):
  The anomaly check function should follow the single-responsibility pattern
  and fail loudly on unknown conditions.

**X API Platform Context:**

- X migrated to pay-per-use pricing in February 2026, progressively rolling
  out to free-tier users. The `GET /2/users/me` endpoint with `public_metrics`
  works on both the legacy free tier and pay-per-use.
- The X syndication API (`cdn.syndication.twimg.com`) returns empty responses
  for profile data (tested live, returns 200 with 0 bytes).
- X.com is a React SPA; follower counts are not in static HTML but loaded
  via GraphQL. The GraphQL guest token approach confirms the count.

**Edge Cases:**

- Genuinely new account with 0 tweets and 0 followers: should not trigger warning
- Account suspended or restricted: API may return different error codes (401/403)
  rather than zeroed metrics
- All metrics zeroed out simultaneously: stronger signal of API degradation vs
  organic decline

### Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Purchase X API credits | May resolve if API-tier related | Ongoing cost, unlikely to fix since web page also shows 0 | Deferred -- issue #497 |
| Web scraping fallback | Zero cost | Web page also shows 0; would not help | **Rejected** (verified) |
| Anomaly detection + warning | Zero cost, informational, future-proof | Does not "fix" the count | **Selected** |
| Hardcode known follower count | Immediate visual fix | Defeats monitoring purpose | Rejected |
| Skip X metrics when suspect | Simple | Hides the problem | Rejected |

## Files to Modify

- `plugins/soleur/skills/community/scripts/x-community.sh` -- Add
  `_check_metrics_anomaly` function and call it from `cmd_fetch_metrics`

## Files to Create

None.

## Acceptance Criteria

- [x] When the X API returns `followers_count: 0` and `tweet_count > 0` and
  `following_count > 0`, a warning is emitted to stderr describing the anomaly
- [x] When the X API returns non-zero `followers_count`, no warning is emitted
- [x] When the X API returns all-zero `public_metrics`, a stronger warning is
  emitted to stderr indicating possible API degradation
- [x] The diagnostic warning is printed to stderr (not stdout) so it does
  not corrupt JSON output
- [x] The `cmd_fetch_metrics` output JSON schema is unchanged (same keys,
  same structure)
- [x] An account with `followers_count: 0`, `tweet_count: 0`, `following_count: 0`
  does not trigger a warning (genuinely new account)

## Test Scenarios

- Given an X API response with `followers_count: 0`, `tweet_count: 67`, and
  `following_count: 18`, when `cmd_fetch_metrics` runs, then a warning is
  emitted to stderr: "Warning: X API returned 0 followers for active account
  (67 tweets, 18 following). This may indicate unfollows, spam cleanup, or
  API degradation."
- Given an X API response with `followers_count: 5` and `tweet_count: 67`,
  when `cmd_fetch_metrics` runs, then no anomaly warning is emitted
- Given an X API response with `followers_count: 0`, `tweet_count: 0`, and
  `following_count: 0`, when `cmd_fetch_metrics` runs, then no warning is
  emitted (genuinely new/empty account)
- Given an X API response where all `public_metrics` values are 0 except
  `tweet_count: 67`, when `cmd_fetch_metrics` runs, then a warning is emitted
  mentioning possible API degradation
- Given `cmd_fetch_metrics` produces a warning on stderr, when the output is
  captured, then stdout contains valid JSON and stderr contains the warning text

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix with
no user-facing, financial, or operational changes. The existing issue #497
already tracks the X API tier upgrade decision.
