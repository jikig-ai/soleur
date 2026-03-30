# Learning: Plausible HTTP 402 Graceful Skip in CI Workflows

## Problem

The weekly analytics CI workflow (`scheduled-weekly-analytics.yml`) failed with HTTP 402 from the Plausible Stats API. The account is on the Growth plan ($9/mo) which does not include Stats API v1 access -- that requires the Business plan ($19/mo). The `provision-plausible-goals.sh` script had the same exposure. Both scripts treated any non-2xx response (except 401/429) as a hard failure (exit 1), triggering Discord failure notifications for what is actually a plan-tier limitation.

## Solution

Added preflight API access checks to both scripts that run outside `$()` command substitution:

- `scripts/weekly-analytics.sh`: preflight curl check before `api_get` calls; exits 0 on HTTP 402
- `scripts/provision-plausible-goals.sh`: preflight curl check before `api_request` calls; exits 0 on HTTP 401/402

The preflight pattern is necessary because both `api_get` and `api_request` are called inside `$()` (e.g., `RESULT=$(api_get "...")`), which creates a subshell. `exit 0` inside a subshell only exits the subshell -- the parent script continues with the error message text as the "response", causing jq parse failures downstream. The preflight runs in the main shell where `exit 0` terminates the script.

## Key Insight

Never rely on `exit 0` inside a bash function to gracefully terminate a script if that function is called inside `$()` command substitution. The `$()` creates a subshell where `exit` only exits the subshell. `exit 1` works because `set -e` catches it in the parent, but `exit 0` is invisible to `set -e`. For graceful-skip patterns, check the condition before entering `$()` or use a non-zero return code with explicit handling.

## Session Errors

- **Stale bare-repo read:** Read `expenses.md` from the bare repo root instead of the worktree, showing outdated data (`free-trial` instead of `active`). Caught before any wrong action was taken. **Prevention:** Already covered by AGENTS.md rule: "After merging a PR, always read files from the merged branch... rather than reading from the bare repo directory."
- **exit 0 in $() subshell:** First attempt (#1323) added `exit 0` inside `api_get` for 402 handling, but `api_get` is called inside `$()`. The`exit 0` only exited the subshell; the parent script continued with the error message as jq input, causing `jq: parse error`. Required a v2 fix with a preflight check outside`$()`. **Prevention:** When adding exit handlers to bash functions, trace all call sites to check if any use `$()` command substitution. If so, use a preflight check or non-zero return code pattern instead of `exit 0`.

## Tags

category: integration-issues
module: ci/plausible-analytics
