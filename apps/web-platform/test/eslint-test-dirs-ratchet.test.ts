import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Live arm of the shrink-only unused-binding ratchet over the test and fixture directories the
 * web-platform eslint run never reaches (#10331, PR3a). The rule is owned by
 * plugins/soleur/scripts/lint-ratchet.py; this file only makes that check block in the required `test` context,
 * where apps/web-platform/node_modules exists. It is deliberately separate from
 * eslint-config.test.ts so that file's 192-count ratchet and file-count floor stay untouched.
 *
 * Declared in test/repo-wide-suites.ts because it reads the repo root.
 */

const REPO_ROOT = resolve(__dirname, "..", "..", "..");
// One name drives both the case count and the class that is run, so they cannot drift apart.
const ESLINT_CLASS = "TestEslintConfigBehaviour";

describe("eslint test-dirs ratchet", () => {
  it("the live tree equals the committed baseline and never grows past the merge base", () => {
    expect.assertions(2);
    const result = spawnSync("python3", ["plugins/soleur/scripts/lint-ratchet.py", "eslint-test-dirs", "--check"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      // spawnSync blocks the event loop, so vitest's own timeout cannot interrupt a hung child.
      timeout: 110_000,
    });
    // Surface the script's own failure text (live path:row, rule, remedy) in the assertion.
    expect(`${result.stdout}${result.stderr}`.trim()).toMatch(/eslint-test-dirs/);
    expect(result.status).toBe(0);
  }, 120_000);

  it("the per-extension eslint config test runs here and is not skipped (#10507)", () => {
    // TestEslintConfigBehaviour is skipUnless(node_modules), and the `test-scripts` shard has no
    // npm ci, so it ran in no CI shard. This shard has node_modules: run it and prove it RAN.
    const source = readFileSync(resolve(REPO_ROOT, "tests/scripts/test_lint_ratchet.py"), "utf8");
    const cls = source.split(new RegExp(`^class ${ESLINT_CLASS}\\b`, "m"))[1]?.split(/^class /m)[0] ?? "";
    const cases = (cls.match(/^\s+def test_/gm) ?? []).length;
    expect(cases).toBeGreaterThan(0);
    const result = spawnSync(
      "python3",
      ["-m", "unittest", `tests.scripts.test_lint_ratchet.${ESLINT_CLASS}`, "-v"],
      { cwd: REPO_ROOT, encoding: "utf8", timeout: 110_000 },
    );
    const output = `${result.stdout}${result.stderr}`;
    expect(result.status, output).toBe(0);
    const ran = /Ran (\d+) tests?/.exec(output);
    expect(ran, output).not.toBeNull();
    expect(Number(ran![1])).toBeGreaterThanOrEqual(cases);
    // unittest -v marks a skipped case "... skipped '<reason>'"; a bare word match would also trip on a test name.
    expect(output).not.toMatch(/\.\.\. skipped /);
    expect(output).toContain(ESLINT_CLASS);
  }, 120_000);
});
