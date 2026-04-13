---
title: "fix: X followers count showing 0 in community monitor"
type: fix
date: 2026-04-13
---

# fix: X followers count showing 0 in community monitor

The community monitor daily digest has been reporting 0 X/Twitter followers since
April 11, 2026. Previous digests showed 3 followers (April 6-9), then 1 (April 10),
then 0 (April 11 onward). The Bluesky follower count (5) is correct and growing
normally, confirming the issue is X-specific.

## Root Cause Analysis

The X API v2 endpoint `GET /2/users/me?user.fields=public_metrics` is returning
`followers_count: 0` in its response. This was verified by calling the live API
directly with the production Doppler credentials (`prd_scheduled` config). The API
authenticates correctly and returns a valid JSON response with the correct username,
description, and tweet count -- but `followers_count` is 0.

**Timeline of the decline:**

| Date | X Followers | Bluesky Followers | Notes |
|------|-------------|-------------------|-------|
| Apr 6-9 | 3 | 3-4 | Normal |
| Apr 10 | 1 | 5 | Degradation begins |
| Apr 11-13 | 0 | 5 | Fully zeroed out |

**Likely cause:** X migrated free-tier API users to a pay-per-use credit model
(announced February 2026, rolled out progressively). Existing free-tier users
received a one-time $10 voucher. After credits are exhausted or during migration,
the API still returns HTTP 200 with valid JSON but zeroes out `public_metrics`
fields. This is a "soft degradation" -- no error, just silently inaccurate data.

The script `plugins/soleur/skills/community/scripts/x-community.sh` function
`cmd_fetch_metrics` (lines 369-379) correctly requests `user.fields=public_metrics`
and extracts `.data.public_metrics`. The script is not at fault -- the upstream API
is returning bad data.

## Proposed Fix

Add a web scraping fallback to `x-community.sh` that detects when the API returns
suspect metrics and falls back to scraping the public profile page for accurate
follower counts.

### Approach: Detect-and-Fallback in `cmd_fetch_metrics`

1. **Detection heuristic:** After the API call, if `followers_count` is 0 AND
   `tweet_count` is > 0, the data is suspect (an account with 67 tweets is
   extremely unlikely to have exactly 0 followers). This heuristic avoids
   false-triggering on genuinely new accounts.

2. **Web scraping fallback:** When suspect data is detected, fetch the public
   profile page at `https://x.com/<username>` and extract the follower count
   from the HTML. The profile page displays the real count regardless of API
   tier.

3. **Implementation in `x-community.sh`:**
   - Add a new function `_scrape_followers_count` that uses `curl` + HTML
     parsing to extract the follower count from the public profile page
   - Modify `cmd_fetch_metrics` to check the detection heuristic and call
     the scrape function when triggered
   - Merge the scraped value back into the JSON output
   - Print a diagnostic to stderr: "Warning: API returned 0 followers for
     account with N tweets. Using web scrape fallback."

4. **Graceful degradation:** If the scrape also fails (rate limiting, page
   structure change), keep the API value and warn on stderr. The monitor
   should not fail entirely because of a metrics accuracy issue.

### Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Purchase X API credits | Clean API fix, no scraping | Ongoing cost ($0.01/call), requires billing setup | Deferred -- existing issue #497 tracks this |
| Hardcode known follower count | Zero-cost | Immediately stale, defeats purpose of monitoring | Rejected |
| Use third-party API (Apify, etc.) | Reliable data | New vendor dependency, cost | Rejected |
| Web scrape fallback | Zero cost, uses public data | Fragile if page structure changes | **Selected** |
| Skip X metrics when suspect | Simple | Hides the problem | Rejected |

## Files to Modify

- `plugins/soleur/skills/community/scripts/x-community.sh` -- Add `_scrape_followers_count`
  function and detection logic in `cmd_fetch_metrics`

## Files to Create

None.

## Acceptance Criteria

- [ ] When the X API returns `followers_count: 0` and `tweet_count > 0`, the
  script falls back to web scraping and returns the actual follower count
- [ ] When the X API returns a non-zero `followers_count`, the script uses
  the API value without fallback (no behavior change)
- [ ] When the web scrape fallback fails, the script returns the API value
  and emits a warning to stderr
- [ ] The diagnostic warning is printed to stderr (not stdout) so it does
  not corrupt JSON output
- [ ] The `cmd_fetch_metrics` output JSON schema is unchanged (same keys,
  same structure)

## Test Scenarios

- Given an X API response with `followers_count: 0` and `tweet_count: 67`,
  when `cmd_fetch_metrics` runs, then the scrape fallback is triggered and
  a non-zero follower count is returned
- Given an X API response with `followers_count: 5` and `tweet_count: 67`,
  when `cmd_fetch_metrics` runs, then the API value is used directly (no
  scrape attempt)
- Given an X API response with `followers_count: 0` and `tweet_count: 0`,
  when `cmd_fetch_metrics` runs, then the API value is used (genuinely new
  account, no scrape needed)
- Given the scrape fallback fails (curl error or parse failure), when
  `cmd_fetch_metrics` runs, then the API value is returned with a warning
  on stderr

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix with
no user-facing, financial, or operational changes. The existing issue #497
already tracks the X API tier upgrade decision.
