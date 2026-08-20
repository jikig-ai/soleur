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

/** Longest consecutive `..` run, across both spellings that appear in-repo. */
function longestParentRun(text: string): number {
  let best = 0;
  // "../../.." as one string literal
  for (const m of text.matchAll(/(?:\.\.\/)+\.\.|\.\.(?:\/\.\.)+/g)) {
    best = Math.max(best, (m[0].match(/\.\./g) ?? []).length);
  }
  // join(__dirname, "..", "..") — segments as separate arguments
  for (const m of text.matchAll(/"\.\."(?:\s*,\s*"\.\.")+/g)) {
    best = Math.max(best, (m[0].match(/"\.\."/g) ?? []).length);
  }
  return best;
}

/** Names a helper that resolves the repo root directly, at any depth. */
const REPO_ROOT_HELPER = /\bGIT_ROOT\b|\bfindRepoRoot\b|\brepoRoot\b|\bREPO_ROOT\b|\brepo_root\b/;

function escapesApp(relPath: string): boolean {
  const text = readFileSync(join(APP_ROOT, relPath), "utf8");
  if (REPO_ROOT_HELPER.test(text)) return true;
  const depth = relPath.split("/").length - 1; // dirs below apps/web-platform
  return longestParentRun(text) > depth;
}

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(join(APP_ROOT, dir), { withFileTypes: true })) {
    const rel = `${dir}/${entry.name}`;
    if (entry.isDirectory()) {
      if (entry.name === "node_modules" || entry.name === "__synthesized__") continue;
      walk(rel, acc);
    } else if (entry.name.endsWith(".test.ts") || entry.name.endsWith(".test.tsx")) {
      acc.push(rel);
    }
  }
  return acc;
}

// Every file in a GATED project. Both `unit` (test|lib/**/*.test.ts) and
// `component` (test/**/*.test.tsx) are declined together, so both need the
// containment property — a `.test.tsx` that read the repo would fail open
// exactly as a `.test.ts` would.
const gatedCandidates = [...walk("test"), ...walk("lib")].sort();
const unitFiles = gatedCandidates.filter((f) => f.endsWith(".test.ts"));

describe("repo-wide suite containment (#7498)", () => {
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
    // The component project has no manifest — it is gated wholesale, so the
    // invariant is absolute rather than "declared or app-local". Measured 0 of
    // 240 at #7498; this keeps it that way.
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
});

// Referenced so the import is not elided, and so a manifest that somehow
// resolves empty fails loudly rather than trivially satisfying every arm above.
it("the manifest is non-empty", () => {
  expect(REPO_WIDE_SUITES.length).toBeGreaterThan(0);
  expect(relative(APP_ROOT, APP_ROOT)).toBe("");
});
