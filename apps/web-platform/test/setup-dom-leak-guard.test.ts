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
    // #5113 — contention-tolerant RTL wait ceiling; deleting it silently
    // reintroduces the 1s-default starvation flake class.
    ["asyncUtilTimeout config", "asyncUtilTimeout: 10_000"],
    // #5796 — vitest `vi.waitFor` default-floor wrapper (1s → 10s). Distinct
    // mechanism from asyncUtilTimeout above; deleting it re-arms the
    // vi.waitFor.timeout flake across every component-project call site.
    ["vi.waitFor floor wrapper", "vi.waitFor ="],
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

// #5796 — the `vi.waitFor` floor wrapper must live in BOTH setup files. The
// node/unit project (test/**/*.test.ts) runs under setup-node.ts and holds 18
// vi.waitFor sites (cc-dispatcher.test.ts, is-template-authorized.test.ts); a
// setup-dom-only fix would leave them at the 1s default. This guards the second
// install site — deleting the setup-node.ts wrapper fails here.
describe("setup-node.ts vi.waitFor floor wrapper", () => {
  const nodeSource = readFileSync(resolve(__dirname, "setup-node.ts"), "utf8");

  it("retains the vi.waitFor floor wrapper", () => {
    expect(nodeSource).toContain("vi.waitFor =");
  });

  it("imports vi from vitest (required for the wrapper)", () => {
    expect(nodeSource).toMatch(/import\s*\{[^}]*\bvi\b[^}]*\}\s*from\s*"vitest"/);
  });
});
