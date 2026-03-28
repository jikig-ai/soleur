---
title: "fix: match local TypeScript strictness to CI Docker build"
type: fix
date: 2026-03-28
issue: "#1225"
deepened: 2026-03-28
---

# fix: match local TypeScript strictness to CI Docker build

## Enhancement Summary

**Deepened on:** 2026-03-28
**Sections enhanced:** 5
**Research sources:** 6 project learnings, TypeScript docs, Vitest API, lefthook glob semantics

### Key Improvements

1. Refined `process.env.NODE_ENV` fix strategy -- `vi.stubEnv` for simple cases, `Record<string, string | undefined>` cast for loop-based assignments in agent-env.test.ts
2. Added lefthook glob caveat from documented learning (gobwas `**` requires 1+ dirs, not 0+)
3. Added warning about `bunx tsc` unreliability from documented learning -- must use project-installed `tsc` via npm script
4. Added edge case for CI step ordering -- typecheck must run after `npm install` in web-platform directory

### New Considerations Discovered

- `agent-env.test.ts` uses dynamic `process.env[key]` indexing over a const array containing `NODE_ENV` -- TypeScript infers the readonly constraint transitively. Requires different fix than `vi.stubEnv`.
- Lefthook glob patterns for `apps/web-platform/**/*.{ts,tsx}` need the array form or `glob_matcher: doublestar` setting to match files at any depth (gobwas default requires 1+ intermediate dirs for `**`).
- The `bun test` pre-commit hook already exists (priority 5) and runs `test-all.sh` which includes web-platform. The new typecheck hook should run BEFORE tests (lower priority number) to fail fast on type errors.

## Overview

Local development misses TypeScript errors that the CI Docker build (`next build`) catches. In PR #1219, an implicit `any` type passed local checks but failed the Docker build, requiring a follow-up PR (#1220). The tsconfig.json already has `"strict": true` (which implies `noImplicitAny`), but there is no local check step that runs `tsc --noEmit` before push, and existing test files have type errors that have accumulated unchecked.

## Problem Statement

Three gaps compound to let type errors slip through to CI:

1. **No explicit `noImplicitAny` in tsconfig.json** -- `strict: true` implies it, but the explicit flag serves as documentation and makes the CI-match intent clear
2. **No `tsc --noEmit` step in pre-commit or CI** -- the `bun-test` hook runs tests but does not type-check. `next build` only type-checks files in the build graph (app pages, components, server code), not test files. `tsc --noEmit` checks all files
3. **Existing type errors in test files** -- 4 categories of errors exist today:
   - `TS2540` (8 occurrences): `process.env.NODE_ENV` assignment in tests -- Node.js types declare `NODE_ENV` as `readonly` under `strict`
   - `TS2307` (1 occurrence): `bun:test` import in `test/domain-router.test.ts` -- should be `vitest`
   - `TS2322` (1 occurrence): `ws-abort.test.ts` type mismatch on `reason` parameter -- test declares `string` but source uses union type `"disconnected" | "superseded"`

### Research Insights

**Why `strict: true` didn't catch the original PR #1219 error locally:**

The root cause is not that `strict` is disabled locally -- it is enabled. The issue is that nobody runs `tsc --noEmit` locally. The `bun test` hook runs tests (runtime), not type-checking (static analysis). And `next dev` (the local dev server) does NOT run a full type check on startup -- it only type-checks files as they are loaded on demand, using a lenient incremental mode. The Docker build's `next build` runs a full type check of all app files.

**Why `bunx tsc` is unreliable:**

Per learning `2026-03-27-react-inert-attribute-typing.md`: "bunx sandboxing doesn't resolve project node_modules, producing false-positive 'Cannot find module react' on every file." The typecheck script must use the project-installed `tsc` via `npx tsc --noEmit` or the npm script `npm run typecheck`, not `bunx tsc`.

## Proposed Solution

### Phase 1: Add explicit `noImplicitAny` to tsconfig.json

Add `"noImplicitAny": true` to `apps/web-platform/tsconfig.json` compilerOptions. While redundant with `strict: true`, this makes the CI-matching intent explicit and prevents accidental removal.

**File:** `apps/web-platform/tsconfig.json`

```jsonc
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noImplicitAny": true, // <-- ADD: explicit for CI-match intent
    "noEmit": true,
    // ... rest unchanged
  }
}
```

### Phase 2: Fix existing type errors in test files

#### 2a. Fix `process.env.NODE_ENV` readonly assignment -- simple cases (6 occurrences)

**Files:**

- `apps/web-platform/lib/auth/validate-origin.test.ts` (lines 15, 19, 77, 84)
- `apps/web-platform/test/callback.test.ts` (lines 60, 64)

