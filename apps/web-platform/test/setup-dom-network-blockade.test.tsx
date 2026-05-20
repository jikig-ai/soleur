import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(resolve(__dirname, "setup-dom.ts"), "utf8");

// #4155 drift-guard: prove the fail-loud network blockade is wired in setup-dom.ts.
// .test.tsx routes to the `component` project (happy-dom env), the only project
// that loads `setupFiles: ["test/setup-dom.ts"]`. .test.ts would route to `unit`
// (node env), where the blockade is intentionally not installed.
// Mirrors the setup-dom-leak-guard pattern (PR #2594, #2505) — source-grep + integration.
describe("setup-dom.ts network blockade (#4155)", () => {
  it("installs a fail-loud WebSocket stub in beforeEach", () => {
    expect(source).toMatch(/beforeEach\([\s\S]*?WebSocket/);
    expect(source).toContain("Unmocked WebSocket construction in test");
  });

  it("installs a fail-loud fetch stub in beforeEach", () => {
    expect(source).toMatch(/beforeEach\([\s\S]*?fetch/);
    expect(source).toContain("Unmocked fetch in test");
  });

  it("throws when an unmocked test attempts new WebSocket()", () => {
    expect(
      () =>
        new (globalThis.WebSocket as new (url: string) => unknown)(
          "ws://localhost:3000/ws",
        ),
    ).toThrow(/Unmocked WebSocket construction/);
  });

  it("rejects when an unmocked test calls fetch()", async () => {
    await expect(
      (globalThis.fetch as (input: string) => Promise<Response>)("/api/probe"),
    ).rejects.toThrow(/Unmocked fetch in test/);
  });

  it("intra-test vi.stubGlobal override wins (sanity)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response("ok", { status: 200 })),
    );
    const res = await fetch("/api/probe");
    expect(res.status).toBe(200);
    vi.unstubAllGlobals();
  });
});
