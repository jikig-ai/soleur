import { describe, it, expect, vi } from "vitest";

// #7665: the `[resolve-origin] Rejected origin` warn is deduplicated per distinct
// origin per process — the dedicated inngest host's --sdk-url poll and deploy
// canary probes are legitimately rejected on a multi-second cadence, and each
// non-JSON console line escapes the app_container_warn_filter level cut.
// The first sighting still logs (the row IS the diagnostic); repeats are
// suppressed until restart. The dedupe Set is module-scoped, so each test
// re-imports under vi.resetModules() for a fresh isolate.

async function loadModule() {
  vi.resetModules();
  return await import("./resolve-origin");
}

describe("resolveOrigin rejection dedupe (#7665)", () => {
  it("logs the first rejection of an origin", async () => {
    const { resolveOrigin } = await loadModule();
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      expect(resolveOrigin("10.0.1.10", "http", null)).toBe(
        "https://app.soleur.ai",
      );
      expect(spy).toHaveBeenCalledTimes(1);
      expect(spy.mock.calls[0][0]).toContain("Rejected origin");
    } finally {
      spy.mockRestore();
    }
  });

  it("suppresses repeat rejections of the same origin", async () => {
    const { resolveOrigin } = await loadModule();
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      for (let i = 0; i < 5; i++) {
        expect(resolveOrigin("10.0.1.10:3000", "http", null)).toBe(
          "https://app.soleur.ai",
        );
      }
      expect(spy).toHaveBeenCalledTimes(1);
    } finally {
      spy.mockRestore();
    }
  });

  it("logs each DISTINCT rejected origin once", async () => {
    const { resolveOrigin } = await loadModule();
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      resolveOrigin("10.0.1.10:3000", "http", null);
      resolveOrigin("localhost:3000", "http", null);
      resolveOrigin("evil.example.com", "https", null);
      expect(spy).toHaveBeenCalledTimes(3);
    } finally {
      spy.mockRestore();
    }
  });

  it("the FIFO cap evicts the oldest entry so a churned novel origin re-logs", async () => {
    const { resolveOrigin, REJECTED_ORIGIN_LOG_CAP } = await loadModule();
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      // Fill past the cap — every DISTINCT origin still logs once.
      for (let i = 0; i < REJECTED_ORIGIN_LOG_CAP + 10; i++) {
        resolveOrigin(`h${i}.scan.example`, "https", null);
      }
      expect(spy).toHaveBeenCalledTimes(REJECTED_ORIGIN_LOG_CAP + 10);
      // h0 was evicted by the cap; its next rejection logs again rather than
      // being starved forever by scanner churn.
      resolveOrigin("h0.scan.example", "https", null);
      expect(spy).toHaveBeenCalledTimes(REJECTED_ORIGIN_LOG_CAP + 11);
      // A never-evicted entry (most recent inserts) still suppresses.
      resolveOrigin(`h${REJECTED_ORIGIN_LOG_CAP + 9}.scan.example`, "https", null);
      expect(spy).toHaveBeenCalledTimes(REJECTED_ORIGIN_LOG_CAP + 11);
    } finally {
      spy.mockRestore();
    }
  });

  it("dedupe never alters the verdict — allow and reject paths unchanged", async () => {
    const { resolveOrigin } = await loadModule();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      expect(resolveOrigin("app.soleur.ai", "https", null)).toBe(
        "https://app.soleur.ai",
      );
      expect(resolveOrigin("evil.com", "https", null)).toBe(
        "https://app.soleur.ai",
      );
      expect(resolveOrigin(null, null, null)).toBe("https://app.soleur.ai");
    } finally {
      vi.mocked(console.warn).mockRestore();
    }
  });
});
