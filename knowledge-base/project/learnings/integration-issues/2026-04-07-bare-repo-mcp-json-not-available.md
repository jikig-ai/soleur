# Learning: Bare repo .mcp.json not available to Claude Code

## Problem

Claude Code sessions started from a bare git repository root don't have MCP
servers (Playwright, etc.) available, even though `.mcp.json` is tracked in the
repo. The user encountered a GitHub OAuth `redirect_uri` error (#1784) and wanted
to fix it via Playwright browser automation, but Playwright MCP tools weren't
loaded.

Bare repos have no working tree — tracked files aren't checked out to disk.
Claude Code reads `.mcp.json` from CWD on startup to discover MCP servers.
If the file is missing or stale at the bare root, MCP servers silently fail
to start with no error surfaced to the user.

## Root Cause

The session-start workflow created worktrees and cleaned up merged branches but
never refreshed `.mcp.json` at the bare repo root. When `.mcp.json` was added or
updated in a feature branch and merged, the bare root copy was never updated.

## Solution

Added a session-start rule to AGENTS.md:

```bash
git show main:.mcp.json > .mcp.json
```

This extracts the latest tracked version from git into the bare root directory
so Claude Code reads it on the next session start. The rule is placed adjacent
to the existing worktree session-start rule.

## Key Insight

Bare repos need manual sync of CWD-read config files. Any tool that reads config
from the working directory (Claude Code reads `.mcp.json`, git reads `.gitconfig`,
etc.) will silently fail in a bare repo because tracked files aren't checked out.
This is a general pattern — when adopting a bare repo workflow, audit which tools
read config from CWD and add refresh steps for each.

## Session Errors

1. **Playwright MCP tools not available** — `.mcp.json` existed at bare root but
   was potentially stale or not read on startup. Prevention: the new session-start
   refresh rule ensures `.mcp.json` is always current.
2. **Attempted file reads at bare root paths** — tried to Read
   `apps/web-platform/app/api/auth/github-resolve/route.ts` directly, which
   doesn't exist in bare repos. Recovery: used `git show main:<path>` instead.
   Prevention: existing AGENTS.md rule already covers this ("bare repo — never
   run working-tree commands from the bare root").
3. **`gh api /app` returned 401** — no GitHub App JWT configured for CLI access.
   Recovery: investigated the code directly instead. Prevention: not actionable
   (App JWT auth is intentionally not configured for CLI).

## Tags

category: integration-issues
module: claude-code-mcp
severity: medium
date: 2026-04-07
