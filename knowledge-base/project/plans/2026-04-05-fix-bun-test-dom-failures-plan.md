---
title: "fix: resolve bun test DOM and cross-environment failures"
type: fix
date: 2026-04-05
---

# fix: resolve bun test DOM and cross-environment failures

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 4 (Proposed Solution, Phase 1, Phase 4, References)
**Research sources:** Context7 bun docs, 4 institutional learnings, plan review (3 reviewers)

### Key Improvements

1. Added `pathIgnorePatterns` for `apps/web-platform/` in the web-platform `bunfig.toml` itself (not just root) -- prevents accidental `bun test` from within the web-platform directory
2. Consolidated reviewer feedback: Phases 2-3 collapsed into verification steps within Phase 1; Phase 4 (dependency cleanup) flagged as separable if PR size is a concern
3. Incorporated 3 institutional learnings that directly apply: TDD enforcement gap (2026-03-30), CI quality gates (2026-04-01), git ceiling directories (2026-03-24)

### Institutional Learnings Applied

| Learning | Relevance |
|----------|-----------|
| `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` | Directly documents the vitest config pattern and confirms `test-all.sh` should use vitest for web-platform |
| `2026-04-01-ci-quality-gates-and-test-failure-visibility.md` | Documents how 50 test failures on main went unnoticed; reinforces need for `test-all.sh` as canonical runner |
| `2026-03-24-git-ceiling-directories-test-isolation.md` | Documents the lefthook change from `bun test` to `bash scripts/test-all.sh` and GIT_DIR isolation |
| `2026-03-20-bun-fpe-spawn-count-sensitivity.md` | Established `test-all.sh` as sequential runner to avoid bun GC crashes |

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

- `bunfig.toml` (root) -- add `"apps/web-platform/**"` to `pathIgnorePatterns`
- `apps/web-platform/bunfig.toml` -- remove `[test].preload` and add `pathIgnorePatterns = ["**"]` to prevent accidental `bun test` from within the directory

#### Research Insights

**Bun pathIgnorePatterns behavior (Context7 docs):** Directories matching a pattern are pruned during scanning -- their contents are never traversed. This means `"apps/web-platform/**"` prevents bun from even entering the directory, which is more efficient than per-file exclusion.

**Defense-in-depth for web-platform bunfig.toml:** Adding `pathIgnorePatterns = ["**"]` to the web-platform `bunfig.toml` ensures that even if someone runs `cd apps/web-platform && bun test`, zero tests are discovered. This prevents the happy-dom corruption issue from ever manifesting. The `[test].preload` removal alone would cause all .tsx tests to fail with `document is not defined` rather than preventing discovery.

**Institutional precedent:** The 2026-03-24 learning documents the same architectural decision -- lefthook was changed from `bun test` to `bash scripts/test-all.sh` because bun test cannot provide per-file DOM environments. This plan completes that transition by also excluding web-platform from bun's discovery.

This immediately eliminates all 110 failures (web-platform tests + their cross-contamination effects on non-web-platform tests).

#### Verification (replaces Phases 2-3 from original plan)

After applying the exclusion, verify all non-web-platform test suites still pass:

- `bun test` from root -- 0 failures, only root-level + telegram-bridge + plugins tests discovered
- `bun test apps/telegram-bridge/` -- 99 pass (confirmed in diagnostics)
- `bun test plugins/soleur/` -- passes (confirmed via test-all.sh)
- `bash scripts/test-all.sh` -- all suites pass (web-platform via vitest, rest via bun)

Add an explanatory comment in root `bunfig.toml` referencing this issue and the rationale.

### Phase 2: Clean up the happy-dom preload

Since web-platform tests will only run under vitest (which has its own `environment: "happy-dom"` per-project config in `vitest.config.ts`), the `test/happy-dom.ts` preload file and `@happy-dom/global-registrator` dependency become unnecessary:

- Remove `apps/web-platform/test/happy-dom.ts`
- Remove `@happy-dom/global-registrator` from `apps/web-platform/package.json` devDependencies
- Regenerate both lockfiles (`bun.lock` and `package-lock.json`) -- AGENTS.md requires both when `package.json` changes

#### Research Insights

**Vitest vs GlobalRegistrator:** Vitest's `environment: "happy-dom"` in `vitest.config.ts` uses happy-dom through a different integration path (`vitest/environments/happy-dom`) that properly scopes DOM APIs per test project without corrupting native Web APIs. The `@happy-dom/global-registrator` package is only needed for bun's preload mechanism, which we are removing.

**Lockfile dual-regeneration (AGENTS.md rule):** The Dockerfile uses `npm ci` which requires `package-lock.json` to be in sync. After `bun install`, always run `npm install` in the same directory to regenerate `package-lock.json`. Failure to do this broke Docker builds for hours in #1293.

**Risk assessment:** Low. The preload was only used by `bun test` for web-platform, which we are excluding from bun discovery entirely. Vitest uses `happy-dom` directly (listed as a separate devDependency), not `@happy-dom/global-registrator`.

**Separability note (reviewer feedback):** This phase can be split into a follow-up PR if the lockfile diff is too large for a single review. The Phase 1 config changes are the actual fix; this phase is cleanup. However, leaving dead code (`test/happy-dom.ts`) that actively corrupts the Request API is a footgun -- prefer same-PR cleanup.

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
- Given `apps/web-platform/`, when `bun test` is run, then 0 tests are discovered (pathIgnorePatterns blocks all)
- Given `apps/telegram-bridge/`, when `bun test` is run, then 99 pass, 0 fail (no regression from root config change)
- Given `plugins/soleur/`, when `bun test` is run, then all pass (no regression from root config change)
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
- Bun pathIgnorePatterns docs: matched directories are pruned during scanning (Context7 /oven-sh/bun)
- Learning: `2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` (vitest config pattern, test-all.sh uses vitest for web-platform)
- Learning: `2026-04-01-ci-quality-gates-and-test-failure-visibility.md` (invisible test failures on main)
- Learning: `2026-03-24-git-ceiling-directories-test-isolation.md` (lefthook changed to test-all.sh)
- Learning: `2026-03-20-bun-fpe-spawn-count-sensitivity.md` (established `test-all.sh` as canonical)
- Constitution line 118: "The project uses Bun as the JavaScript runtime"
