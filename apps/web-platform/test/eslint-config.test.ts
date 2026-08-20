import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { parse as parseYaml } from "yaml";
import ts from "typescript";
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
 * Pinned baseline, as a RATCHET rather than an equality (see the assertion for why).
 * Derived from the as-written config by running the same command this suite runs —
 * never from a prose estimate. Re-derive, and re-pin DOWNWARD, with:
 *
 *   cd apps/web-platform && ./node_modules/.bin/eslint . -f json > /var/tmp/r.json
 *   node -e 'const r=require("/var/tmp/r.json");
 *            const b={}; for (const f of r) for (const m of f.messages)
 *              b[m.ruleId ?? "(unused-disable-directive)"] = (b[m.ruleId ?? "(unused-disable-directive)"]??0)+1;
 *            console.log(r.reduce((n,f)=>n+f.errorCount+f.warningCount,0), b)'
 */
const BASELINE_FINDINGS = 192;

/**
 * Anti-vacuity floor, re-derived 2026-08-20 against 2021 actually-scanned files:
 *
 *   ./node_modules/.bin/eslint . -f json | node -e '…JSON.parse(…).length'
 *
 * This used to be 500, which was NOT a floor. 1882 of the 2021 scanned files
 * carry zero findings, so a config that ignored 1519 of those finding-free
 * files produced results.length = 500, total = 192 and a byte-identical
 * byRule — every assertion in this suite green with 75.2% of the tree
 * unlinted. A floor only bounds vacuity when the headroom between it and the
 * real count is smaller than the finding-free population.
 */
const MIN_FILES_SCANNED = 1900;

/**
 * Per-directory coverage. The global floor above bounds how much of the tree can vanish
 * IN TOTAL; it cannot see a whole LAYER dropped, because a layer is smaller than the
 * headroom — `ignores: ["app/api/**"]` removes 109 finding-free files and still clears
 * 1900. These floors make each layer's disappearance its own failure, and name the layer.
 *
 * COVERS EVERY LAYER ESLINT SCANS, not just the big five. The first version floored
 * test/server/components/app/lib only, leaving scripts/ 30, e2e/ 16 and hooks/ 13 — 59
 * files, comfortably inside the global floor's 121-file headroom — assertable-away by a
 * config change alone, with no test edit at all.
 *
 * Measured 2026-08-20: test 1143, server 317, components 220, app 165, lib 106,
 * scripts 30, e2e 16, hooks 13. Floors sit 12-15% below (not "~12%" — the real spread is
 * 11.7% for test/ to 15.2% for app/) so ordinary churn does not red the suite while any
 * layer-scale removal does.
 *
 * The remaining 11 scanned files — 10 at the package root and 1 under infra/ — carry no
 * layer floor: a floor of 1 is not a floor, and it would red on a single file move. They
 * are covered only by the global count, which is stated here rather than left implicit.
 */
