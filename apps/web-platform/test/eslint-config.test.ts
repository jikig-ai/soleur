import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Guard suite for the ESLint flat-config migration (#1327).
 *
 * Guard 1 — the lint script is non-interactive and terminates.
 * Guard 2 — the finding set is pinned, with an anti-vacuity floor so a config
 *           that silently scanned nothing cannot report "0 findings, all good"
 *           (ADR-193 floor contract).
 * Guard 3 — the dependency tree that makes ESLint runnable at all.
 *
 * The Guard Contract and its mutation matrices live in
 * knowledge-base/project/plans/2026-08-19-chore-eslint-flat-config-migration-plan.md
 */

const APP_ROOT = resolve(__dirname, "..");
const REPO_ROOT = resolve(APP_ROOT, "..", "..");
const ESLINT_BIN = resolve(APP_ROOT, "node_modules/.bin/eslint");
const SELF = resolve(__dirname, "eslint-config.test.ts");

/**
 * Pinned baseline. Derived from the as-written config by running the same
 * command this suite runs — never from a prose estimate.
 */
const BASELINE_FINDINGS = 192;

/**
 * Anti-vacuity floor, re-derived 2026-08-20 against 2019 actually-scanned files:
 *
 *   ./node_modules/.bin/eslint . -f json | node -e '…JSON.parse(…).length'
 *
 * This used to be 500, which was NOT a floor. 1880 of the 2019 scanned files
 * carry zero findings, so a config that ignored 1519 of those finding-free
 * files produced results.length = 500, total = 192 and a byte-identical
 * byRule — every assertion in this suite green with 75.2% of the tree
 * unlinted. A floor only bounds vacuity when the headroom between it and the
 * real count is smaller than the finding-free population.
 */
const MIN_FILES_SCANNED = 1900;

/**
 * Per-directory coverage. The global floor above bounds how much of the tree
 * can vanish IN TOTAL; it cannot see a whole LAYER dropped, because the layer
 * is smaller than the headroom — `ignores: ["app/api/**"]` removes 109
 * finding-free files and still clears 1900. These floors make each layer's
 * disappearance its own failure, and they name the layer in the message.
 *
 * Measured (same run as above): test 1142, server 317, components 220,
 * app 165, lib 106. Floors sit ~12% below so ordinary churn does not red the
 * suite while any layer-scale removal does.
 */
const MIN_FILES_BY_DIR: Record<string, number> = {
  test: 1000,
  server: 280,
  components: 190,
  app: 140,
  lib: 90,
};

/** Per-rule breakdown, so a drift names the rule that moved, not just a delta. */
const BASELINE_BY_RULE: Record<string, number> = {
  "(unused-disable-directive)": 31,
  "@next/next/no-assign-module-variable": 1,
  "@next/next/no-img-element": 7,
  "@typescript-eslint/no-unused-vars": 74,
  "no-control-regex": 19,
  "no-empty": 25,
  "no-fallthrough": 5,
  "no-redeclare": 2,
  "no-regex-spaces": 1,
  "no-useless-escape": 10,
  "react-hooks/exhaustive-deps": 6,
  "require-yield": 11,
};

type EslintFileResult = {
  filePath: string;
  errorCount: number;
  warningCount: number;
  messages: { ruleId: string | null; message: string; fatal?: boolean }[];
};

function readPkg(): {
  scripts: Record<string, string>;
  overrides?: Record<string, unknown>;
  devDependencies?: Record<string, string>;
} {
  return JSON.parse(readFileSync(resolve(APP_ROOT, "package.json"), "utf8"));
}

function lintScript(): string {
  return readPkg().scripts.lint ?? "";
}

/**
 * The arguments the `lint` script itself carries. The guard runs THESE rather
 * than a hardcoded argv, because otherwise every mutation of the script's
 * arguments — `--config <path that does not exist>`, a flag that disables the
 * rule set — is invisible to a guard that asserts only the script's first
 * token. Guard 1 rows 3 and 4 both live on this axis.
 */
function lintScriptArgs(): string[] {
  return lintScript().trim().split(/\s+/).filter(Boolean).slice(1);
}

/**
 * ESLint over ~2000 files takes ~30s, so it runs ONCE and every assertion reads
 * the memo. Three independent invocations blew the default test timeout and
 * tripled the suite's cost for identical data.
 */
let MEMO: { results: EslintFileResult[]; status: number } | undefined;

/**
 * The wall-clock budget for the one ESLint invocation. This is Guard 1's
 * "terminates" half, and before it existed that half had NO enforcing
 * assertion at all: `execFileSync` blocks the vitest worker's event loop, so
 * the 600_000 test timeout below cannot fire against a config that hangs, and
 * CI would have run to its own six-hour ceiling instead. Measured cost of a
 * clean run is ~30s.
 */
const ESLINT_TIMEOUT_MS = 300_000;

function runEslint(): { results: EslintFileResult[]; status: number } {
  if (MEMO) return MEMO;
  let stdout = "";
  let stderr = "";
  let status = 0;
  let detail = "";
  try {
    stdout = execFileSync(ESLINT_BIN, [...lintScriptArgs(), "-f", "json"], {
      cwd: APP_ROOT,
      encoding: "utf8",
      // stdin is closed rather than inherited so a config-less `next lint`
      // cannot read a real terminal. This does NOT make a stdin wait throw —
      // a reader on an "ignore" fd gets EOF immediately — so it is the
      // `timeout` below, not this, that bounds the run.
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 256 * 1024 * 1024,
      timeout: ESLINT_TIMEOUT_MS,
    });
  } catch (err) {
    const e = err as {
      status?: number;
      signal?: string;
      code?: string;
      message?: string;
      stdout?: string;
      stderr?: string;
    };
    status = e.status ?? 1;
    stdout = e.stdout ?? "";
    stderr = e.stderr ?? "";
    // Keep the spawn-level cause. Reporting only `exit 1 ... (empty)` buries
    // ENOENT, EACCES, ENOBUFS and the timeout kill as thoroughly as the bare
    // `Unexpected end of JSON input` this replaced.
    detail = [
      e.code ? `code=${e.code}` : "",
      e.signal ? `signal=${e.signal}` : "",
      e.signal === "SIGTERM" ? `(timed out after ${ESLINT_TIMEOUT_MS}ms)` : "",
      e.message ? `message=${e.message.split("\n")[0]}` : "",
    ]
      .filter(Boolean)
      .join(" ");
  }
  let results: EslintFileResult[];
  try {
    results = JSON.parse(stdout) as EslintFileResult[];
  } catch {
    // ESLint emitted no parseable report: a config-resolution failure, an
    // all-files-are-ignored refusal, a crash, or the timeout above. Surface
    // ITS diagnosis rather than a bare `Unexpected end of JSON input`, which
    // names the symptom and buries the cause. Guard 1 mutation 3 and Guard 2
    // mutation 3 both land here, and both were unreadable before this.
    throw new Error(
      `eslint produced no JSON report (exit ${status}${detail ? `, ${detail}` : ""}). stderr:\n${
        stderr.trim() || "(empty)"
      }`,
    );
  }
  MEMO = { results, status };
  return MEMO;
}

/** Files scanned under each top-level directory of apps/web-platform. */
function scannedByTopDir(results: EslintFileResult[]): Record<string, number> {
  const marker = `${resolve(APP_ROOT)}/`;
  const counts: Record<string, number> = {};
  for (const f of results) {
    const rel = f.filePath.startsWith(marker)
      ? f.filePath.slice(marker.length)
      : f.filePath;
    const top = rel.includes("/") ? rel.slice(0, rel.indexOf("/")) : "(root)";
    counts[top] = (counts[top] ?? 0) + 1;
  }
  return counts;
}

describe("Guard 1 — the lint script is non-interactive and terminates", () => {
  it("package.json's lint script invokes eslint, never `next lint`", () => {
    // Assertion-count floor: gutting this body while leaving the test name in
    // place must FAIL, not pass as a test that asserts nothing.
    expect.assertions(3);
    const lint = lintScript();
    // `next lint` is precisely the form that drops into an interactive prompt
    // when no config exists, and it is removed in Next 16.
    expect(lint).not.toMatch(/\bnext\s+lint\b/);
    expect(lint.trim().split(/\s+/)[0]).toBe("eslint");
    // npm runs `prelint` and `postlint` around `lint`, and neither is inside
    // the window this guard measures — `runEslint` spawns the eslint binary
    // directly. A `"postlint": "next lint"` therefore passed every assertion
    // in this suite while restoring the exact interactive form Guard 1 exists
    // to forbid. The only honest fix is to require the hooks not to exist.
    const scripts = readPkg().scripts;
    expect(
      Object.keys(scripts).filter((k) => k === "prelint" || k === "postlint"),
    ).toEqual([]);
  });

  it("a flat config exists and no higher-precedence config shadows it", () => {
    expect.assertions(2);
    expect(existsSync(resolve(APP_ROOT, "eslint.config.mjs"))).toBe(true);
    // ESLint resolves eslint.config.js / .mjs / .cjs / .ts in that order, so a
    // `cp eslint.config.mjs eslint.config.js` makes the reviewed file dead
    // code with every guard here still green. Asserting only that the .mjs
    // EXISTS cannot see that.
    expect(
      ["eslint.config.js", "eslint.config.cjs", "eslint.config.ts", "eslint.config.mts"].filter(
        (f) => existsSync(resolve(APP_ROOT, f)),
      ),
    ).toEqual([]);
  });

  it("eslint runs to completion with stdin closed and exits 0 with a JSON report", () => {
    expect.assertions(2);
    const { results, status } = runEslint();
    expect(Array.isArray(results)).toBe(true);
    // The VERDICT, not just the report. `eslint . --max-warnings 0` emits a
    // byte-identical report and exits 1 — so before this line CI went red
    // while this suite stayed green, which is the precise inversion the guard
    // exists to prevent. It also closes a shim that prints `[]` and exits 2.
    expect(status).toBe(0);
  }, 600_000);

  it("CI carries a job that actually runs the lint script", () => {
    expect.assertions(3);
    const ci = readFileSync(
      resolve(REPO_ROOT, ".github/workflows/ci.yml"),
      "utf8",
    );
    // Nothing in this suite reaches the CI job, so deleting the job — or just
    // its ESLint step — left all three guards green with zero linting on any
    // PR. Scoped to the job's own block so a same-named step elsewhere in the
    // workflow cannot satisfy it.
    const start = ci.indexOf("\n  lint-webplat:\n");
    expect(start).toBeGreaterThan(-1);
    const rest = ci.slice(start + 1);
    const nextJob = rest.search(/\n {2}[a-zA-Z0-9_-]+:\n/);
    const block = nextJob === -1 ? rest : rest.slice(0, nextJob);
    expect(block).toMatch(/^\s+run:\s+npm run lint$/m);
    // The floor step is the job's own anti-vacuity story. Without it the job
    // reports green having linted 11 of 2019 files (`export default []`
    // exits 0), and its only floor lived in a different job on a different
    // matrix.
    expect(block).toMatch(/MIN_FILES_SCANNED/);
  });
});

describe("Guard 2 — the finding set is pinned", () => {
  it("scans at least the anti-vacuity floor of files", () => {
    expect.assertions(1);
    const { results } = runEslint();
    // Without this floor, `ignores: ["**"]` would report zero findings and read
    // as a clean codebase.
    expect(results.length).toBeGreaterThanOrEqual(MIN_FILES_SCANNED);
  }, 600_000);

  it("scans every top-level layer, not just enough files to clear the floor", () => {
    expect.assertions(1);
    const { results } = runEslint();
    const counts = scannedByTopDir(results);
    const short = Object.entries(MIN_FILES_BY_DIR)
      .filter(([dir, floor]) => (counts[dir] ?? 0) < floor)
      .map(([dir, floor]) => `${dir}/ scanned ${counts[dir] ?? 0}, floor ${floor}`);
    expect(short).toEqual([]);
  }, 600_000);

  it("reports exactly the pinned baseline finding count", () => {
    expect.assertions(2);
    const { results } = runEslint();
    const total = results.reduce(
      (n, f) => n + f.errorCount + f.warningCount,
      0,
    );
    const byRule: Record<string, number> = {};
    let fatal = 0;
    for (const f of results) {
      for (const m of f.messages) {
        // A fatal parse error also carries a null ruleId, so bucketing on
        // `?? "(unused-disable-directive)"` alone reported an unparseable file
        // as a stale disable directive. Branch on `fatal` FIRST and count it
        // separately — an unparseable file is not a lint finding.
        if (m.fatal) {
          fatal += 1;
          continue;
        }
        // ESLint reports unused `eslint-disable` directives with a null ruleId. Name
        // the bucket for what it is — a bare "(no-rule)" hides that 31 of these are
        // stale disables written for a linter that never ran.
        const k = m.ruleId ?? "(unused-disable-directive)";
        byRule[k] = (byRule[k] ?? 0) + 1;
      }
    }
    expect(fatal).toBe(0);
    // Printed on failure so a drift names the rule that moved rather than only
    // the delta.
    expect({ total, byRule }).toEqual({ total: BASELINE_FINDINGS, byRule: BASELINE_BY_RULE });
  }, 600_000);
});

/**
 * The source of this file with comments removed. Every self-guard below reads
 * THIS, not the raw text.
 *
 * The previous version asserted against the raw source under the claim that
 * "a comment can name `toEqual`, but it cannot produce this construct". That
 * claim is false — a comment can contain any construct verbatim — and the
 * mutation it licensed was the cheap one: comment out both assertions, paste
 * the pinned text back as a `//` line, and the self-guard stays green over a
 * suite that asserts nothing.
 */
function selfSourceWithoutComments(): string {
  return readFileSync(SELF, "utf8")
    .split("\n")
    .map((line) => {
      const t = line.trimStart();
      // Whole-line comments, including a block comment's opener and its body
      // lines (which start with `*`). A regex-based `/\*...\*/` sweep is not
      // used here: this file contains the glob literal `**` + `/` + `*` in a
      // fixture string, which opens a block comment the sweep then runs to
      // the end of the file on.
      if (t.startsWith("//") || t.startsWith("*") || t.startsWith("/*")) return "";
      // Trailing comments. The lookbehind keeps `https:` + `//`, a path's
      // doubled separator, and an escaped separator inside a regex literal
      // from being read as the start of one.
      return line.replace(/(?<![:\\/])\/\/.*$/, "");
    })
    .join("\n");
}

describe("Harness — the guard's own dispatch", () => {
  it("pins the baseline by exact equality, not a predicate any constant satisfies", () => {
    expect.assertions(2);
    const src = selfSourceWithoutComments();
    // Anchored on the comparison's CALL SHAPE rather than a bare token, and
    // read from comment-stripped source so pasting the shape into a comment
    // cannot satisfy it.
    expect(src).toMatch(
      /expect\(\{ total, byRule \}\)\.toEqual\(\{\s*total: BASELINE_FINDINGS,\s*byRule: BASELINE_BY_RULE,?\s*\}\)/,
    );
    // The floor must compare against the named constant, never an inline 0 —
    // `>= 0` is satisfied by a run that scanned nothing.
    expect(src).toMatch(
      /expect\(results\.length\)\.toBeGreaterThanOrEqual\(MIN_FILES_SCANNED\)/,
    );
  });

  it("keeps its own floors above the values that would make them vacuous", () => {
    expect.assertions(4);
    // A baseline of 0 would make the pin unfalsifiable by an inert config.
    expect(BASELINE_FINDINGS).toBeGreaterThan(0);
    // Closing the inline `>= 0` form above left the other half open: setting
    // the CONSTANT to 0 satisfied `toBeGreaterThanOrEqual(MIN_FILES_SCANNED)`
    // for a run that scanned nothing. 1500 is well under today's 2019 and well
    // over the 500 that let 75% of the tree go unlinted.
    expect(MIN_FILES_SCANNED).toBeGreaterThanOrEqual(1500);
    // Per-layer floors are only floors while they are positive, and only
    // coverage while every measured layer is present.
    expect(Object.keys(MIN_FILES_BY_DIR).sort()).toEqual([
      "app",
      "components",
      "lib",
      "server",
      "test",
    ]);
    expect(
      Object.entries(MIN_FILES_BY_DIR).filter(([, n]) => n < 50),
    ).toEqual([]);
  });

  it("cannot be neutered by skipping or deleting its tests", () => {
    expect.assertions(2);
    const src = selfSourceWithoutComments();
    // `it.skip(` on both Guard 2 tests left the source text every regex above
    // matches completely untouched, and the suite reported green having run
    // neither. `.only` is the same hole from the other side: it silently
    // deselects every sibling.
    expect(src).not.toMatch(/\b(?:describe|it|test)\.(?:skip|only|todo|failing)\s*\(/);
    // An assertion-count floor covers a GUTTED body; it cannot see a deleted
    // one. Ten `it(` blocks exist today across Guards 1-3 and this harness.
    expect((src.match(/(?<![.\w])it\(/g) ?? []).length).toBeGreaterThanOrEqual(10);
  });
});

/**
 * Guard 3 — the dependency tree that makes ESLint runnable at all.
 *
 * The plan's Observability block names "the guard suite fails" as the detection
 * route for a reintroduced blanket `brace-expansion` override. Nothing asserted
 * it, so that route did not exist. It does now.
 *
 * FLOORS ARE MEASURED, NOT INHERITED. The plan quoted 1.1.12 / 2.0.2 / 3.0.1 /
 * 4.0.1 — the patched set for ONE advisory (GHSA-v6h2-p8h4-qcjw, LOW). The
 * GitHub advisory API returns SEVEN advisories for this package, FOUR of them
 * HIGH. The union of their vulnerable ranges, re-derived 2026-08-20 via
 * `gh api "/advisories?ecosystem=npm&affects=brace-expansion"`, is what is
 * encoded below; the plan's 1.1.12 is vulnerable to three HIGH advisories.
 *
 *   GHSA-v6h2-p8h4-qcjw  LOW       <=1.1.11, <=2.0.1, =3.0.0, =4.0.0
 *   GHSA-f886-m6hf-6m8v  MODERATE  <1.1.13, <2.0.3, <3.0.2, >=4.0.0 <5.0.5
 *   GHSA-jxxr-4gwj-5jf2  MODERATE  >=5.0.0 <5.0.6
 *   GHSA-832h-xg76-4gv6  HIGH      <1.1.7
 *   GHSA-3jxr-9vmj-r5cp  HIGH      <1.1.16, <2.1.2, >=3.0.0 <5.0.7
 *   GHSA-mh99-v99m-4gvg  HIGH      <1.1.17, <2.1.3, <3.0.3, >=4.0.0 <5.0.8
 *   GHSA-rgw5-rvv9-x895  HIGH      <1.1.18, <2.1.4, <3.0.6, >=4.0.0 <5.0.9
 *
 * NO 3.x OR 4.x RELEASE CLEARS ALL SEVEN. This is deliberately not the same
 * claim as "no patched 3.x exists": GHSA-rgw5 names 3.0.6 as its own
 * first_patched and npm ships it under dist-tag `maintenance-v3`. But
 * GHSA-3jxr's range is `>=3.0.0 <5.0.7`, which swallows every 3.x and every
 * 4.x including 3.0.6 — so those lines have no version this table could
 * encode, and `null` (fail closed, must move to the 5.x line) stays correct.
 * An unknown future major also fails closed rather than passing unexamined —
 * re-check the advisory feed and update this table deliberately.
 */
const BRACE_EXPANSION_FLOORS: Record<number, string | null> = {
  1: "1.1.18",
  2: "2.1.4",
  3: null, // 3.0.6 exists but sits inside GHSA-3jxr — must move to the 5.x line
  4: null, // no 4.x release exists outside GHSA-3jxr/GHSA-rgw5 — same move
  5: "5.0.9",
};

function semverGte(a: string, b: string): boolean {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] ?? 0) !== (pb[i] ?? 0)) return (pa[i] ?? 0) > (pb[i] ?? 0);
  }
  return true;
}

