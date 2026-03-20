---
title: "sec: add settingSources: [] to production agent-runner query()"
type: fix
date: 2026-03-20
---

# sec: add settingSources: [] to production agent-runner query()

## Overview

The production `agent-runner.ts` does not set `settingSources: []` in the `query()` call. If a workspace's `.claude/settings.json` contains `permissions.allow` entries, those tools bypass `canUseTool` entirely (permission chain step 4 before step 5). Adding `settingSources: []` prevents the SDK from loading any settings file, making the workspace sandbox immune to settings-based bypass.

## Problem Statement

The SDK permission chain evaluates in order: (1) hooks, (2) deny rules, (3) permission mode, (4) allow rules from settings files, (5) canUseTool callback. Tools listed in `.claude/settings.json` `permissions.allow` are resolved at step 4 and never reach the `canUseTool` callback at step 5.

The existing `patchWorkspacePermissions()` function strips `Read`, `Glob`, `Grep` from workspace settings as a migration (#725), but:

1. It only removes a hardcoded set of tool names -- future pre-approvals written by agents or plugins are not covered
2. It runs per-session, creating a TOCTOU window (settings could be modified between patch and query)
3. The defense-in-depth principle requires preventing settings loading entirely, not just patching known entries

The test file (`canusertool-caching.test.ts:60`) correctly uses `settingSources: []`, but production does not. This was discovered during the security review of PR #881 (#876).

## Proposed Solution

Add `settingSources: []` to the `query()` options in `apps/web-platform/server/agent-runner.ts`. This is a one-line change in the options object passed to `query()`.

### apps/web-platform/server/agent-runner.ts

```typescript
// Current (line 179):
    options: {
      cwd: workspacePath,
      model: "claude-sonnet-4-6",
      permissionMode: "default",
      // ...

// Fixed:
    options: {
      cwd: workspacePath,
      model: "claude-sonnet-4-6",
      permissionMode: "default",
      settingSources: [],
      // ...
```

### Retain patchWorkspacePermissions()

Keep `patchWorkspacePermissions()` as defense-in-depth. If `settingSources` is ever accidentally removed or the SDK changes default behavior, the patch still protects against known pre-approvals. Add a code comment explaining the layered defense.

## Acceptance Criteria

- [ ] `settingSources: []` is present in the `query()` options in `apps/web-platform/server/agent-runner.ts`
- [ ] `patchWorkspacePermissions()` is retained with a comment explaining defense-in-depth layering
- [ ] Existing test (`canusertool-caching.test.ts`) continues to pass
- [ ] No other `query()` calls in the codebase are missing `settingSources: []`

## Test Scenarios

- Given a workspace with `.claude/settings.json` containing `permissions.allow: ["Read"]`, when the agent session starts with `settingSources: []`, then the `canUseTool` callback fires for every `Read` invocation (not bypassed at step 4)
- Given a workspace with no `.claude/settings.json`, when the agent session starts with `settingSources: []`, then behavior is unchanged (no settings to load)
- Given a workspace where an agent writes new entries to `.claude/settings.json` `permissions.allow`, when a subsequent session starts with `settingSources: []`, then those entries are ignored

## Context

- **Issue:** #895
- **Discovery:** Security review of PR #881 (#876)
- **Learning:** `knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md`
- **Learning:** `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- **File to modify:** `apps/web-platform/server/agent-runner.ts:179`
- **Reference pattern:** `apps/web-platform/test/canusertool-caching.test.ts:60`

## References

- Related issue: #895
- Prior security PRs: #881, #876, #725
