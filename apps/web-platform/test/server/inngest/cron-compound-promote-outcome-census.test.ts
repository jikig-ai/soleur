// Guard 1 (#8281) — every terminal return of the promote handler emits exactly
// one outcome marker.
//
// The property is over the SET of `return { ok: ... }` statements in the
// handler, present and future — not over the 7 statuses that happen to exist
// today. The census buckets each return as classified (a marker emit precedes
// it inside its own block) or UNCLASSIFIED, and any unclassified member is RED.
// MIN_TERMINAL_RETURNS is a floor, not the definition: adding an 8th return
// without a marker must fail here, which is the mutation that motivated the
// guard.
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/** Floor, not a pin — Phase 5 (#8293) may legitimately add returns. */
const MIN_TERMINAL_RETURNS = 7;

const SRC_PATH = join(
  __dirname,
  "..",
  "..",
  "..",
  "server",
  "inngest",
  "functions",
  "cron-compound-promote.ts",
);

/**
 * Enumerate the handler's terminal returns and classify each by whether an
 * outcome-marker emit precedes it within its enclosing block.
 *
 * Exported shape is deliberate: the dispatch row below drives this function
 * with a source that has no returns, and the census must report that as a
 * FAILURE rather than as a clean sweep.
 */
export function censusTerminalReturns(src: string): {
  classified: number;
  markers: number;
  unclassified: string[];
} {
  // Scope to the handler. Module-level helpers (checkDiffPaths) legitimately
  // return `{ ok: ... }` shapes of their own and are NOT terminal paths of a
  // run — counting them would make the census assert a property nobody holds.
  // Falls back to the whole source so a synthetic fixture (the must-PASS and
  // dispatch rows below) still censuses.
  const handlerStart = src.indexOf("export async function cronCompoundPromoteHandler");
  const scoped = handlerStart === -1 ? src : src.slice(handlerStart);
  const lineOffset = handlerStart === -1 ? 0 : src.slice(0, handlerStart).split("\n").length - 1;
  const lines = scoped.split("\n");
  const unclassified: string[] = [];
  let classified = 0;
  let markers = 0;

  lines.forEach((line, i) => {
    if (/emitOutcomeMarker\(/.test(line)) markers += 1;
    // Match a terminal return ANYWHERE on the line, not only at line start:
    // `if (cond) { return { ok: true, ... }; }` is a terminal path too, and a
    // line-anchored pattern is blind to exactly the inline form an author
    // reaches for when adding a quick early exit. (Mutation row 1 caught this.)
    if (!/return \{ ok: (true|false)/.test(line)) return;
    const windowStart = Math.max(0, i - 12);
    const preceding = lines.slice(windowStart, i).join("\n");
    if (/emitOutcomeMarker\(/.test(preceding)) {
      classified += 1;
    } else {
      unclassified.push(`L${lineOffset + i + 1}: ${line.trim()}`);
    }
  });

  return { classified, markers, unclassified };
}

describe("Guard 1 — outcome-marker census", () => {
  it("every terminal return emits an outcome marker, and there are at least 7", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const { classified, markers, unclassified } = censusTerminalReturns(src);

    expect(unclassified).toEqual([]);
    expect(classified).toBeGreaterThanOrEqual(MIN_TERMINAL_RETURNS);
    // One marker per terminal return. A look-back window alone would classify
    // an added return that merely sits near someone else's marker.
    expect(markers).toBe(classified);
  });

  it("mutation row 1: an added return with no marker is UNCLASSIFIED", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const mutated = src.replace(
      /(\n\s*)return \{ ok: true, status: "disabled" \};/,
      '$1if (Math.random() < 0) { return { ok: true, status: "sneaked" }; }$1return { ok: true, status: "disabled" };',
    );
    expect(mutated).not.toBe(src); // the mutation must LAND, or the row is vacuous
    const c = censusTerminalReturns(mutated);
    expect(c.unclassified.length + (c.classified - c.markers)).toBeGreaterThan(0);
  });

  it("mutation row 2: deleting a marker emit leaves its return UNCLASSIFIED", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const mutated = src.replace(
      'emitOutcomeMarker(logger, { status: "disabled" });',
      'noopMarker(logger, { status: "disabled" });',
    );
    expect(mutated).not.toBe(src);
    const c2 = censusTerminalReturns(mutated);
    expect(c2.unclassified.length + (c2.classified - c2.markers)).toBeGreaterThan(0);
  });

  it("mutation row 3 (dispatch): a census finding zero returns must not read as clean", () => {
    // A scanner that yields [] reports `unclassified: []` — indistinguishable
    // from a healthy sweep by that field alone. The classified-count floor is
    // what makes "0 checked" fail, so assert it directly.
    const { classified, unclassified } = censusTerminalReturns("// no returns here\n");
    expect(unclassified).toEqual([]);
    expect(classified).toBe(0);
    expect(classified).toBeLessThan(MIN_TERMINAL_RETURNS);
  });

  it("must-PASS non-canonical: two returns sharing one marker helper both classify", () => {
    const synthetic = [
      "async function h() {",
      "  if (a) {",
      '    emitOutcomeMarker(logger, { status: "one" });',
      '    return { ok: true, status: "one" };',
      "  }",
      '  emitOutcomeMarker(logger, { status: "two" });',
      '  return { ok: true, status: "two" };',
      "}",
    ].join("\n");
    const { classified, markers, unclassified } = censusTerminalReturns(synthetic);
    expect(unclassified).toEqual([]);
    expect(classified).toBe(2);
    expect(markers).toBe(2);
  });
});
