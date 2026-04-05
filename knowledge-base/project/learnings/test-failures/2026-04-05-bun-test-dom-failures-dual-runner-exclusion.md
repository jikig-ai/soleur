---
module: System
date: 2026-04-05
problem_type: test_failure
component: testing_framework
symptoms:
  - "document is not defined at render() in @testing-library/react"
  - "bun test from repo root: 110 failures across web-platform test files"
  - "happy-dom GlobalRegistrator silently drops Request/Headers in native APIs"
  - "vi.resetModules unavailable in bun vitest compat layer"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [bun-test, vitest, happy-dom, dual-runner, pathIgnorePatterns, test-isolation]
---

# Troubleshooting: bun test DOM failures from cross-runner test discovery

## Problem

Running `bun test` from the repo root discovered and attempted to run web-platform test files designed exclusively for vitest, causing 110+ failures across 5 distinct categories. The canonical test path (`bash scripts/test-all.sh`) passed cleanly because it delegates web-platform tests to vitest.

## Environment

- Module: System-wide (test infrastructure)
- Runtime: Bun 1.3.11, Vitest 3.2.4
- Affected Component: Root and web-platform test configuration
- Date: 2026-04-05

## Symptoms

- `bun test` from repo root: 110 failures (77 DOM-not-defined, 10 Request API corruption, 19 next/navigation ESM, 3 vi.resetModules, 1 cross-contamination)
- `cd apps/web-platform && npx vitest run`: 438 pass, 0 fail
- `bash scripts/test-all.sh`: all pass (uses vitest for web-platform)
- happy-dom's `GlobalRegistrator.register()` replaces native `Request`/`Headers`/`Response` with implementations that silently drop headers

## What Didn't Work

**Prior fix attempt (#1436):** Added `test/happy-dom.ts` preload to web-platform's `bunfig.toml` to provide DOM environment for bun. This fixed the immediate `document is not defined` errors but exposed deeper issues: happy-dom's GlobalRegistrator corrupts native Request/Headers APIs (headers silently dropped), and vitest-only APIs (`vi.resetModules`) are unavailable in bun's compat layer. The preload was treating the symptom, not the architecture mismatch.

## Session Errors

**CWD drift during git operations** -- After `cd apps/web-platform` for bun test verification, subsequent git commands ran from the wrong directory, causing `git add` to fail with "pathspec did not match."

- **Recovery:** Used absolute path `cd /home/jean/.../worktree-root` before git commands.
- **Prevention:** Always use absolute paths for git commands after any `cd`, or avoid `cd` and use `bun test --cwd` flags instead.

**CWD drift during QA scenarios** -- Same root cause: QA scenarios 4-6 ran from wrong directory after the earlier `cd`, returning incorrect results.

- **Recovery:** Re-ran with explicit `cd` to worktree root.
- **Prevention:** Each QA scenario should explicitly set CWD before running, not rely on inherited shell state.

**Ralph loop script path wrong** -- `./plugins/soleur/skills/one-shot/scripts/setup-ralph-loop.sh` did not exist; correct path was `./plugins/soleur/scripts/setup-ralph-loop.sh`.

- **Recovery:** Corrected to the right path.
- **Prevention:** One-shot skill should reference the correct script path in its instructions.

## Solution

**Strategy: Exclude vitest-only tests from bun test discovery entirely.**

The fundamental insight is that bun test and vitest serve different test populations. Rather than forcing all tests through one runner, formalize the split:

**Config changes:**

```toml
# Root bunfig.toml -- exclude web-platform from bun discovery
[test]
pathIgnorePatterns = [".worktrees/**", "apps/web-platform/**"]

# apps/web-platform/bunfig.toml -- defense-in-depth
[test]
pathIgnorePatterns = ["**"]
```

**Dependency cleanup:**

```bash
# Remove dead preload and its dependency
rm apps/web-platform/test/happy-dom.ts
# Remove @happy-dom/global-registrator from package.json devDependencies
# Regenerate both bun.lock and package-lock.json
```

## Why This Works

1. **Root cause:** Bun discovers all `*.test.ts(x)` files in a single process with a global environment. Web-platform tests were designed for vitest's per-project environment isolation (component tests in `happy-dom`, unit tests in `node`). The architecture mismatch is fundamental -- bun has no per-file environment directive.

2. **Solution addresses root cause:** By excluding `apps/web-platform/**` from bun's `pathIgnorePatterns`, bun never enters the directory during test discovery. The matched directories are pruned during scanning (not filtered post-discovery), so bun never loads happy-dom or encounters vitest-only APIs.

3. **Defense-in-depth:** The local `pathIgnorePatterns = ["**"]` in web-platform's `bunfig.toml` prevents accidental `cd apps/web-platform && bun test` from discovering tests. Without this, someone running bun test from within the directory would hit all 110 failures.

4. **Dependency removal:** `@happy-dom/global-registrator` was only needed for bun's preload mechanism. Vitest uses `happy-dom` directly through its own environment integration (`vitest/environments/happy-dom`), which properly scopes DOM APIs without corrupting native Web APIs.

## Prevention

- When adding a new app with its own test runner (vitest, jest, etc.), immediately add it to the root `bunfig.toml` `pathIgnorePatterns`
- The canonical test path is always `bash scripts/test-all.sh`, which routes each app to its correct runner
- Never use `GlobalRegistrator.register()` in a shared process -- it replaces ALL globalThis properties including native Request/Headers/Response
- If `bun test` from root shows failures, check whether the failing tests belong to a vitest-managed app first

## Related Issues

- See also: [2026-04-03-bun-test-dom-preload-execution-order.md](./2026-04-03-bun-test-dom-preload-execution-order.md)
- See also: [../integration-issues/vitest-bun-test-cross-runner-compat-20260402.md](../integration-issues/vitest-bun-test-cross-runner-compat-20260402.md)
- See also: [../2026-03-30-tdd-enforcement-gap-and-react-test-setup.md](../2026-03-30-tdd-enforcement-gap-and-react-test-setup.md)
- See also: [../2026-03-24-git-ceiling-directories-test-isolation.md](../2026-03-24-git-ceiling-directories-test-isolation.md)
