import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, beforeAll, vi } from "vitest";

// Capture the pristine `fetch` reference at setup-file load, BEFORE any test
// file's module-scope code runs. Several test files in this app assign
// `global.fetch = vi.fn(...)` directly instead of calling `vi.stubGlobal("fetch", ...)`.
// `vi.unstubAllGlobals()` does NOT undo raw property assignments — only
// stubs registered via stubGlobal. We pin the original reference so we
// can force-restore it at file boundaries.
//
// See knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md
// for the full leak taxonomy.
const originalFetch: typeof fetch | undefined =
  typeof globalThis !== "undefined" ? globalThis.fetch : undefined;

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

// File boundary: BEFORE the first test in each file.
// Scrub worker-level storage that may have leaked from a PRIOR file on the
// same worker thread (pool: threads reuses workers by default).
//
// IMPORTANT: do NOT force-restore `globalThis.fetch` here. Many test files
// call `vi.stubGlobal("fetch", mockFetch)` at module top level, which runs
// BEFORE this hook fires. Overwriting `globalThis.fetch` in beforeAll would
// wipe out the file's own stub before its tests run. Fetch restoration
// happens in afterAll — that's sufficient to keep files isolated, because
// the prior file's afterAll already restored fetch before this file loaded.
beforeAll(() => {
  resetBrowserLikeGlobals();
});

afterEach(async () => {
  // DOM cleanup (pre-existing behavior — retained).
  if (typeof document !== "undefined") {
    const { cleanup } = await import("@testing-library/react");
    cleanup();
  }
});

// File boundary: AFTER the last test in each file.
// Scrub mutable worker-level state so the next file on this worker starts
// from a pristine baseline. This is the cross-file leak guard — the #2594
// symptom is specifically "files flake when parallel but pass serially",
// which means state leaked between files, not between tests within a file.
afterAll(() => {
  // Restore spy targets and clear call history so stats don't bleed into
  // the next file on this worker.
  vi.restoreAllMocks();
  // Undo any `vi.stubGlobal(...)` (e.g., `vi.stubGlobal("fetch", fn)`) that
  // the file registered at module scope or in a hook.
  vi.unstubAllGlobals();
  // Undo any `vi.stubEnv(...)` for the same reason.
  vi.unstubAllEnvs();
  // Force-restore `fetch` for files that did `global.fetch = vi.fn(...)`
  // without a matching teardown. See `originalFetch` comment above.
  if (originalFetch && typeof globalThis !== "undefined") {
    globalThis.fetch = originalFetch;
  }
  // Ensure timers are real — a file that forgot its own `vi.useRealTimers()`
  // would otherwise leak fake timers into the next file.
  vi.useRealTimers();
  // Final storage scrub before the next file loads.
  resetBrowserLikeGlobals();
});
