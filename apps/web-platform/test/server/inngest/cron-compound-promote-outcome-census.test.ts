// Guard 1 (#8281) — every terminal return of the promote handler emits exactly
// one outcome marker.
//
// The property is over the SET of `return { ok: ... }` statements in the
// handler, present and future — not over the 7 statuses that happen to exist
// today. The census buckets each return as classified (the marker emit
// immediately preceding it, with no other return between) or UNCLASSIFIED,
// and any unclassified member is RED.
// MIN_TERMINAL_RETURNS is a floor, not the definition: adding an 8th return
// without a marker must fail here, which is the mutation that motivated the
// guard.
import { beforeEach, describe, expect, it } from "vitest";
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

  // COMMENT-STRIPPED. The SUT documents the very constructs this census
  // counts, so an unstripped haystack is satisfied by prose: a comment reading
  // `// emitOutcomeMarker( is deliberately not called here` used to classify
  // an unmarked return that sat beneath it.
  const stripped = scoped
    .split("\n")
    .map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/^\s*\*.*$/, ""))
    .join("\n");

  // Whitespace- and layout-TOLERANT. The previous anchor demanded exactly one
  // space after `{` and none before `:`, on a single line — so `return {ok:`,
  // `return { ok : true`, a prettier-wrapped multi-line object and the
  // shorthand `{ ok, status }` were all INVISIBLE, and an 8th terminal return
  // in any of those spellings left counts at 7/7 and the guard green. That is
  // the exact mutation the guard exists to catch.
  const RET = /return\s*\{[^}]*?\bok\s*[:,}]/g;

  // BLOCK-SCOPED by construction, no line window. Split on the marker call:
  // segment 0 precedes any marker, so a terminal return there has none;
  // segment i>0 follows marker i, and its FIRST terminal return is the one
  // that marker classifies. A second return in the same segment has no marker
  // of its own and is unclassified. A 12-line look-back used to reclassify a
  // healthy site as unclassified the moment its emit grew past 12 lines, and
  // classified a sneaked return by a marker belonging to a different branch.
  const segments = stripped.split(/emitOutcomeMarker\s*\(/);
  const markers = segments.length - 1;
  const unclassified: string[] = [];
  let classified = 0;
  segments.forEach((seg, i) => {
    const rets = seg.match(RET) ?? [];
    if (i === 0) {
      for (const r of rets) unclassified.push(`before any marker: ${r.trim()}`);
      return;
    }
    if (rets.length > 0) classified += 1;
    for (const r of rets.slice(1)) unclassified.push(`after marker ${i}, unmarked: ${r.trim()}`);
  });

  return { classified, markers, unclassified };
}

// Assertion floor. Stripping every `expect` from this file left it reporting
// "N passed", exit 0 -- indistinguishable from a suite that pins something.
// `requireAssertions` at the runner would be stronger, but it fails 174
// pre-existing tests across 28 unrelated files (measured), so it is scoped
// here: every test in this file must assert at least once.
beforeEach(() => {
  expect.hasAssertions();
});

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
    // Four spellings the old single-line, exact-whitespace anchor could not
    // see. Each inserts an 8th terminal return with no marker of its own.
    const spellings = [
      'if (Math.random() < 0) { return {ok:true, status:"sneaked"}; }',
      'if (Math.random() < 0) { return { ok : true, status: "sneaked" }; }',
      'if (Math.random() < 0) {\n  return {\n    ok: true,\n    status: "sneaked",\n  };\n}',
      'if (Math.random() < 0) { const ok = true; return { ok, status: "sneaked" }; }',
    ];
    for (const sneak of spellings) {
      const mutated = src.replace(
        /(\n\s*)return \{ ok: true, status: "disabled" \};/,
        `$1${sneak}$1return { ok: true, status: "disabled" };`,
      );
      expect(mutated).not.toBe(src); // the mutation must LAND, or the row is vacuous
      const c = censusTerminalReturns(mutated);
      expect(c.unclassified.length + (c.markers - c.classified), sneak).toBeGreaterThan(0);
    }
  });

  it("mutation row 1b: a COMMENT naming the marker does not classify an unmarked return", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const mutated = src.replace(
      /(\n\s*)return \{ ok: true, status: "disabled" \};/,
      '$1// emitOutcomeMarker( is deliberately not called on this path$1if (Math.random() < 0) { return { ok: true, status: "sneaked" }; }$1return { ok: true, status: "disabled" };',
    );
    expect(mutated).not.toBe(src);
    const c = censusTerminalReturns(mutated);
    expect(c.unclassified.length + (c.markers - c.classified)).toBeGreaterThan(0);
  });

  it("mutation row 2: deleting a marker emit leaves its return UNCLASSIFIED", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    // Anchored on the CALL VERB plus its distinguishing status, not on the
    // full argument list: threading `trigger`/`run_id` through the emit sites
    // made a full-argument-list anchor stale, and the `not.toBe(src)` landing
    // assertion below is what caught that rather than reporting a false pass.
    const mutated = src.replace(
      /emitOutcomeMarker\(\{([^}]*status: "disabled")/,
      "noopMarker({$1",
    );
    expect(mutated).not.toBe(src);
    const c2 = censusTerminalReturns(mutated);
    expect(c2.unclassified.length + (c2.markers - c2.classified)).toBeGreaterThan(0);
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
      '    emitOutcomeMarker({ status: "one" });',
      '    return { ok: true, status: "one" };',
      "  }",
      '  emitOutcomeMarker({ status: "two" });',
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
