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
    // Anchored on the CALL VERB plus its distinguishing status, not on the
    // full argument list: threading `trigger`/`run_id` through the emit sites
    // made a full-argument-list anchor stale, and the `not.toBe(src)` landing
    // assertion below is what caught that rather than reporting a false pass.
    const mutated = src.replace(
      /emitOutcomeMarker\(logger, \{([^}]*status: "disabled")/,
      "noopMarker(logger, {$1",
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

/**
 * Extract the `apply-and-pr` step callback body — the region Inngest MEMOIZES
 * and therefore does not re-enter on a replay.
 *
 * The lint wants the assembly declaration as a line comment, not docblock
 * prose, so it sits immediately above the declaration below.
 */
// window-assembly: applyStepWindow — complete against the single
// `async (): Promise<ClusterOutcome> => {` callback in the handler. The
// function asserts that opener occurs EXACTLY once in the source, so the
// window cannot silently become a subset of a larger set of step callbacks:
// if a second cluster step is ever added, that uniqueness check throws rather
// than this guard quietly covering only the first.
export function applyStepWindow(src: string): string {
  const opener = "async (): Promise<ClusterOutcome> => {";
  const starts = src.split(opener).length - 1;
  if (starts !== 1) throw new Error(`expected exactly 1 step callback, found ${starts}`);
  const from = src.indexOf(opener) + opener.length;
  // The callback closes with the step.run call's own `},\n      );`.
  const closer = "\n        },\n      );";
  const to = src.indexOf(closer, from);
  if (to === -1) throw new Error("step callback close not found");
  // Comment-strip: this file DOCUMENTS the very constructs the assertions
  // below forbid, and an unstripped haystack is satisfied by the prose.
  return src
    .slice(from, to)
    .split("\n")
    .map((l) => l.replace(/^\s*\/\/.*$/, ""))
    .join("\n");
}

describe("Guard 3 — replay safety of the outcome accumulators", () => {
  const MUTATED = [
    "refusals.push(",
    "refusalDetail.push(",
    "clustersOpened++",
  ];

  it("no handler-scope accumulator is mutated INSIDE the memoized step callback", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const inside = applyStepWindow(src);
    const offenders = MUTATED.filter((m) => inside.includes(m));
    // Inngest replays the handler body but serves a completed step from memo
    // WITHOUT re-entering its callback. An accumulator mutated in there is
    // therefore empty on the pass that emits the marker — which reported
    // `refusals: []` for a run that refused every cluster, indistinguishable
    // from a quiet corpus. The datum #8281 exists to add answered "nothing
    // happened" in both cases.
    expect(offenders).toEqual([]);
  });

  it("non-vacuity: the accumulation DOES happen, just outside the callback", () => {
    // Without this, deleting the accumulation entirely would satisfy the
    // assertion above — an emptiness check with no totality companion pins
    // nothing.
    const src = readFileSync(SRC_PATH, "utf-8");
    const inside = applyStepWindow(src);
    for (const m of MUTATED) {
      expect(src).toContain(m);
      expect(inside).not.toContain(m);
    }
  });

  it("mutation row: a push moved back inside the callback is caught", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const anchor = 'return { kind: "refused", reason: "diff-size-exceeded" };';
    expect(src).toContain(anchor); // the anchor must LAND, or the row is vacuous
    const mutated = src.replace(
      anchor,
      `refusals.push("diff-size-exceeded");\n          ${anchor}`,
    );
    expect(mutated).not.toBe(src);
    expect(applyStepWindow(mutated)).toContain("refusals.push(");
  });

  it("every exit of the memoized callback returns a ClusterOutcome", () => {
    // A bare `return;` inside the callback is the old shape: it yields
    // `undefined`, which the accumulation below reads as neither opened nor
    // refused, silently dropping the cluster from both counts.
    const inside = applyStepWindow(readFileSync(SRC_PATH, "utf-8"));
    expect(inside).not.toMatch(/\breturn;\s*$/m);
    const returns = inside.match(/\breturn \{ kind: "(opened|refused)"/g) ?? [];
    expect(returns.length).toBeGreaterThanOrEqual(9);
  });
});