**Fix:** Use `vi.stubEnv('NODE_ENV', 'production')` in beforeEach/individual tests and `vi.unstubAllEnvs()` in afterEach. Vitest 3.1+ supports this API.

```typescript
// Before (TS2540 error):
beforeEach(() => {
  process.env.NODE_ENV = "production";
});
afterEach(() => {
  process.env.NODE_ENV = origNodeEnv;
});

// After (type-safe):
beforeEach(() => {
  vi.stubEnv('NODE_ENV', 'production');
});
afterEach(() => {
  vi.unstubAllEnvs();
});
```

For inline assignments within individual tests (e.g., `validate-origin.test.ts` line 77 inside "accepts localhost in development mode"):

```typescript
// Before:
it("accepts localhost in development mode", () => {
  process.env.NODE_ENV = "development";
  // ...
});

// After:
it("accepts localhost in development mode", () => {
  vi.stubEnv('NODE_ENV', 'development');
  // ...
});
```

**Edge case:** The `validate-origin.test.ts` file has a `const origNodeEnv = process.env.NODE_ENV` at describe scope, then restores in afterEach. With `vi.unstubAllEnvs()`, the manual save/restore pattern is no longer needed -- `unstubAllEnvs` restores original values automatically.

#### 2b. Fix `process.env` readonly assignment -- dynamic indexing case (2 occurrences)

**File:** `apps/web-platform/test/agent-env.test.ts` (lines 53, 68)

**Why `vi.stubEnv` doesn't work here:** This test loops over `EXPECTED_ALLOWLIST` (a const array including `NODE_ENV`) and assigns `process.env[key]` dynamically. TypeScript resolves the union type of `key` and determines that `NODE_ENV` (readonly) is a possible assignment target.

**Fix:** Cast `process.env` to a mutable record for the assignment:

```typescript
// Before (TS2540 error):
for (const key of EXPECTED_ALLOWLIST) {
  savedEnv[key] = process.env[key];
  process.env[key] = `test-${key.toLowerCase()}`;
}

// After (type-safe):
const mutableEnv = process.env as Record<string, string | undefined>;
for (const key of EXPECTED_ALLOWLIST) {
  savedEnv[key] = process.env[key];
  mutableEnv[key] = `test-${key.toLowerCase()}`;
}
```

Apply the same pattern to the afterEach restore loop on line 68.

**Why not `vi.stubEnv` for this case:** `vi.stubEnv` requires one call per variable. Rewriting the loop to call `vi.stubEnv` 16+ times would change the test's structure significantly and make it harder to verify the exhaustive env-var coverage that is the test's purpose. The cast is more appropriate here because the test intentionally exercises the full env-var boundary.

#### 2c. Fix `bun:test` import in domain-router.test.ts

**File:** `apps/web-platform/test/domain-router.test.ts` (line 1)

**Fix:** Change `import { describe, expect, test } from "bun:test"` to `import { describe, expect, test } from "vitest"`. All other web-platform tests use vitest. This is a pre-existing error noted in learning `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` Session Error #4.

```typescript
// Before:
import { describe, expect, test } from "bun:test";

// After:
import { describe, expect, test } from "vitest";
```

#### 2d. Fix type mismatch in ws-abort.test.ts

**File:** `apps/web-platform/test/ws-abort.test.ts` (line 10)

**Fix:** Change the `agentRunnerModule` type declaration from `reason?: string` to `reason?: "disconnected" | "superseded"` to match the actual function signature in `server/agent-runner.ts:66`.

```typescript
// Before:
let agentRunnerModule: {
  abortSession: (userId: string, conversationId: string, reason?: string) => void;
};

// After:
let agentRunnerModule: {
  abortSession: (userId: string, conversationId: string, reason?: "disconnected" | "superseded") => void;
};
```

### Phase 3: Add `typecheck` npm script and integrate into CI

#### 3a. Add npm script

**File:** `apps/web-platform/package.json`

Add a `"typecheck"` script. Use `tsc --noEmit` (not `bunx tsc` -- see research insight above about bunx sandboxing issues).

```json
{
  "scripts": {
    "typecheck": "tsc --noEmit",
    // ... existing scripts
  }
}
```

#### 3b. Add lefthook pre-commit hook

**File:** `lefthook.yml`

Add a `web-platform-typecheck` command with priority 4 (before `bun-test` at priority 5) to fail fast on type errors before running the full test suite. Renumber `markdown-lint` to priority 3 to preserve ordering.

