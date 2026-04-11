# Learning: Stale main ref in bare repo and Playwright-first violation

## Problem

Two workflow gaps exposed during #1926 verification:

1. **Stale local main:** AGENTS.md session-start rule said to run `cleanup-merged` only "from any active worktree (not the bare repo root)". When starting at the bare root with no worktree, `git fetch` was skipped, leaving local main 40+ commits behind remote. This caused `git show main:<path>` to report files as nonexistent even though PR #1925 was merged.

2. **Playwright-first violation:** Agent labeled GitHub App permission changes as "manual" without attempting Playwright MCP first. The task was fully automatable — navigate to settings page, click dropdowns, save.

## Solution

### Gap 1: Stale main

Updated AGENTS.md session-start rule to remove the bare-root exclusion. The `worktree-manager.sh cleanup-merged` function already handles bare repos correctly (detects `IS_BARE`, runs `git fetch origin main:main` + `sync_bare_files`). The instruction was more restrictive than the script required.

Also added explicit ordering: `.mcp.json` refresh must happen *after* `cleanup-merged` has fetched main, since it reads from the local ref.

### Gap 2: Playwright-first

The Playwright-first rule already exists in AGENTS.md ("Browser tasks → Playwright MCP first"). The violation was a judgment error — the agent rationalized "needs org admin auth" as a reason to skip Playwright, when the correct behavior is to attempt Playwright and only hand off the auth step itself.

## Key Insight

Instructions that add restrictions beyond what the underlying tool requires create workflow gaps. The `cleanup-merged` script already handled bare repos, but the AGENTS.md rule artificially excluded them. Test instructions against the script's own guard clauses.

For Playwright-first: never pre-judge a browser task as "manual" based on assumed auth barriers. Attempt the automation, discover the barrier at runtime, hand off only the minimal blocked step (the login), then resume automation.

## Session Errors

1. **Stale local main ref** — `git show main:apps/web-platform/server/github-api.ts` returned fatal error because local main was 40+ commits behind remote. Recovery: `git fetch origin && git update-ref refs/heads/main origin/main`. **Prevention:** AGENTS.md rule updated to always run `cleanup-merged` (which fetches main) regardless of starting location.

2. **Explorer agent gave incorrect analysis** — Reported PR #1925 as "not merged" and files as "MISSING" because it read stale local main. Second agent incorrectly reported auto-approve reads as lacking audit logging when `canUseTool` already logs them. Recovery: Verified against actual code. **Prevention:** Consequence of error #1; fix propagates.

3. **Playwright-first violation** — Labeled GitHub App permission changes as "manual" without attempting Playwright. Recovery: User corrected, then successfully automated via Playwright (navigate, click 3 dropdowns, save). **Prevention:** The rule exists; this was a judgment error. Added to compound learning for reinforcement.

## Tags

category: workflow
module: AGENTS.md / worktree-manager.sh / Playwright
