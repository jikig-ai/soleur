---
module: web-platform/agent-runner
date: 2026-04-06
problem_type: security_issue
component: canUseTool
symptoms:
  - "canUseTool blanket mcp__ prefix allow auto-approves all MCP tools"
  - "Future MCP servers would be auto-allowed without explicit review"
root_cause: overly_broad_allow_rule
severity: medium
tags: [canUseTool, mcp, security, defense-in-depth, agent-sdk]
synced_to: []
---

# Learning: Scope canUseTool MCP tool allow to registered tool names, not prefix

## Problem

When adding the first in-process MCP server tool (`create_pull_request` via `createSdkMcpServer`), the initial `canUseTool` implementation used a blanket prefix check:

```typescript
// WRONG: allows ANY tool with mcp__ prefix
if (toolName.startsWith("mcp__")) {
  return { behavior: "allow" as const };
}
```

This would auto-allow any future MCP server's tools without explicit review -- a latent privilege escalation vector. The existing `canUseTool` structure is meticulous about explicit allow-listing (file tools, Agent tool, safe tools each have their own block), and the blanket prefix broke that pattern.

Caught by 4 out of 6 review agents (security-sentinel, architecture-strategist, code-simplicity-reviewer, code-quality-analyst) as a P1 finding.

## Solution

Replace the blanket prefix check with an explicit allowlist check against the `platformToolNames` array, which already existed in the same scope:

```typescript
// CORRECT: only allows tools registered via mcpServersOption
if (platformToolNames.includes(toolName)) {
  log.info({ sec: true, toolName, agentId: options.agentID }, "MCP tool invoked");
  return { behavior: "allow" as const };
}
```

The `platformToolNames` array is populated only when the user has a GitHub App installation with a valid `repo_url`, and contains only the specific tool names registered via `createSdkMcpServer`. When no installation exists, the array is empty, and the check is a no-op.

## Key Insight

When extending `canUseTool` for new tool categories (MCP, future SDK extensions), always scope the allow-check to the specific registered tool names rather than a prefix or pattern. The `canUseTool` deny-by-default philosophy requires that every allowed tool be explicitly enumerated. A prefix-based allow rule is equivalent to a wildcard that grows silently as new tools are added.

This is the MCP-specific corollary to the existing sandbox defense-in-depth principle (see `2026-03-20-canuse-tool-sandbox-defense-in-depth.md`): each new tool category needs its own explicit allowlist, not a pattern match.

## Session Errors

**Blanket `mcp__` prefix allow in initial implementation** -- Recovery: Fixed during review phase by replacing `startsWith("mcp__")` with `platformToolNames.includes(toolName)`. Added test verifying unregistered MCP tools are denied. **Prevention:** When adding new tool categories to `canUseTool`, always check against an explicit allowlist variable, never a string prefix.

## Prevention

- When extending `canUseTool` for new tool categories, use an explicit allowlist (array `.includes()`) instead of prefix matching
- The `platformToolNames` pattern (populated conditionally, checked in `canUseTool`) is the template for future MCP tool additions
- Review agents catch this class of issue reliably -- always run `/soleur:review` before shipping security-sensitive `canUseTool` changes

## Cross-References

- [canUseTool sandbox defense-in-depth](../2026-03-20-canuse-tool-sandbox-defense-in-depth.md) -- the foundational sandbox learning this extends
- [GitHub #1648](https://github.com/jikig-ai/soleur/issues/1648) -- the feature that introduced MCP tools
- [GitHub #1661](https://github.com/jikig-ai/soleur/issues/1661) -- related: owner/repo format validation (P3)
- [GitHub #1662](https://github.com/jikig-ai/soleur/issues/1662) -- related: extract MCP tool definitions (P3)
