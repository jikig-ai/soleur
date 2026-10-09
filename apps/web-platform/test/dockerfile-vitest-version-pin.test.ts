import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import canaryConfig from "./vitest.canary.config";

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

  // Canary-config specifier pin (#9860): in the runner image vitest is a
  // global `npm install -g` and /app has no `node_modules/vitest`, so a bare
  // specifier written into the config file resolves against nothing and the
  // whole probe fails at config-load with `[UNRESOLVED_IMPORT]` (suite-file
  // `vitest` imports resolve internally to the running install; config-file
  // imports do not). The ban covers every specifier-resolution form, not just
  // the `import` keyword: `export … from "x"` re-exports resolve identically,
  // `import(…)` at any position, `require(…)`, and a `;`-separated `import`
  // on a shared line. `import.meta` is excluded — it resolves no specifier.
  // Type-space imports (`import type`, JSDoc `{import("x").T}`) are banned
  // too: the pin reads text, not semantics, and the simpler invariant is the
  // point.
  it("test/vitest.canary.config.ts carries no specifier-resolution forms — the in-image run resolves nothing from the config file", () => {
    const config = read("test/vitest.canary.config.ts");
    const code = config
      .split("\n")
      .filter((l) => !/^\s*\/\//.test(l)) // drop whole-line comments; they legitimately name banned forms
      .join("\n");
    // Vacuity floor: an empty or comment-only file satisfies every ban — the
    // file must still carry its export for the guard to mean anything.
    expect(code).toMatch(/export\s+default/);
    const BANNED = [
      /(^|;)\s*import(?![\w.])/m, // static/side-effect imports, incl. post-`;`
      /\bimport\s*\(/, // dynamic import(), any position
      /\bexport\b[^\n]*\bfrom\s*["']/, // re-export specifiers
      /\brequire\s*\(/, // CJS specifier loads
    ] as const;
    for (const re of BANNED) expect(code).not.toMatch(re);
    // Self-pin probes (guard-contract harness row): each predicate must fire
    // on its own banned shape, or a weakened regex vacates the guard while
    // staying green in both worlds.
    expect('import { x } from "pkg"').toMatch(BANNED[0]);
    expect('const m = await import("pkg")').toMatch(BANNED[1]);
    expect('export { a } from "pkg"').toMatch(BANNED[2]);
    expect('const r = require("pkg")').toMatch(BANNED[3]);
  });

  // Exact-shape pin (#9860): dropping `defineConfig` also dropped
  // UserConfig excess-property checking, and config VALUES reach the resolver
  // the same way specifiers do — `environment: "jsdom"`, `coverage.provider`,
  // `reporters`, custom `pool`/`browser` all resolve packages that exist
  // locally (devDeps) but are `--omit=dev`-pruned in-image. A deep-equal on
  // the imported object pins keys AND values: a typo'd key, a drifted
  // `environment`, or a new resolution-reaching key all go RED at PR time.
  it("test/vitest.canary.config.ts exports exactly the pinned shape", () => {
    expect(canaryConfig).toEqual({
      cacheDir: "/tmp/vitest-cache",
      test: {
        environment: "node",
        include: ["test/sandbox-isolation.test.ts"],
        testTimeout: 120_000,
        hookTimeout: 60_000,
      },
    });
  });

  // Payload-specifier pin (#9860): the same unresolvable-module class applies
  // one level down — a bare specifier in the suite or helper file resolves
  // in-image only if it is a `node:` builtin, vitest-internal (`vitest`,
  // `vitest/*`), a prod `dependencies` entry (`npm ci --omit=dev` prunes
  // devDeps), or a relative path INSIDE the baked payload set. The payload
  // list, the Dockerfile COPY set and the .dockerignore bang set are pinned
  // to each other so a payload rename forces this test's list to move with it
  // (a stale-file-persists rename would otherwise leave the guard green over
  // a dead path).
  it("the canary payload's specifiers resolve in the runner image (builtins, vitest-internal, prod deps, in-payload relatives)", () => {
    const payload = [
      "test/vitest.canary.config.ts",
      "test/sandbox-isolation.test.ts",
      "test/helpers/sandbox-isolation-fixtures.ts",
    ];
    const dockerfile = read("Dockerfile");
    const dockerignore = read(".dockerignore");
    for (const p of payload) {
      const esc = p.replace(/\./g, "\\.");
      expect(dockerfile, `Dockerfile must COPY ${p} into the runner stage`).toMatch(
        new RegExp(`COPY\\s+--from=builder\\s+/app/${esc}\\s+\\./${esc}`),
      );
      expect(dockerignore, `.dockerignore must re-include ${p}`).toContain(`!${p}`);
    }
    const deps = new Set(
      Object.keys(
        (JSON.parse(read("package.json")) as {
          dependencies?: Record<string, string>;
        }).dependencies ?? {},
      ),
    );
    const unresolvable: string[] = [];
    for (const rel of payload) {
      const code = read(rel)
        .split("\n")
        .filter((l) => !/^\s*\/\//.test(l))
        .join("\n");
      const specRe =
        /(?:import|export)\s[^'"]*?\bfrom\s*["']([^"']+)["']|(?:^|;)\s*import\s*["']([^"']+)["']|\bimport\s*\(\s*["']([^"']+)["']|\brequire\s*\(\s*["']([^"']+)["']/g;
      for (const m of code.matchAll(specRe)) {
        const spec = m[1] ?? m[2] ?? m[3] ?? m[4];
        if (spec.startsWith("node:") || spec === "vitest" || spec.startsWith("vitest/"))
          continue;
        if (spec.startsWith(".")) {
          const resolved = path.posix.normalize(
            path.posix.join(path.posix.dirname(rel), spec),
          );
          const inPayload = payload.some(
            (p) =>
              resolved === p.replace(/\.ts$/, "") ||
              `${resolved}.ts` === p ||
              `${resolved}/index.ts` === p,
          );
          if (!inPayload) unresolvable.push(`${rel} → ${spec} (escapes payload)`);
          continue;
        }
        const depHit = [...deps].some((d) => spec === d || spec.startsWith(`${d}/`));
        if (!depHit) unresolvable.push(`${rel} → ${spec} (not a prod dependency)`);
      }
    }
    expect(unresolvable).toEqual([]);
  });
});
