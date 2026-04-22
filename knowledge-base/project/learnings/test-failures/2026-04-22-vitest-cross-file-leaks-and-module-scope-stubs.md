---
category: test-failures
module: apps/web-platform
tags: [vitest, happy-dom, test-isolation, parallel-tests, setup-files]
related_prs: [2819]
closes_issues: [2594, 2505]
---

# Vitest cross-file leaks and module-scope stubs

## Problem

`./node_modules/.bin/vitest run` in `apps/web-platform` intermittently failed 1-8 tests across seven `kb-chat-sidebar`/`chat-surface` files (#2594, #2505). Serial (`--no-file-parallelism`) was always green. Classic cross-file worker-state leak.

## Investigation — what didn't work, and why

Three successive setup-dom.ts attempts each made it worse before the right architecture emerged:

### Attempt 1: aggressive per-test cleanup → 45 failures (+)

Added `vi.restoreAllMocks()` + `vi.unstubAllGlobals()` + storage clear to an `afterEach` hook in `setup-dom.ts`. Broke `team-names-hook`, `command-center`, `chat-input-attachments`, `team-settings` and others.

**Why:** many files declare module-scope singletons like `const mockFetch = vi.fn(); vi.stubGlobal("fetch", mockFetch)` at module top level, then reset call history with `mockFetch.mockReset()` in their own `beforeEach`. The module-scope stub is expected to persist for **every** test in the file. A global `afterEach` calling `unstubAllGlobals()` undoes it between tests, leaving subsequent tests in the file with the real `fetch`.

### Attempt 2: move cleanup to file boundaries → 31 failures (+)

Moved scrubs to `afterAll` and added a defensive `beforeAll` that did `globalThis.fetch = originalFetch`. New breakage on `team-names-hook` etc.

**Why:** vitest setup-file hook ordering. The test file's module-scope code (including `vi.stubGlobal`) runs at *import*, BEFORE any hook fires. Then `beforeAll` hooks run — ours included — and overwrote `globalThis.fetch` back to the original, wiping the file's own stub before its first test.

### Attempt 3: afterAll-only cleanup → 16 failures

Dropped the destructive `beforeAll`. Intra-file patterns now worked. But the original #2594 flakes persisted. `restoreAllMocks + unstubAllGlobals + storage clear` at `afterAll` still wasn't enough because hoisted `vi.mock(...)` module graphs survive afterAll and on reused workers, sibling files' module graphs could still alias.

### Attempt 4 (shipped): `isolate: true` on the component project

Adding `isolate: true` to the `component` vitest project (and keeping the `afterAll` scrub for worker-level globals like raw `global.fetch =` assignments) produced 3/3 green parallel runs. The two layers cover different leak surfaces:

- `isolate: true` → per-file **module graph** isolation (hoisted `vi.mock` won't leak).
- `afterAll` scrub → per-file **worker-level** scrub (happy-dom storage + raw global.fetch raw writes that aren't tracked by vitest stubs).

## Solution

```ts
// apps/web-platform/vitest.config.ts  (component project only)
isolate: true,
```

```ts
// apps/web-platform/test/setup-dom.ts
const originalFetch = globalThis.fetch;

afterEach(async () => {
  if (typeof document !== "undefined") {
    const { cleanup } = await import("@testing-library/react");
    cleanup();
  }
});

afterAll(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  if (originalFetch) globalThis.fetch = originalFetch;
  vi.useRealTimers();
  // storage clear
});
```

Plus a small drift-guard test (`setup-dom-leak-guard.test.ts`) that asserts the six cleanup-surface tokens remain in `setup-dom.ts` so a future PR can't silently remove a load-bearing line.

## Key Insight

**Test setup-file `afterEach` hooks run per-test, not per-file.** If a test file declares module-scope singletons via `vi.stubGlobal(...)` or `let state = ...`, those are module-scope for the whole file — a global `afterEach` that unstubs globals breaks any file that relies on module-scope stub persistence.

Cross-file state leaks are fixed at **file boundaries** (`afterAll` in setup files), not test boundaries. Even then, hoisted `vi.mock(...)` module graphs escape worker-level scrubs — `isolate: true` is the only reliable cure for module-graph cross-file contamination.

## Prevention

- When adding scrubs to `setup-dom.ts`, place them in `afterAll`, not `afterEach`. Intra-file test isolation is the file's own responsibility (its `beforeEach`).
- Never set `globalThis.fetch = originalFetch` in `beforeAll` of a shared setup file. Test files load their module-scope `vi.stubGlobal` BEFORE setup-file hooks fire; any `beforeAll` fetch-restore will clobber them.
- Diagnose "symbol persists across tests in a file but not across files" as a hoisted-mock leak → engage `isolate: true` on the project, not heavier per-test scrubs.

## Session Errors

- **Attempt 1 over-scrub in afterEach** — Recovery: moved scrubs to `afterAll` — Prevention: the new bullet in setup-file guidance above.
- **Attempt 2 destructive beforeAll** — Recovery: removed the `beforeAll` fetch restore — Prevention: noted in code comment inside `setup-dom.ts` explaining why the restore lives only in `afterAll`.
- **Attempt 3 insufficient without isolate** — Recovery: added `isolate: true` to `component` project — Prevention: plan's conditional Phase 4 is now the default starting point, not a fallback.
- **Wrong agent namespace** — invoked `pr-review-toolkit:code-simplicity-reviewer` (doesn't exist) — Recovery: used `soleur:engineering:review:code-simplicity-reviewer` — Prevention: quick `Available agents` check on launch failure rather than retry.
- **Context7 MCP quota exceeded** — Recovery: direct source inspection of `node_modules/vitest/package.json` + vitest API reference from memory — Prevention: none needed; fallback worked.

## Related

- AGENTS.md `cq-in-worktrees-run-vitest-via-node-node` — this PR stayed in `./node_modules/.bin/vitest` (app-level), consistent with that rule.
- AGENTS.md `cq-raf-batching-sweep-test-helpers` — thematically adjacent teardown-sweep rule; this fix strengthens its spirit.
