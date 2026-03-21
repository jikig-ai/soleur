# Learning: Depth-Limited API Retry Pattern

## Problem

The `discord_request` function in `discord-community.sh` and `discord-setup.sh` handled HTTP 429 (rate limit) responses by recursively calling itself after sleeping for the `retry_after` duration. This recursion had no depth limit -- under sustained rate limiting (e.g., a Discord API outage returning 429 on every attempt), the function would recurse indefinitely until hitting a shell stack overflow. The `x_request` function in `x-community.sh` already had this pattern solved with a `depth` parameter, but the Discord scripts were written without it.

## Solution

Added a `depth` parameter to `discord_request` in both scripts (default 0), with a max retry count of 3 -- matching the existing `x_request` convention. When the limit is reached, the function prints a clear error to stderr and exits with code 2. The retry log message now includes `(attempt N/3)` for observability. A missing jq fallback (`|| echo "5"`) was also added to `discord-community.sh` to handle cases where `retry_after` parsing fails entirely.

Key changes per file:

- `discord-community.sh`: Added `depth` param, depth guard, jq fallback, attempt logging, recursive depth propagation.
- `discord-setup.sh`: Added `depth` param, depth guard, attempt logging, recursive depth propagation. (This file already had a manual `retry_after` fallback.)

## Key Insight

Recursive retry is unbounded by default. Any function that handles transient errors by calling itself must accept a depth parameter with an explicit ceiling. The pattern is simple -- add `local depth="${N:-0}"`, guard with `if (( depth >= MAX ))`, and propagate `"$((depth + 1))"` on each recursive call -- but it is easy to forget when the retry logic is the "happy path" that rarely fires. When adding API integration scripts, audit all recursive retry paths before merging. If one integration already has the pattern (as `x_request` did here), treat it as the template for all others.

## Session Errors

1. shellcheck not installed -- gracefully skipped verification step
2. Plan subagent format mismatch -- handled via fallback extraction path

## Tags

category: logic-errors
module: community
symptoms: stack-overflow, rate-limit-loop, unbounded-recursion
