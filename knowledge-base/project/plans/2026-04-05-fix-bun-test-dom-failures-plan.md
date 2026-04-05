---
title: "fix: resolve bun test DOM and cross-environment failures"
type: fix
date: 2026-04-05
---

# fix: resolve bun test DOM and cross-environment failures

## Overview

110 `bun test` failures persist across the repository despite #1436's happy-dom preload fix. The failures span 5 distinct root causes, all stemming from a fundamental architecture mismatch: **bun test runs all test files in a single process with a global happy-dom preload, but the test suite was designed for vitest's per-project environment isolation** (component tests in `happy-dom` environment, unit tests in `node` environment).

The canonical test path (`bash scripts/test-all.sh`) delegates web-platform tests to vitest, which passes cleanly. But `bun test` from the repo root or from `apps/web-platform/` fails because happy-dom's `GlobalRegistrator.register()` replaces native Web APIs (`Request`, `Headers`, `Response`, `fetch`) with broken implementations, and non-DOM tests import vitest-only APIs.

## Problem Statement

### Current State

- `bash scripts/test-all.sh` -- **all pass** (uses vitest for web-platform)
- `cd apps/web-platform && npx vitest run` -- **438 pass, 0 fail**
- `bun test` from repo root -- **110 fail**
- `cd apps/web-platform && bun test` -- **33 fail**

### Root Cause Analysis

Five distinct failure categories identified through diagnostic testing:

| Category | Count | Root Cause | Affected Files |
|----------|-------|------------|----------------|
| DOM not defined | ~77 | .tsx files run from root without happy-dom preload (root `bunfig.toml` has no preload) | All `.test.tsx` files |
| Happy-dom corrupts Request API | 10 | `GlobalRegistrator.register()` replaces native `Request`/`Headers` with broken implementations that silently drop headers | `validate-origin.test.ts` |
| next/navigation ESM export | ~19 | Bun resolves `next/navigation.js` (CJS) which lacks `usePathname` named export; vitest's `vi.mock()` intercepts this before resolution | `chat-page.test.tsx` and others using `usePathname` |
| vi.resetModules unavailable | 3 | Bun's vitest compat layer supports `vi.fn/spyOn/mock/restoreAllMocks/clearAllMocks` but NOT `vi.resetModules` | `workspace-error-handling.test.ts` |
| Cross-contamination | ~1 | Tests pass individually but fail together due to shared process state (e.g., `ws-protocol.test.ts` idle timeout test) | `ws-protocol.test.ts` |

### Key Evidence

Happy-dom's `GlobalRegistrator.register()` iterates over **all** properties of its `Window` object and replaces the corresponding `globalThis` properties. The only exclusions are `constructor`, `undefined`, `NaN`, `global`, and `globalThis`. This means it replaces `Request`, `Response`, `Headers`, and `fetch` with its own implementations that have incompatible behavior:

```typescript
// Native bun Request -- works correctly
const r = new Request('https://example.com', { headers: { origin: 'https://example.com' } });
r.headers.get('origin'); // => "https://example.com"

// After GlobalRegistrator.register() -- headers silently dropped
const r2 = new Request('https://example.com', { headers: { origin: 'https://example.com' } });
r2.headers.get('origin'); // => null
```

## Proposed Solution

### Strategy: Dual-runner architecture with clear boundaries

The fundamental insight is that **bun test and vitest serve different populations of tests**. Rather than forcing all tests through one runner, formalize the split:

1. **Component tests (.tsx)** -- vitest-only, with `happy-dom` environment (already working)
2. **Unit tests (.ts) in web-platform** -- vitest-only, with `node` environment (already working)
3. **Root-level tests and non-web-platform tests** -- bun test only

The goal is NOT to make every test pass under both runners. The goal is: `bun test` passes with 0 failures by excluding tests that belong to vitest.

### Phase 1: Exclude vitest-only tests from bun test discovery

**Problem:** Bun discovers and attempts to run all `*.test.ts(x)` files, including those designed for vitest.

**Solution:** Configure bun's test discovery to skip `apps/web-platform/` entirely, since those tests are already covered by `test-all.sh` via vitest.

Files to modify:

- `bunfig.toml` (root) -- add `apps/web-platform/**` to `pathIgnorePatterns`
- `apps/web-platform/bunfig.toml` -- remove `[test].preload` (no longer needed; vitest handles all web-platform tests)