function braceExpansionResolutions(): { path: string; version: string }[] {
  const lock = JSON.parse(
    readFileSync(resolve(APP_ROOT, "package-lock.json"), "utf8"),
  ) as { packages: Record<string, { version?: string; overrides?: unknown }> };
  return Object.entries(lock.packages)
    .filter(([p]) => /(^|\/)node_modules\/brace-expansion$/.test(p))
    // A lock entry without a `version` (a link/workspace entry) would otherwise
    // reach `version.split(".")` as undefined and throw a TypeError that reads
    // as a harness bug rather than a tree the guard cannot classify.
    .filter(([, v]) => typeof v.version === "string" && v.version.length > 0)
    .map(([path, v]) => ({ path, version: v.version as string }));
}

describe("Guard 3 — the dependency tree stays repaired", () => {
  it("resolves every brace-expansion at or above its own line's patched floor", () => {
    expect.assertions(2);
    const found = braceExpansionResolutions();
    // Anti-vacuity: an empty set satisfies "every member is patched" trivially.
    // If this ever legitimately reaches zero, delete the guard deliberately
    // rather than letting it pass while asserting nothing.
    expect(found.length).toBeGreaterThanOrEqual(1);
    const verdicts = found.map(({ path, version }) => {
      const major = Number(version.split(".")[0]);
      const floor = Object.prototype.hasOwnProperty.call(
        BRACE_EXPANSION_FLOORS,
        major,
      )
        ? BRACE_EXPANSION_FLOORS[major]
        : undefined;
      // undefined = major not in the table (fail closed, unexamined line).
      // null     = no release on this major clears every advisory.
      const ok = typeof floor === "string" && semverGte(version, floor);
      return `${path} @ ${version} -> ${ok ? "OK" : `VULNERABLE (line ${major} floor: ${floor === undefined ? "UNKNOWN MAJOR — re-check the advisory feed" : (floor ?? "no release on this line clears all advisories")})`}`;
    });
    // Asserted per line, never in aggregate: an aggregate check passes while
    // one line sits below its floor.
    expect(verdicts.filter((v) => !v.endsWith("-> OK"))).toEqual([]);
  });

  it("carries no blanket brace-expansion override", () => {
    expect.assertions(1);
    // A blanket `"brace-expansion": "^5"` forces the 5.x API onto minimatch@3,
    // whose `expand` import then resolves to a non-function — every brace glob
    // crashes ESLint. A SCOPED override (the `gray-matter` -> `js-yaml` shape)
    // is fine; a top-level one is the defect.
    //
    // SCOPE, stated honestly: this asserts apps/web-platform ONLY. The repo
    // ROOT package.json carries a top-level blanket `"brace-expansion":
    // "^1.1.16"` (and a top-level `"js-yaml": "^4.3.1"`) right now, in exactly
    // the shape forbidden here — an earlier version of this comment claimed
    // the root used only a scoped override, which was false. Root is not
    // covered because its blanket is inert there: its sole minimatch is 3.1.5,
    // which wants ^1 anyway, and its resolved 1.1.18 is floored independently
    // by scripts/assert-dependabot-drain.py's ("root", "brace-expansion", 1)
    // row. Widening this guard to root is a deliberate separate change, not
    // something to infer from this test's name.
    expect(readPkg().overrides?.["brace-expansion"]).toBeUndefined();
  });

  it("gives rimraf's minimatch@9 a 2.x brace-expansion, not the hoisted 5.x", () => {
    expect.assertions(1);
    const rimraf = braceExpansionResolutions().find((r) =>
      r.path.startsWith("node_modules/rimraf/"),
    );
    // Proves the repair is not scoped to the ESLint stack alone.
    expect(rimraf?.version.split(".")[0]).toBe("2");
  });

  it("expands a brace glob without the `expand is not a function` crash", () => {
    expect.assertions(2);
    const dir = mkdtempSync(join(tmpdir(), "eslint-brace-glob-"));
    try {
      // A config whose `files` uses the brace form the blanket override broke.
      writeFileSync(
        join(dir, "eslint.config.mjs"),
        'export default [{ files: ["**/*.{ts,tsx}"], rules: { "no-empty": "error" } }];\n',
      );
      writeFileSync(join(dir, "probe.ts"), "if (1) {}\n");
      let stdout = "";
      let stderr = "";
      try {
        stdout = execFileSync(ESLINT_BIN, [".", "-f", "json"], {
          cwd: dir,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
          timeout: ESLINT_TIMEOUT_MS,
        });
      } catch (err) {
        const e = err as { stdout?: string; stderr?: string };
        stdout = e.stdout ?? "";
        stderr = e.stderr ?? "";
      }
      expect(stderr).not.toMatch(/expand is not a function/);
      // Not merely "did not crash": the brace glob must actually MATCH, or a
      // config that silently selected no files would pass this test.
      const results = JSON.parse(stdout || "[]") as EslintFileResult[];
      expect(
        results.some(
          (r) => r.filePath.endsWith("probe.ts") && r.errorCount === 1,
        ),
      ).toBe(true);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 120_000);
});