```yaml
pre-commit:
  parallel: false
  commands:
    # ... existing commands at priorities 1-4 ...
    web-platform-typecheck:
      priority: 5
      glob: "apps/web-platform/**/*.{ts,tsx}"
      run: npm run --prefix apps/web-platform typecheck
    bun-test:
      priority: 6
      glob: "*.{ts,tsx,js,jsx}"
      run: bash scripts/test-all.sh
    # ... remaining commands renumbered ...
```

### Research Insights (lefthook glob)

Per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`: Lefthook's default glob matcher (gobwas) treats `**` as requiring 1+ intermediate directories, unlike bash/ripgrep where `**` matches 0+. The glob `apps/web-platform/**/*.{ts,tsx}` will match files in subdirectories but NOT files directly in `apps/web-platform/`. Since all relevant `.ts` files are in subdirectories (app/, lib/, server/, test/), this is acceptable. However, if files are ever added directly to `apps/web-platform/`, they would be missed. To be safe, use array glob:

```yaml
      glob:
        - "apps/web-platform/*.{ts,tsx}"
        - "apps/web-platform/**/*.{ts,tsx}"
```

#### 3c. Add CI step

**File:** `.github/workflows/ci.yml`

Add a typecheck step after web-platform dependency installation, before running tests. This catches type errors in PR CI without waiting for the Docker release build.

```yaml
    - name: Type-check web-platform
      run: npm run --prefix apps/web-platform typecheck
```

**Ordering:** This step must come after `Install web-platform dependencies` (which runs `bun install` in `apps/web-platform`) because `tsc --noEmit` requires `node_modules/` to resolve imports.

## Acceptance Criteria

- [ ] `apps/web-platform/tsconfig.json` contains explicit `"noImplicitAny": true`
- [ ] `npx tsc --noEmit` in `apps/web-platform/` passes with zero errors
- [ ] `bun:test` import replaced with `vitest` in `domain-router.test.ts`
- [ ] `process.env.NODE_ENV` assignments fixed in all test files (vi.stubEnv for simple cases, Record cast for loop-based)
- [ ] `ws-abort.test.ts` type annotation matches `agent-runner.ts` signature
- [ ] `npm run typecheck` script exists in `apps/web-platform/package.json`
- [ ] Pre-commit hook runs type checking on `.ts`/`.tsx` changes under `apps/web-platform/`
- [ ] CI workflow runs `tsc --noEmit` for web-platform before tests
- [ ] All existing tests still pass after changes (`bun test apps/web-platform/`)
- [ ] Lefthook glob uses array form to avoid gobwas `**` edge case

## Test Scenarios

- Given the tsconfig has `strict: true` and `noImplicitAny: true`, when running `npm run --prefix apps/web-platform typecheck`, then zero errors are reported
- Given a test file uses `vi.stubEnv('NODE_ENV', ...)`, when type-checking, then no `TS2540` error occurs
- Given `agent-env.test.ts` casts `process.env` via `as Record<string, string | undefined>`, when type-checking, then no `TS2540` error occurs on the dynamic loop assignment
- Given `domain-router.test.ts` imports from `vitest`, when running `bun test apps/web-platform/test/domain-router.test.ts`, then the test passes
- Given the `typecheck` npm script exists, when running `npm run typecheck` in `apps/web-platform/`, then it runs `tsc --noEmit` and exits 0
- Given the pre-commit hook is configured, when committing `.ts` files under `apps/web-platform/`, then `tsc --noEmit` runs as part of the hook
- Given CI runs typecheck, when a PR introduces an implicit `any` type, then CI fails before the Docker build step

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- **Root cause:** Learning `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md` Session Error #2 documents this exact gap
- **Prior PRs:** #1219 (failed CI), #1220 (type fix)
- **Issue:** #1225

## References

- Related PRs: #1219, #1220
- Learning: `knowledge-base/project/learnings/2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`
- Learning: `knowledge-base/project/learnings/2026-03-27-react-inert-attribute-typing.md` (bunx tsc unreliable)
- Learning: `knowledge-base/project/learnings/2026-03-21-lefthook-gobwas-glob-double-star.md` (glob semantics)
- Learning: `knowledge-base/project/learnings/technical-debt/2026-02-12-precommit-hooks-missing-test-execution.md` (pre-commit hook gap)
- Learning: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` (test runner isolation)
- Learning: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md` (deps needed before tsc)
- TypeScript strict mode: `strict: true` enables `noImplicitAny`, `strictNullChecks`, `strictFunctionTypes`, `strictBindCallApply`, `strictPropertyInitialization`, `alwaysStrict`, `useUnknownInCatchVariables`
- Vitest `vi.stubEnv`: <https://vitest.dev/api/vi.html#vi-stubenv>
