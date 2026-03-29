---
title: "sec: add /proc to sandbox deny list"
type: fix
date: 2026-03-29
---

# sec: add /proc to sandbox deny list

All agent processes run as the same Linux user (UID 1001). A malicious agent could read `/proc/<pid>/` of another user's agent process to extract environment variables, file descriptors, memory maps, and command-line arguments. The SDK `denyRead` list currently blocks `/workspaces` (preventing cross-tenant workspace access) but not `/proc`.

## Proposed Solution

Add `/proc` to the `denyRead` array in the sandbox configuration at `apps/web-platform/server/agent-runner.ts`. This is a single-element addition to the existing array. The SDK's bubblewrap sandbox enforces `denyRead` at the OS level, so no application-layer path checking is needed -- the existing `denyRead: ["/workspaces"]` pattern already works.

### Attack Surface Enumeration

All code paths that touch the `/proc` security surface:

1. **SDK sandbox `denyRead`** (`agent-runner.ts:346`) -- OS-level bubblewrap enforcement. The fix targets this path.
2. **Bash `containsSensitiveEnvAccess`** (`bash-sandbox.ts:29`) -- defense-in-depth regex `/\/proc\/.*\/environ/` already blocks `/proc/*/environ` access via Bash commands. This is a separate, complementary layer.
3. **File-tool sandbox hook** (`sandbox-hook.ts:18-35`) -- `isPathInWorkspace` check denies file tools (Read, Glob, etc.) outside the workspace. `/proc` is outside any workspace, so file tools are already blocked by this layer.
4. **`canUseTool` callback** (`agent-runner.ts:376+`) -- defense-in-depth file-tool check for tools that bypass hooks. Also blocks `/proc` because it is outside the workspace.

**Gap analysis:** Path 1 is the only gap. Paths 2-4 already deny `/proc` access but are defense-in-depth layers, not the primary boundary. The SDK `denyRead` (bubblewrap) is the authoritative enforcement point -- adding `/proc` here closes the gap at the OS level.

## Acceptance Criteria

- [ ] `/proc` added to `denyRead` array in sandbox config (`apps/web-platform/server/agent-runner.ts`)
- [ ] Integration test verifies agent cannot read `/proc/1/environ`
- [ ] Existing tests continue to pass

## Test Scenarios

- Given an agent running in the sandbox, when it attempts to read `/proc/1/environ`, then the read is denied by the SDK sandbox
- Given the existing `denyRead: ["/workspaces"]` entry, when `/proc` is added, then both `/workspaces` and `/proc` are denied

## Context

- **Issue:** #1047
- **Roadmap:** Phase 2, item 2.6
- **Source:** CTO review -- one-line fix
- **Existing patterns:** `apps/web-platform/server/agent-runner.ts:344-347` (sandbox filesystem config), `apps/web-platform/test/bash-sandbox.test.ts` (env access test patterns), `apps/web-platform/test/sandbox-hook.test.ts` (hook deny/allow test patterns)

## Implementation Notes

### Code change (`apps/web-platform/server/agent-runner.ts`)

Change line 346 from:

```typescript
denyRead: ["/workspaces"],
```

to:

```typescript
denyRead: ["/workspaces", "/proc"],
```

### Test file

Add a test to verify the sandbox config includes `/proc` in `denyRead`. The test should validate the config structure rather than requiring a running bubblewrap sandbox (which is not available in CI). Pattern: import or reference the sandbox config and assert `/proc` is in the `denyRead` array.

For an integration-level test matching the issue requirement ("verify agent cannot read `/proc/1/environ`"), add a test case in `apps/web-platform/test/sandbox-hook.test.ts` that verifies the PreToolUse hook denies a `Read` tool call targeting `/proc/1/environ` (this path is outside the workspace, so it is already denied by the hook -- the test documents the defense-in-depth).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/security hardening change.

## References

- Issue: [#1047](https://github.com/jikig-ai/soleur/issues/1047)
- Learning: [process-env-spread-leaks-secrets](../learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md)
- Learning: [canuse-tool-sandbox-defense-in-depth](../learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md)
- Bash sandbox `/proc` regex: `apps/web-platform/server/bash-sandbox.ts:29`
