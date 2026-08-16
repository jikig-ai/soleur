import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { hasLocalMatch } from "next/dist/shared/lib/match-local-pattern.js";
import nextConfig from "../next.config";

/**
 * The image optimizer must not be able to decode attacker-supplied bytes.
 *
 * This replaces an earlier guard that asserted `next.config.ts` declares NO `images` key.
 * That premise was BACKWARDS. Absence of the key does not restrict local URLs — it permits
 * every one of them: `imageConfigDefault.localPatterns` is `undefined` and Next's
 * `hasLocalMatch(undefined, anyPath)` returns `true`. The old guard would therefore have
 * gone RED on the very change that closes the hole, and stayed GREEN while it was open.
 *
 * The hole was live and unauthenticated:
 *   middleware.ts excludes `_next/image` from auth
 *   → `/_next/image?url=/api/shared/<token>` takes the optimizer's LOCAL branch
 *   → local is matched against `localPatterns` only, never `remotePatterns`
 *   → `/api/shared` is in PUBLIC_PATHS, and serves KB binaries RAW with an
 *     extension-derived content type (no decode, no re-encode on upload or read)
 *   → decoded by `next/node_modules/sharp`, which `next` pins at 0.34.5 — the copy
 *     Dependabot advisory 144 covers. Our top-level sharp is patched at 0.35.3, but the
 *     optimizer does not resolve that one.
 *
 * These assertions execute Next's OWN matcher rather than pattern-matching the config, so
 * they test the behaviour the optimizer will actually have rather than the spelling of the
 * config that produces it.
 */
describe("next/image optimizer scope", () => {
  const localPatterns = nextConfig.images?.localPatterns;

  it("declares localPatterns (absence permits every local path, it does not deny them)", () => {
    expect(
      localPatterns,
      "next.config.ts must declare images.localPatterns. Leaving it undefined makes " +
        "hasLocalMatch() return true for EVERY local path, which re-opens the " +
        "/_next/image?url=/api/shared/<token> path to the next-pinned vulnerable sharp " +
        "(Dependabot advisory 144). See ADR-191.",
    ).toBeDefined();
    expect(Array.isArray(localPatterns)).toBe(true);
    expect(localPatterns!.length).toBeGreaterThan(0);
  });

  // The must-ALLOW row. Without it, a guard that denies everything would score full marks
  // on every must-DENY row below while breaking the one image the app actually renders.
  it("still allows the only next/image call site", () => {
    expect(hasLocalMatch(localPatterns, "/icons/soleur-logo-mark.png")).toBe(true);
  });

  it("denies every route that can return attacker-supplied bytes", () => {
    for (const path of [
      "/api/shared/abc123", // public, unauthenticated, serves raw KB binaries
      "/api/workspace/logo/whatever", // user-uploaded logo bytes
      "/api/kb/download/abc", // any other API-served bytes
      "/icons/../api/shared/abc123", // traversal back out of the allowed prefix
    ]) {
      expect(
        hasLocalMatch(localPatterns, path),
        `next/image optimizer would fetch and DECODE ${path}. That path can carry ` +
          "attacker-supplied bytes, and the optimizer resolves the next-pinned sharp " +
          "(advisory 144), not our patched top-level copy.",
      ).toBe(false);
    }
  });

  // Anti-vacuity: proves the matcher is the real one and can answer BOTH ways under this
  // config. Without it, an import that silently resolved to a stub returning `false` would
  // satisfy every deny row above.
  it("the matcher is live and discriminates (control)", () => {
    expect(hasLocalMatch(undefined, "/api/shared/abc123")).toBe(true); // the unconfigured hole
    expect(hasLocalMatch([{ pathname: "/nothing/**" }], "/icons/x.png")).toBe(false);
  });

  it("declares no remotePatterns (the optimizer must not fetch third-party origins)", () => {
    const remote = nextConfig.images?.remotePatterns;
    expect(remote === undefined || remote.length === 0).toBe(true);
  });

  // The nested-copy premise itself: if `next` ever stops pinning its own sharp, the whole
  // deferral of advisory 144 is moot and should be re-derived rather than inherited.
  it("records why the deferral of advisory 144 is scoped to the nested copy", () => {
    const src = readFileSync(join(__dirname, "..", "next.config.ts"), "utf8");
    expect(src).toMatch(/localPatterns/);
    expect(src).toMatch(/advisory 144|Dependabot advisory/);
  });
});
