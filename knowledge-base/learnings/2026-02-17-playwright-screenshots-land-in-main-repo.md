---
title: Playwright MCP screenshots write to main repo, not active worktree
date: 2026-02-17
category: workflow
tags: [playwright, worktree, screenshots, browser-testing]
module: docs
symptoms: [screenshots-in-wrong-directory, playwright-mcp-in-main-repo]
---

# Playwright MCP Screenshots Write to Main Repo, Not Active Worktree

## Problem

When using Playwright MCP tools (browser_take_screenshot, browser_snapshot) while working in a git worktree, screenshots and console logs are saved to `.playwright-mcp/` in the main repository root, not in the active worktree directory.

## Root Cause

Playwright MCP resolves its output directory relative to the project root (the git repository root), not the current working directory or active worktree. Since worktrees share the same `.git` reference, Playwright sees the main repo as the project root.

## Impact

- Screenshots accumulate in the main repo and show up as untracked files on `git status`
- Must manually clean `.playwright-mcp/` after visual verification sessions
- Screenshots are not co-located with the worktree branch they belong to

## Workaround

After completing browser-based visual verification in a worktree session, clean up the screenshots directory in the main repo:

```bash
rm /path/to/main-repo/.playwright-mcp/*.png
rm /path/to/main-repo/.playwright-mcp/*.log
```

## Key Takeaway

When using Playwright MCP for visual verification during worktree-based development, remember to clean `.playwright-mcp/` in the main repo as part of post-merge cleanup. Add this to the mental checklist alongside worktree removal and branch deletion.
