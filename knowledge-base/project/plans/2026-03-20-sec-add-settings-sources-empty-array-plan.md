---
title: "sec: add settingSources: [] to production agent-runner query()"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

# sec: add settingSources: [] to production agent-runner query()

## Enhancement Summary

**Deepened on:** 2026-03-20
**Research sources:** Claude Agent SDK documentation (Context7), project learnings, codebase analysis

### Key Findings from Research

1. **SDK v0.1.0+ defaults `settingSources` to `[]`** -- the current SDK version (`^0.2.80`) already does not load filesystem settings by default. This means production is NOT currently vulnerable; the fix is defense-in-depth hardening, not an active vulnerability patch.
2. **Explicit `settingSources: []` protects against SDK regression** -- if the SDK ever changes its default or someone adds `settingSources: ["project"]` for CLAUDE.md support, the explicit empty array makes the security intent visible in code review.
3. **`patchWorkspacePermissions()` remains valuable** -- even with `settingSources: []`, cleaning stale permissions from disk matters if `settingSources` is ever changed to load project settings.

### Risk Reclassification

The issue was filed as "settings-based bypass of canUseTool" which implies an active vulnerability. Research confirms this is a **defense-in-depth gap**, not an exploitable vulnerability in the current configuration. The priority remains valid (p3-low) but the urgency is lower than initially perceived.

## Overview

The production `agent-runner.ts` does not explicitly set `settingSources: []` in the `query()` call. While the SDK v0.1.0+ defaults to `[]` (no settings loaded), making the intent explicit is defense-in-depth: it prevents future regressions where someone adds `settingSources: ["project"]` for CLAUDE.md support without realizing this re-enables the `permissions.allow` bypass of `canUseTool`.

## Problem Statement

The SDK permission chain evaluates in order: (1) hooks, (2) deny rules, (3) permission mode, (4) allow rules from settings files, (5) canUseTool callback. Tools listed in `.claude/settings.json` `permissions.allow` are resolved at step 4 and never reach the `canUseTool` callback at step 5.

