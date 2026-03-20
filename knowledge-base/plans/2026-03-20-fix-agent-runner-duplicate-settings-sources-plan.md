---
title: "fix: remove duplicate settingSources property in agent-runner.ts"
type: fix
date: 2026-03-20
---

# fix: remove duplicate settingSources property in agent-runner.ts

The TypeScript build for the Web Platform fails with:

```
apps/web-platform/server/agent-runner.ts:198
error TS2300: An object literal cannot have multiple properties with the same name.
```

This blocks the Web Platform Release CI pipeline on main (two consecutive failures: runs 23347249025 and 23346880998). No deploy can proceed until resolved.

## Root Cause

Two concurrent security PRs both added `settingSources: []` to the `query()` options object in `agent-runner.ts`:

1. **PR #904** (`0793128`) -- `fix(sec): add settingSources: [] to production agent-runner query()` -- added `settingSources: []` at line 191 with a defense-in-depth comment block.
2. **PR #903** (`d7e6e50`) -- `feat(sec): migrate sandbox enforcement from canUseTool to PreToolUse hooks` -- restored `settingSources: []` at line 198 during its review fixup ("Restore settingSources: [] removed during migration").

Both PRs were squash-merged to main independently. The second merge did not conflict because its `settingSources: []` landed at a different position in the options block. The result is two identical properties in the same object literal -- a TypeScript compilation error.

## Fix

Remove the **second** occurrence (line 198: bare `settingSources: [],`). The **first** occurrence (line 191) has the defense-in-depth comment block explaining the security rationale from PR #904, making it the canonical one.

### `apps/web-platform/server/agent-runner.ts`

```diff
         systemPrompt,
         env: buildAgentEnv(apiKey),
-        settingSources: [],
         disallowedTools: ["WebSearch", "WebFetch"],
```

## Acceptance Criteria

- [ ] `settingSources: []` appears exactly once in the `query()` options block
- [ ] The remaining instance retains the defense-in-depth comment (lines 188-191)
- [ ] `npx tsc --noEmit` passes for `apps/web-platform/`
- [ ] Next.js build (`next build`) succeeds
- [ ] Web Platform Release CI pipeline goes green on main

## Test Scenarios

- Given the fix is applied, when `npx tsc --noEmit` runs, then no TS2300 error is emitted
- Given the fix is applied, when the agent-runner `query()` call executes, then `settingSources` is `[]` (unchanged runtime behavior -- both values were identical)
- Given the fix is applied, when the Web Platform Release workflow triggers, then the Docker build step succeeds

## Context

- **File:** `apps/web-platform/server/agent-runner.ts:191,198`
- **Error:** TS2300 -- An object literal cannot have multiple properties with the same name
- **CI runs:** 23347249025, 23346880998 (both failed at Next.js build step)
- **Introduced by:** concurrent merge of PRs #903 and #904
- **Risk:** Zero -- removing a duplicate property with an identical value. No behavioral change.

## References

- PR #904 (added first `settingSources: []`): commit `0793128`
- PR #903 (added second `settingSources: []`): commit `d7e6e50`
- PR #891 (related sandbox security audit): commit `24de993`
