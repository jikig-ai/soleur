import { describe, it, expect } from "vitest";
import fs from "fs";
import path from "path";

// A file in the Docker build context must not import a file the build context
// EXCLUDES.
//
// The failure this guards is silent in every pre-merge gate. Local `tsc`, the
// CI `test` job and `vitest` all see the complete tree, so an import from a
// dockerignored directory resolves for them. Only the image build sees the
// pruned tree, and `next build` type-checks the context-root `*.config.ts`
// files, so the break surfaces as a production release failure and nowhere
// else.
//
// #7666 did exactly this: it added `test/repo-wide-suites.ts` and imported it
// from `vitest.config.ts`, while `.dockerignore` prunes `test/`. Eight
// consecutive releases failed (2026-08-20 -> 2026-08-26) and production served
// a stale build for six days. The prior instance of the same class was #5890
// (`scripts/sandbox-canary.mjs`), remedied the same way — a `!` re-include.

const APP_ROOT = path.resolve(__dirname, "..");

/** Root-level config files that `next build` type-checks inside the image. */
function contextRootConfigs(): string[] {
  return fs
    .readdirSync(APP_ROOT)
    .filter((f) => f.endsWith(".config.ts"))
    .sort();
}

function dockerignoreLines(): string[] {
  return fs
    .readFileSync(path.join(APP_ROOT, ".dockerignore"), "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("#"));
}

/**
 * Docker semantics, narrowed to the two forms this file actually uses:
 * a `dir/` line prunes everything beneath `dir`, and a later `!path` line
 * re-includes that exact path. Last matching rule wins.
 */
export function isExcludedFromContext(relPath: string, lines: string[]): boolean {
  let excluded = false;
  for (const line of lines) {
    const negated = line.startsWith("!");
    const pattern = negated ? line.slice(1) : line;
    let match = false;
    if (pattern.endsWith("/")) {
      match = relPath === pattern.slice(0, -1) || relPath.startsWith(pattern);
    } else {
      match = relPath === pattern;
    }
    if (match) excluded = !negated;
  }
  return excluded;
}

/** Relative import specifiers (`./x`, `../x`) declared by a source file. */
function relativeImports(file: string): string[] {
  const src = fs.readFileSync(file, "utf8");
  const out: string[] = [];
  const re = /^\s*(?:import|export)[^'"]*?from\s+["'](\.[^"']+)["']/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) out.push(m[1]);
  return out;
}

function resolveToRepoRelative(configFile: string, spec: string): string | null {
  const base = path.resolve(APP_ROOT, path.dirname(configFile), spec);
  for (const cand of [base, `${base}.ts`, `${base}.tsx`, path.join(base, "index.ts")]) {
    if (fs.existsSync(cand) && fs.statSync(cand).isFile()) {
      return path.relative(APP_ROOT, cand);
    }
  }
  return null;
}

describe("docker build context: no included file imports an excluded one", () => {
  const lines = dockerignoreLines();

  it("enumerates a non-trivial set of context-root configs", () => {
    // Anti-vacuity floor: if the readdir ever stops finding configs, every
    // assertion below passes for the wrong reason.
    expect(contextRootConfigs().length).toBeGreaterThanOrEqual(3);
  });

  it("models .dockerignore correctly (controls)", () => {
    // Positive control: test/ is pruned, so an arbitrary file under it is out.
    expect(isExcludedFromContext("test/some-file.ts", lines)).toBe(true);
    // Negative control: a re-included path is back in.
    expect(isExcludedFromContext("test/repo-wide-suites.ts", lines)).toBe(false);
    // Negative control: an untouched directory is never excluded.
    expect(isExcludedFromContext("lib/security-headers.ts", lines)).toBe(false);
  });

  it.each(contextRootConfigs())(
    "%s imports only files that survive the build context prune",
    (config) => {
      const offenders: string[] = [];
      for (const spec of relativeImports(config)) {
        const target = resolveToRepoRelative(config, spec);
        if (target === null) continue; // unresolvable here; tsc owns that error
        if (isExcludedFromContext(target, lines)) {
          offenders.push(`${config} imports "${spec}" -> ${target}, excluded by .dockerignore`);
        }
      }
      expect(
        offenders,
        offenders.length
          ? `\n${offenders.join(
              "\n",
            )}\n\nThis compiles locally and in CI but FAILS the production image build.\nEither add a "!<path>" re-include to apps/web-platform/.dockerignore\n(see !test/repo-wide-suites.ts and !scripts/sandbox-canary.mjs), or move the\nimported file out of the excluded directory.\n`
          : undefined,
      ).toEqual([]);
    },
  );
});

/**
 * WIDENING (#7756). The block above is correct and its WINDOW was narrower than
 * the property this file names: it enumerated only context-root `*.config.ts`,
 * and `relativeImports()` matches only `./`-style specifiers. So it was blind on
 * both axes at once to the shape that broke the release —
 * `lib/feature-flags/identity.test.ts` (build-INCLUDED, not a root config)
 * importing `@/test/helpers/mock-supabase` (an ALIAS, not a relative path).
 *
 * The import was years old and unchanged; #7756's Next 16 bump widened the set
 * of files `next build` type-checks to include colocated `lib/**\/*.test.ts`,
 * which is why every pre-merge gate stayed green while the image build failed.
 *
 * Both axes are covered here: every build-INCLUDED source file, and the `@/`
 * alias form in addition to relative specifiers.
 */

/**
 * Context-root entries that survive the `.dockerignore` prune — DERIVED, never
 * hand-listed.
 *
 * The first draft of this block hardcoded
 * `["app", "components", "hooks", "lib", "server"]`, which reproduced the very
 * defect this file exists to catch, one level up: `e2e/` (16 files) and the root
 * `middleware.ts` / `instrumentation.ts` are all in-context and type-checked by
 * `next build`, and none was in that window. `tsconfig.json` includes `**\/*.ts`
 * with no exclude beyond node_modules, so the type-checked set is "whatever
 * survives the prune" — deriving it is the only form that cannot drift as
 * directories are added.
 */
function buildIncludedRoots(lines: string[]): { dirs: string[]; rootFiles: string[] } {
  const dirs: string[] = [];
  const rootFiles: string[] = [];
  for (const entry of fs.readdirSync(APP_ROOT, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
    if (entry.isDirectory()) {
      if (!isExcludedFromContext(`${entry.name}/`, lines)) dirs.push(entry.name);
    } else if (/\.tsx?$/.test(entry.name) && !isExcludedFromContext(entry.name, lines)) {
      rootFiles.push(entry.name);
    }
  }
  return { dirs: dirs.sort(), rootFiles: rootFiles.sort() };
}

function walkTs(dir: string, acc: string[] = []): string[] {
  const abs = path.join(APP_ROOT, dir);
  if (!fs.existsSync(abs)) return acc;
  for (const entry of fs.readdirSync(abs, { withFileTypes: true })) {
    const rel = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "node_modules" || entry.name === ".next") continue;
      walkTs(rel, acc);
    } else if (/\.tsx?$/.test(entry.name)) {
      acc.push(rel);
    }
  }
  return acc;
}

/** `@/x` alias specifiers declared by a source file (tsconfig maps `@/*` -> app root). */
function aliasImports(file: string): string[] {
  const src = fs.readFileSync(path.join(APP_ROOT, file), "utf8");
  const out: string[] = [];
  // Covers `import … from "@/x"`, `export … from "@/x"`, and `vi.mock("@/x")`
  // — the mock form matters because it is how this very file references
  // build-excluded modules elsewhere.
  const re = /(?:from\s+|vi\.mock\(\s*|import\(\s*)["'](@\/[^"']+)["']/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) out.push(m[1]);
  return out;
}

function resolveAlias(spec: string): string | null {
  const base = path.resolve(APP_ROOT, spec.slice(2));
  // `index.tsx` and the JS extensions are not decoration: `components/icons/` is
  // an index.tsx barrel with no index.ts, so a candidate list of
  // [base, .ts, .tsx, index.ts] left 18 real edges resolving to null — and a
  // null target hits the `continue` below, i.e. it is silently NOT CHECKED.
  // A future prune of a directory whose entry point is an index.tsx barrel would
  // then report green while the image build died. Measured: adding these keeps
  // the sweep at 0 offenders, so it is a pure widening.
  for (const cand of [
    base,
    `${base}.ts`,
    `${base}.tsx`,
    `${base}.js`,
    `${base}.jsx`,
    `${base}.mjs`,
    path.join(base, "index.ts"),
    path.join(base, "index.tsx"),
    path.join(base, "index.js"),
  ]) {
    if (fs.existsSync(cand) && fs.statSync(cand).isFile()) {
      return path.relative(APP_ROOT, cand);
    }
  }
  return null;
}

describe("docker build context: build-included sources do not import excluded ones", () => {
  const lines = dockerignoreLines();
  const { dirs, rootFiles } = buildIncludedRoots(lines);
  const files = [...dirs.flatMap((d) => walkTs(d)), ...rootFiles].filter(
    (f) => !isExcludedFromContext(f, lines),
  );

  it("derives the in-context root set rather than hand-listing it", () => {
    // The directories a hardcoded list forgot. `e2e/` has no .dockerignore line
    // at all, so it ships into the context and `next build` type-checks it; one
    // `@/test/helpers/...` import added there reproduces #7756 past a green
    // guard. Root files matter for the same reason (middleware.ts is in-context).
    expect(dirs).toContain("e2e");
    expect(dirs).toContain("lib");
    expect(dirs).toContain("server");
    expect(rootFiles).toContain("middleware.ts");
    // ...and the pruned ones must NOT appear, or the derivation is inverted.
    expect(dirs).not.toContain("test");
    expect(dirs).not.toContain("scripts");
    expect(dirs).not.toContain("infra");
  });

  it("the walk drops nothing (per-root conservation against an independent enumerator)", () => {
    // A flat total floor is the wrong shape twice over. Too low, it tolerates a
    // silent collapse — `> 200` against ~820 real files survives dropping
    // `server/` entirely (316 files, the largest root). Too strict per-root, it
    // false-fails on a legitimately TS-free in-context dir such as `docs/`,
    // which is what a naive `> 5` floor did on its first run here.
    //
    // Conservation is the property that actually matters: for every root, what
    // walkTs() finds must equal what an INDEPENDENT enumerator finds. Zero is a
    // valid answer (docs/), and a root that silently stops being reached cannot
    // produce a matching zero when the disk says otherwise. fs.readdirSync's
    // recursive mode is a genuinely different code path from walkTs's hand-rolled
    // recursion, so agreement is evidence rather than a tautology.
    const independent = (dir: string): number => {
      const abs = path.join(APP_ROOT, dir);
      if (!fs.existsSync(abs)) return 0;
      return (fs.readdirSync(abs, { recursive: true }) as string[]).filter(
        (p) =>
          /\.tsx?$/.test(p) &&
          !p.split(path.sep).includes("node_modules") &&
          !p.split(path.sep).includes(".next"),
      ).length;
    };
    for (const dir of dirs) {
      expect(
        walkTs(dir).length,
        `${dir}: walkTs disagrees with an independent enumeration — the walk is dropping files`,
      ).toBe(independent(dir));
    }
    // Absolute floor too: conservation alone would pass on an empty repo.
    expect(files.length).toBeGreaterThan(400);
  });

  it("the walk reaches the file that broke the #7756 release", () => {
    // Non-vacuity control naming a concrete member: a future refactor that
    // stops walking lib/ must fail here rather than silently shrink coverage.
    expect(files).toContain(path.join("lib", "feature-flags", "identity.test.ts"));
    // ...and the root-level in-context files actually reach the swept set.
    // Without this, dropping `...rootFiles` from the spread survives: the total
    // floor still passes and middleware.ts silently stops being checked
    // (measured — that mutation survived until this line existed).
    expect(files).toContain("middleware.ts");
  });

  it("alias resolution is total — an unresolvable specifier is an UNCHECKED one", () => {
    // The offender sweep skips any specifier that resolves to null
    // (`if (target === null) continue`), so a resolver missing an extension does
    // not fail — it silently stops checking those edges. That makes the
    // offenders-is-empty assertion satisfiable by a resolver that resolves
    // nothing, and it is why dropping `index.tsx` from the candidate list
    // survived every other assertion in this file (measured).
    //
    // Pin resolution itself. `components/icons/` is an index.tsx barrel with no
    // index.ts, so this is 0 only while the candidate list stays complete.
    const unresolvable: string[] = [];
    for (const file of files) {
      for (const spec of aliasImports(file)) {
        if (resolveAlias(spec) === null) unresolvable.push(`${file} -> ${spec}`);
      }
    }
    expect(
      unresolvable,
      unresolvable.length
        ? `\n${unresolvable
            .slice(0, 10)
            .join(
              "\n",
            )}\n\nThese alias imports resolve to nothing, so the offender sweep SKIPS them.\nWiden the candidate list in resolveAlias() rather than accepting the gap.\n`
        : undefined,
    ).toEqual([]);
  });

  it("no build-included file imports a build-excluded module", () => {
    const offenders: string[] = [];
    for (const file of files) {
      for (const spec of [...aliasImports(file), ...relativeImports(file)]) {
        const target = spec.startsWith("@/")
          ? resolveAlias(spec)
          : resolveToRepoRelative(file, spec);
        if (target === null) continue; // unresolvable here; tsc owns that error
        if (isExcludedFromContext(target, lines)) {
          offenders.push(`${file} imports "${spec}" -> ${target}, excluded by .dockerignore`);
        }
      }
    }
    expect(
      offenders,
      offenders.length
        ? `\n${offenders.join(
            "\n",
          )}\n\nThis compiles locally and in CI but FAILS the production image build.\nEither add a "!<path>" re-include to apps/web-platform/.dockerignore\n(see !test/helpers/mock-supabase.ts, !test/repo-wide-suites.ts and\n!scripts/sandbox-canary.mjs), or move the imported file out of the\nexcluded directory.\n`
        : undefined,
    ).toEqual([]);
  });
});
