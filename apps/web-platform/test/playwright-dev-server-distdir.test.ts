import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * The e2e harness runs TWO next dev servers (a public origin and an authenticated one).
 * Since next 16 that is only possible if they use different dist directories.
 *
 * next 16 acquires a lock at `<distDir>/lock` when `experimental.lockDistDir` is set, and
 * that flag DEFAULTS TO TRUE (next/dist/server/config-shared.js). The second server to
 * start exits with "Another next dev server is already running" and Playwright then fails
 * the whole run at `config.webServer` startup — which is exactly how the next 15 -> 16 bump
 * first presented (#7591): three red checks whose root cause was one lock.
 *
 * The lock is keyed on the DIST DIRECTORY, not the port
 * (next/dist/server/lib/router-utils/setup-dev-bundler.js joins `opts.dir` with
 * `nextConfig.distDir`), so running the two servers on different ports is NOT sufficient
 * and looks like it should be. That is the trap this guard exists to hold shut.
 *
 * Asserted against the config SOURCE rather than by importing it: playwright.config.ts
 * pulls in the Playwright runtime, which is not what a vitest unit suite should boot.
 */
describe("playwright dev servers use distinct dist directories", () => {
  const source = readFileSync(join(__dirname, "..", "playwright.config.ts"), "utf-8");
  const distDirs = [...source.matchAll(/NEXT_DIST_DIR:\s*"([^"]+)"/g)].map((m) => m[1]);

  it("declares one NEXT_DIST_DIR per webServer entry", () => {
    const webServers = (source.match(/command:\s*`npm run dev`/g) ?? []).length;
    expect(webServers, "expected the two-dev-server harness").toBe(2);
    expect(
      distDirs.length,
      "every webServer must pin NEXT_DIST_DIR or it inherits the default and collides",
    ).toBe(webServers);
  });

  it("gives each server a different directory", () => {
    expect(new Set(distDirs).size, `NEXT_DIST_DIR values collide: ${distDirs.join(", ")}`).toBe(
      distDirs.length,
    );
  });

  it("keeps them under .next/ so .gitignore still covers them", () => {
    for (const d of distDirs) {
      expect(d, `${d} escapes the ignored .next/ tree`).toMatch(/^\.next\//);
    }
  });

  it("next.config.ts honours NEXT_DIST_DIR", () => {
    const cfg = readFileSync(join(__dirname, "..", "next.config.ts"), "utf-8");
    expect(cfg, "next.config.ts must read NEXT_DIST_DIR or the env var is inert").toMatch(
      /distDir:\s*process\.env\.NEXT_DIST_DIR/,
    );
  });
});
