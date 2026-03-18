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

Additionally, `canUseTool` may cache "allow" decisions per-tool-name within a session — only 1 callback invocation was observed despite 5 tool uses.

## Tags
category: integration-issues
module: agent-sdk
