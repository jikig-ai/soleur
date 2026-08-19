import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
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

/**
 * ESLint over ~2000 files takes ~30s, so it runs ONCE and every assertion reads
 * the memo. Three independent invocations blew the default test timeout and
 * tripled the suite's cost for identical data.
 */
let MEMO: { results: EslintFileResult[]; status: number } | undefined;

function runEslint(): { results: EslintFileResult[]; status: number } {
  if (MEMO) return MEMO;
  let stdout = "";
  let status = 0;
  try {
    stdout = execFileSync(ESLINT_BIN, [".", "-f", "json"], {
      cwd: APP_ROOT,
      encoding: "utf8",
      // stdin closed: a config-less `next lint` prompts here. If anything ever
      // waits on stdin this throws rather than hanging the suite.
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 256 * 1024 * 1024,
    });
  } catch (err) {
    const e = err as { status?: number; stdout?: string };
    status = e.status ?? 1;
    stdout = e.stdout ?? "";
  }
  MEMO = { results: JSON.parse(stdout) as EslintFileResult[], status };
  return MEMO;
}

describe("Guard 1 — the lint script is non-interactive and terminates", () => {
  it("package.json's lint script invokes eslint, never `next lint`", () => {
    const pkg = JSON.parse(
      readFileSync(resolve(APP_ROOT, "package.json"), "utf8"),
    ) as { scripts: Record<string, string> };
    const lint = pkg.scripts.lint ?? "";
    // `next lint` is precisely the form that drops into an interactive prompt
    // when no config exists, and it is removed in Next 16.
    expect(lint).not.toMatch(/\bnext\s+lint\b/);
    expect(lint.trim().split(/\s+/)[0]).toBe("eslint");
  });

  it("a flat config exists and is discovered without an explicit --config", () => {
    expect(existsSync(resolve(APP_ROOT, "eslint.config.mjs"))).toBe(true);
  });

  it("eslint runs to completion with stdin closed and returns a JSON report", () => {
    const { results } = runEslint();
    expect(Array.isArray(results)).toBe(true);
  }, 600_000);
});

describe("Guard 2 — the finding set is pinned", () => {
  it("scans at least the anti-vacuity floor of files", () => {
    const { results } = runEslint();
    // Without this floor, `ignores: ["**"]` would report zero findings and read
    // as a clean codebase.
    expect(results.length).toBeGreaterThanOrEqual(MIN_FILES_SCANNED);
  }, 600_000);

  it("reports exactly the pinned baseline finding count", () => {
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
