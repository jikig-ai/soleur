import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// Drift guard: if a future PR removes one of the cleanup surfaces from
// setup-dom.ts, this test fails with a clear message — cheaper than
// re-debugging another multi-week flake cycle.
//
// See knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md
// for the cleanup-surface rationale.

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

// Pattern-class guard: any test file that mutates `global.fetch = ...` or
// `globalThis.fetch = ...` directly MUST either be on the allowlist below
// (the setup-dom `originalFetch` restore covers these) or migrate to
// `vi.stubGlobal("fetch", ...)` so `vi.unstubAllGlobals()` handles it.
//
// Rationale: `vi.unstubAllGlobals()` does NOT undo raw property writes —
// only `vi.stubGlobal(...)`-registered stubs. New files using raw assignment
// without teardown create silent cross-file leakage on the worker thread.
describe("test-file raw global.fetch assignments", () => {
  // Files we know do raw assignment today (audited 2026-04-22). The
  // setup-dom `originalFetch` restore covers them. A new file not on this
  // list MUST use vi.stubGlobal or vi.spyOn instead.
  const KNOWN_RAW_ASSIGNERS = new Set([
    "kb-layout.test.tsx",
    "kb-layout-panels.test.tsx",
    "kb-layout-chat-close-on-switch.test.tsx",
    "kb-layout-thread-info-prefetch.test.tsx",
    "file-preview.test.tsx",
    "shared-page-ui.test.tsx",
    "shared-token-content-changed-ui.test.tsx",
    "shared-page-head-first.test.tsx",
    "command-center.test.tsx",
  ]);

  const testDir = resolve(__dirname);
  const files = readdirSync(testDir).filter((f) => f.endsWith(".test.tsx"));
  const rawAssignRe = /(?:global|globalThis)\.fetch\s*=\s*vi\.fn/;

  for (const file of files) {
    it(`${file} does not introduce new raw global.fetch = vi.fn(...) assignments`, () => {
      const body = readFileSync(join(testDir, file), "utf8");
      const hasRawAssign = rawAssignRe.test(body);
      if (hasRawAssign && !KNOWN_RAW_ASSIGNERS.has(file)) {
        throw new Error(
          `${file} uses raw \`global.fetch = vi.fn(...)\`. Switch to ` +
            `\`vi.stubGlobal("fetch", vi.fn(...))\` so \`vi.unstubAllGlobals()\` ` +
            `in setup-dom.ts cleans it up, or add an in-file restore. See ` +
            `knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md`,
        );
      }
    });
  }
});
