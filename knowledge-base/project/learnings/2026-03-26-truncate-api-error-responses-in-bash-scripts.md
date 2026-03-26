# Learning: Truncate API error responses in bash scripts

## Problem
`github-community.sh` dumped full GitHub API responses to stderr on failure, e.g.:
```bash
echo "Error: Failed to fetch issues: ${issues}" >&2
```
In CI (publicly visible logs for public repos), a large or unexpected API response could expose internal details.

## Solution
Pipe each response variable through `head -c 200` before including it in the error message:
```bash
echo "Error: Failed to fetch issues ($(echo "$issues" | head -c 200))" >&2
```
Applied to all 7 API-response error lines in the file.

## Key Insight
When logging API error responses in shell scripts, always truncate to a fixed byte limit. Full responses can include stack traces, auth hints, or other details that shouldn't appear in shared logs. `head -c 200` is a safe, portable truncation idiom that works on both Linux and macOS.

## Session Errors
None.

## Tags
category: security-issues
module: community/github-community.sh
