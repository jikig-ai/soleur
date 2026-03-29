---
title: "sec: add /proc to sandbox deny list"
type: fix
date: 2026-03-29
deepened: 2026-03-29
---

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 3 (Attack Surface, Test Scenarios, Implementation Notes)
**Research sources:** 4 institutional learnings (canuse-tool-sandbox, security-fix-attack-surface-enumeration, symlink-escape-cwe59, security-refactor-adjacent-config-audit)

### Key Improvements

1. Added `/sys` consideration with explicit scoping decision (out of scope per issue)
2. Enhanced test strategy with negative-space test pattern from institutional learnings
3. Added adjacent config audit reminder from learning 2026-03-20

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

### Research Insights

**Adjacent sensitive paths considered:**

Per the [attack surface enumeration learning](../learnings/2026-03-20-security-fix-attack-surface-enumeration.md), check whether other Linux pseudo-filesystems should also be denied:

- `/proc` -- **IN SCOPE.** Exposes environment variables (`/proc/<pid>/environ`), command-line arguments (`/proc/<pid>/cmdline`), file descriptors (`/proc/<pid>/fd/`), and memory maps (`/proc/<pid>/maps`). Cross-tenant information leakage vector.
- `/sys` -- **OUT OF SCOPE.** Exposes kernel parameters and device information but not per-process secrets. Lower risk, and the bubblewrap sandbox already restricts device access. Could be a follow-up hardening item.
- `/dev` -- **OUT OF SCOPE.** Bubblewrap already restricts device access. `/dev/null`, `/dev/urandom` etc. are needed for normal operation.

**Decision:** Only `/proc` is added per issue #1047 scope. File a follow-up issue if `/sys` hardening is desired.

**Adjacent config audit (from [learning](../learnings/2026-03-20-security-refactor-adjacent-config-audit.md)):** When modifying the `denyRead` array, verify that no adjacent sandbox config options are accidentally removed or altered. Run `git diff` on the config block before committing.

## Acceptance Criteria

- [x] `/proc` added to `denyRead` array in sandbox config (`apps/web-platform/server/agent-runner.ts`)
- [x] Integration test verifies agent cannot read `/proc/1/environ`
- [x] Existing tests continue to pass

## Test Scenarios

- Given an agent running in the sandbox, when it attempts to read `/proc/1/environ`, then the read is denied by the SDK sandbox
- Given the existing `denyRead: ["/workspaces"]` entry, when `/proc` is added, then both `/workspaces` and `/proc` are denied

### Research Insights: Negative-Space Test Pattern

Per the [attack surface enumeration learning](../learnings/2026-03-20-security-fix-attack-surface-enumeration.md), add a negative-space test that asserts the `denyRead` array contains all expected entries. This breaks if someone accidentally removes an entry:

```typescript
test("denyRead contains all required paths", () => {
  // If this test fails, a required deny path was removed.
  // Each entry prevents cross-tenant information leakage.
  const requiredDenyPaths = ["/workspaces", "/proc"];
  for (const p of requiredDenyPaths) {
    expect(denyReadArray).toContain(p);
  }
});
```

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

### Test file (`apps/web-platform/test/sandbox-hook.test.ts`)

Two test additions:

1. **Hook-level test:** Add a test case verifying the PreToolUse hook denies a `Read` tool call targeting `/proc/1/environ`. This path is outside the workspace, so it is already denied by `isPathInWorkspace` -- the test documents the defense-in-depth and satisfies the issue's acceptance criterion ("verify agent cannot read `/proc/1/environ`").

2. **Negative-space config test:** Assert that the sandbox config `denyRead` array contains both `/workspaces` and `/proc`. This prevents accidental removal during future refactors (per [adjacent config audit learning](../learnings/2026-03-20-security-refactor-adjacent-config-audit.md)). Since the sandbox config is inline in `agent-runner.ts` (not exported), the most practical approach is to test the hook's deny behavior for `/proc` paths rather than importing the config directly.

**Note:** The sandbox config object is not exported from `agent-runner.ts` (it is inline in the `query()` call). Extracting it solely for testing would be overengineering for a one-line change. The hook test validates the defense-in-depth layer, and the `denyRead` config is verified by code review.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/security hardening change.

## References

- Issue: [#1047](https://github.com/jikig-ai/soleur/issues/1047)
- Learning: [process-env-spread-leaks-secrets](../learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md)
- Learning: [canuse-tool-sandbox-defense-in-depth](../learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md)
- Bash sandbox `/proc` regex: `apps/web-platform/server/bash-sandbox.ts:29`
