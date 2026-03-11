---
status: pending
priority: p2
tags: [code-review, performance, reliability]
---

# Add inter-tweet delay in thread posting

## Problem Statement

The thread posting loop fires tweets with no delay between posts. X API has aggressive rate limits (50 tweets/day free tier). A burst of 429s could exhaust all retries before the rate limit window resets.

## Findings

- **Location:** `scripts/content-publisher.sh:234-248`
- **Flagged by:** performance-oracle
- x-community.sh handles 429 per-request with backoff, but retry depth resets between tweets

## Proposed Solutions

### Solution A: Add sleep 2 between successive tweets
- **Effort:** Small (one line)
- **Risk:** Low

## Acceptance Criteria

- [ ] `sleep 2` added between successive tweet posts in the thread loop
