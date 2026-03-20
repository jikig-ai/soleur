# Learning: Agent SDK Spike — canUseTool Requires Empty Permissions

## Problem

When validating the Claude Agent SDK (`@anthropic-ai/claude-agent-sdk` v0.2.76) for use in a hosted web platform, the `canUseTool` callback was not firing despite being configured. The agent used Read, Glob, and Bash tools without the callback intercepting any of them.

## Solution

The `canUseTool` callback only fires for tools that are NOT pre-approved. Two sources of pre-approval silently bypass it:

1. **`allowedTools` option** in `query()` — explicitly auto-approves tools
2. **`.claude/settings.json`** with `permissions.allow` array — project-level pre-approval

To use `canUseTool` as a workspace sandbox (validating file paths), either:
- Remove tools from both `allowedTools` and `.claude/settings.json` permissions
- Or use `allowedTools` only for safe read-only tools and `canUseTool` for dangerous tools (Write, Edit, Bash)

## Key Insight

The Agent SDK's permission system has a priority chain: `allowedTools` > `.claude/settings.json` > `canUseTool` callback. If a tool is approved at a higher level, lower levels are never consulted. For a hosted web platform using `canUseTool` as a security boundary (workspace isolation), the workspace's `.claude/settings.json` must have empty permissions.

**Update (2026-03-20, #876):** The SDK does NOT cache `canUseTool` decisions. The "1 callback vs 5 tool uses" observation had two root causes: (1) pre-approved tools in `.claude/settings.json` bypass `canUseTool` at permission chain step 4, and (2) Claude Code's bridge auth handles permissions internally without invoking the callback. Under BYOK keys (web platform production), `canUseTool` fires for every tool invocation with a unique `toolUseID`. See `apps/web-platform/test/canusertool-caching.test.ts`.

## Tags
category: integration-issues
module: agent-sdk
