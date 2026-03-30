# Learning: Plausible HTTP 402 Graceful Skip in CI Workflows

## Problem

The weekly analytics CI workflow (`scheduled-weekly-analytics.yml`) failed with HTTP 402 from the Plausible Stats API. The account is on the Growth plan ($9/mo) which does not include Stats API v1 access -- that requires the Business plan ($19/mo). The `provision-plausible-goals.sh` script had the same exposure. Both scripts treated any non-2xx response (except 401/429) as a hard failure (exit 1), triggering Discord failure notifications for what is actually a plan-tier limitation.

## Solution

Added HTTP 402 handling to both scripts:

- `scripts/weekly-analytics.sh` `api_get()`: exit 0 with message explaining Stats API requires Business plan
- `scripts/provision-plausible-goals.sh` `api_request()`: exit 0 with message explaining endpoint requires higher plan

This matches the existing 401 graceful-skip pattern already in `provision-plausible-goals.sh`. Exit 0 prevents CI failure notifications; the informative message explains what was skipped and when it will auto-resolve.

## Key Insight

When integrating third-party APIs with tiered plans, map each non-2xx status code to either "code issue" (exit 1) or "account/config issue" (exit 0). Plan-tier restrictions (402) and authentication mismatches (401) are account issues that cannot be fixed by code changes -- they should skip gracefully, not alarm on-call.

## Session Errors

- **Stale bare-repo read:** Read `expenses.md` from the bare repo root instead of the worktree, showing outdated data (`free-trial` instead of `active`). Caught before any wrong action was taken. **Prevention:** Already covered by AGENTS.md rule: "After merging a PR, always read files from the merged branch... rather than reading from the bare repo directory."

## Tags

category: integration-issues
module: ci/plausible-analytics
