---
title: "Bash integer validation for date parameters"
date: 2026-03-25
category: security-issues
module: community/scripts/github-community.sh
tags: [bash, input-validation, security, defense-in-depth]
issue: 1066
---

# Learning: Bash integer validation for date parameters

## Problem

`date_n_days_ago()` in `github-community.sh` passed the `days` parameter directly to GNU `date -d` without validation. GNU `date -d` accepts arbitrary natural-language strings (e.g., `"next week"`, `"tomorrow"`), so a non-numeric value silently produced an unexpected timestamp instead of failing with an error.

## Solution

Add a regex guard at the top of `date_n_days_ago()` before the `date` call:

```bash
date_n_days_ago() {
  local days="${1:-7}"
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo "Error: days must be a positive integer, got '${days}'" >&2
    exit 1
  fi
  date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
```

The pattern `^[0-9]+$` rejects empty strings, negative numbers, floats, and natural-language strings, accepting only non-negative integers.

## Key Insight

GNU `date -d` is intentionally permissive — it accepts a wide range of human-readable date strings. Any bash function that wraps `date -d` with a caller-supplied value is implicitly accepting arbitrary date expressions unless it validates first. The fix is a one-line regex guard.

## Session Errors

None detected.

## Tags
category: security-issues
module: community/scripts/github-community.sh