This immediately eliminates ~100 of the 110 failures (all web-platform tests).

### Phase 2: Fix remaining non-web-platform failures

After Phase 1, only root-level and `apps/telegram-bridge/` tests run under bun. Verify these pass cleanly. Based on the diagnostic run, `apps/telegram-bridge/` already passes (99 pass, 0 fail). Root-level tests (`test/content-publisher.test.ts`, `test/x-community.test.ts`, `test/pre-merge-rebase.test.ts`) pass via `test-all.sh`.

Check for any remaining failures after the exclusion and fix individually.

### Phase 3: Harden test-all.sh as the canonical test command

Ensure `test-all.sh` is the single source of truth for "do all tests pass":

- Verify it covers all test suites (root-level bun tests, web-platform vitest, telegram-bridge bun tests, plugin tests)
- Add a comment in root `bunfig.toml` explaining why `apps/web-platform/` is excluded
- Update any CI or documentation references

### Phase 4: Clean up the happy-dom preload

Since web-platform tests will only run under vitest (which has its own `environment: "happy-dom"` per-project config), the `test/happy-dom.ts` preload file and `@happy-dom/global-registrator` dependency become unnecessary:

- Remove `apps/web-platform/test/happy-dom.ts`
- Remove `@happy-dom/global-registrator` from `apps/web-platform/package.json` devDependencies
- Regenerate both lockfiles (`bun.lock` and `package-lock.json`)

**Risk assessment:** Low. The preload was only used by `bun test` for web-platform, which we are moving entirely to vitest. Vitest uses `happy-dom` directly (not `@happy-dom/global-registrator`), configured via `vitest.config.ts`.

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Fix happy-dom to not replace Request/Headers | Rejected | Upstream issue in happy-dom v20.8.9; would require patching node_modules |
| Use `// @bun` per-file annotations | Rejected | Bun has no per-file environment directive equivalent to vitest's `@vitest-environment` |
| Make all tests work under both runners | Rejected | Vitest features (`vi.resetModules`, per-project environments, `vi.mock` module interception) have no bun equivalents; maintaining dual compatibility adds complexity with no benefit |
| Selective happy-dom registration (only DOM APIs) | Rejected | `GlobalRegistrator` has no option to exclude specific APIs; would require a custom preload that manually assigns only `document`/`window`/etc. -- fragile and version-dependent |

## Acceptance Criteria

- [ ] `bun test` from repo root passes with 0 failures
- [ ] `cd apps/web-platform && npx vitest run` passes with 0 failures (no regression)
- [ ] `bash scripts/test-all.sh` passes with 0 failures (no regression)
- [ ] `apps/web-platform/bunfig.toml` no longer has `[test].preload`
- [ ] Root `bunfig.toml` excludes `apps/web-platform/**` from bun test discovery
- [ ] `@happy-dom/global-registrator` removed from web-platform devDependencies
- [ ] Both `bun.lock` and `package-lock.json` regenerated after dependency removal

## Test Scenarios

- Given repo root, when `bun test` is run, then 0 failures and no web-platform tests are discovered
- Given `apps/web-platform/`, when `npx vitest run` is run, then all component and unit tests pass with happy-dom environment
- Given `apps/web-platform/`, when `bun test` is run, then 0 tests are discovered (all excluded)
- Given `scripts/test-all.sh`, when run from any worktree, then all suites pass including web-platform via vitest
- Given a new `.test.tsx` file in `apps/web-platform/test/`, when `bun test` is run from root, then it is NOT discovered by bun

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- test infrastructure fix with no user-facing, legal, marketing, or operational impact.

## References

- Issue: #1469
- Prior fix attempt: #1436 (PR), #1430 (issue)
- Prior tracking: #1413
- Happy-dom GlobalRegistrator source: `node_modules/@happy-dom/global-registrator/lib/GlobalRegistrator.js`
- Bun vitest compat docs: only `vi.fn`, `vi.spyOn`, `vi.mock`, `vi.restoreAllMocks`, `vi.clearAllMocks` supported
- Learning: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` (established `test-all.sh` as canonical)
- Constitution: "The project uses Bun as the JavaScript runtime" (line 118)
