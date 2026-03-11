---
status: pending
priority: p1
tags: [code-review, silent-failure, error-handling]
---

# Reply tweet stderr discarded via 2>/dev/null

## Problem Statement

In `scripts/content-publisher.sh` line 235, reply tweet failures suppress stderr with `2>/dev/null`, while the hook tweet (line 208) correctly captures stderr to a temp file for 402 detection. This means body tweet failures lose all diagnostic information — the partial thread issue gives zero indication of *why* it failed.

## Findings

- **Location:** `scripts/content-publisher.sh:235`
- **Flagged by:** silent-failure-hunter, architecture-strategist, performance-oracle, code-quality-analyst
- **Severity consensus:** CRITICAL (all 4 agents flagged this independently)
- Hook tweet captures stderr to temp file and inspects for 402 — correct pattern
- Reply tweets discard stderr entirely — incorrect pattern
- A 402 on tweet 2+ would be classified as generic partial-thread failure rather than payment-required

## Proposed Solutions

### Solution A: Mirror hook tweet pattern (Recommended)
Capture stderr to a temp file for reply tweets, matching the hook tweet pattern.

- **Pros:** Consistent error handling, enables 402 detection on body tweets, diagnostic info in fallback issues
- **Cons:** Slightly more temp file management
- **Effort:** Small
- **Risk:** Low

## Technical Details

- **Affected files:** `scripts/content-publisher.sh`
- **Line:** 235 (`reply_result=$(bash "$X_SCRIPT" post-tweet "${tweets[$i]}" --reply-to "$prev_id" 2>/dev/null)`)

## Acceptance Criteria

- [ ] Reply tweets capture stderr to temp file like hook tweet does
- [ ] 402 errors on body tweets create payment-required fallback issue (not generic partial-thread issue)
- [ ] Error text included in partial thread issue body for debugging
