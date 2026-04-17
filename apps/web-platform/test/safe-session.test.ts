// @vitest-environment happy-dom
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Phase 0 RED — safeSession wraps sessionStorage with try/catch and SSR
// guard. Contract:
//   - safeSession(key) reads → string | null
//   - safeSession(key, "value") writes → returns the written value
//   - safeSession(key, null) clears (removeItem) → returns null
//   - SSR (no window) returns null and is a no-op for writes
//   - Throwing sessionStorage never propagates

describe("safeSession", () => {
  beforeEach(() => {
    try {
      sessionStorage.clear();
    } catch {
      /* jsdom only */
    }
  });
  afterEach(() => {
    vi.restoreAllMocks();
    try {
      sessionStorage.clear();
    } catch {
      /* noop */
    }
  });

  it("reads a value set via setItem", async () => {
    sessionStorage.setItem("x", "hello");
    const { safeSession } = await import("@/lib/safe-session");
    expect(safeSession("x")).toBe("hello");
  });

  it("returns null for a missing key", async () => {
    const { safeSession } = await import("@/lib/safe-session");
    expect(safeSession("missing")).toBeNull();
  });

  it("writes a string value (returns the written value)", async () => {
    const { safeSession } = await import("@/lib/safe-session");
    const out = safeSession("k", "v");
    expect(out).toBe("v");
    expect(sessionStorage.getItem("k")).toBe("v");
  });

  it("clears a key when value is null (returns null)", async () => {
    sessionStorage.setItem("k", "prior");
    const { safeSession } = await import("@/lib/safe-session");
    const out = safeSession("k", null);
    expect(out).toBeNull();
    expect(sessionStorage.getItem("k")).toBeNull();
  });

  it("swallows getItem errors and returns null", async () => {
    const getSpy = vi
      .spyOn(Storage.prototype, "getItem")
      .mockImplementation(() => {
        throw new Error("quota/security");
      });
    const { safeSession } = await import("@/lib/safe-session");
    expect(safeSession("anything")).toBeNull();
    getSpy.mockRestore();
  });

  it("swallows setItem errors and still returns the intended value", async () => {
    const setSpy = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new Error("quota");
      });
    const { safeSession } = await import("@/lib/safe-session");
    expect(safeSession("k", "v")).toBe("v");
    setSpy.mockRestore();
  });

  it("is a no-op read returning null when window is undefined (SSR)", async () => {
    const originalWindow = globalThis.window;
    // Simulate SSR by deleting window — cast to optional makes delete legal.
    delete (globalThis as { window?: unknown }).window;
    try {
      // Import fresh after window removal so module-scope typeof check is accurate.
      vi.resetModules();
      const { safeSession } = await import("@/lib/safe-session");
      expect(safeSession("any")).toBeNull();
      // Writes are also a no-op — return the intended value but do not throw.
      expect(safeSession("any", "v")).toBe("v");
    } finally {
      (globalThis as { window?: unknown }).window = originalWindow;
      vi.resetModules();
    }
  });
});
