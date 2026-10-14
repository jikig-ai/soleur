import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";
import { stripComments } from "../helpers/strip-comments";

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
const RAIL_SUITE = join(__dirname, "rail-assert-verdict.test.ts");
const RAIL_COMPONENT = join(
  __dirname,
  "../../components/chat/conversations-rail.tsx",
);

describe("no bare visibility wait outside the diagnosing seam", () => {
  const code = stripComments(readFileSync(SRC, "utf8"));

  it("strips comments (non-vacuity control: the stripper actually works)", () => {
    // If this ever returns the prose, every assertion below is vacuous.
    expect(stripComments("// x\nkeep\n/* y */\n")).not.toContain("x");
    expect(stripComments("// x\nkeep\n/* y */\n")).toContain("keep");
    expect(code.length).toBeGreaterThan(1000);
  });

  it("routes every visibility wait through a seam callback — class-scoped, not name-scoped", () => {
    // Naming `railRow.waitFor`/`input.waitFor`/`page.waitForSelector` pins
    // three SPELLINGS and lets `page.locator(X).waitFor(` or
    // `railRow.first().waitFor(` slide through — the class is "a waitFor
    // not handed to awaitVisibleOrDiagnose as a `() =>` callback". Strip
    // the sanctioned arrow-arg form, then NOTHING may waitFor at all.
    const unsanctioned = code.replace(
      /=>\s*[A-Za-z0-9_$.[\]()'"`]*\.waitFor[A-Za-z]*\s*\(/g,
      "",
    );
    // The whole waitFor* family — waitFor, waitForSelector, waitForURL,
    // waitForTimeout, waitForEvent, waitForFunction — not just one spelling.
    expect(unsanctioned.match(/\.waitFor[A-Za-z]*\s*\(/g) ?? []).toHaveLength(0);
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

describe("rail assert seam (#9581) — the wire, not the endpoints", () => {
  const code = stripComments(readFileSync(SRC, "utf8"));

  it("routes the rail verdict through assertRailRowVisible and railVerdictToResult", () => {
    // One definition + at least one call site each. A seam that is exported
    // and unit-tested but never wired is the #8092 class all over again.
    const seamCalls = code.match(/assertRailRowVisible\s*\(/g) ?? [];
    const mapCalls = code.match(/railVerdictToResult\s*\(/g) ?? [];
    expect(seamCalls.length).toBeGreaterThanOrEqual(2);
    expect(mapCalls.length).toBeGreaterThanOrEqual(2);
  });

  it("returns the mapper's result rather than discarding the verdict", () => {
    // `railVerdictToResult(verdict, convId); return {kind:"PASS",…}` compiles
    // and leaves the wire pin above green — assert the mapped Result is
    // bound to `result` and that `result` is what driveAndVerify returns.
    expect(code).toMatch(
      /const result: Result = railVerdictToResult\(verdict, convId\)/,
    );
    expect(code).toMatch(/return result;/);
  });

  it("never reintroduces a bare railRow.waitFor (the single-shot wait this removed)", () => {
    expect(code.match(/railRow\.waitFor\s*\(/g) ?? []).toHaveLength(0);
  });

  it("produces the RESULT line through emitLine — the tested builder, not a copy", () => {
    // `emit` once duplicated emitLine's format inline; the suite asserts
    // emitLine while production wrote the copy — drift-invisible. emit must
    // delegate.
    expect(code).toMatch(/function emit\(result: Result\)[^}]*emitLine\(result\)/s);
  });

  it("passes no budget override at the call site — production reads the named constants", () => {
    // `budget` is the test-only escape hatch; a production call site
    // carrying it could shrink the check to instant-FAIL or an unbounded
    // observe while every suite stays green.
    const callBlock = code.match(/assertRailRowVisible\(\{[\s\S]*?\}\);/)?.[0] ?? "";
    // A vacuous non-match must FAIL, not pass — a call-site reshape (or an
    // arg object hoisted to a const, the exact shape a budget smuggle
    // takes) would otherwise empty `callBlock` and satisfy the assertion.
    expect(callBlock).toContain("productionUrl");
    expect(callBlock).not.toContain("budget");
  });

  it("scopes the rail-row locator to this conversation's id — a wider anchor would PASS on a stale row", () => {
    expect(code).toContain('a[href$="/dashboard/chat/${convId}"]');
  });

  it("keeps the probe's p_limit at rail parity — a RAIL_LIMIT change must drift red", () => {
    const component = stripComments(readFileSync(RAIL_COMPONENT, "utf8"));
    const limit = component.match(/RAIL_LIMIT\s*=\s*(\d+)/)?.[1];
    expect(limit).toBeDefined();
    expect(code).toContain(`p_limit: ${limit}`);
  });
});

describe("anti-vacuity floor for the #9581 suite", () => {
  const suite = stripComments(readFileSync(RAIL_SUITE, "utf8"));

  it("declares at least the cases the seam's review established", () => {
    const cases = suite.match(/^\s*it(?:\.each\([^)]*\))?\s*\(/gm) ?? [];
    expect(cases.length).toBeGreaterThanOrEqual(14);
  });

  it("is not switched off wholesale", () => {
    expect(suite).not.toMatch(/\bdescribe\.skip\b/);
    expect(suite).not.toMatch(/\bit\.skip\b/);
    expect(suite).not.toMatch(/\bdescribe\.only\b/);
    expect(suite).not.toMatch(/\bxdescribe\b/);
    expect(suite).not.toMatch(/\bxit\b/);
    expect(suite).not.toMatch(/\bdescribe\.todo\b/);
    expect(suite).not.toMatch(/\bit\.todo\b/);
    expect(suite).not.toMatch(/\b(?:it|describe)\.skipIf\b/);
    expect(suite).not.toMatch(/\btest\.skip\b/);
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
