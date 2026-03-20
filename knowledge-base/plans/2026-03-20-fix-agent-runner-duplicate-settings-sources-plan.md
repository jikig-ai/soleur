---
title: "fix: remove duplicate settingSources property in agent-runner.ts"
type: fix
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Root Cause, Fix, Context, Test Scenarios)
**Research sources:** Claude Agent SDK docs (Context7), git history analysis, TypeScript compiler behavior, CI pipeline analysis

### Key Improvements
1. Added SDK documentation confirming `settingSources: []` is the default since v0.1.0 -- validates the defense-in-depth classification
2. Confirmed no other duplicate properties exist in the file or codebase
3. Documented that local `tsc --noEmit` cannot reproduce the error (no `node_modules` in worktree) -- verification must happen via CI or Docker build
4. Added process improvement note: concurrent security PRs touching the same options block should use dependent PR chains or be rebased sequentially

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

Both PRs were squash-merged to main independently. The second merge did not conflict because its `settingSources: []` landed at a different position in the options block (line 198 vs line 191, separated by 6 other properties). The result is two identical properties in the same object literal -- a TypeScript compilation error under `strict: true`.

### Research Insights

**SDK documentation confirms defense-in-depth classification:**

From the [Claude Agent SDK migration guide](https://platform.claude.com/docs/en/agent-sdk/migration-guide):

> AFTER (v0.1.0) - No settings loaded by default. `settingSources` defaults to `[]`.

The explicit `settingSources: []` is defense-in-depth against future SDK regression -- the SDK already defaults to `[]` since v0.1.0. Removing the duplicate does not change runtime behavior since: (a) both values are identical (`[]`), and (b) in JavaScript, the second property would silently shadow the first at runtime anyway.

**TypeScript strict mode enforcement:**

The `tsconfig.json` has `"strict": true`, which enables `--noImplicitAny`, `--strictNullChecks`, and other strict checks. TS2300 (duplicate properties) is always an error regardless of strict mode, but `next build` runs the TypeScript compiler as part of the build step, catching it during CI.

**Local reproduction not possible without dependencies:**

The worktree does not have `node_modules` installed (dependencies are installed inside the Docker build). Running `npx tsc --noEmit` locally produces a false positive ("ok") because it invokes a global/cached `tsc` without the project's type dependencies. Verification must happen via the CI pipeline's Docker build or by running `npm ci && npx tsc --noEmit` locally.

## Fix

Remove the **second** occurrence (line 198: bare `settingSources: [],`). The **first** occurrence (line 191) has the defense-in-depth comment block explaining the security rationale from PR #904, making it the canonical one.

### `apps/web-platform/server/agent-runner.ts`

```diff
         systemPrompt,
         env: buildAgentEnv(apiKey),
-        settingSources: [],
         disallowedTools: ["WebSearch", "WebFetch"],
```

**Verification:** After the fix, `settingSources` appears exactly twice in the file:
- Line 191: `settingSources: []` (the query option -- kept)
- Lines 27-29: comment block referencing `settingSources: []` in the `patchWorkspacePermissions` docstring (not code)

And once in the test file:
- `apps/web-platform/test/canusertool-caching.test.ts:60` (separate test fixture)

## Acceptance Criteria

- [ ] `settingSources: []` appears exactly once in the `query()` options block
- [ ] The remaining instance retains the defense-in-depth comment (lines 188-191)
- [ ] Next.js build (`next build`) succeeds in Docker (CI pipeline)
- [ ] Web Platform Release CI pipeline goes green on main
- [ ] No other duplicate properties exist in the `query()` options block (spot-checked: none found)

## Test Scenarios

- Given the fix is applied, when the Web Platform Release workflow triggers, then the Docker build step (`npm run build`) succeeds
- Given the fix is applied, when the agent-runner `query()` call executes, then `settingSources` is `[]` (unchanged runtime behavior -- both values were identical, and JS would shadow the first with the second anyway)
- Given the fix is applied, when `npm ci && npx tsc --noEmit` runs inside the Docker container, then no TS2300 error is emitted

### Edge Cases

- **No behavioral regression:** In JavaScript, when an object literal has duplicate keys, the last value wins silently. Both values are `[]`, so runtime behavior is identical before and after the fix.
- **Test file unaffected:** `canusertool-caching.test.ts` has its own `settingSources: []` in a separate options object -- not a duplicate.

## Context

- **File:** `apps/web-platform/server/agent-runner.ts:191,198`
- **Error:** TS2300 -- An object literal cannot have multiple properties with the same name
- **CI workflow:** `.github/workflows/web-platform-release.yml` triggers on push to main, calls `reusable-release.yml` which builds the Docker image (runs `next build` + `build:server`)
- **CI runs:** 23347249025, 23346880998 (both failed at Next.js build step)
- **Introduced by:** concurrent merge of PRs #903 and #904 to main
- **Risk:** Zero -- removing a duplicate property with an identical value. No behavioral change.
- **tsconfig:** `apps/web-platform/tsconfig.json` has `strict: true`, `target: ES2022`

### Process Improvement

This duplicate was introduced because two security PRs (#903, #904) both touched the `query()` options block in `agent-runner.ts` and were merged concurrently. The second merge's diff context did not overlap with the first's insertion point, so git did not detect a conflict. For future concurrent PRs touching the same function's option block, consider:

1. Using dependent PR chains (PR B based on PR A's branch) when both touch the same config block
2. Rebasing PR B after PR A merges before merging PR B
3. Running the full build step in CI before auto-merging (the Docker build would have caught this)

## References

- PR #904 (added first `settingSources: []`): commit `0793128`
- PR #903 (added second `settingSources: []`): commit `d7e6e50`
- PR #891 (related sandbox security audit): commit `24de993`
- [Claude Agent SDK - settingSources documentation](https://platform.claude.com/docs/en/agent-sdk/typescript)
- [Claude Agent SDK - v0.1.0 migration guide](https://platform.claude.com/docs/en/agent-sdk/migration-guide) -- confirms `settingSources` defaults to `[]`
