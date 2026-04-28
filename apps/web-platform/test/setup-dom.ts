import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, vi } from "vitest";

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
