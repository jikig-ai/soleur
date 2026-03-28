---
module: community
date: 2026-03-28
problem_type: integration_issue
component: tooling
symptoms:
  - "jq: Argument list too long when passing paginated gh api output via --argjson"
  - "github-community.sh fetch-interactions fails on repos with many comments"
root_cause: config_error
resolution_type: code_fix
severity: medium
tags: [gh-api, paginate, jq, argument-list, shell-limits, community-monitor]
---

# Troubleshooting: gh api --paginate output exceeds shell argument limits

## Problem

When using `gh api --paginate` to fetch all issue comments, the output can exceed shell argument size limits (`ARG_MAX`). Passing the result to `jq` via `--argjson` in a command substitution fails with "Argument list too long."

## Environment

- Module: community (github-community.sh)
- Affected Component: `cmd_fetch_interactions()` in `github-community.sh`
- Date: 2026-03-28

## Symptoms

- `jq: Argument list too long` error when running `fetch-interactions 7` on a repo with many comments
- Only affects paginated endpoints returning large datasets; non-paginated commands with `per_page=100` work fine

## What Didn't Work

**Attempted Solution 1:** Store paginated output in a shell variable, then pass via `jq -n --argjson comments "$comments"`

- **Why it failed:** Shell variables can hold large strings, but passing them as arguments to `jq` via command-line `--argjson` exceeds `ARG_MAX` (typically ~2MB on Linux). The `issues/comments` endpoint returns the full comment body for every comment, making payloads large even with pagination merged via `jq -s 'add // []'`.

## Solution

Use a temp file instead of a shell variable. Write the paginated output to a temp file, then pass the file as an argument to `jq` (file input, not `--argjson`).

**Code changes:**

```bash
# Before (broken):
comments=$(gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" \
  --paginate 2>&1 | jq -s 'add // []') || { ... }
jq -n --argjson comments "$comments" '{ ... }'

# After (fixed):
tmpfile=$(mktemp)
if ! gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" \
  --paginate 2>/dev/null | jq -s 'add // []' > "$tmpfile"; then
  rm -f "$tmpfile"
  exit 1
fi
jq '{ ... }' "$tmpfile"
rm -f "$tmpfile"
```

## Why This Works

1. **Root cause:** Shell argument size limits (`ARG_MAX`) apply to the total size of arguments passed to a command. `jq -n --argjson key "$variable"` expands the variable into a command-line argument, which is subject to this limit.
2. **File input bypasses the limit:** When `jq` reads from a file argument (not `--argjson`), it reads the file via file I/O, not command-line argument expansion. No size limit applies.
3. **The existing `cmd_repo_stats()` uses `--argjson` for stargazers:** This works because stargazers are small (just login + date). But issue comments include full body text, making them orders of magnitude larger per item.

## Prevention

- When using `gh api --paginate` on endpoints that return large payloads (comments, PR reviews, file contents), always use temp files instead of shell variables + `--argjson`.
- The existing `gh api --paginate` learning (2026-03-24) covers the `jq -s 'add // []'` merge pattern but does not cover the argument-size issue. This learning extends it.
- Rule of thumb: if the API response includes user-generated content (comment bodies, PR descriptions), expect large payloads and use file-based `jq` input.

## Related Issues

- See also: [2026-03-24-gh-api-paginate-concatenated-arrays.md](../2026-03-24-gh-api-paginate-concatenated-arrays.md) -- pagination merge pattern
- See also: [2026-03-09-shell-api-wrapper-hardening-patterns.md](../2026-03-09-shell-api-wrapper-hardening-patterns.md) -- five-layer hardening
