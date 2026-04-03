---
title: "fix: resolve Vite CJS deprecation and environmentMatchGlobs warning"
type: fix
date: 2026-04-03
---

# fix: resolve Vite CJS deprecation and environmentMatchGlobs warning

Closes #1476

Every `vitest run` in `apps/web-platform` prints two deprecation warnings:

1. **"The CJS build of Vite's Node API is deprecated"** -- because `apps/web-platform/package.json` lacks `"type": "module"`, Node resolves `vitest/config` to the CJS entry point (`dist/config.cjs`) instead of the ESM entry (`dist/config.js`).
2. **"environmentMatchGlobs is deprecated"** -- Vitest v3.x replaced `environmentMatchGlobs` with `test.projects` for defining per-glob environment overrides.

These warnings appear on every test run, every pre-commit hook, and every CI run. They add noise and will eventually become errors in future Vitest/Vite versions.

## Root Cause Analysis

### CJS Deprecation

The root `package.json` has `"type": "module"` but `apps/web-platform/package.json` does not. Node.js uses the nearest `package.json` to determine module resolution -- so `vitest.config.ts` resolves imports in CJS context. Verified:

```text
$ node -e "console.log(require.resolve('vitest/config'))"
.../node_modules/vitest/dist/config.cjs   # CJS entry -- triggers the warning
```

The web-platform codebase is pure ESM (zero `require()` calls in any `.ts` or `.js` file). Adding `"type": "module"` is safe.

### environmentMatchGlobs

The current config uses:

```ts
environmentMatchGlobs: [
  ["test/**/*.tsx", "happy-dom"],
],
```

This maps `.tsx` test files (React component tests) to `happy-dom` environment while `.ts` files (unit/integration tests) default to `node`. Vitest v3.x replaces this with `test.projects`, which defines inline project configurations with their own `include` patterns and environments.

## Proposed Solution

### Task 1: Add `"type": "module"` to web-platform package.json

**File:** `apps/web-platform/package.json`

Add `"type": "module"` to the package.json. This makes Node resolve ESM entry points for vitest/config and vite, eliminating the CJS warning.

**Risk assessment:** Low. The entire codebase uses ESM imports. Next.js 15 supports `"type": "module"`. The `next.config.ts`, `vitest.config.ts`, `playwright.config.ts`, and `postcss.config.mjs` files are all ESM-compatible.

### Task 2: Replace environmentMatchGlobs with test.projects

**File:** `apps/web-platform/vitest.config.ts`

Migrate from:

```ts
import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  esbuild: {
    jsx: "automatic",
  },
  test: {
    environment: "node",
    exclude: ["e2e/**", "node_modules/**"],
    environmentMatchGlobs: [
      ["test/**/*.tsx", "happy-dom"],
    ],
    setupFiles: ["test/setup-dom.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});
```

To:

```ts
import { defineConfig } from "vitest/config";
import path from "path";

export default defineConfig({
  esbuild: {
    jsx: "automatic",
  },
  test: {
    exclude: ["e2e/**", "node_modules/**"],
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          environment: "node",
          include: ["test/**/*.test.ts", "lib/**/*.test.ts"],
        },
      },
      {
        extends: true,
        test: {
          name: "component",
          environment: "happy-dom",
          include: ["test/**/*.test.tsx"],
          setupFiles: ["test/setup-dom.ts"],
        },
      },
    ],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});
```

Key decisions in the migration:

- **`extends: true`** on both projects inherits root config (esbuild, resolve.alias, exclude).
- **Named projects** (`unit`, `component`) for clear test output labeling.
- **`setupFiles` moved to component project only** -- `test/setup-dom.ts` imports `@testing-library/jest-dom/vitest` and runs `cleanup()` on `document`. The jest-dom matchers are only needed for component tests; node tests do not use DOM assertions. Moving setupFiles to the component project avoids loading DOM setup in node-only tests.
- **Explicit `include` patterns** for both projects to avoid ambiguity. The unit project includes both `test/**/*.test.ts` and `lib/**/*.test.ts` to cover the two test files in `lib/auth/`.
- **Root-level `environment` and `setupFiles` removed** -- these are now per-project.

### Task 3: Verify warnings are gone

Run `npx vitest run` and confirm:

- Zero deprecation warnings in output
- All 420+ tests still pass
- Test count matches before/after (no tests accidentally excluded)

## Acceptance Criteria

- [ ] `vitest run` produces zero deprecation warnings (no CJS warning, no environmentMatchGlobs warning)
- [ ] All existing tests pass with identical results (420 passed, 1 skipped)
- [ ] `.tsx` test files run in `happy-dom` environment
- [ ] `.ts` test files run in `node` environment
- [ ] `lib/auth/*.test.ts` files are included and pass
- [ ] No changes to test files themselves -- config-only migration

## Test Scenarios

- Given the updated vitest config, when running `npx vitest run`, then zero lines contain "CJS build of Vite's Node API is deprecated"
- Given the updated vitest config, when running `npx vitest run`, then zero lines contain "environmentMatchGlobs"
- Given a `.tsx` test file (e.g., `test/chat-page.test.tsx`), when vitest runs it, then the test environment is `happy-dom`
- Given a `.ts` test file (e.g., `test/csp.test.ts`), when vitest runs it, then the test environment is `node`
- Given `lib/auth/validate-origin.test.ts`, when vitest runs it, then the test is included and passes

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Rename `vitest.config.ts` to `vitest.config.mts` | Forces ESM without touching package.json | Unusual convention, `__dirname` not available in ESM `.mts` without `import.meta` | Rejected -- `"type": "module"` is cleaner |
| Use `/// <reference types="vitest/config" />` with vite's defineConfig | Avoids vitest/config import entirely | Does not fix the CJS resolution since vite itself has the same issue | Rejected -- treats symptom, not cause |
| Separate vitest config files per environment | Maximum isolation | Unnecessary complexity for two environments | Rejected -- inline projects are simpler |

## References

- Issue: #1476
- [Vite CJS deprecation guide](https://vite.dev/guide/troubleshooting.html#vite-cjs-node-api-deprecated)
- [Vitest v3.x projects configuration](https://vitest.dev/guide/projects.html)
- Installed versions: vitest 3.2.4, vite (bundled with vitest)
