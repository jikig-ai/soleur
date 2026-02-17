---
title: Playwright MCP screenshots write to main repo, not active worktree
date: 2026-02-17
category: workflow
tags: [playwright, worktree, screenshots, browser-testing, cleanup]
module: docs
symptoms: [screenshots-in-wrong-directory, playwright-mcp-in-main-repo, loose-png-files-in-repo-root]
---

# Playwright MCP Screenshots Write to Main Repo, Not Active Worktree

## Problem

When using Playwright MCP tools while working in a git worktree, screenshots land in the **main repository root**, not the active worktree directory. This happens in two ways:

1. **Auto-named screenshots** (no `filename` param): saved to `.playwright-mcp/` in the main repo root
2. **Custom-named screenshots** (with `filename` param like `desktop-homepage.png`): saved as loose files directly in the main repo root

Both are invisible to `git status` inside the worktree but clutter the main repo. In this session, 15 named audit screenshots (`desktop-homepage.png`, `mobile-nav-open.png`, `tablet-commands.png`, etc.) accumulated in the repo root unnoticed until after the PR was merged.

## Root Cause

Playwright MCP resolves its output directory relative to the project root (the git repository root), not the current working directory or active worktree. Since worktrees share the same `.git` reference, Playwright sees the main repo as the project root.

## Impact

- Loose `.png` files accumulate in the main repo root
- `.playwright-mcp/` directory fills with timestamped screenshots and logs
- Easy to miss during cleanup because `git status` in the worktree won't show them
- Can accidentally get committed if a future `git add .` is run from main

## Workaround

After completing browser-based visual verification, clean up **both** locations in the main repo:

```bash
# Clean auto-named screenshots and logs
rm /path/to/main-repo/.playwright-mcp/*.png
rm /path/to/main-repo/.playwright-mcp/*.log

# Clean custom-named screenshots from repo root
rm /path/to/main-repo/*.png  # review first with ls *.png to avoid deleting legitimate files
```

## Key Takeaway

Add screenshot cleanup to the post-merge checklist alongside worktree removal and branch deletion. Always check the main repo root for loose `.png` files after any Playwright-based visual verification session -- they will NOT appear in the worktree's `git status`.
