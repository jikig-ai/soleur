# Learning: Playwright MCP --isolated mode for parallel Claude Code sessions

## Problem

Multiple parallel Claude Code sessions fail when using Playwright MCP simultaneously:

```
Error: Browser is already in use for /home/jean/.cache/ms-playwright/mcp-chrome-59989f3,
use --isolated to run multiple instances of the same browser
```

The Playwright MCP plugin's default config (`~/.claude/plugins/marketplaces/.../playwright/.mcp.json`) launched `npx @playwright/mcp@latest` without `--isolated`, causing all sessions to fight over a singleton Chrome user-data-dir lock at `~/.cache/ms-playwright/mcp-chrome-*`.

## Solution

Created a project-level `.mcp.json` at the repo root with the `--isolated` flag:

```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--isolated"]
  }
}
```

Project-root `.mcp.json` takes precedence over plugin-cache defaults, so all Soleur users get isolated browser profiles on clone.

Also added an AGENTS.md hard rule: all workflow improvements must be committed to the repo, not stored in local-only locations. The litmus test: "If a new Soleur user clones this repo, do they get this improvement?"

## Key Insight

MCP server configurations that affect all users belong in the project-level `.mcp.json` (committed to the repo), not in local plugin caches or user-specific settings. This is the same principle as the existing rule about CC memory -- local-only knowledge is trapped knowledge. The `--isolated` flag was the technical fix, but the process fix was ensuring it lived in the repo.

## Tags

category: integration-issues
module: playwright-mcp
tags: playwright, mcp, parallel-sessions, browser-isolation, configuration
