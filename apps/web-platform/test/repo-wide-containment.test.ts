/**
 * Containment guard for the gated app-local vitest projects (#7498).
 *
 * `test-all.sh` declines the `unit` and `component` projects when a diff
 * touches no `apps/web-platform/` file. That is only safe while every suite in
 * those projects is genuinely app-local. The moment one reads a file outside
 * the app, it FAILS OPEN: declined on exactly the diffs it exists to catch,
 * with the decline rendering as an intentional skip in the run summary. Nothing
 * else in the pipeline would notice — which is why this guard exists rather
 * than a convention.
 *
 * So the manifest is not hand-maintained. This recomputes the escape set from
 * disk and fails on any drift, naming the files.
 *
 * WHY THE PREDICATE IS DEPTH-AWARE, NOT A GREP
 *
 * The obvious spelling — grep the test files for `../../..` or for repo-root
 * path literals — is unsound in both directions, and this repo has been bitten
 * each way:
 *
 *   over-match:  `join(__dirname, "..", "..")` in `test/server/foo.test.ts`
 *                resolves to `apps/web-platform` itself. App-local, despite two
 *                levels of `..`. Likewise `test/c4-render.test.ts` contains the
 *                string `knowledge-base/engineering/...` but only as a synthetic
 *                `/workspaces/ws-1/...` constant it asserts against; it reads
 *                nothing. #7498 measured a literal-grep over-match of ~50 files.
 *
 *   under-match: `test/git-lock-marker-telemetry.test.ts` reaches the repo via
 *                `"../../../plugins/soleur/skills/..."`. A `readFileSync`-plus-
 *                repo-dir-literal heuristic misses it, and an under-match is
 *                the dangerous direction — it puts a repo-reading suite INSIDE
 *                the gated project.
 *
 * A path expression escapes the app only when its longest consecutive `..` run
 * EXCEEDS the file's depth below `apps/web-platform`. `test/server/x.test.ts`
 * is depth 2, so a 2-run lands on the app root (local) and a 3-run escapes.
 */
import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { REPO_WIDE_SUITES } from "./repo-wide-suites";

const APP_ROOT = join(fileURLToPath(new URL(".", import.meta.url)), "..");

