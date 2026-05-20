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
// Mirrors the setup-dom-leak-guard pattern (PR #2594, #2505) — source-grep
// pins the structural shape; runtime asserts behavior; identity-by-name guards
// against happy-dom upgrades that might throw sync for unrelated reasons.
describe("setup-dom.ts network blockade (#4155)", () => {
  it("installs the WebSocket stub in a beforeEach (structural)", () => {
    expect(source).toMatch(/beforeEach\([\s\S]*?WebSocket/);
  });

  it("installs the fetch stub in a beforeEach (structural)", () => {
    expect(source).toMatch(/beforeEach\([\s\S]*?fetch/);
  });

  it("activates the blockade by identity, not by accidental sync throw", () => {
    // `.name` distinguishes "blockade fired" from "happy-dom future-throws-sync
    // for an unrelated reason" — a future happy-dom upgrade that synchronously
    // rejects bad URLs would make a generic toThrow assertion pass for the
    // wrong reason. Pin the class name.
    expect((globalThis.WebSocket as { name?: string }).name).toBe(
      "BlockedWebSocket",
    );
    expect((globalThis.fetch as { name?: string }).name).toBe("blockedFetch");
  });

  it("throws with the actionable URL when an unmocked test new()s WebSocket", () => {
    expect(
      () =>
        new (globalThis.WebSocket as new (url: string) => unknown)(
          "ws://localhost:3000/ws",
        ),
    ).toThrow(/Unmocked WebSocket construction/);
  });

  it("rejects with the actionable input when an unmocked test calls fetch", async () => {
    await expect(
      (globalThis.fetch as (input: string) => Promise<Response>)("/api/probe"),
    ).rejects.toThrow(/Unmocked fetch in test/);
  });

  it("yields to intra-test vi.stubGlobal override", async () => {
    // Anchor: prove the blockade is the active fetch BEFORE we stub, so the
    // subsequent override-wins assertion is not vacuous (it would pass against
    // happy-dom's real fetch too, since stubGlobal wins over any prior value).
    await expect(
      (globalThis.fetch as (input: string) => Promise<Response>)("/api/probe"),
    ).rejects.toThrow(/Unmocked fetch in test/);

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response("ok", { status: 200 })),
    );
    const res = await fetch("/api/probe");
    expect(res.status).toBe(200);
    vi.unstubAllGlobals();
  });
});
