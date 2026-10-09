import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { isBuiltin } from "node:module";
import path from "node:path";
import canaryConfig from "./vitest.canary.config";
import { parseModule, specifiersOf } from "./helpers/ts-import-graph";
import { stripComments } from "./helpers/strip-comments";

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
  // global `npm install -g` and /app has no `node_modules/vitest`, so a
  // specifier written into the config file resolves against nothing and the
  // whole probe fails at config-load with `[UNRESOLVED_IMPORT]` (suite-file
  // `vitest` imports resolve internally to the running install; config-file
  // specifiers do not). Extraction goes through the shared AST walker
  // (helpers/ts-import-graph.ts › specifiersOf) — a regex would miss
  // multiline `export {…} from`, comment-gapped and non-line-start forms;
  // the walker covers import/export-from/import-equals/require()/import()
  // and fails closed on non-literal arguments. Type-only clauses are erased
  // by TypeScript and resolve nothing at runtime, so they are permitted —
  // JSDoc `import("x")` types never reach here because comments are stripped
  // by the parser (helpers/strip-comments.ts), not a regex.
  it("test/vitest.canary.config.ts resolves zero specifiers — the in-image run can resolve none", () => {
    const code = stripComments(
      read("test/vitest.canary.config.ts"),
      "vitest.canary.config.ts",
    );
    // Vacuity floor: an empty or comment-only file satisfies every ban — the
    // file must still carry its export for the guard to mean anything.
    expect(code).toMatch(/export\s+default/);
    const sf = parseModule("vitest.canary.config.ts", code);
    expect(
      specifiersOf(sf, { elideTypeOnlySpecifiers: true }),
      "config file must contain zero specifier-resolution edges",
    ).toEqual([]);
    // Specifier-bearing channels the module graph does not model.
    const BANNED = [
      /\bimport\.meta\s*(?:\.(?:resolve|glob)|\[\s*["'](?:resolve|glob)["']\s*\])\s*\(/,
      /\b(?:vi|vitest)\s*(?:\.(?:mock|doMock|importActual|importMock|hoisted)|\[\s*["'](?:mock|doMock|importActual|importMock|hoisted)["']\s*\])\s*\(/,
      /\bnew\s+URL\s*\(\s*[^,]+,\s*import\.meta\.url/,
    ] as const;
    for (const re of BANNED) expect(code).not.toMatch(re);
    // Self-pin probes (guard-contract harness row): the extractor and each
    // side-channel predicate must fire on their own banned shape, or a
    // weakening stays green in both worlds.
    for (const src of [
      'import { x } from "pkg"',
      'export {\n  a\n} from "pkg"',
      'import "pkg"',
      'const m = await import("pkg")',
      'const r = require("pkg")',
    ]) {
      const sfs = parseModule("probe.ts", src);
      expect(specifiersOf(sfs).length, `extractor must see ${src}`).toBe(1);
    }
    expect('import.meta.resolve("pkg")').toMatch(BANNED[0]);
    expect('import.meta["resolve"]("pkg")').toMatch(BANNED[0]);
    expect('vi.mock("pkg")').toMatch(BANNED[1]);
    expect('vitest["importActual"]("pkg")').toMatch(BANNED[1]);
    expect('new URL("./x", import.meta.url)').toMatch(BANNED[2]);
    // `import.meta` on its own resolves no specifier — must not trip.
    expect("const u = import.meta.url;").not.toMatch(BANNED[0]);
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
  // one level down — a specifier in the suite or helper file resolves
  // in-image only if it is a builtin, vitest-internal (`vitest`, `vitest/*`),
  // a prod `dependencies` entry (`npm ci --omit=dev` prunes devDeps), or a
  // relative path INSIDE the baked payload set. The runner payload set is
  // derived BOTH ways — test list == Dockerfile runner COPY set == banged
  // .dockerignore set — so an added or renamed payload file forces this
  // list to move with it.
  it("the canary payload's specifiers resolve in the runner image (builtins, vitest-internal, prod deps, in-payload relatives)", () => {
    const payload = [
      "test/vitest.canary.config.ts",
      "test/sandbox-isolation.test.ts",
      "test/helpers/sandbox-isolation-fixtures.ts",
    ].sort();
    const dockerfile = read("Dockerfile");
    const dockerignore = read(".dockerignore");
    // The runner-stage COPY set must equal the payload list in BOTH
    // directions (a new COPY, or a missing one, is a RED); the .dockerignore
    // bang set must cover payload one-directionally — other `!test/…` bangs
    // legitimately exist for builder-stage files outside the payload.
    const copySet = [
      ...dockerfile.matchAll(
        /^COPY\s+(?:--\S+\s+)*\/app\/(test\/\S+)\s+\.\/(test\/\S+)\s*$/gm,
      ),
    ].map((m) => ({ src: m[1], dst: m[2] }));
    for (const { src, dst } of copySet)
      expect(dst, `Dockerfile COPY must keep ${src} at its own path`).toBe(src);
    expect(
      copySet.map((c) => c.src).sort(),
      "Dockerfile runner COPY set must equal the canary payload list",
    ).toEqual(payload);
    const bangSet = [
      ...dockerignore.matchAll(/^!(test\/\S+)\s*$/gm),
    ].map((m) => m[1]);
    for (const p of payload)
      expect(bangSet, `.dockerignore must re-include ${p}`).toContain(p);

    const pkg = JSON.parse(read("package.json")) as {
      dependencies?: Record<string, string>;
      optionalDependencies?: Record<string, string>;
    };
    // `npm ci --omit=dev` installs dependencies + optionalDependencies.
    const deps = new Set([
      ...Object.keys(pkg.dependencies ?? {}),
      ...Object.keys(pkg.optionalDependencies ?? {}),
    ]);
    const depHit = (spec: string) =>
      [...deps].some((d) => spec === d || spec.startsWith(`${d}/`));
    const inPayload = (from: string, spec: string) => {
      const resolved = path.posix.normalize(
        path.posix.join(path.posix.dirname(from), spec),
      );
      // vitest/NodeNext tolerate `./x`, `./x.ts`, and `.js`→`.ts` spelling.
      const candidates = [
        resolved,
        `${resolved}.ts`,
        `${resolved}/index.ts`,
        resolved.replace(/\.js$/, ".ts"),
      ];
      return candidates.some((c) => payload.includes(c));
    };
    const classify = (file: string, spec: string | null, argText = "") => {
      if (spec === null)
        return `${file} → non-literal specifier (${argText})`;
      if (isBuiltin(spec) || spec === "vitest" || spec.startsWith("vitest/"))
        return null;
      if (spec.startsWith("."))
        return inPayload(file, spec)
          ? null
          : `${file} → ${spec} (escapes payload)`;
      return depHit(spec) ? null : `${file} → ${spec} (not a prod dependency)`;
    };

    const unresolvable: string[] = [];
    const literals: string[] = [];
    for (const rel of payload) {
      const code = stripComments(read(rel), rel);
      for (const s of specifiersOf(parseModule(rel, code), {
        elideTypeOnlySpecifiers: true,
      })) {
        const bad = classify(
          rel,
          s.kind === "literal" ? s.spec : null,
          s.kind === "non-literal" ? s.argText : "",
        );
        if (bad) unresolvable.push(bad);
        else if (s.kind === "literal") literals.push(s.spec);
      }
      // Specifier-bearing call forms the module graph does not model:
      // vi.mock/vi.importActual family, import.meta.glob/resolve,
      // require.resolve/createRequire, and `new URL("./x", import.meta.url)`
      // (the release-#8136 class). A NON-literal first arg on any of these
      // is itself a problem — the guard can't classify what it can't read.
      for (const m of code.matchAll(
        /\b(?:vi|vitest)\s*(?:\.(?:mock|doMock|importActual|importMock|hoisted)|\[\s*["'](?:mock|doMock|importActual|importMock|hoisted)["']\s*\])\s*\(\s*([^,)]*)|\b(?:import\.meta\s*(?:\.(?:resolve|glob)|\[\s*["'](?:resolve|glob)["']\s*\])|require\.resolve|createRequire)\s*\(\s*([^,)]*)|\bnew\s+URL\s*\(\s*([^,)]+)\s*,\s*import\.meta\.url/g,
      )) {
        const arg = (m[1] ?? m[2] ?? m[3]).trim();
        const lit = /^["']([^"']+)["']$/.exec(arg)?.[1];
        const bad = classify(rel, lit ?? null, lit ? "" : arg || "(empty)");
        if (bad) unresolvable.push(bad);
        else if (lit) literals.push(lit);
      }
    }
    // Vacuity floor: the sweep must extract the payload's known imports —
    // a broken extractor producing zero specifiers would pass `toEqual([])`
    // vacuously.
    for (const known of [
      "vitest",
      "node:crypto",
      "@anthropic-ai/claude-agent-sdk",
      "./helpers/sandbox-isolation-fixtures",
    ]) {
      expect(literals, `extractor must find ${known} (vacuity floor)`).toContain(known);
    }
    expect(unresolvable).toEqual([]);
  });
});
