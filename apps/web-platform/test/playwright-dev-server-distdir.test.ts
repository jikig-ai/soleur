import { readFileSync } from "node:fs";
import { join, normalize } from "node:path";
import { describe, expect, it } from "vitest";
import { stripComments } from "./helpers/strip-comments";

/**
 * The e2e harness runs TWO next dev servers (a public origin and an authenticated one).
 * Since next 16 that is only possible if they use different dist directories.
 *
 * next 16 acquires a lock at `<distDir>/lock` when `experimental.lockDistDir` is set, and
 * that flag DEFAULTS TO TRUE (next/dist/server/config-shared.js). The second server to
 * start exits with "Another next dev server is already running" and Playwright then fails
 * the whole run at `config.webServer` startup — the outermost of two causes behind
 * #7591's red `e2e` check.
 *
 * The lock is keyed on the DIST DIRECTORY, not the port: setupDevBundler() joins
 * `opts.dir` with `nextConfig.distDir` before acquiring. Distinct ports are therefore not
 * sufficient, which is exactly why this looks like it should already work.
 *
 * COMMENTS ARE STRIPPED BEFORE MATCHING, and that is load-bearing rather than tidy. These
 * assertions read the config as TEXT, and this PR adds prose to both files that mentions
 * `NEXT_DIST_DIR` and `distDir`. Measured against the un-stripped version: replacing a live
 * `NEXT_DIST_DIR:` line with a commented-out copy left all four assertions green while the
 * two servers shared one lock — the regression this file exists to prevent, satisfied by
 * the comment explaining it (cq-assert-anchor-not-bare-token).
 */


const read = (name: string) => stripComments(readFileSync(join(__dirname, "..", name), "utf-8"));

describe("playwright dev servers use distinct dist directories", () => {
  const playwright = read("playwright.config.ts");
  const distDirs = [...playwright.matchAll(/NEXT_DIST_DIR:\s*"([^"]+)"/g)].map((m) => m[1]);
  // Counted by readiness key (`port:` or `url:`), not by the command string. Playwright
  // rejects an entry that sets BOTH and accepts one that sets NEITHER (no readiness
  // poll), so counting the readiness key alone would miss a keyless entry: the entry
  // count is cross-checked against `command:` below. Counting occurrences of
  // "command: `npm run dev`" instead would answer "how many entries use that one command"
  // — measured: a third entry spelled `npm run dev:mock` was invisible to it, and its
  // undercount exactly cancelled the missing declaration, leaving the suite green.
  const webServerBlock = playwright.slice(playwright.indexOf("webServer:"));
  // Unanchored on purpose: a single-line entry (`{ command: ..., url: ... }`) must count too.
  const webServers = (webServerBlock.match(/\b(?:port|url):\s/g) ?? []).length;
  const webServerCommands = (webServerBlock.match(/\bcommand:\s/g) ?? []).length;
  // One segment per webServer entry (text after each `command:`), so per-entry properties
  // are asserted per entry rather than counted across the whole block.
  const entries = webServerBlock.split(/\bcommand:\s/).slice(1);

  it("polls /login for readiness on both servers, with a budget that covers the cold compile", () => {
    // `port:` is a TCP check: a server whose first compile 5xx's counts as ready and the
    // suite then fails one test at a time (64 reds, ~14 min). `url:` treats a 5xx as not
    // ready. Reverting either entry, or pointing it at a path that is not `/login`
    // (which renders app/layout.tsx), must turn this red.
    expect(entries).toHaveLength(2);
    const [pub, auth] = entries;
    expect(pub).toMatch(/\burl:\s*`http:\/\/localhost:\$\{PUBLIC_PORT\}\/login`/);
    expect(auth).toMatch(/\burl:\s*`http:\/\/localhost:\$\{AUTH_PORT\}\/login`/);
    for (const entry of entries) {
      expect(entry, "an entry must not fall back to a TCP port check").not.toMatch(/\bport:\s/);
      expect(entry, "every entry needs the 180s readiness budget").toMatch(/\btimeout:\s*180_000\b/);
    }
  });

  it("declares one NEXT_DIST_DIR per webServer entry", () => {
    expect(webServerCommands, "every webServer entry must carry a readiness key").toBe(webServers);
    expect(webServers, "expected the two-dev-server harness").toBe(2);
    expect(
      distDirs.length,
      "every webServer must pin NEXT_DIST_DIR or it inherits the default and collides",
    ).toBe(webServers);
  });

  it("gives each server a genuinely different directory", () => {
    // Compared as NORMALISED PATHS, not strings: `.next/e2e-public` and
    // `.next/e2e-public/` are two strings and one directory, so a string-inequality check
    // accepts a pair that shares a single `<distDir>/lock`.
    const normalised = distDirs.map((d) => normalize(d));
    expect(
      new Set(normalised).size,
      `dist dirs resolve to the same directory: ${distDirs.join(", ")}`,
    ).toBe(normalised.length);
  });

  it("keeps them under .next/ so .gitignore still covers them", () => {
    for (const d of distDirs) {
      expect(d, `${d} escapes the ignored .next/ tree`).toMatch(/^\.next\//);
    }
  });

  it("next.config.ts honours NEXT_DIST_DIR", () => {
    const cfg = read("next.config.ts");
    expect(cfg, "next.config.ts must read NEXT_DIST_DIR or the env var is inert").toMatch(
      /^\s*distDir:\s*process\.env\.NEXT_DIST_DIR/m,
    );
  });

  it("declares every dist dir in tsconfig's include, so next does not rewrite it", () => {
    // next writes `<distDir>/types/**/*.ts` + `<distDir>/dev/types/**/*.ts` into the
    // TRACKED tsconfig.json on startup (writeConfigurationDefaults). Undeclared, every CI
    // e2e run dirties a tracked file; declared, next finds them present and leaves it
    // alone (measured: both dist dirs, no rewrite).
    const tsconfig = JSON.parse(readFileSync(join(__dirname, "..", "tsconfig.json"), "utf-8"));
    for (const d of distDirs) {
      for (const suffix of ["types/**/*.ts", "dev/types/**/*.ts"]) {
        expect(tsconfig.include, `tsconfig.include is missing ${d}/${suffix}`).toContain(
          `${d}/${suffix}`,
        );
      }
    }
  });
});
