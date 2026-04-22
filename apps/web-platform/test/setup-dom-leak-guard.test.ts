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
  ])("retains %s", (_label, token) => {
    expect(source).toContain(token);
  });
});
