---
title: "Enumerate full attack surface when fixing security boundaries"
category: security
date: 2026-03-20
trigger: "Fixing or tightening a deny-by-default security boundary"
---

## Problem

When PR #873 emptied `permissions.allow` to route all file tools through `canUseTool`, the `SAFE_TOOLS` allowlist was not audited. `LS` and `NotebookRead` bypass `isPathInWorkspace` entirely because they are in `SAFE_TOOLS`. The security fix hardened one bypass path but left another unexamined.

This pattern -- fixing the reported vector without enumerating all code paths that touch the same security surface -- is how defense-in-depth gaps persist across fixes.

## Solution

Three practices to catch these proactively:

### 1. Enumerate the full attack surface, not just the reported vector

Before implementing a security fix, ask: "What are ALL the ways an agent can [read files / access network / execute code]?" List every code path, not just the one in the issue. A one-line prompt in the plan template forces this reframing.

### 2. Write negative-space tests

Instead of only testing "does the fix block the attack?", write a test that enumerates every tool/path and asserts it either routes through the security check or is explicitly documented as exempt:

```typescript
test("all tools with path args go through isPathInWorkspace", () => {
  const toolsWithPathArgs = ["Read", "Write", "Edit", "Glob", "Grep", "LS", "NotebookRead"];
  const checkedTools = getToolsRoutedThroughPathCheck();
  const exemptTools = SAFE_TOOLS_WITH_DOCUMENTED_JUSTIFICATION;
  for (const tool of toolsWithPathArgs) {
    expect(checkedTools.has(tool) || exemptTools.has(tool)).toBe(true);
  }
});
```

This breaks the moment someone adds a new file-accessing tool without a path check.

### 3. Audit allowlists when tightening deny-by-default

Any time you make a security boundary stricter, ask: "What bypasses this boundary?" Allowlists (`SAFE_TOOLS`, `permissions.allow`, env var allowlists) are explicit bypass mechanisms. Each item on every bypass list needs re-evaluation when the boundary it bypasses changes.

## References

- PR #884 (symlink escape fix)
- Issue #891 (LS/NotebookRead bypass tracking)
- Issue #877 (original symlink escape report)
