import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, beforeEach, vi } from "vitest";
import { configure } from "@testing-library/react";

// #5113 — align RTL's async-util ceiling (findBy*/waitFor, default 1000ms)
// with the #4128 contention philosophy (testTimeout 16s; see the suite-size
// figures in vitest.config.ts): forked workers can be CPU-starved past 1s
// under full-suite load. Passing waits are unaffected (they resolve when
// the condition is met); only genuinely-failing waits get slower (10s vs
// 1s), same tradeoff as isolate:true ("acceptable for a reliable suite").
configure({ asyncUtilTimeout: 10_000 });

// #5796 — raise vitest's `vi.waitFor` default timeout floor (1000ms) to 10_000ms,
// mirroring the #5113 `asyncUtilTimeout` fix above for RTL. These are TWO
// INDEPENDENT mechanisms: vitest's `vi.waitFor` does NOT read RTL's
// `configure({ asyncUtilTimeout })` and has no global config knob of its own, so
// the ~47 `vi.waitFor` sites stayed at the 1s default after #5113. Under
// full-suite forked-worker CPU contention a 1s wait is exceeded before the
// condition settles, which is the proven CI-red flake (live-repo-badge.test.tsx
// vi.waitFor.timeout). Wrapping the singleton here lifts the default across every
// call site — existing and future — so a new bare `vi.waitFor` cannot re-arm the
// flake. Explicit per-site timeouts still win (object form spreads over the
// injected default; number form replaces it). Passing waits are unaffected (they
// resolve when the condition is met); only genuinely-failing waits get slower
// (10s vs 1s) — same tradeoff as the RTL ceiling above and isolate:true.
const _origDomWaitFor = vi.waitFor.bind(vi);
vi.waitFor = ((
  callback: Parameters<typeof _origDomWaitFor>[0],
  options?: Parameters<typeof _origDomWaitFor>[1],
) => {
  const opts =
    typeof options === "number"
      ? { timeout: options }
      : { timeout: 10_000, ...(options ?? {}) };
  return _origDomWaitFor(callback, opts);
}) as typeof vi.waitFor;

// Pristine `fetch` captured at setup-file load. Several test files assign
// `global.fetch = vi.fn(...)` directly; `vi.unstubAllGlobals()` does NOT
// undo raw property writes — only `vi.stubGlobal(...)` stubs. We restore
// the captured reference in afterAll. See PR #2594, #2505.
const originalFetch: typeof fetch | undefined =
  typeof globalThis !== "undefined" ? globalThis.fetch : undefined;

// Mirror of `originalFetch` for XMLHttpRequest. Today only `chat-input-attachments`
// and `file-tree-upload` stub XHR via `vi.stubGlobal` (already undone by
// `vi.unstubAllGlobals()`); the proactive capture-and-restore prevents a future
// raw `globalThis.XMLHttpRequest = vi.fn(...)` assignment from leaking across files.
// See `originalFetch` above and PR #2524 / #2470.
const originalXHR: typeof XMLHttpRequest | undefined =
  typeof globalThis !== "undefined" ? globalThis.XMLHttpRequest : undefined;

// #4155 — Pristine `WebSocket` reference at setup-file load. Needed for the
// conditional blockade install below; lets us distinguish "happy-dom's real
// WebSocket is still in place" from "a test file already installed its own
// MockWebSocket / vi.stubGlobal stub" so we only blockade the former.
const originalWebSocket: typeof WebSocket | undefined =
  typeof globalThis !== "undefined" ? globalThis.WebSocket : undefined;

function resetBrowserLikeGlobals() {
  if (typeof sessionStorage !== "undefined") {
    try {
      sessionStorage.clear();
    } catch {
      /* happy-dom with disabled storage — ignore */
    }
  }
  if (typeof localStorage !== "undefined") {
    try {
      localStorage.clear();
    } catch {
      /* ignore */
    }
  }
}

// #4155 — fail-loud network blockade. happy-dom's Window provides a REAL
// `WebSocket` (delegates to the `ws` npm package, opens a real TCP socket)
// and a REAL `fetch`; `window.location.host` defaults to `localhost:3000`.
// Without this blockade, an unmocked `useWebSocket()` or relative-path
// `fetch("/api/...")` in a component test attempts a real loopback connect
// and surfaces as a transient ECONNREFUSED only after vitest's 16s test
// timeout — non-actionable error + wall-clock cost.
//
// Strategy: install loud stubs in `beforeEach` ONLY when the current global is
// still the pristine happy-dom reference (or the blockade itself, for idempotent
// re-install). If a test file already swapped in a mock at any earlier point —
// module-init `vi.stubGlobal("fetch", mockFetch)` (load-bearing for 5+ existing
// `.test.tsx` files), file-level `globalThis.WebSocket = MockWebSocket`, or a
// `vi.spyOn(globalThis, "fetch")` wrapper — leave it alone. This preserves
// pre-blockade test patterns and keeps file-level beforeEach overrides
// (which run AFTER this hook in vitest's composition chain) free to win.
class BlockedWebSocket {
  constructor(url: string | URL) {
    throw new Error(
      `[setup-dom] Unmocked WebSocket construction in test — url=${String(url)}. ` +
        `Mock @/lib/ws-client via vi.mock(...) OR assign globalThis.WebSocket = MockWebSocket in this test's beforeEach. ` +
        `See knowledge-base/project/learnings/2026-05-20-happy-dom-ws-fetch-blockade.md.`,
    );
  }
}

const blockedFetch: typeof fetch = (input, _init) =>
  Promise.reject(
    new Error(
      `[setup-dom] Unmocked fetch in test — input=${
        typeof input === "string"
          ? input
          : input instanceof URL
            ? input.toString()
            : "[Request]"
      }. Mock with vi.stubGlobal("fetch", vi.fn().mockResolvedValue(...)) in this test's beforeEach.`,
    ),
  );

beforeEach(() => {
  if (typeof globalThis === "undefined") return;
  const currentWS = globalThis.WebSocket as unknown;
  if (
    currentWS === (originalWebSocket as unknown) ||
    currentWS === (BlockedWebSocket as unknown)
  ) {
    globalThis.WebSocket = BlockedWebSocket as unknown as typeof WebSocket;
  }
  const currentFetch = globalThis.fetch as unknown;
  if (
    currentFetch === (originalFetch as unknown) ||
    currentFetch === (blockedFetch as unknown)
  ) {
    globalThis.fetch = blockedFetch;
  }
});

afterEach(async () => {
  if (typeof document !== "undefined") {
    const { cleanup } = await import("@testing-library/react");
    cleanup();
  }
});

// File boundary: scrub worker-level state so the next file on this worker
// (pool: threads reuses workers) starts pristine. Running in afterAll rather
// than afterEach lets files keep their module-scope `vi.stubGlobal("fetch", ...)`
// across their own tests — stubs survive intra-file, reset inter-file.
afterAll(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  if (originalFetch && typeof globalThis !== "undefined") {
    globalThis.fetch = originalFetch;
  }
  if (originalXHR && typeof globalThis !== "undefined") {
    globalThis.XMLHttpRequest = originalXHR;
  }
  vi.useRealTimers();
  resetBrowserLikeGlobals();
});
