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

// #5796 — the vi.waitFor floor wrapper lives in ONE shared helper
// (test/helpers/install-vi-waitfor-floor.ts) called from BOTH setup files. The
// node/unit project (test/**/*.test.ts) and the component project each exercise
// vi.waitFor; installing in only one would leave the other's sites at the 1s
// default. This guards the helper body (incl. the 10s floor value, which the
// behavioral floor tests cannot cheaply assert) AND both call sites, so a silent
// removal or a divergence of the floor value fails fast.
describe("vi.waitFor floor wrapper (#5796)", () => {
  const helper = readFileSync(
    resolve(__dirname, "helpers/install-vi-waitfor-floor.ts"),
    "utf8",
  );
  const nodeSetup = readFileSync(resolve(__dirname, "setup-node.ts"), "utf8");
  const domSetup = readFileSync(resolve(__dirname, "setup-dom.ts"), "utf8");

  it("helper reassigns vi.waitFor with the 10s floor", () => {
    expect(helper).toContain("vi.waitFor =");
    expect(helper).toContain("10_000");
  });

  it.each([
    ["setup-node.ts", nodeSetup],
    ["setup-dom.ts", domSetup],
  ])("%s installs the floor via installViWaitForFloor()", (_label, src) => {
    expect(src).toContain("installViWaitForFloor()");
  });
});
