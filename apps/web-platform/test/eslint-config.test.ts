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
 *
 * The Guard Contract and its mutation matrices live in
 * knowledge-base/project/plans/2026-08-19-chore-eslint-flat-config-migration-plan.md
 */

const APP_ROOT = resolve(__dirname, "..");
const ESLINT_BIN = resolve(APP_ROOT, "node_modules/.bin/eslint");

/**
 * Pinned baseline. Derived from the as-written config by running the same
 * command this suite runs — never from a prose estimate.
 */
const BASELINE_FINDINGS = 192;

/**
 * Anti-vacuity floor. A run that scans fewer files than this did not lint the
 * codebase, so "0 findings" is not evidence of health. Deliberately well below
 * the real count so ordinary file churn does not red the suite, while still
 * being unreachable by a config whose `ignores` swallowed everything.
 */
const MIN_FILES_SCANNED = 500;

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
  messages: { ruleId: string | null; message: string }[];
};

function lintScript(): string {
  const pkg = JSON.parse(
    readFileSync(resolve(APP_ROOT, "package.json"), "utf8"),
  ) as { scripts: Record<string, string> };
  return pkg.scripts.lint ?? "";
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

function runEslint(): { results: EslintFileResult[]; status: number } {
  if (MEMO) return MEMO;
  let stdout = "";
  let stderr = "";
  let status = 0;
  try {
    stdout = execFileSync(ESLINT_BIN, [...lintScriptArgs(), "-f", "json"], {
      cwd: APP_ROOT,
      encoding: "utf8",
      // stdin closed: a config-less `next lint` prompts here. If anything ever
      // waits on stdin this throws rather than hanging the suite.
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 256 * 1024 * 1024,
    });
  } catch (err) {
    const e = err as { status?: number; stdout?: string; stderr?: string };
    status = e.status ?? 1;
    stdout = e.stdout ?? "";
    stderr = e.stderr ?? "";
  }
  let results: EslintFileResult[];
  try {
    results = JSON.parse(stdout) as EslintFileResult[];
  } catch {
    // ESLint emitted no parseable report: a config-resolution failure, an
    // all-files-are-ignored refusal, or a crash. Surface ITS diagnosis rather
    // than a bare `Unexpected end of JSON input`, which names the symptom and
    // buries the cause. Guard 1 mutation 3 and Guard 2 mutation 3 both land
    // here, and both were unreadable before this.
    throw new Error(
      `eslint produced no JSON report (exit ${status}). stderr:\n${
        stderr.trim() || "(empty)"
      }`,
    );
  }
  MEMO = { results, status };
  return MEMO;
}

describe("Guard 1 — the lint script is non-interactive and terminates", () => {
  it("package.json's lint script invokes eslint, never `next lint`", () => {
    // Assertion-count floor: gutting this body while leaving the test name in
    // place must FAIL, not pass as a test that asserts nothing.
    expect.assertions(2);
    const lint = lintScript();
    // `next lint` is precisely the form that drops into an interactive prompt
    // when no config exists, and it is removed in Next 16.
    expect(lint).not.toMatch(/\bnext\s+lint\b/);
    expect(lint.trim().split(/\s+/)[0]).toBe("eslint");
  });

  it("a flat config exists and is discovered without an explicit --config", () => {
    expect.assertions(1);
    expect(existsSync(resolve(APP_ROOT, "eslint.config.mjs"))).toBe(true);
  });

  it("eslint runs to completion with stdin closed and returns a JSON report", () => {
    expect.assertions(1);
    const { results } = runEslint();
    expect(Array.isArray(results)).toBe(true);
  }, 600_000);
});

describe("Guard 2 — the finding set is pinned", () => {
  it("scans at least the anti-vacuity floor of files", () => {
    expect.assertions(1);
    const { results } = runEslint();
    // Without this floor, `ignores: ["**"]` would report zero findings and read
    // as a clean codebase.
    expect(results.length).toBeGreaterThanOrEqual(MIN_FILES_SCANNED);
  }, 600_000);

  it("reports exactly the pinned baseline finding count", () => {
    expect.assertions(1);
    const { results } = runEslint();
    const total = results.reduce(
      (n, f) => n + f.errorCount + f.warningCount,
      0,
    );
    const byRule: Record<string, number> = {};
    for (const f of results) {
      for (const m of f.messages) {
        // ESLint reports unused `eslint-disable` directives with a null ruleId. Name
        // the bucket for what it is — a bare "(no-rule)" hides that 31 of these are
        // stale disables written for a linter that never ran.
        const k = m.ruleId ?? "(unused-disable-directive)";
        byRule[k] = (byRule[k] ?? 0) + 1;
      }
    }
    // Printed on failure so a drift names the rule that moved rather than only
    // the delta.
    expect({ total, byRule }).toEqual({ total: BASELINE_FINDINGS, byRule: BASELINE_BY_RULE });
  }, 600_000);
});

describe("Harness — the guard's own dispatch", () => {
  it("pins the baseline by exact equality, not a predicate any constant satisfies", () => {
    expect.assertions(3);
    const src = readFileSync(resolve(__dirname, "eslint-config.test.ts"), "utf8");
    // Anchored on the comparison's CALL SHAPE, not on a bare token: a comment can
    // name `toEqual`, but it cannot produce this construct. Weakening the
    // comparison to a one-sided predicate (`>= 0`) removes the shape and reds here.
    expect(src).toMatch(
      /expect\(\{ total, byRule \}\)\.toEqual\(\{\s*total: BASELINE_FINDINGS,\s*byRule: BASELINE_BY_RULE,?\s*\}\)/,
    );
    // The floor must compare against the named constant, never an inline 0 —
    // `>= 0` is satisfied by a run that scanned nothing.
    expect(src).toMatch(
      /expect\(results\.length\)\.toBeGreaterThanOrEqual\(MIN_FILES_SCANNED\)/,
    );
    // A baseline of 0 would make the pin unfalsifiable by an inert config.
    expect(BASELINE_FINDINGS).toBeGreaterThan(0);
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
 * 4.0.1 — the patched set for ONE advisory (GHSA-v6h2-p8h4-qcjw, LOW). The npm
 * advisory API returns six advisories for this package, three of them HIGH. The
 * union of their vulnerable ranges, re-derived 2026-08-19, is what is encoded
 * below; the plan's 1.1.12 is vulnerable to two HIGH advisories.
 *
 *   GHSA-v6h2-p8h4-qcjw  LOW       <=1.1.11, <=2.0.1, =3.0.0, =4.0.0
 *   GHSA-f886-m6hf-6m8v  MODERATE  <1.1.13, <2.0.3, <3.0.2, >=4.0.0 <5.0.5
 *   GHSA-jxxr-4gwj-5jf2  MODERATE  >=5.0.0 <5.0.6
 *   GHSA-3jxr-9vmj-r5cp  HIGH      <1.1.16, <2.1.2, >=3.0.0 <5.0.7
 *   GHSA-mh99-v99m-4gvg  HIGH      <1.1.17, <2.1.3, <3.0.3, >=4.0.0 <5.0.8
 *   GHSA-rgw5-rvv9-x895  HIGH      <1.1.18, <2.1.4, <3.0.6, >=4.0.0 <5.0.9
 *
 * The 3.x and 4.x lines have NO patched release: GHSA-3jxr's range runs to
 * 5.0.7 and GHSA-rgw5's to 5.0.9, so every 3.x and every 4.x sits inside them.
 * Those lines are therefore unsatisfiable by design, and an unknown future
 * major fails closed rather than passing unexamined — re-check the advisory
 * feed and update this table deliberately.
 */
const BRACE_EXPANSION_FLOORS: Record<number, string | null> = {
  1: "1.1.18",
  2: "2.1.4",
  3: null, // no patched 3.x exists — must move to the 5.x line
  4: null, // no patched 4.x exists — must move to the 5.x line
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
  ) as { packages: Record<string, { version: string; overrides?: unknown }> };
  return Object.entries(lock.packages)
    .filter(([p]) => /(^|\/)node_modules\/brace-expansion$/.test(p))
    .map(([path, v]) => ({ path, version: v.version }));
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
      // null     = major has no patched release at all.
      const ok = typeof floor === "string" && semverGte(version, floor);
      return `${path} @ ${version} -> ${ok ? "OK" : `VULNERABLE (line ${major} floor: ${floor === undefined ? "UNKNOWN MAJOR — re-check the advisory feed" : (floor ?? "no patched release on this line")})`}`;
    });
    // Asserted per line, never in aggregate: an aggregate check passes while
    // one line sits below its floor.
    expect(verdicts.filter((v) => !v.endsWith("-> OK"))).toEqual([]);
  });

  it("carries no blanket brace-expansion override", () => {
    expect.assertions(1);
    const pkg = JSON.parse(
      readFileSync(resolve(APP_ROOT, "package.json"), "utf8"),
    ) as { overrides?: Record<string, unknown> };
    // A blanket `"brace-expansion": "^5"` forces the 5.x API onto minimatch@3,
    // whose `expand` import then resolves to a non-function — every brace glob
    // crashes ESLint. A SCOPED override (the `gray-matter` -> `js-yaml` shape
    // the repo root uses) is fine; a top-level one is the defect.
    expect(pkg.overrides?.["brace-expansion"]).toBeUndefined();
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
