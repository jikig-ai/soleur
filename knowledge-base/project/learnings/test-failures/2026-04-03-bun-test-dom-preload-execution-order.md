---
module: web-platform
date: 2026-04-03
problem_type: test_failure
component: testing_framework
symptoms:
  - "71 .tsx test files fail with ReferenceError: document is not defined under bun test"
  - "Tests pass under npx vitest run but fail under bun test"
  - "@testing-library/react screen throws 'global document has to be available' when imported before DOM registration"
  - "DOM state pollution between test files causes failures when running all tests together"
root_cause: incomplete_setup
resolution_type: config_change
severity: high
tags: [bun-test, happy-dom, preload, dynamic-import, testing-library, dom-globals]
---

# Bun Test DOM Preload: Execution Order and Dynamic Imports

## Problem

71 React component tests (.tsx) in `apps/web-platform/test/` failed with `ReferenceError: document is not defined` when run under `bun test`, but passed under `npx vitest run`. The root cause: vitest's `environmentMatchGlobs` in `vitest.config.ts` maps `.tsx` files to `happy-dom`, but bun's test runner ignores vitest config entirely.

## Investigation Steps

1. **Added `@happy-dom/global-registrator`** as devDependency — this is a SEPARATE package from `happy-dom`, not re-exported from it.
2. **Created preload with static imports** — Failed. ES imports are hoisted before `GlobalRegistrator.register()`, so `@testing-library/react` initializes `screen` without `document`.
3. **Extended `bun:test` expect with matchers** — Worked for individual files but not the full suite; DOM state pollution between files.
4. **Added `setup-dom.ts` to bunfig.toml preload** — Failed. `@testing-library/react` calls `beforeAll()` at module load, which errors in bun's preload context ("Cannot call beforeAll() inside a test").
5. **Used dynamic `await import()`** — Success. Top-level await defers all imports after `GlobalRegistrator.register()`, then extends expect and registers afterEach cleanup.

## Root Cause

Three interacting issues:

1. **ES module hoisting**: Static `import` statements execute before any imperative code, so `GlobalRegistrator.register()` can't run first.
2. **Module initialization side effects**: `@testing-library/react` probes for `document.body` at import time and caches a throwing `screen` proxy if absent.
3. **No cross-file cleanup**: Without `afterEach(cleanup)`, rendered DOM elements persist between test files, causing failures in subsequent tests.

## Solution

```typescript
// apps/web-platform/test/happy-dom.ts
// @ts-nocheck — bun-only preload script; tsc does not resolve bun:test types
import { GlobalRegistrator } from "@happy-dom/global-registrator";

GlobalRegistrator.register();

// Must be after register() — dynamic imports guarantee execution order
const { expect, afterEach } = await import("bun:test");
const matchers = await import("@testing-library/jest-dom/matchers");
const { cleanup } = await import("@testing-library/react");

expect.extend(matchers);

afterEach(() => {
  cleanup();
});
```

```toml
# apps/web-platform/bunfig.toml
[test]
# Fallback for ad-hoc `bun test` runs. The canonical test path is
# `bash scripts/test-all.sh` which uses vitest for web-platform.
preload = ["./test/happy-dom.ts"]
```

Also changed `/ship` Phase 4 from `bun test` to `bash scripts/test-all.sh` for CI parity.

## Key Insight

When a library needs DOM globals before other imports can evaluate, dynamic `await import()` is the only reliable pattern in bun preload scripts. Static imports are always hoisted regardless of code order. The `@happy-dom/global-registrator` package (separate from `happy-dom`) + `bunfig.toml [test].preload` is the official bun approach for DOM testing.

## Session Errors

1. **`sync-bare` overwrote worktree files** — Running `worktree-manager.sh sync-bare` synced main's HEAD into the active worktree, overwriting uncommitted work. Recovery: `git checkout HEAD -- <files>` to restore. **Prevention:** Never run `sync-bare` from an active worktree with uncommitted changes; commit WIP first.

2. **`core.bare=true` leaked into worktree context** — After sync-bare, git commands returned "fatal: this operation must be run in a work tree". Recovery: Set `core.bare=false` in `config.worktree`. **Prevention:** The worktree-manager fix merged from main addresses this; ensure `ensure_bare_config` runs in cleanup-merged.

3. **`git stash` used in worktree** — Violated AGENTS.md rule. Recovery: Stash worked via explicit GIT_DIR/GIT_WORK_TREE env vars. **Prevention:** Always commit WIP before merging, never stash in worktrees.

4. **GIT_DIR env leak in pre-commit hook tests** — Lefthook sets GIT_DIR during pre-commit, leaking into `git init` calls in welcome-hook.test.ts. Recovery: Wrapped git commands in `bash -c 'unset GIT_DIR ...'`. **Prevention:** All test helpers that spawn git processes should unset GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE.

5. **ES import hoisting broke @testing-library/react** — Static import of cleanup caused `screen` to initialize without document. Recovery: Switched to dynamic imports. **Prevention:** In bun preload scripts that register globals, always use dynamic `await import()` for all subsequent dependencies.

6. **happy-dom.ts not included in first commit** — The file existed on disk but wasn't committed (pre-commit hook failure masked the omission). Recovery: Separate follow-up commit. **Prevention:** Always verify `git show --stat HEAD` after commit to confirm all intended files are included.

## Prevention

- Use `bash scripts/test-all.sh` (not `bun test`) as the canonical test command — it routes each app to the correct runner.
- When adding DOM preloads for bun, always use dynamic `await import()` after `GlobalRegistrator.register()`.
- Both `bun.lock` and `package-lock.json` must be updated when adding dependencies (Dockerfile uses `npm ci`).
- `@happy-dom/global-registrator` is a separate npm package from `happy-dom` — check before assuming it's re-exported.

## Related

- `knowledge-base/project/learnings/2026-03-30-tdd-enforcement-gap-and-react-test-setup.md` — original React test setup with happy-dom for vitest
- `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md` — cross-runner compatibility rules
- GitHub issue: #1430

## Tags

category: test-failures
module: web-platform
