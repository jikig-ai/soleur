---
module: agent-runner
date: 2026-04-10
problem_type: integration_issue
component: tooling
symptoms:
  - "Plausible MCP tools not registered for users without GitHub installation"
  - "Service tools nested inside GitHub-specific code block"
  - "Test passed but only because mock also lacked installation"
root_cause: scope_issue
resolution_type: code_fix
severity: high
tags: [mcp-tools, canUseTool, service-automation, scope-guard]
---

# Learning: Service tool registration must not be gated behind unrelated feature guards

## Problem

When adding Plausible API MCP tools to `agent-runner.ts`, the tool registration was placed inside the `if (installationId && repoUrl)` block that gates GitHub PR creation tools. This meant users with stored Plausible API keys but no GitHub installation (the majority of early users) would never get Plausible tools.

The bug was invisible in tests because the test for "Plausible tools not registered when no token" also had no GitHub installation in its mock, so the outer guard silently swallowed both conditions.

## Solution

Extract service tool registration (Plausible, future services) outside the GitHub installation guard. Build a shared `platformTools` array at the top level. GitHub PR tools push into it conditionally on `installationId`. Service tools push into it conditionally on their respective API keys. The MCP server is created once from all collected tools.

```typescript
// BEFORE (broken): Plausible nested inside GitHub gate
if (installationId && repoUrl) {
  // ... GitHub PR tool ...
  if (plausibleKey) {
    // Plausible tools — NEVER reached without GitHub installation
  }
}

// AFTER (fixed): Independent guards
const platformTools = [];
if (installationId && repoUrl) {
  // GitHub PR tool only
  platformTools.push(createPr);
}
if (plausibleKey) {
  // Plausible tools — independent of GitHub
  platformTools.push(...plausibleTools);
}
if (platformTools.length > 0) {
  mcpServersOption = { soleur_platform: createSdkMcpServer({ tools: platformTools }) };
}
```

## Key Insight

When adding new MCP tools to an existing tool registration block, verify each tool's prerequisites are independent. A tool that requires only an API key should not be gated behind a GitHub installation check just because the code structure puts it in the same block. Write a test that specifically validates the new tool works WITHOUT the existing block's prerequisites.

## Session Errors

1. **npx vitest stale cache** — Running `npx vitest` from the repo root picked up a stale global cache with missing native bindings. Recovery: Run from `apps/web-platform/` directory. **Prevention:** Always run vitest from the app directory, not the repo root.

2. **TypeScript type inference on heterogeneous tool array** — `[createPr]` inferred the specific schema type, making `push()` with differently-typed Plausible tools fail. Recovery: Used `Array<ReturnType<typeof tool<any>>>`. **Prevention:** When building arrays of SDK tools with different schemas, explicitly type the array to accept any tool definition.

3. **Connected services prompt leaked env var names** — System prompt showed `PLAUSIBLE_API_KEY: connected` instead of `Plausible: connected`. Recovery: Mapped through `PROVIDER_CONFIG` labels. **Prevention:** When injecting internal state into agent-visible prompts, always map internal identifiers to user-facing labels.

## Tags

category: integration-issues
module: agent-runner

## See Also

- `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` — canUseTool deny-by-default policy
- `knowledge-base/project/learnings/security-issues/2026-04-06-mcp-tool-canusertool-scope-allowlist.md` — MCP tool allowlist pattern
