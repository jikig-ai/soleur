import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Pins the WIRE that no unit test can see (#8092 review).
 *
 * `waitFailureState` and `awaitVisibleOrDiagnose` are both unit-tested, and that
 * is not enough: reverting either call site to a bare `await …waitFor(…)` left
 * the entire suite GREEN at 73/73, because a unit test observes the helper, not
 * whether anything calls it. Both endpoints were covered; the wire was not.
 *
 * So assert it at the source. Anchored on the CALL FORM and run against
 * comment-stripped text — the file documents this very construct in prose, and
 * a bare-token grep would be satisfied by the comment explaining the rule
 * (`cq-assert-anchor-not-bare-token`).
 */
const SRC = join(__dirname, "../../scripts/live-verify/run.ts");
const SUITE = join(__dirname, "wait-failure-state.test.ts");

/** Strip line and block comments so prose cannot satisfy a source assertion. */
function stripComments(src: string): string {
  return src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^[ \t]*\/\/.*$/gm, "");
}

describe("no bare visibility wait outside the diagnosing seam", () => {
  const code = stripComments(readFileSync(SRC, "utf8"));

  it("strips comments (non-vacuity control: the stripper actually works)", () => {
    // If this ever returns the prose, every assertion below is vacuous.
    expect(stripComments("// x\nkeep\n/* y */\n")).not.toContain("x");
    expect(stripComments("// x\nkeep\n/* y */\n")).toContain("keep");
    expect(code.length).toBeGreaterThan(1000);
  });

  it("routes every visibility wait through awaitVisibleOrDiagnose", () => {
    // The two waits #7969 is about. Each must appear exactly once, and only as
    // the callback handed to the seam — never awaited directly.
    const bareLocator = /await\s+input\.waitFor\s*\(/g;
    const bareSelector = /await\s+page\.waitForSelector\s*\(/g;
    expect(code.match(bareLocator) ?? []).toHaveLength(0);
    expect(code.match(bareSelector) ?? []).toHaveLength(0);
  });

  it("calls the seam from both sites, with the labels the report distinguishes", () => {
    const calls = code.match(/awaitVisibleOrDiagnose\s*\(/g) ?? [];
    // one definition + two call sites
    expect(calls.length).toBeGreaterThanOrEqual(2);
    expect(code).toContain('"composer"');
    expect(code).toContain('"rail"');
  });

  it("acts on the seam's verdict rather than discarding it", () => {
    // `await awaitVisibleOrDiagnose(...)` whose result is never returned would
    // compile, pass every unit test, and silently drop the diagnosis.
    expect(code).toMatch(/if\s*\(\s*composerFailed\s*\)\s*return\s+composerFailed/);
    expect(code).toMatch(/if\s*\(\s*railFailed\s*\)\s*return\s+railFailed/);
  });
});

describe("anti-vacuity floor for the #7969 suite", () => {
  // Deliberately in a DIFFERENT file, asserting over SOURCE. A floor inside
  // wait-failure-state.test.ts is skipped along with it — `describe.skip` on
  // that file reports "8 skipped" and exits 0, so a floor living there cannot
  // observe its own suite being switched off.
  const suite = readFileSync(SUITE, "utf8");

  it("declares at least the cases this PR's review established", () => {
    const cases = suite.match(/^\s*it(?:\.each\([^)]*\))?\s*\(/gm) ?? [];
    expect(cases.length).toBeGreaterThanOrEqual(19);
  });

  it("is not switched off wholesale", () => {
    expect(suite).not.toMatch(/\bdescribe\.skip\b/);
    expect(suite).not.toMatch(/\bit\.skip\b/);
    expect(suite).not.toMatch(/\bdescribe\.only\b/);
  });
});
