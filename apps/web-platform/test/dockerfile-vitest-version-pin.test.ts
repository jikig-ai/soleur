import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Drift guard (#2640): the vitest the deploy-time canary executes is a global
// `npm install -g` in the Dockerfile `cli-tools` stage — NOT the devDependency
// `npm ci` resolves. If the two drift, the canary's cross-workspace isolation
// verdict measures a different runner than the suite was authored against,
// and the report-only deploy probe (ci-deploy.sh `docker exec … vitest run`)
// reports on a binary nobody tests locally. The lockfile's
// `node_modules/vitest` entry is the independently maintained reference; the
// Dockerfile pin is compared to the lock, not to a second copy of itself
// (playwright-mcp-version-pin.test.ts precedent). The `--before`/`--ignore-scripts`
// flag pair mirrors the likec4 install convention: `--before` bounds the
// floating transitive tree to a cutoff after the pin's publish date, and
// `--ignore-scripts` keeps the install mode identical to what the tests that
// consume the binary assume.
const ROOT = path.resolve(__dirname, "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

describe("Dockerfile vitest global-install pin parity", () => {
  it("`npm install -g vitest@X` matches package-lock's vitest and carries --before + --ignore-scripts", () => {
    const dockerfile = read("Dockerfile");
    const lock = JSON.parse(read("package-lock.json")) as {
      packages: Record<string, { version?: string }>;
    };

    // Anchor on the install-line form, never a bare `vitest` substring: a
    // comment naming the package must not satisfy this guard. Whole-line `#`
    // comments are dropped before matching; the image carries exactly one
    // vitest resolution site (like the likec4 single-site rule).
    const installLines = dockerfile
      .split("\n")
      .filter((l) => !/^\s*#/.test(l))
      .filter((l) => /npm install -g vitest@[0-9]/.test(l));
    expect(
      installLines,
      "Dockerfile must hold exactly one non-comment `npm install -g vitest@<version>` line",
    ).toHaveLength(1);

    const installLine = installLines[0];
    const version = installLine.match(/npm install -g vitest@([^\s"'`]+)/)![1];
    expect(
      version,
      `Dockerfile vitest pin must be an exact version, found ${JSON.stringify(version)}`,
    ).toMatch(/^\d+\.\d+\.\d+$/);

    const lockfileVersion = lock.packages["node_modules/vitest"]?.version;
    expect(
      lockfileVersion,
      "package-lock.json must resolve node_modules/vitest",
    ).toBeTruthy();
    expect(version).toBe(lockfileVersion);

    expect(
      installLine,
      "the vitest install line must carry `--before=<YYYY-MM-DD>` (bounds the floating transitive tree, likec4 convention)",
    ).toMatch(/--before=\d{4}-\d{2}-\d{2}/);
    expect(
      installLine,
      "the vitest install line must carry `--ignore-scripts` (same install mode the tests validate)",
    ).toMatch(/(^|\s)--ignore-scripts(\s|$)/);
  });

  // Canary-config minimality pin (#2640 review): vitest.canary.config.ts is the
  // config the deploy probe runs INSIDE the runner image, where only the
  // three-file payload exists (test/, helpers/, vitest.canary.config.ts). A
  // drift adding a `globalSetup`/`setupFiles`/`projects` key — or widening the
  // include glob past the payload file — compiles locally but fails in-image
  // (the referenced files are pruned), surfacing as a Sentry page on every
  // deploy. Pin the shape so the discovery happens at PR time.
  it("test/vitest.canary.config.ts stays minimal — payload-only include, no setup hooks or project fan-out", () => {
    const config = read("test/vitest.canary.config.ts");
    const code = config
      .split("\n")
      .filter((l) => !/^\s*\/\//.test(l)) // drop whole-line comments; they may name keys
      .join("\n");
    expect(code).not.toMatch(/\b(globalSetup|setupFiles|projects|workspace)\s*:/);
    expect(code).toMatch(/include:\s*\[\s*"test\/sandbox-isolation\.test\.ts"\s*\]/);
  });

  // Canary-config zero-imports pin (#9860): in the runner image vitest is a
  // global `npm install -g` and /app has no `node_modules/vitest`, so the
  // config file's bare specifiers have nothing to resolve against — a single
  // `import … from "vitest/config"` fails the whole probe with
  // `[UNRESOLVED_IMPORT]` at config-load (suite-file `vitest` imports resolve
  // internally to the running install; config-file imports do not). The `\b`
  // terminator also catches a leading-position dynamic `import(…)`, which a
  // `\s`-anchored predicate would miss.
  it("test/vitest.canary.config.ts carries zero import statements — the in-image run resolves no bare specifiers from the config file", () => {
    const config = read("test/vitest.canary.config.ts");
    const code = config
      .split("\n")
      .filter((l) => !/^\s*\/\//.test(l)) // drop whole-line comments; they may name keys
      .join("\n");
    expect(code).not.toMatch(/^\s*import\b/m);
  });
});
