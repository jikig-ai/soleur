# Learning: GitHub Code Scanning API dismissed_reason format

## Problem

When dismissing CodeQL code scanning alerts via the GitHub API, using `dismissed_reason=false_positive` (with underscore) returns HTTP 422. The API requires space-separated values.

## Solution

Use the exact enum values with spaces, quoted in the shell:

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{N} \
  -X PATCH \
  -f state=dismissed \
  -f "dismissed_reason=false positive" \
  -f dismissed_comment="explanation"
```

Valid `dismissed_reason` values: `"false positive"`, `"won't fix"`, `"used in tests"`.

## Key Insight

The GitHub Code Scanning API uses space-separated enum values for `dismissed_reason`, not the snake_case format common in other GitHub APIs. Always check the error message — it lists valid values.

## Session Errors

**GitHub API dismissed_reason format error** — Used `false_positive` (underscore) instead of `"false positive"` (space). HTTP 422 returned with valid values listed. Recovery: retried with correct format. **Prevention:** The error message itself is self-documenting — check the API response body on 422 errors before retrying.

## Tags

category: integration-issues
module: github-api
