---
title: "Playwright browser cleanup on session exit"
date: 2026-04-03
category: workflow-issues
module: Playwright MCP / Hooks
problem_type: workflow_issue
severity: medium
tags: [playwright, browser, cleanup, hooks, stop-hook, resource-management]
---

# Playwright Browser Cleanup on Session Exit

## Problem

Playwright browser processes (Chrome instances launched via `--remote-debugging-pipe`) were left running after agent sessions completed browser automation tasks. The agent used Playwright MCP to navigate pages, click elements, and verify results, but never called `browser_close` before moving on to non-browser work. Orphaned Chrome processes accumulated, wasting system resources and potentially blocking parallel Claude Code sessions due to singleton user-data-dir locks.

## Root Cause

No enforcement mechanism existed to ensure browser cleanup. The agent's workflow had no rule requiring `browser_close` after Playwright tasks, and no safety net caught the gap at session exit. The `--isolated` flag in `.mcp.json` gives each session its own browser profile (preventing cross-session lock conflicts during the session) but does nothing to terminate the Chrome process when the session ends.

## Solution

Two complementary changes:

1. **AGENTS.md behavioral rule**: Hard rule requiring agents to call `browser_close` after completing any Playwright browser task, before moving on to non-browser work. This is primary prevention.

2. **Stop hook safety net** (`plugins/soleur/hooks/browser-cleanup-hook.sh`): Registered in `hooks.json` as a Stop hook alongside ralph-loop. Runs on every session exit, finds Chrome processes with `--remote-debugging-pipe` flag (unique to Playwright-managed Chrome), and kills them. Always exits 0 (never blocks session exit). Defense-in-depth for when the rule is missed.

## Key Insight

Agent tools that spawn persistent OS processes need both a behavioral rule (call cleanup when done) and a structural safety net (kill on exit). Neither alone is sufficient: the rule can be forgotten, and the hook only runs at session end. The pattern generalizes to any agent tool with long-lived child processes.

## Session Errors

1. **Playwright `browser_click` used wrong ref for modal button**: The "Set new avatar" modal overlay rendered new elements, but the agent clicked using a ref from the pre-modal snapshot (e335 was a footer link, not the modal button). Required fallback to `browser_run_code` with direct locator.
   - **Prevention:** After any action that changes page state (opening a modal, navigation), take a fresh `browser_snapshot` to get updated refs before interacting with new elements.

2. **Agent did not call `browser_close` after Playwright task**: After uploading the GitHub App logo and verifying on the public page, the agent moved to non-browser work without closing the browser.
   - **Prevention:** AGENTS.md rule now makes `browser_close` mandatory. Stop hook provides structural backstop.

## Prevention

- AGENTS.md hard rule loaded every turn via CLAUDE.md
- Stop hook runs automatically on every session exit
- `--isolated` flag in `.mcp.json` limits blast radius per session

## Related

- `knowledge-base/project/learnings/2026-04-02-playwright-mcp-isolated-mode-for-parallel-sessions.md` — singleton lock prevention
- `knowledge-base/project/learnings/2026-03-25-check-mcp-api-before-playwright.md` — MCP-first priority chain
- `knowledge-base/project/learnings/2026-03-30-pkce-magic-link-same-browser-context.md` — Chrome singleton lock recovery
