---
date: 2026-05-20
category: test-failures
tags: [vitest, happy-dom, test-isolation, network-blockade, econnrefused]
issue: 4155
pr: 4158
---

# happy-dom's WebSocket and fetch are real network adapters — install a fail-loud blockade in setup-dom for deterministic test isolation

## TL;DR

happy-dom@20.x ships a **real** `WebSocket` (delegates to the `ws` npm package, opens a real TCP socket) and a **real** `fetch`. Its `Window.location.host` defaults to `localhost:3000`. Any vitest component test (`environment: 'happy-dom'`) that exercises a `useWebSocket()` hook or a relative-path `fetch("/api/...")` without explicitly mocking those globals attempts a real loopback connection during `npm test`. The result is a transient `ECONNREFUSED 127.0.0.1:3000` that only surfaces after vitest's full test-timeout (16s post-#4128) and looks like a flaky environment, not a missing mock.

Fix: install fail-loud stubs for `globalThis.WebSocket` + `globalThis.fetch` in a setup-file `beforeEach` — **conditionally**, only when the current global still points at the pristine happy-dom reference (or the blockade itself, for idempotent re-install). This preserves three pre-existing patterns: (a) module-init `vi.stubGlobal("fetch", mockFetch)` (any `.test.tsx` that already swaps in a mock at import time); (b) file-level `beforeEach` reassignment (`globalThis.WebSocket = MockWebSocket` — composes AFTER setup-file `beforeEach` in vitest's hook chain); (c) `vi.spyOn(globalThis, "fetch")` wrappers. The blockade only catches genuinely-unmocked paths and names the offending URL.

## Symptom

```
RERUN  apps/web-platform/test/<some-component>.test.tsx
 FAIL  |component| test/<component>.test.tsx
   Failed to execute "fetch()" on "Window" with URL "http://localhost:3000/api/admin/check":
   connect ECONNREFUSED 127.0.0.1:3000
```

Reproduces ~1 in 3 full-suite runs (`apps/web-platform && doppler run -p soleur -c dev -- npm test`, 5003 tests / 473 files). The same test passes in isolation. The same test passes when run in a different file ordering. The error message names the URL but not the test that issued the connect.

## Root cause

Verified by direct inspection:

1. `node_modules/happy-dom/lib/web-socket/WebSocket.js:8` — `import WS from 'ws'`.
2. `node_modules/happy-dom/lib/web-socket/WebSocket.js:67` — `this.#connect(parsedURL, protocolList)` runs **unconditionally** in the WebSocket constructor.
3. `vitest`'s happy-dom environment initializer sets `Window.location.href = 'http://localhost:3000'` by default; `window.location.host` resolves to `localhost:3000`.
4. `apps/web-platform/lib/ws-client.ts:491` builds `ws://${window.location.host}/ws` and calls `new WebSocket(url)` at `:532`. Under happy-dom, `globalThis.WebSocket` IS happy-dom's `WebSocket` → real `ws.connect()` → ECONNREFUSED.
5. Same story for relative-path `fetch("/api/...")` in mounted components (`app/(dashboard)/layout.tsx:112`, `lib/analytics-client.ts:35`, etc.) — happy-dom resolves the relative URL against `window.location.origin = http://localhost:3000` and calls Node's `undici`.

Cross-file isolation is already closed (`pool: "forks"` + `isolate: true` from #4097). The remaining surface is **intra-file**: a test that imports `useWebSocket` directly without `vi.mock("@/lib/ws-client", ...)` AND without reassigning `globalThis.WebSocket` in its own `beforeEach`. Only 3 files override the global today — any future test that adds a fourth direct-import without the override silently inherits happy-dom's real WebSocket and reopens the flake class.

## Fix shape

`apps/web-platform/test/setup-dom.ts` (loaded only by the `component` project per `vitest.config.ts:61`):

```ts
const originalFetch = globalThis.fetch;
const originalWebSocket = globalThis.WebSocket;

class BlockedWebSocket {
  constructor(url: string | URL) { throw new Error(`[setup-dom] Unmocked WebSocket — url=${String(url)}. ...`); }
}
const blockedFetch: typeof fetch = (input) =>
  Promise.reject(new Error(`[setup-dom] Unmocked fetch — input=${typeof input === "string" ? input : input instanceof URL ? input.toString() : "[Request]"}. ...`));

beforeEach(() => {
  const currentWS = globalThis.WebSocket as unknown;
  if (currentWS === originalWebSocket || currentWS === BlockedWebSocket) {
    globalThis.WebSocket = BlockedWebSocket as unknown as typeof WebSocket;
  }
  const currentFetch = globalThis.fetch as unknown;
  if (currentFetch === originalFetch || currentFetch === blockedFetch) {
    globalThis.fetch = blockedFetch;
  }
});
```

The conditional check is load-bearing. A naive `beforeEach` that unconditionally assigns `globalThis.fetch = blockedFetch` clobbers any module-init `vi.stubGlobal("fetch", mockFetch)` and breaks ~19 pre-existing tests across `team-names-hook`, `display-format`, `team-settings`, `chat-input-attachments` (all share the same pattern: module-top-level `vi.stubGlobal` + per-test `mockFetch.mockResolvedValueOnce(...)`).

Hook composition order (empirically verified on vitest 3.2.4, the pinned version): setup-file `beforeEach` → file-level `beforeEach` → describe-level `beforeEach`. Per-file overrides still win — the conditional check makes module-init stubs also win, which the unconditional version did not.

## Why this is the right scope

- **Default fail-closed.** The blockade makes "I forgot to mock the network" a synchronous, actionable test failure naming the URL — not a 16-second timeout that requires bisecting which file leaked.
- **Zero regression risk for existing tests.** 25+ component-project tests already assign `global.fetch = vi.fn(...)` or use `MockWebSocket` in their own `beforeEach`; those overwrites compose AFTER the setup-file `beforeEach` and win. 33 test files use `vi.mock("@/lib/ws-client", ...)`, which short-circuits the real module entirely.
- **`unit` project unaffected.** `setupFiles: ["test/setup-dom.ts"]` is component-project only. The `unit` project (`environment: 'node'`, `.test.ts`) doesn't load this file and doesn't have the happy-dom-real-network problem.
- **Future-proof.** A drift-guard test (`apps/web-platform/test/setup-dom-network-blockade.test.tsx`) asserts both stubs are present in source AND that intra-test `vi.stubGlobal` override semantics hold. Mirrors the `setup-dom-leak-guard.test.ts` precedent (PR #2594, #2505).

## Edge cases verified

- `vi.spyOn(globalThis, "fetch")` (5 component test files) records `blockedFetch` as its captured "original" at spy-create time. Safe — every call site uses `.mockResolvedValue(...)` / `.mockReturnValue(...)`, none uses pass-through that would invoke the recorded original.
- `vi.stubGlobal("fetch", ...)` at module top-level in 3 files (all `.test.ts`, routed to `unit` project — blockade doesn't apply).
- `vi.stubGlobal("fetch", ...)` inside file-level `beforeEach` in `connect-repo-page.test.tsx` — composition order makes it run AFTER the blockade install, so the per-file stub wins.
- A test that intentionally exercises the REAL `WebSocket` (e.g., spinning up a `ws` server in `beforeAll`) must capture and restore the blockaded stub in its own `beforeEach`/`afterEach` pair — same pattern as before for any global-restore.

## Related

- #4097: `pool: "forks"` + `isolate: true` — closed cross-file leak class; intra-file remained.
- #4128 / PR #4141: bumped `testTimeout` to 16_000ms + scrubbed Doppler env leak. Explicitly scoped out the ECONNREFUSED class to #4155.
- PR #2594, #2505: `setup-dom-leak-guard.test.ts` precedent — same drift-guard-via-source-grep pattern. Note: those PR numbers are pre-existing citations on `main` that do not resolve via `gh pr view`; the new file inherits the citation unchanged.
- happy-dom source: `node_modules/happy-dom/lib/web-socket/WebSocket.js`.

## Session Errors

- **Drift-guard test file created as `.test.ts` (wrong vitest project routing).** `.test.ts` routes to the `unit` project (`environment: 'node'`) which does NOT load `setupFiles: ["test/setup-dom.ts"]`; integration assertions for the blockade therefore observed happy-dom-absent globals and failed for the wrong reason. **Recovery:** deleted and recreated as `.test.tsx` (routes to `component` project, happy-dom env, blockade loaded). **Prevention:** when writing a test whose assertions depend on a `setupFiles`-loaded module, verify project routing via `vitest.config.ts`'s `include:` patterns BEFORE writing — the file extension is the routing key in multi-project vitest configs.

- **Plan undercounted module-init `vi.stubGlobal("fetch", ...)` files.** Plan §Risks "vi.stubGlobal at module-init" enumerated 3 `.test.ts` files in the `unit` project and asserted "ALL THREE are .test.ts files routed to the unit project" — missed 5+ `.test.tsx` files (`team-names-hook`, `display-format`, `team-settings`, `chat-input-attachments`, `chat-input-image-placeholder-paste`) in the `component` project doing the same pattern. Initial unconditional blockade install clobbered the module-init stubs → 19 false-positive test failures across the 5× full-suite run. **Recovery:** switched to conditional install (only overwrite when current global is the pristine happy-dom reference or the blockade itself); preserves module-init stubs transparently. **Prevention:** plan-time `git grep` for setup-file-mutation conflicts MUST be project-scope-aware — when a vitest config defines multiple projects with disjoint `include:` patterns, sweep every pattern across every project, not just the subset matching the file-extension the plan first considered. Same class as `hr-write-boundary-sentinel-sweep-all-write-sites` but for test-file global-mutation enumeration.

- **CWD shift after background command.** A worktree-relative `find apps/web-platform/test -name '*.test.tsx'` returned "No such file or directory" because the parent shell's CWD had shifted to bare-root state after a background invocation. **Recovery:** re-anchored each call with `cd <worktree-abs-path> && cmd`. **Prevention:** already covered by existing work-skill prose ("When running test/lint/budget commands from inside a worktree pipeline, chain `cd <worktree-abs-path> && <cmd>` in a single Bash call. The Bash tool does NOT persist CWD across calls."). No new rule needed.
