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
