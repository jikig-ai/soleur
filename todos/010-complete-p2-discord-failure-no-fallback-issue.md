---
status: pending
priority: p2
tags: [code-review, silent-failure, error-handling]
---

# Discord posting failure has no fallback issue

## Problem Statement

When Discord posting fails, the script prints a warning and continues. Unlike X/Twitter failures which create a fallback GitHub issue, Discord failures produce only an ephemeral log line. If the webhook is misconfigured, posts silently fail with no record.

## Findings

- **Location:** `scripts/content-publisher.sh:324`
- **Flagged by:** silent-failure-hunter
- X/Twitter has fallback issue creation on failure — Discord does not
- The asymmetry means Discord failures are invisible after CI logs scroll off

## Proposed Solutions

### Solution A: Create Discord fallback issue (Recommended)
Add a `create_discord_fallback_issue()` function matching the X fallback pattern.

- **Effort:** Small
- **Risk:** Low

## Acceptance Criteria

- [ ] Discord posting failure creates a GitHub issue with the content for manual posting
- [ ] Issue includes `action-required` and `content-publisher` labels