/** All `..` hops in one expression, counting both spellings. */
function parentHops(expr: string): number {
  let hops = 0;
  for (const m of expr.matchAll(/(?:\.\.\/)+\.\.|\.\.(?:\/\.\.)+/g)) {
    hops = Math.max(hops, (m[0].match(/\.\./g) ?? []).length);
  }
  const seq = expr.match(/["']\.\.["'](?:\s*,\s*["']\.\.["'])+/g) ?? [];
  for (const m of seq) hops = Math.max(hops, (m.match(/["']\.\.["']/g) ?? []).length);
  if (hops === 0 && /["']\.\.["']/.test(expr)) hops = 1;
  return hops;
}

/** Longest consecutive `..` run anywhere in a file. */
function longestParentRun(text: string): number {
  let best = 0;
  for (const m of text.matchAll(/(?:\.\.\/)+\.\.|\.\.(?:\/\.\.)+/g)) {
    best = Math.max(best, (m[0].match(/\.\./g) ?? []).length);
  }
  for (const m of text.matchAll(/["']\.\.["'](?:\s*,\s*["']\.\.["'])+/g)) {
    best = Math.max(best, (m[0].match(/["']\.\.["']/g) ?? []).length);
  }
  return best;
}

/** Names a helper that resolves the repo root directly, at any depth. */
const REPO_ROOT_HELPER =
  /\bGIT_ROOT\b|\bfindRepoRoot\b|\brepoRoot\b|\bREPO_ROOT\b|\brepo_root\b|--show-toplevel/;

/**
 * Deepest reach of the file, in `..` hops, ACCOUNTING FOR ONE LEVEL OF
 * VARIABLE SUBSTITUTION.
 *
 * The naive "longest single run" under-matches on a chain, and under-matching
 * is the direction that fails open:
 *
 *   const APP = join(__dirname, "..", "..");   // 2 hops, == depth -> app root
 *   readFileSync(join(APP, "..", "..", "x"));  // +2 more -> the REPO
 *
 * `longestParentRun` sees 2 and calls a depth-2 file app-local. Summing the
 * referenced binding's hops sees 4 and correctly calls it an escape.
 */
function deepestReach(text: string): number {
  // const NAME = <expr containing ..>
  const bindings = new Map<string, number>();
  // SINGLE LINE, and the initialiser must be a genuine path ROOT (`__dirname`
  // or `import.meta`). A multi-line capture swallowed following statements and
  // credited their `..` to an unrelated binding — `const row = emitAndParse(…)`
  // picked up a later `join(__dirname, "../../server/…")` and mislabelled three
  // app-local suites as escapes. Over-inclusion is the safe direction, but a
  // guard that flags app-local files teaches people to pad the manifest.
  for (const m of text.matchAll(
    /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*([^;\n]*)/g,
  )) {
    if (!/__dirname|import\.meta/.test(m[2])) continue;
    const hops = parentHops(m[2]);
    if (hops > 0) bindings.set(m[1], hops);
  }
  let best = longestParentRun(text);
  // join(X, "..", "..") / resolve(X, "../..") where X is such a binding.
  for (const m of text.matchAll(/(?:join|resolve)\s*\(([^)]*)\)/g)) {
    const args = m[1];
    // Identifier references only — string literals stripped first. A binding
    // named `kb` was matching the LITERAL "kb" inside
    // `join(__dirname, "..", "components", "kb", f)`, which credited the
    // binding's own hop a second time and mislabelled an app-local suite.
    const idents = args.replace(/"[^"]*"|'[^']*'|`[^`]*`/g, "");
    let base = 0;
    for (const [name, hops] of bindings) {
      if (new RegExp(`\\b${name}\\b`).test(idents)) base = Math.max(base, hops);
    }
    if (base > 0) best = Math.max(best, base + parentHops(args));
  }
  return best;
}

function escapesText(text: string, depth: number): boolean {
  if (REPO_ROOT_HELPER.test(text)) return true;
  return deepestReach(text) > depth;
}

function escapesApp(relPath: string): boolean {
  const text = readFileSync(join(APP_ROOT, relPath), "utf8");
  return escapesText(text, relPath.split("/").length - 1);
}

/**
 * Non-test modules under test/ and lib/ that themselves escape the app. A gated
 * suite importing one becomes a repo reader without a single `..` of its own —
 * the import-graph hole a per-file text scan cannot see.
 */
function escapingHelpers(): Set<string> {
  const out = new Set<string>();
  for (const dir of ["test", "lib"]) {
    for (const f of walkAll(dir)) {
      if (/\.test\.tsx?$/.test(f) || !/\.(ts|tsx|mts|cts)$/.test(f)) continue;
      if (escapesApp(f)) out.add(f);
    }
  }
  return out;
}

/** Relative import specifiers, resolved to repo-app-relative paths. */
function relativeImports(relPath: string, text: string): string[] {
  const dir = relPath.split("/").slice(0, -1);
  const out: string[] = [];
  for (const m of text.matchAll(/(?:from|import)\s*\(?\s*["'](\.[^"']*)["']/g)) {
    const parts = [...dir];
    for (const seg of m[1].split("/")) {
      if (seg === "." || seg === "") continue;
      if (seg === "..") parts.pop();
      else parts.push(seg);
    }
    out.push(parts.join("/"));
  }
  return out;
}

function walkAll(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(join(APP_ROOT, dir), { withFileTypes: true })) {
    const rel = `${dir}/${entry.name}`;
    // `node_modules` only. NOT `__synthesized__`: the unit project's
    // `include: ["test/**/*.test.ts"]` does not skip it either, so skipping it
    // here would leave a directory inside the gated project that the guard
    // cannot see — a hole in a guard whose stated job is to have none.
    if (entry.isDirectory()) {
      if (entry.name === "node_modules") continue;
      walkAll(rel, acc);
    } else {
      acc.push(rel);
    }
  }
  return acc;
}

function walk(dir: string): string[] {
  return walkAll(dir).filter((f) => /\.test\.tsx?$/.test(f));
}

// Candidates for the containment check. `unit` (test|lib/**/*.test.ts) is the
// gated project, so its containment is load-bearing. `component`
// (test/**/*.test.tsx) runs always, so its arm is a kept invariant rather than
// a live guard — see the note on that arm below.
const gatedCandidates = [...walk("test"), ...walk("lib")].sort();
const unitFiles = gatedCandidates.filter((f) => f.endsWith(".test.ts"));

describe("repo-wide suite containment (#7498)", () => {
  it("no gated suite imports a helper that escapes the app", () => {
    // A suite with no `..` of its own still reads the repo if a module it
    // imports does. Per-file text scanning cannot see that; this can.
    const helpers = escapingHelpers();
    const offenders: string[] = [];
    for (const f of gatedCandidates) {
      if (REPO_WIDE_SUITES.includes(f)) continue;
      const text = readFileSync(join(APP_ROOT, f), "utf8");
      for (const imp of relativeImports(f, text)) {
        for (const h of helpers) {
          if (h === imp || h === `${imp}.ts` || h === `${imp}.tsx` || h === `${imp}/index.ts`) {
            offenders.push(`${f} -> ${h}`);
          }
        }
      }
    }
    expect(
      offenders,
      "these gated suites reach the repo through an imported helper; add them to test/repo-wide-suites.ts",
    ).toEqual([]);
  });

  it("the manifest matches what actually escapes apps/web-platform", () => {
    const actual = unitFiles.filter(escapesApp).sort();
    const declared = [...REPO_WIDE_SUITES].sort();

    const missing = actual.filter((f) => !declared.includes(f));
    const stale = declared.filter((f) => !actual.includes(f));

    // Asserted as one combined object so a drift in either direction reports
    // BOTH lists in a single failure rather than hiding the second behind the
    // first assertion's throw.
    expect(
      { missing, stale },
      [
        "REPO_WIDE_SUITES has drifted from what is on disk.",
        "",
        "`missing` = suites that escape apps/web-platform but are NOT in the",
        "manifest. These are in the GATED project right now and are declined on",
        "diffs that touch nothing in this app — i.e. exactly the diffs they",
        "guard. Add them to test/repo-wide-suites.ts.",
        "",
        "`stale` = manifest entries that no longer escape (or no longer exist).",
        "They run on every commit for no reason. Remove them.",
      ].join("\n"),
    ).toEqual({ missing: [], stale: [] });
  });

  it("no component (.test.tsx) suite escapes the app", () => {
    // NOT load-bearing for the gate any more — `component` runs always (#7498
    // declined gating it on measurement, and that decision was restored). The
    // invariant is kept because it is true, cheap, and the precondition anyone
    // would need if gating `component` is ever revisited: measured 0 of 240 at
    // #7498. Deleting it would make that future decision unmeasurable again.
    const escaping = gatedCandidates.filter((f) => f.endsWith(".test.tsx")).filter(escapesApp);
    expect(
      escaping,
      "a .test.tsx that reads outside apps/web-platform would be declined on the diffs it guards",
    ).toEqual([]);
  });

  it("every manifest entry still exists on disk", () => {
    const gone = REPO_WIDE_SUITES.filter((f) => !unitFiles.includes(f));
    expect(gone, "manifest names files that no longer exist").toEqual([]);
  });

  it("the manifest is a strict subset of the unit include globs", () => {
    // A manifest entry outside test/ or lib/ would be silently collected by no
    // project at all — the zero-runner shape this repo has been bitten by.
    const outside = REPO_WIDE_SUITES.filter(
      (f) => !f.startsWith("test/") && !f.startsWith("lib/"),
    );
    expect(outside, "manifest entries must live under test/ or lib/").toEqual([]);
  });

  it("detects an escaping suite that is absent from the manifest", () => {
    // Anti-vacuity: prove the predicate can actually fire. A synthetic file at
    // depth 1 with a 3-deep parent run escapes, and is not in the manifest.
    const synthetic = "test/__vacuity__.test.ts";
    const depth = synthetic.split("/").length - 1;
    expect(depth).toBe(1);
    expect(longestParentRun('readFileSync("../../../plugins/x.sh")')).toBe(3);
    expect(longestParentRun('readFileSync("../../../plugins/x.sh")') > depth).toBe(true);
    // …and the app-local shape must NOT fire at the depth where it resolves to
    // the app root, which is the over-match half of the hazard.
    expect(longestParentRun('join(__dirname, "..", "..")')).toBe(2);
    expect(longestParentRun('join(__dirname, "..", "..")') > 2).toBe(false);
  });

  it("detects a CHAINED escape that a longest-single-run scan misses", () => {
    // The hole a per-expression scan leaves open: each hop is within depth, the
    // composition is not. At depth 2 this reaches the repo root.
    const chained = [
      'const APP = join(__dirname, "..", "..");',
      'readFileSync(join(APP, "..", "..", "plugins", "x.sh"));',
    ].join("\n");
    expect(longestParentRun(chained)).toBe(2); // the naive scan says app-local…
    expect(deepestReach(chained)).toBe(4); // …substitution sees the real reach
    expect(escapesText(chained, 2)).toBe(true);

    // Control: the same first hop WITHOUT a second must stay app-local, or the
    // guard would flag most of the app.
    const single = 'const APP = join(__dirname, "..", "..");\nreadFileSync(join(APP, "server", "x.ts"));';
    expect(escapesText(single, 2)).toBe(false);
  });

  it("does not credit a binding named like a path SEGMENT", () => {
    // `kb` the binding vs "kb" the literal. Matching the latter double-counted
    // the hop and mislabelled an app-local suite as an escape.
    const shadowed = 'const kb = (f) => join(__dirname, "..", "components", "kb", f);';
    expect(escapesText(shadowed, 1)).toBe(false);
  });

  it("a repo-root helper name escapes at any depth", () => {
    expect(escapesText("const r = GIT_ROOT;", 9)).toBe(true);
    expect(escapesText("git rev-parse --show-toplevel", 9)).toBe(true);
  });
});

// Referenced so the import is not elided, and so a manifest that somehow
// resolves empty fails loudly rather than trivially satisfying every arm above.
it("the manifest is non-empty", () => {
  expect(REPO_WIDE_SUITES.length).toBeGreaterThan(0);
  expect(relative(APP_ROOT, APP_ROOT)).toBe("");
});