The existing `patchWorkspacePermissions()` function strips `Read`, `Glob`, `Grep` from workspace settings as a migration (#725), but:

1. It only removes a hardcoded set of tool names -- future pre-approvals written by agents or plugins are not covered
2. It runs per-session, creating a TOCTOU window (settings could be modified between patch and query)
3. The defense-in-depth principle requires preventing settings loading entirely, not just patching known entries

The test file (`canusertool-caching.test.ts:60`) correctly uses `settingSources: []`, but production does not. This was discovered during the security review of PR #881 (#876).

### Research Insights

**SDK Documentation (v0.1.0+ migration guide):**

- Before v0.1.0: settings loaded automatically from `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`
- After v0.1.0: `settingSources` defaults to `[]` -- no filesystem settings loaded unless explicitly requested
- Valid sources: `"user"` (global), `"project"` (`.claude/settings.json`), `"local"` (`.claude/settings.local.json`)
- Loading project settings (`settingSources: ["project"]`) also loads CLAUDE.md files and custom slash commands

**Security implication:** If this codebase ever needs CLAUDE.md support (e.g., for project-specific agent instructions), someone would naturally add `settingSources: ["project"]`. Without the explicit `settingSources: []` and its comment, that change would silently re-enable the `permissions.allow` bypass path. The explicit empty array with a security comment acts as a speed bump for that future change.

**Institutional learnings applied:**

- **CWE-22 path traversal learning:** "SDK `permissions.allow` bypasses `canUseTool`. This is architectural, not a bug -- the SDK evaluates allow rules before the callback. An overly permissive `permissions.allow` list silently disables your entire `canUseTool` security layer for those tools. Use `allow: []` and route everything through the callback."
- **Attack surface enumeration learning:** "When fixing or tightening a deny-by-default security boundary, enumerate ALL code paths that touch the same security surface." Applied here: verified no other `query()` calls exist in production code.
- **Defense-in-depth learning:** "Layered defense matters. Neither layer alone is sufficient." Applied: retain `patchWorkspacePermissions()` alongside `settingSources: []`.

## Proposed Solution

Add `settingSources: []` to the `query()` options in `apps/web-platform/server/agent-runner.ts`. This is a one-line change in the options object passed to `query()`, with a comment explaining the security rationale.

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
      // Prevent SDK from loading .claude/settings.json -- permissions.allow
      // entries bypass canUseTool entirely (permission chain step 4 before
      // step 5). Default is [] since SDK v0.1.0; explicit for defense-in-depth.
      settingSources: [],
      // ...
```

### Retain patchWorkspacePermissions()

Keep `patchWorkspacePermissions()` as defense-in-depth. Update its comment to explain the layered defense:

```typescript
// ---------------------------------------------------------------------------
// Workspace permissions migration (#725)
// Defense-in-depth layer 2: settingSources: [] (layer 1) prevents the SDK
// from loading settings files. This migration cleans stale pre-approvals
// from disk -- relevant if settingSources is ever changed to ["project"]
// for CLAUDE.md support.
// ---------------------------------------------------------------------------
```

### Edge Cases

- **Future CLAUDE.md support:** If project-level CLAUDE.md files become needed, the solution is NOT to add `settingSources: ["project"]` -- instead, load CLAUDE.md content separately and inject it via `systemPrompt`. This keeps the settings-file security boundary intact while still providing project-level instructions.
- **SDK version downgrade:** If the SDK is ever downgraded below v0.1.0 (unlikely), the explicit `settingSources: []` prevents the old behavior of auto-loading all settings.
- **Multiple `query()` calls:** The `sendUserMessage` function calls `startAgentSession` which contains the single `query()` call. There is only one `query()` call site in the codebase.

## Acceptance Criteria

- [x] `settingSources: []` is present in the `query()` options in `apps/web-platform/server/agent-runner.ts`
- [x] Inline comment explains the security rationale (permission chain step 4 bypass, defense-in-depth)
- [x] `patchWorkspacePermissions()` comment updated to explain layered defense relationship
- [x] Existing test (`canusertool-caching.test.ts`) continues to pass (skipped: requires ANTHROPIC_API_KEY, already uses settingSources: [])
- [x] No other `query()` calls in the codebase are missing `settingSources: []`

## Test Scenarios

- Given a workspace with `.claude/settings.json` containing `permissions.allow: ["Read"]`, when the agent session starts with `settingSources: []`, then the `canUseTool` callback fires for every `Read` invocation (not bypassed at step 4)
- Given a workspace with no `.claude/settings.json`, when the agent session starts with `settingSources: []`, then behavior is unchanged (no settings to load)
- Given a workspace where an agent writes new entries to `.claude/settings.json` `permissions.allow`, when a subsequent session starts with `settingSources: []`, then those entries are ignored

**Note on testing:** These scenarios are already covered by the existing `canusertool-caching.test.ts` which uses `settingSources: []`. No new tests are needed -- the existing test validates the behavior, and the production change aligns production with what's already tested.

## Context

- **Issue:** #895
- **Discovery:** Security review of PR #881 (#876)
- **SDK version:** `@anthropic-ai/claude-agent-sdk@^0.2.80` (post-v0.1.0, defaults to `settingSources: []`)
- **SDK docs:** <https://platform.claude.com/docs/en/agent-sdk/typescript> (settingSources), <https://platform.claude.com/docs/en/agent-sdk/migration-guide> (v0.1.0 change)
- **Learning:** `knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md`
- **Learning:** `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- **Learning:** `knowledge-base/project/learnings/2026-03-20-security-fix-attack-surface-enumeration.md`
- **File to modify:** `apps/web-platform/server/agent-runner.ts:179`
- **Reference pattern:** `apps/web-platform/test/canusertool-caching.test.ts:60`

## References

- Related issue: #895
- Prior security PRs: #881, #876, #725
- SDK documentation: <https://platform.claude.com/docs/en/agent-sdk/typescript>
- SDK migration guide: <https://platform.claude.com/docs/en/agent-sdk/migration-guide>
