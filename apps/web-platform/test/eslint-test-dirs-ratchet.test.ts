import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Live arm of the shrink-only unused-binding ratchet over the test and fixture directories the
 * web-platform eslint run never reaches (#10331, PR3a). The rule is owned by
 * scripts/lint-ratchet.py; this file only makes that check block in the required `test` context,
 * where apps/web-platform/node_modules exists. It is deliberately separate from
 * eslint-config.test.ts so that file's 192-count ratchet and file-count floor stay untouched.
 *
 * Declared in test/repo-wide-suites.ts because it reads the repo root.
 */

const REPO_ROOT = resolve(__dirname, "..", "..", "..");

describe("eslint test-dirs ratchet", () => {
  it("the live tree equals the committed baseline and never grows past the merge base", () => {
    expect.assertions(2);
    const result = spawnSync("python3", ["scripts/lint-ratchet.py", "eslint-test-dirs", "--check"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
    });
    // Surface the script's own failure text (live path:row, rule, remedy) in the assertion.
    expect(`${result.stdout}${result.stderr}`.trim()).toMatch(/eslint-test-dirs/);
    expect(result.status).toBe(0);
  }, 120_000);
});
