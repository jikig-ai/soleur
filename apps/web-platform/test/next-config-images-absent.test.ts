import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Audit contract for a DELIBERATELY DEFERRED high-severity advisory — not a security gate.
 *
 * Dependabot alert 144 (sharp, high) and 161/162/170 (postcss) are left open rather than
 * dismissed, because `next` pins its own nested copies (`sharp` at `^0.34.3`, `postcss`
 * exact `8.4.31`) and only a `next` 15.x → 16.x major can move them. The top-level copies
 * are already patched.
 *
 * What makes the deferral defensible is REACHABILITY: the only `next/image` call site
 * renders a first-party static asset, and `next.config.ts` declares no image configuration,
 * so Next's optimizer cannot be pointed at a remote or user-supplied URL. This test pins
 * that premise. If someone adds image config, this fails and forces the deferral to be
 * re-argued on the diff that invalidates it.
 *
 * The assertion is deliberately WIDER than `images.remotePatterns`: `images.domains` (the
 * deprecated Next 15 spelling, still functional) and a custom `images.loader` each revive
 * reachability, and a `remotePatterns`-keyed check would stay green through both.
 *
 * RECORDED RESIDUAL — this control does not cover everything, and saying so is the point:
 * a same-origin proxy route would reach the nested decoder with no image config at all,
 * because `<Image src="/api/...">` is a LOCAL src that the optimizer fetches and decodes
 * itself. That path does not exist today (`logo_url` has zero consumers; the route exposes
 * only POST/DELETE) and is partly mitigated (stored objects are re-encoded to WebP by the
 * PATCHED top-level sharp before storage). It is stated in the follow-up issue rather than
 * papered over by widening a guard that structurally cannot see it.
 */
describe("next.config.ts declares no image configuration", () => {
  const configPath = join(__dirname, "..", "next.config.ts");
  const source = readFileSync(configPath, "utf8");

  // Strip comments before asserting: this file's own prose names `images` (and so does this
  // test's rationale), so a bare-token grep over the raw source would match the explanation
  // rather than the configuration — the exact false-positive class that gets a guard
  // disabled. Anchored on the syntactic shape a config key must take.
  const withoutComments = source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^[ \t]*\/\/.*$/gm, "");

  it("has no `images` key at all (not merely no remotePatterns)", () => {
    const imagesKey = /^\s*images\s*:/m;
    expect(
      imagesKey.test(withoutComments),
      "next.config.ts declares an `images` key. That revives the reachability of Dependabot " +
        "advisory 144 (nested sharp, high) and 161/162/170 (nested postcss), which are " +
        "deliberately left OPEN on the argument that Next's image optimizer cannot be " +
        "pointed at remote or user-supplied bytes. Re-argue the deferral on this diff, or " +
        "clear the advisories by moving to next 16.x. See ADR-191 and the follow-up issue.",
    ).toBe(false);
  });

  it("has no `images.domains` and no custom `images.loader` (the narrow-check holes)", () => {
    expect(/\bdomains\s*:/.test(withoutComments)).toBe(false);
    expect(/\bloader(File)?\s*:/.test(withoutComments)).toBe(false);
  });

  // Anti-vacuity: proves the file was actually read and the comment-stripper did not eat
  // everything. Without this, a bad path or an over-greedy strip makes every assertion
  // above pass against an empty string.
  it("actually read next.config.ts", () => {
    expect(source.length).toBeGreaterThan(500);
    expect(withoutComments).toMatch(/^\s*const nextConfig\s*:\s*NextConfig\s*=/m);
  });
});