const MIN_FILES_BY_DIR: Record<string, number> = {
  test: 1000,
  server: 280,
  components: 190,
  app: 140,
  lib: 90,
  scripts: 25,
  e2e: 13,
  hooks: 11,
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

type Step = {
  name?: string;
  run?: string;
  "continue-on-error"?: boolean;
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

  it("CI carries a job that actually runs the lint script, and can fail", () => {
    expect.assertions(6);
    // Parsed as YAML, not grepped. Every text-matching version of this test lost: the
    // first matched a bare `MIN_FILES_SCANNED` that the step's own `#` comment supplied,
    // and the second still asserted the step NAME and the token independently — so
    // replacing the whole floor step with `run: echo MIN_FILES_SCANNED` kept it green,
    // and nothing could see a `continue-on-error: true` added to the lint step.
    const wf = parseYaml(
      readFileSync(resolve(REPO_ROOT, ".github/workflows/ci.yml"), "utf8"),
    ) as { jobs?: Record<string, { "continue-on-error"?: boolean; steps?: Step[] }> };
    const job = wf.jobs?.["lint-webplat"];
    expect(job).toBeDefined();
    const steps = job?.steps ?? [];

    const lintStep = steps.find((st) => (st.run ?? "").trim() === "npm run lint");
    expect(lintStep).toBeDefined();
    const floorStep = steps.find((st) =>
      (st.run ?? "").includes("eslint-vacuity-floor.mjs"),
    );
    expect(floorStep).toBeDefined();

    // `continue-on-error` reports green on failure, which the job's own comment calls
    // worse than having no job at all. Checked on the job AND on both steps.
    expect(
      [
        job?.["continue-on-error"] ? "job" : "",
        lintStep?.["continue-on-error"] ? "lint step" : "",
        floorStep?.["continue-on-error"] ? "floor step" : "",
      ].filter(Boolean),
    ).toEqual([]);

    // The floor step must be a real script on disk, and that script must both read the
    // floor from this file and be able to fail. A step that merely mentions the name
    // satisfies neither.
    const floorSrc = readFileSync(
      resolve(APP_ROOT, "scripts/eslint-vacuity-floor.mjs"),
      "utf8",
    );
    expect(floorSrc).toMatch(/process\.exit\(1\)/);
    // ...and it must read the floor from here rather than hand-copying the number, which
    // is how the two silently drifted apart in the first version.
    expect(floorSrc).toMatch(/MIN_FILES_SCANNED = \(\\d\+\)/);
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

  it("reports no more than the pinned baseline, per rule", () => {
    expect.assertions(3);
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
        // `?? "(unused-disable-directive)"` alone reported an unparseable file as a
        // stale disable directive. Branch on `fatal` FIRST and count it separately —
        // an unparseable file is not a lint finding.
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

    // A RATCHET, deliberately one-sided — this was exact equality, and exact equality
    // here is merge-blocking in the direction the design explicitly rejected.
    //
    // This file matches vitest.config.ts's `unit` project, so it runs in `test-webplat`,
    // which feeds the `test` aggregator, which IS in scripts/required-checks.txt. The
    // ci.yml comment, this config's own ratchet note and work/SKILL.md all said a lint
    // finding is "a signal to read, not a merge blocker"; with a two-sided pin all three
    // were false. Worse, it was blocking in BOTH directions: FIXING a warning also
    // reddened a required check, which directly contradicts "it can be driven down file
    // by file". Measured: 139 of 2021 files carry findings, 111 of 192 of them under test/, and
    // 49 of those files were touched on main in the last 60 days.
    //
    // So: a regression blocks, an improvement does not. A rule that appears with no
    // baseline entry is a hard failure — that is the "cannot grow silently" half, and it
    // is what makes the one-sided form still a ratchet rather than a rubber stamp.
    // Re-pin downward with the derivation command in BASELINE_FINDINGS' docstring.
    // A local red here is far more often a stray file than a real regression: `eslint .`
    // walks the WORKING TREE and does not read .gitignore, so any untracked .ts under
    // apps/web-platform is linted. On this repo's parallel-worktree workflow a sibling
    // session's scratch file lands in the count (observed: totals of 194 and 196 against
    // the pinned 192). CI is the authoritative environment precisely because
    // actions/checkout gives a clean tree. Say so in the failure rather than making the
    // next reader rediscover it — cq-ac-must-not-depend-on-concurrent-sessions.
    const strays = results
      .map((f) => f.filePath)
      .filter((fp) => /\/(__)?(probe|scratch|tmp)[-_.]/.test(fp));
    const hint = strays.length
      ? ` NOTE: ${strays.length} scratch-looking file(s) are in the lint set (${strays[0]}). Check \`git status\` — an untracked file from a concurrent session inflates this count.`
      : " If this is unexpected, check `git status` for untracked files: eslint lints the working tree, not the index.";
    const grew = Object.entries(byRule)
      .filter(([k, n]) => n > (BASELINE_BY_RULE[k] ?? 0))
      .map(([k, n]) => `${k}: ${n} > baseline ${BASELINE_BY_RULE[k] ?? 0}${k in BASELINE_BY_RULE ? "" : " (NEW RULE — no baseline entry)"}${hint}`);
    expect(grew).toEqual([]);
    expect(total).toBeLessThanOrEqual(BASELINE_FINDINGS);
  }, 600_000);
});

/**
 * The harness's self-guard, over the TYPESCRIPT AST rather than over source text.
 *
 * Two earlier versions matched regexes against this file's own source and both lost.
 * The first matched raw text, so commenting the assertions out and pasting the pinned
 * text back as a `//` line kept it green. The second stripped comment lines — and lost
 * to two cheaper launderings: a `const _pinned = ["expect({ total, byRule }).toEqual(…)"]`
 * string array satisfied every regex while Guard 2 was deleted outright, and a block
 * comment OPENED MID-LINE left its body starting with ordinary code tokens, so the
 * stripper skipped it and the pinned assertion was inert.
 *
 * Text matching cannot win this: the next laundering is a template literal, or a line
 * split. An AST can — a comment, a string literal and a commented-out region simply are
 * not CallExpressions, so none of them can satisfy an assertion about one.
 */
type SelfFacts = {
  itCount: number;
  describes: string[];
  skipMarkers: string[];
  hasRatchet: boolean;
  hasNewRuleGate: boolean;
  hasFloorAssertion: boolean;
};

function selfFacts(): SelfFacts {
  // `typescript` is already a devDependency (the repo typechecks with it), so this adds
  // no dependency surface.
  const src = ts.createSourceFile(
    SELF,
    readFileSync(SELF, "utf8"),
    ts.ScriptTarget.Latest,
    true,
  );
  const facts: SelfFacts = {
    itCount: 0,
    describes: [],
    skipMarkers: [],
    hasRatchet: false,
    hasNewRuleGate: false,
    hasFloorAssertion: false,
  };
  const text = (n: ts.Node) => n.getText(src).replace(/\s+/g, " ");

  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node)) {
      const callee = node.expression;
      if (ts.isIdentifier(callee)) {
        if (callee.text === "it") facts.itCount += 1;
        if (callee.text === "describe" && node.arguments.length > 0) {
          const a = node.arguments[0];
          if (ts.isStringLiteralLike(a)) facts.describes.push(a.text);
        }
      }
      // `it.skip(` / `describe.only(` / `test.todo(` as a real call, not as text.
      if (
        ts.isPropertyAccessExpression(callee) &&
        ts.isIdentifier(callee.expression) &&
        ["it", "describe", "test"].includes(callee.expression.text) &&
        ["skip", "only", "todo", "failing", "concurrent"].includes(callee.name.text) &&
        callee.name.text !== "concurrent"
      ) {
        facts.skipMarkers.push(`${callee.expression.text}.${callee.name.text}`);
      }
      // The ratchet, matched on the CALL and its argument shape. Weakening it to a
      // predicate any constant satisfies (`toBeGreaterThanOrEqual(0)`) removes the shape.
      if (
        ts.isPropertyAccessExpression(callee) &&
        callee.name.text === "toBeLessThanOrEqual" &&
        text(callee.expression) === "expect(total)" &&
        node.arguments.length === 1 &&
        text(node.arguments[0]) === "BASELINE_FINDINGS"
      ) {
        facts.hasRatchet = true;
      }
      // The half that makes a one-sided bound still a ratchet: a rule that grew, or that
      // has no baseline entry at all, must be a hard failure.
      if (
        ts.isPropertyAccessExpression(callee) &&
        callee.name.text === "toEqual" &&
        text(callee.expression) === "expect(grew)" &&
        node.arguments.length === 1 &&
        text(node.arguments[0]) === "[]"
      ) {
        facts.hasNewRuleGate = true;
      }
      if (
        ts.isPropertyAccessExpression(callee) &&
        callee.name.text === "toBeGreaterThanOrEqual" &&
        text(callee.expression) === "expect(results.length)" &&
        node.arguments.length === 1 &&
        text(node.arguments[0]) === "MIN_FILES_SCANNED"
      ) {
        facts.hasFloorAssertion = true;
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(src);
  return facts;
}

describe("Harness — the guard's own dispatch", () => {
  it("pins the ratchet and the floor as real calls rather than as text", () => {
    expect.assertions(3);
    const f = selfFacts();
    // All three were satisfiable by a string literal before they moved to the AST.
    expect(f.hasRatchet).toBe(true);
    expect(f.hasNewRuleGate).toBe(true);
    expect(f.hasFloorAssertion).toBe(true);
  });

  it("keeps its own floors above the values that would make them vacuous", () => {
    expect.assertions(4);
    // A baseline of 0 would make the pin unfalsifiable by an inert config.
    expect(BASELINE_FINDINGS).toBeGreaterThan(0);
    // Setting the CONSTANT to 0 satisfied `toBeGreaterThanOrEqual(MIN_FILES_SCANNED)`
    // for a run that scanned nothing. 1900 sits under the measured total in
    // MIN_FILES_SCANNED's docstring, which is the one site that re-derives it; the
    // bound sits just under it because a harness floor that sanctions a quarter of the
    // tree going unlinted is the same defect one level up — at >= 1500, ignoring 519
    // finding-free files kept every assertion in this suite green.
    expect(MIN_FILES_SCANNED).toBeGreaterThanOrEqual(1850);
    // Per-layer floors are only floors while they are positive, and only coverage while
    // every layer eslint actually scans is present. SUPERSET, not exact equality: the
    // previous exact-equality form meant ADDING a floor for an uncovered layer FAILED
    // the harness, so the self-guard actively forbade improving coverage.
    const required = ["app", "components", "e2e", "hooks", "lib", "scripts", "server", "test"];
    expect(required.filter((d) => !(d in MIN_FILES_BY_DIR))).toEqual([]);
    expect(Object.entries(MIN_FILES_BY_DIR).filter(([, n]) => n < 10)).toEqual([]);
  });

  it("cannot be neutered by skipping or deleting its tests", () => {
    expect.assertions(3);
    const f = selfFacts();
    // `it.skip(` on both Guard 2 tests left every byte the old regexes matched untouched.
    // As AST nodes these are unmistakable, and a string containing ".skip(" is not one.
    expect(f.skipMarkers).toEqual([]);
    // An assertion-count floor covers a GUTTED body; it cannot see a DELETED one. The
    // floor sits AT today's count (15), not below it: at >= 10 against 14 actual, all three
    // Guard 2 tests plus one more could be deleted with this green.
    expect(f.itCount).toBeGreaterThanOrEqual(15);
    // Counting is not coverage — 14 blocks satisfy a count regardless of WHICH 14. The
    // describe SET is what pins that every guard is still present.
    expect(f.describes.map((d) => d.split(" ")[0] + d.split(" ")[1]).sort()).toEqual([
      "Guard1",
      "Guard2",
      "Guard3",
      "Harness—",
    ]);
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
  it("keeps its own floors on their major line and off the bare X.0.0", () => {
    expect.assertions(2);
    // The python sibling grew this check because zeroing every threshold there exited 0
    // with a clean summary. This mirror had NO equivalent: setting 1, 2 and 5 all to
    // "0.0.0" passed all fourteen tests and declared every copy in the tree patched.
    const bad = Object.entries(BRACE_EXPANSION_FLOORS)
      .filter(([, v]) => typeof v === "string")
      .filter(([major, v]) => {
        const p = (v as string).split(".").map(Number);
        return p[0] !== Number(major) || (p[1] === 0 && p[2] === 0);
      })
      .map(([major, v]) => `line ${major} floor ${v} is off its major line or is the bare ${major}.0.0`);
    expect(bad).toEqual([]);
    // The unsatisfiable lines are unsatisfiable BY DESIGN (see the header). Flipping
    // either to a string would silently declare a 3.x or 4.x copy patched.
    expect([BRACE_EXPANSION_FLOORS[3], BRACE_EXPANSION_FLOORS[4]]).toEqual([null, null]);
  });

  it("resolves every brace-expansion at or above its own line's patched floor", () => {
    expect.assertions(2);
    const found = braceExpansionResolutions();
    // Anti-vacuity floored at the MEASURED population, not at 1. At >= 1 the matcher
    // could be narrowed until two of the three resolutions were unwatched and this
    // still passed.
    expect(found.length).toBeGreaterThanOrEqual(3);
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

  it("nests the three major lines independently instead of flattening them", () => {
    expect.assertions(1);
    // The property wanted is that removing the blanket override let each consumer keep
    // the major its minimatch needs — minimatch@3 wants ^1, rimraf's minimatch@9 wants
    // ^2, minimatch@10 wants ^5. Asserting it as a SET rather than as
    // `rimraf?.version` avoids a failure mode that names the wrong cause: rimraf is a
    // TRANSITIVE dependency, so a Dependabot bump that drops it entirely would red this
    // with "expected undefined to be '2'" under a test claiming the 2.x line regressed.
    expect(
      [...new Set(braceExpansionResolutions().map((r) => r.version.split(".")[0]))].sort(),
    ).toEqual(["1", "2", "5"]);
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
