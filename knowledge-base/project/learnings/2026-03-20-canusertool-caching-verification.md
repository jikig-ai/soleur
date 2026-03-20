# Learning: canUseTool Does Not Cache — Bridge Auth Is a Separate Code Path

## Problem

The Agent SDK spike (#876) observed "only 1 canUseTool callback invocation despite 5 tool uses," raising concern that the SDK caches permission decisions per tool name, which would invalidate the canUseTool-based workspace sandbox.

## Solution

The SDK does NOT cache canUseTool results. Two independent factors caused the spike's observation:

1. **Pre-approved tools bypass canUseTool**: Tools listed in `allowedTools` or `.claude/settings.json` `permissions.allow` are resolved at permission chain step 4, before reaching `canUseTool` at step 5. The spike workspace had `["Read", "Glob", "Grep"]` pre-approved.

2. **Bridge auth bypasses canUseTool entirely**: When running under Claude Code's built-in authentication (no explicit `ANTHROPIC_API_KEY`), the bridge handles ALL permissions internally and never invokes the `canUseTool` callback. This is a completely separate code path from direct API key usage.

The web platform uses BYOK keys (not bridge auth), so `canUseTool` fires for every tool invocation in production.

## Key Insight

The SDK's permission chain has 5 steps: (1) hooks, (2) deny rules, (3) permission mode, (4) allow rules, (5) canUseTool. Each step can resolve a tool permission without consulting later steps. When testing canUseTool behavior, use `settingSources: []` to prevent settings.json from loading, and provide an explicit API key to avoid the bridge auth path.

Evidence that caching does not exist:
- Each canUseTool invocation receives a unique `toolUseID`
- The `suggestions` field externalizes caching to the host (SDK delegates persistence)
- The `updatedInput` response would be broken under caching (cached allow can't carry per-invocation input changes)
- Zero GitHub issues or changelog entries reference canUseTool caching
- SDK source decompilation (#162) shows no caching layer in the permission pipeline

Defense-in-depth recommendation: migrate sandbox enforcement from canUseTool (step 5) to PreToolUse hooks (step 1) for immunity to allowedTools, settings.json, and bypassPermissions mode.

## Session Errors

- Tests initially wrote a bridge-auth silent-pass path that passed with zero assertions — caught by all 5 review agents. Fix: gate on `ANTHROPIC_API_KEY` so the test skips rather than silently passes when it cannot verify its claim.
- `npx vitest` global cache broke with a rolldown native binding error — use local `./node_modules/.bin/vitest` instead.
- Cyrillic characters in branch name caused git pathspec issues — use proper quoting from worktree root.

## Tags
category: security-verification
module: agent-sdk
