import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Drift guard: if a future PR removes a cleanup surface from setup-dom.ts,
// this test fails with a clear message — cheaper than re-debugging another
// multi-week flake cycle. See PR #2594, #2505.

const __dirname = dirname(fileURLToPath(import.meta.url));

describe("setup-dom.ts cleanup surfaces", () => {
  const source = readFileSync(resolve(__dirname, "setup-dom.ts"), "utf8");

  it.each([
    ["sessionStorage clear", "sessionStorage.clear()"],
    ["localStorage clear", "localStorage.clear()"],
    ["restoreAllMocks", "vi.restoreAllMocks()"],
    ["unstubAllGlobals", "vi.unstubAllGlobals()"],
    ["useRealTimers", "vi.useRealTimers()"],
    ["originalFetch capture", "originalFetch"],
    ["fetch restore line", "globalThis.fetch = originalFetch"],
    ["originalXHR capture", "originalXHR"],
    ["XMLHttpRequest restore line", "globalThis.XMLHttpRequest = originalXHR"],
  ])("retains %s", (_label, token) => {
    expect(source).toContain(token);
  });

  // #3818 recurrence prevention: scrub MUST live in afterAll, not afterEach.
  // See learning 2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md Error 1.
  it("scrubs inside afterAll (not afterEach)", () => {
    const afterAllBlock =
      source.match(/afterAll\s*\([\s\S]*?\n\}\);/)?.[0] ?? "";
    expect(afterAllBlock).toContain("vi.restoreAllMocks()");
    // Negative-space: an afterEach hook calling vi.restoreAllMocks() would
    // defeat intra-file `vi.stubGlobal(...)` survival across tests — the
    // exact regression #2594/#2505 fixed.
    const afterEachBlock =
      source.match(/afterEach\s*\([\s\S]*?\n\}\);/)?.[0] ?? "";
    expect(afterEachBlock).not.toContain("vi.restoreAllMocks()");
  });
});
