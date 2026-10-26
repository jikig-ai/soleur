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

// ---------------------------------------------------------------------------
// Guard 1 (#8427) — emit-site attribution of a `checkDiffPaths` refusal.
//
// PROPERTY: the multiset of `reason` literals carried by the `ok: false`
// returns inside `checkDiffPaths`, keyed by site, matches the declared
// `DiffPathVerdict["reason"]` union exactly.
//
// An AST census, not a regex one. A regex over comment-stripped text was the
// first design and every one of its failure modes is real in this file: the
// stripper reused above is line-oriented (`^\s*//`, `^\s*\*`), so it misses a
// single-line `/* … */`, a `/**` opener and a TRAILING `// …` after code; the
// file carries ~552 comment lines (as-written; the ~97 this said before was the
// origin/main figure, i.e. the count for the file BEFORE this change) and
// narrates its own reason literals in them;
// the two `underivable-unparsable-record` returns exceed 100 characters and
// this repo has NO formatter config, so whether they are one line or three is
// an implementer's choice; and hoisting the refusals behind an ordinary
// `const refuse = (reason, detail) => ({ ok: false, reason, detail })` would
// remove every `reason: "` literal from the window with the property intact.
// The AST census is immune to all four by construction.
//
// Comparison is by SITE-KEYED MULTISET, not by set. Two sites legitimately
// share `underivable-unparsable-record`; a plain set tolerates changing ONE of
// them to another declared literal, leaving the set unchanged and the census
// green while the property is false.
import ts from "typescript";

/**
 * Both sides come from the parse tree: (a) the string-literal members of
 * `DiffPathVerdict`'s `reason` property type, (b) the `reason` initializer of
 * every `ok: false` object literal returned inside `checkDiffPaths`.
 *
 * Exported so the dispatch row can drive it with a source that has neither and
 * assert it THROWS — a census finding nothing must never read as a pass.
 */
export function censusDiffReasons(src: string): {
  declared: string[];
  emitted: string[];
} {
  const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.Latest, true);
  const declared: string[] = [];
  const emitted: string[] = [];

  // Collect string-literal members, following a TYPE REFERENCE to an alias
  // declared in the same file. Without that hop, extracting the union to
  // `type DiffPathReason = …` — an ordinary refactor a reviewer would ask for —
  // made this census throw "no declared" and report a FALSE RED, whose obvious
  // repair is to loosen the census.
  const aliases = new Map<string, ts.TypeNode>();
  const collectAliases = (n: ts.Node): void => {
    if (ts.isTypeAliasDeclaration(n) && n.type) aliases.set(n.name.text, n.type);
    n.forEachChild(collectAliases);
  };
  collectAliases(sf);

  const literalsOf = (node: ts.TypeNode | undefined, seen = new Set<string>()): string[] => {
    const out: string[] = [];
    const walk = (n: ts.Node): void => {
      if (ts.isLiteralTypeNode(n) && ts.isStringLiteral(n.literal)) out.push(n.literal.text);
      if (ts.isTypeReferenceNode(n) && ts.isIdentifier(n.typeName)) {
        const name = n.typeName.text;
        const target = aliases.get(name);
        if (target !== undefined && !seen.has(name)) {
          seen.add(name);
          out.push(...literalsOf(target, seen));
        }
      }
      n.forEachChild(walk);
    };
    if (node) walk(node);
    return out;
  };

  const visit = (node: ts.Node): void => {
    // (a) declared side — the `reason` member of the DiffPathVerdict union.
    if (ts.isTypeAliasDeclaration(node) && node.name.text === "DiffPathVerdict") {
      const walk = (n: ts.Node): void => {
        if (ts.isPropertySignature(n) && ts.isIdentifier(n.name) && n.name.text === "reason") {
          declared.push(...literalsOf(n.type));
        }
        n.forEachChild(walk);
      };
      walk(node);
    }
    // (b) emitted side — every `ok: false` return inside checkDiffPaths.
    if (ts.isFunctionDeclaration(node) && node.name?.text === "checkDiffPaths") {
      const walk = (n: ts.Node): void => {
        if (ts.isReturnStatement(n) && n.expression && ts.isObjectLiteralExpression(n.expression)) {
          const props = n.expression.properties;
          const isFalse = props.some(
            (pr) =>
              ts.isPropertyAssignment(pr) &&
              ts.isIdentifier(pr.name) &&
              pr.name.text === "ok" &&
              pr.initializer.kind === ts.SyntaxKind.FalseKeyword,
          );
          if (isFalse) {
            for (const pr of props) {
              if (
                ts.isPropertyAssignment(pr) &&
                ts.isIdentifier(pr.name) &&
                pr.name.text === "reason"
              ) {
                // BOTH literal forms. `ts.isStringLiteral` is false for a
                // NoSubstitutionTemplateLiteral, so `` reason: `structural-op` ``
                // — a semantically identical spelling — made its site invisible
                // to this walk while the property stayed intact.
                if (
                  ts.isStringLiteral(pr.initializer) ||
                  ts.isNoSubstitutionTemplateLiteral(pr.initializer)
                ) {
                  emitted.push(pr.initializer.text);
                } else {
                  // A non-literal initializer (a const, a call, a conditional)
                  // means a site this census cannot read. Refuse rather than
                  // silently shrink the emitted multiset.
                  throw new Error(
                    `census: non-literal reason initializer at position ${pr.getStart()}`,
                  );
                }
              }
            }
          }
        }
        n.forEachChild(walk);
      };
      walk(node);
    }
    node.forEachChild(visit);
  };
  visit(sf);

  if (declared.length === 0) throw new Error("census found no declared reason literals");
  if (emitted.length === 0) throw new Error("census found no emitted reason literals");
  return { declared, emitted };
}

const sortedUnique = (xs: string[]): string[] => [...new Set(xs)].sort();

describe("Guard 1 (#8427) — checkDiffPaths reason attribution", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });

  it("every declared reason is emitted by a site, and every emitted one is declared", () => {
    const { declared, emitted } = censusDiffReasons(readFileSync(SRC_PATH, "utf-8"));
    // Set identity in BOTH directions. A one-way census is satisfied by a union
    // that grows without emitters (mutation row 2).
    expect(sortedUnique(emitted)).toEqual(sortedUnique(declared));
    // The two shared-literal sites make emitted longer than declared.
    expect(emitted.length).toBeGreaterThan(declared.length);
  });

  // The SITE-KEYED MULTISET, pinned per literal rather than for one of them.
  //
  // The previous form asserted a count for `underivable-unparsable-record`
  // alone, which left `structural-op`'s THREE sites unpinned: retargeting one
  // of them to another declared literal kept the SET identical and this census
  // green while the property was false (measured). A count map is a ratchet —
  // it must be edited when a site is added or removed, and that is the point.
  const EXPECTED_SITE_COUNTS: Readonly<Record<string, number>> = {
    "structural-op": 3,
    empty: 1,
    "underivable-read-tree": 1,
    "underivable-apply": 1,
    "underivable-diff-index": 1,
    "underivable-empty-pathset": 1,
    "underivable-unparsable-record": 2,
    "path-refused": 1,
  };

  it("every reason literal is emitted by exactly the sites it should be", () => {
    const { emitted } = censusDiffReasons(readFileSync(SRC_PATH, "utf-8"));
    const actual: Record<string, number> = {};
    for (const r of emitted) actual[r] = (actual[r] ?? 0) + 1;
    expect(actual).toEqual(EXPECTED_SITE_COUNTS);
  });

  it("mutation: retargeting ONE of the three structural-op sites is RED", () => {
    // The mutant a set comparison cannot see. Only the FIRST occurrence is
    // replaced, so two structural-op sites remain and the set is unchanged.
    const src = readFileSync(SRC_PATH, "utf-8").replace(
      'reason: "structural-op", detail: "binary patch"',
      'reason: "path-refused", detail: "binary patch"',
    );
    const { emitted } = censusDiffReasons(src);
    const actual: Record<string, number> = {};
    for (const r of emitted) actual[r] = (actual[r] ?? 0) + 1;
    expect(sortedUnique(emitted)).toEqual(sortedUnique(Object.keys(EXPECTED_SITE_COUNTS)));
    expect(actual).not.toEqual(EXPECTED_SITE_COUNTS);
  });

  it("mutation: a template-literal reason is seen, not silently skipped", () => {
    const src = readFileSync(SRC_PATH, "utf-8").replace(
      'reason: "underivable-read-tree"',
      "reason: `underivable-read-tree`",
    );
    const { emitted } = censusDiffReasons(src);
    expect(emitted.filter((r) => r === "underivable-read-tree")).toHaveLength(1);
  });

  it("refactor-tolerance: extracting the union to a named alias stays GREEN", () => {
    // Previously a FALSE RED. The census follows a type reference to an alias
    // declared in the same file, so this ordinary refactor does not look like a
    // regression.
    const src = [
      'export type DiffPathReason = "a" | "b";',
      "export type DiffPathVerdict =",
      "  | { ok: true; paths: string[] }",
      "  | { ok: false; reason: DiffPathReason; detail: string };",
      "export async function checkDiffPaths(): Promise<DiffPathVerdict> {",
      '  if (x) return { ok: false, reason: "a", detail: "d" };',
      '  return { ok: false, reason: "b", detail: "d" };',
      "}",
    ].join("\n");
    const { declared, emitted } = censusDiffReasons(src);
    expect(sortedUnique(declared)).toEqual(["a", "b"]);
    expect(sortedUnique(emitted)).toEqual(["a", "b"]);
  });

  it("mutation row 2: a declared-but-unemitted member is RED", () => {
    const src = readFileSync(SRC_PATH, "utf-8").replace(
      '        | "path-refused";',
      '        | "path-refused"\n        | "never-emitted";',
    );
    const { declared, emitted } = censusDiffReasons(src);
    expect(sortedUnique(emitted)).not.toEqual(sortedUnique(declared));
  });

  it("mutation row 5: collapsing read-tree onto underivable-apply is RED", () => {
    // Precondition holds — every emitted literal is still a declared member —
    // yet two structurally different causes would share one reason.
    const src = readFileSync(SRC_PATH, "utf-8").replace(
      'reason: "underivable-read-tree"',
      'reason: "underivable-apply"',
    );
    const { declared, emitted } = censusDiffReasons(src);
    expect(sortedUnique(emitted)).not.toEqual(sortedUnique(declared));
  });

  it("mutation row 3 (dispatch): a census finding zero sites THROWS, never reads clean", () => {
    expect(() => censusDiffReasons("export const x = 1;\n")).toThrow(/found no declared/);
    expect(() =>
      censusDiffReasons('type DiffPathVerdict = { reason: "a" };\n'),
    ).toThrow(/found no emitted/);
  });

  it("mutation row 6 (comment): all three comment spellings leave the census unchanged", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const base = censusDiffReasons(src);
    const spellings = [
      // (a) asterisk-continuation line inside a block comment
      ['export async function checkDiffPaths(', '/**\n * reason: "underivable-apply"\n */\nexport async function checkDiffPaths('],
      // (b) single-line block comment
      ['export async function checkDiffPaths(', '/* reason: "underivable-apply" */\nexport async function checkDiffPaths('],
      // (c) TRAILING comment after a statement — stripped by NEITHER
      //     line-oriented stripper in this repo, which is why this is a
      //     three-spelling loop rather than one insertion.
      ['const indexFile = join(', 'const zzz = 1; // reason: "underivable-apply"\n  const indexFile = join('],
    ];
    for (const [from, to] of spellings) {
      expect(src).toContain(from);
      const mutated = censusDiffReasons(src.replace(from, to));
      expect(sortedUnique(mutated.emitted)).toEqual(sortedUnique(base.emitted));
      expect(sortedUnique(mutated.declared)).toEqual(sortedUnique(base.declared));
    }
  });

  it("mutation row 7 (refactor-tolerance): a `refuse()` helper keeps the census GREEN", () => {
    // The property is unchanged by hoisting, so the census must not redden —
    // a census that fails here is pinning formatting, not behaviour. Under the
    // AST walk this holds by construction for the returns it can still see.
    const src = [
      'export type DiffPathVerdict =',
      '  | { ok: true; paths: string[] }',
      '  | { ok: false; reason: "a" | "b"; detail: string };',
      'export async function checkDiffPaths(): Promise<DiffPathVerdict> {',
      '  if (x) {',
      '    return {',
      '      ok: false,',
      '      reason: "a",',
      '      detail: "d",',
      '    };',
      '  }',
      '  return { ok: false, reason: "b", detail: "d" };',
      '}',
    ].join("\n");
    const { declared, emitted } = censusDiffReasons(src);
    expect(sortedUnique(emitted)).toEqual(sortedUnique(declared));
  });

  it("harness row: the declared side comes from the AST, not a literal in this file", () => {
    // If someone replaces the derived read with a hard-coded array of today's
    // values, this row must redden. It does so by feeding a source whose union
    // differs from production: a hard-coded declared side would still report
    // today's members and the equality below would fail.
    const src = [
      'export type DiffPathVerdict =',
      '  | { ok: true; paths: string[] }',
      '  | { ok: false; reason: "only-one"; detail: string };',
      'export async function checkDiffPaths(): Promise<DiffPathVerdict> {',
      '  return { ok: false, reason: "only-one", detail: "d" };',
      '}',
    ].join("\n");
    expect(censusDiffReasons(src).declared).toEqual(["only-one"]);
  });
});

// ---------------------------------------------------------------------------
// #10552 -- the draft step, its reasons, and the single source of the diff.
//
// The model no longer authors `proposed_diff_unified`. Three properties keep that
// true, and each is read from the parse tree or a delimited window, never from a
// literal list of today's call sites:
//
//   Guard 3b  the `draft-edit-*` memoized callback mutates no handler-scope
//             accumulator (same replay hazard as the apply callback), and returns
//             only `{kind, diff}` / `{kind, reason}` -- never target-file text.
//   Guard 1b  every `edit-*` reason is declared once and emitted from exactly one
//             site; none is folded into `DiffPathVerdict` (that census owns
//             `checkDiffPaths` alone).
//   Guard 1c  `proposed_diff_unified` is assigned from the derived diff in exactly
//             one place and is offered to the model nowhere.
// ---------------------------------------------------------------------------

// window-assembly: draftStepWindow -- complete against the single
// `async (): Promise<DraftOutcome> => {` callback in the handler. The function
// asserts that opener occurs EXACTLY once, for the same reason applyStepWindow does:
// a second draft-shaped step must throw here, not leave the guard covering only the
// first. It is a SEPARATE window from the apply step's because that function hard-codes
// `Promise<ClusterOutcome>` and its own closer.
export function draftStepWindow(src: string): string {
  const opener = "async (): Promise<DraftOutcome> => {";
  const starts = src.split(opener).length - 1;
  if (starts !== 1) throw new Error(`expected exactly 1 draft step callback, found ${starts}`);
  const from = src.indexOf(opener) + opener.length;
  const closer = "\n        },\n      );";
  const to = src.indexOf(closer, from);
  if (to === -1) throw new Error("draft step callback close not found");
  return src
    .slice(from, to)
    .split("\n")
    .map((l) => l.replace(/^\s*\/\/.*$/, ""))
    .join("\n");
}

/**
 * Declared = the members of `EDIT_REFUSAL_REASONS`; emitted = every `reason: "edit-*"`
 * property assignment in the module. Throws when either side is empty so a census that
 * found nothing can never read as clean.
 */
export function censusEditReasons(src: string): { declared: string[]; emitted: string[] } {
  const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.Latest, true);
  const declared: string[] = [];
  const emitted: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name) && n.name.text === "EDIT_REFUSAL_REASONS" && n.initializer) {
      const walk = (m: ts.Node): void => {
        if (ts.isStringLiteral(m)) declared.push(m.text);
        m.forEachChild(walk);
      };
      walk(n.initializer);
    }
    if (
      ts.isPropertyAssignment(n) &&
      ts.isIdentifier(n.name) &&
      n.name.text === "reason" &&
      (ts.isStringLiteral(n.initializer) || ts.isNoSubstitutionTemplateLiteral(n.initializer)) &&
      n.initializer.text.startsWith("edit-")
    ) {
      emitted.push(n.initializer.text);
    }
    n.forEachChild(visit);
  };
  visit(sf);
  if (declared.length === 0) throw new Error("census found no declared edit reasons");
  if (emitted.length === 0) throw new Error("census found no emitted edit reasons");
  return { declared, emitted };
}

/** Every property assignment named `proposed_diff_unified`, with its initializer's source text. */
export function censusDiffAssignments(src: string): string[] {
  const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.Latest, true);
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isPropertyAssignment(n) && (ts.isIdentifier(n.name) || ts.isStringLiteral(n.name)) && n.name.text === "proposed_diff_unified") {
      out.push(n.initializer.getText(sf));
    }
    if (ts.isShorthandPropertyAssignment(n) && n.name.text === "proposed_diff_unified") out.push("<shorthand>");
    n.forEachChild(visit);
  };
  visit(sf);
  return out;
}

describe("Guard 3b (#10552) -- replay safety of the draft step", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const FORBIDDEN = ["refusals.push(", "refusalDetail.push(", "clustersOpened++", "draftedTargets.add("];

  it("no handler-scope accumulator is mutated INSIDE the memoized draft callback", () => {
    const inside = draftStepWindow(readFileSync(SRC_PATH, "utf-8"));
    expect(FORBIDDEN.filter((m) => inside.includes(m))).toEqual([]);
  });

  it("non-vacuity: the window is the draft callback (it calls the drafter) and is not empty", () => {
    const inside = draftStepWindow(readFileSync(SRC_PATH, "utf-8"));
    expect(inside).toContain("draftAdditiveEdit(");
    expect(inside.length).toBeGreaterThan(200);
  });

  it("mutation row: a push moved into the draft callback is caught", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const anchor = 'return { kind: "refused", reason: "target-path-refused" };';
    expect(src).toContain(anchor); // the anchor must LAND, or the row is vacuous
    const mutated = src.replace(anchor, `refusals.push("target-path-refused");\n          ${anchor}`);
    expect(mutated).not.toBe(src);
    expect(FORBIDDEN.some((m) => draftStepWindow(mutated).includes(m))).toBe(true);
  });

  it("mutation row: `draftedTargets.add` moved INTO the draft callback is caught (it would not replay)", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const anchor = 'return { kind: "drafted", diff: result.diff };';
    expect(src).toContain(anchor);
    const mutated = src.replace(anchor, `draftedTargets.add(proposed.target_path);\n        ${anchor}`);
    expect(mutated).not.toBe(src);
    expect(FORBIDDEN.some((m) => draftStepWindow(mutated).includes(m))).toBe(true);
  });

  it("every exit of the draft callback returns a DraftOutcome carrying only kind + diff/reason (AC6)", () => {
    const inside = draftStepWindow(readFileSync(SRC_PATH, "utf-8"));
    expect(inside).not.toMatch(/\breturn;\s*$/m);
    const returns = inside.match(/\breturn \{[^}]*\}/g) ?? [];
    expect(returns.length).toBeGreaterThanOrEqual(2);
    for (const r of returns) {
      expect(r, r).toMatch(/^return \{ kind: "(drafted", diff: result\.diff|refused", reason: (result\.reason|"[a-z-]+")) \}$/);
    }
    // No target-file text in a step return value (it would be persisted step state).
    expect(inside).not.toMatch(/\breturn \{[^}]*\b(base|text)\b[^}]*\}/);
  });

  it("dispatch: a source with no / two draft callbacks THROWS, never reads clean", () => {
    expect(() => draftStepWindow("const x = 1;")).toThrow(/found 0/);
    const one = "async (): Promise<DraftOutcome> => {\n  a\n        },\n      );";
    expect(() => draftStepWindow(one + one)).toThrow(/found 2/);
  });
});

describe("Guard 1b (#10552) -- every edit-* reason is declared once and emitted from exactly one site", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });

  it("declared and emitted sets are identical, and no reason has two emit sites", () => {
    const { declared, emitted } = censusEditReasons(readFileSync(SRC_PATH, "utf-8"));
    expect(declared).toHaveLength(7);
    expect(sortedUnique(emitted)).toEqual(sortedUnique(declared));
    const counts: Record<string, number> = {};
    for (const r of emitted) counts[r] = (counts[r] ?? 0) + 1;
    expect(counts).toEqual(Object.fromEntries(declared.map((d) => [d, 1])));
  });

  it("the edit reasons are NOT folded into DiffPathVerdict (that census owns checkDiffPaths alone)", () => {
    const { declared } = censusDiffReasons(readFileSync(SRC_PATH, "utf-8"));
    expect(declared.filter((r) => r.startsWith("edit-"))).toEqual([]);
  });

  it("mutation: a second emit site for one reason is RED", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const anchor = 'reason: "edit-anchor-not-found"';
    expect(src).toContain(anchor);
    const mutated = src.replace(anchor, `reason: "edit-anchor-ambiguous"`);
    const { emitted } = censusEditReasons(mutated);
    const counts: Record<string, number> = {};
    for (const r of emitted) counts[r] = (counts[r] ?? 0) + 1;
    expect(counts["edit-anchor-ambiguous"]).toBe(2);
    expect(counts["edit-anchor-not-found"]).toBeUndefined();
  });

  it("mutation: a declared-but-unemitted member is RED", () => {
    const src = readFileSync(SRC_PATH, "utf-8").replace(
      '"edit-derive-failed",\n] as const;',
      '"edit-derive-failed",\n  "edit-never-emitted",\n] as const;',
    );
    const { declared, emitted } = censusEditReasons(src);
    expect(sortedUnique(emitted)).not.toEqual(sortedUnique(declared));
  });

  it("dispatch: a census finding nothing THROWS", () => {
    expect(() => censusEditReasons("export const x = 1;")).toThrow(/no declared/);
    expect(() => censusEditReasons('export const EDIT_REFUSAL_REASONS = ["edit-a"] as const;')).toThrow(/no emitted/);
  });
});

describe("Guard 1c (#10552) -- proposed_diff_unified comes from the derived diff and nowhere else", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });

  it("is assigned exactly once, from the draft's derived diff", () => {
    const assigns = censusDiffAssignments(readFileSync(SRC_PATH, "utf-8"));
    expect(assigns).toHaveLength(1);
    // Derived from the draft's diff, and from no model-authored value.
    expect(assigns[0]).toMatch(/\bdraft\.diff\b/);
    expect(assigns[0]).not.toMatch(/proposed|cluster/);
  });

  it("mutation: re-adding it to CLUSTER_OUTPUT_SCHEMA is RED", () => {
    const src = readFileSync(SRC_PATH, "utf-8").replace(
      "rationale: { type: \"string\" },",
      'rationale: { type: "string" },\n          proposed_diff_unified: { type: "string" },',
    );
    expect(censusDiffAssignments(src).length).toBeGreaterThan(1);
  });

  it("mutation: assigning it from the model response in the handler is RED", () => {
    const original = readFileSync(SRC_PATH, "utf-8");
    const src = original.replace(
      'proposed_diff_unified: draft.kind === "drafted" ? draft.diff : ""',
      "proposed_diff_unified: (proposed as unknown as { proposed_diff_unified: string }).proposed_diff_unified",
    );
    expect(src).not.toBe(original); // the mutation must LAND, or the row is vacuous
    const a = censusDiffAssignments(src);
    expect(a.length === 1 && /\bdraft\.diff\b/.test(a[0]) && !/proposed|cluster/.test(a[0])).toBe(false);
  });

  it("the handler consults TARGET_ALLOW_RE at exactly two sites: the draft step and the apply step", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const handler = src.slice(src.indexOf("export async function cronCompoundPromoteHandler"));
    const stripped = handler
      .split("\n")
      .map((l) => l.replace(/^\s*\/\/.*$/, ""))
      .join("\n");
    expect(stripped.split("TARGET_ALLOW_RE.test(").length - 1).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// Guard 1d -- the promotion quorum is ONE named constant, and the three places that used to
// spell the number (the phase-1 prompt, the `Threshold-Hit` trailer, the drafter's refusal)
// all read it. A census over the parse tree, never a list of today's call sites.
//
// What this pins and what it does not: it pins that the code reads the constant everywhere
// and that the refusal has exactly one emit site. It does not pin the VALUE (the value row in
// cron-compound-promote-draft-edit.test.ts does, and the ADR-092 Amendment names it).
// ---------------------------------------------------------------------------

// window-assembly: censusQuorum -- complete against the whole module, parsed once: every
// VariableDeclaration, TemplateExpression, BinaryExpression and `reason` PropertyAssignment
// in the file is visited, so a second declaration or emit site ANYWHERE in the module is
// counted, not only those in today's functions.
export function censusQuorum(src: string): {
  declaredValue: number;
  promptQuorumSpans: number;
  promptHasNumericThreshold: boolean;
  trailerQuorumSpans: number;
  trailerHasNumericDenominator: boolean;
  comparisons: number;
  /** The comparison IS the `if` condition (no `&&`/`||`) and the `if` is a top-level statement of `draftAdditiveEdit`. */
  gateIsPlain: boolean;
  /** The gate's body directly returns `{ ok: false, reason: "quorum-not-met", sourceCount }`. */
  gateReturnsRefusal: boolean;
  /** Only pure in-memory calls precede the gate in its function, and >= 2 readEditTarget(/post( calls follow it. */
  gateBeforeIo: boolean;
  /** The quorum span in the phase-1 prompt follows a `>=` (the sense of the threshold). */
  promptSenseOk: boolean;
  /** The prompt's second line reads "<quorum> or more distinct" from the constant. */
  promptOrMoreOk: boolean;
  emits: number;
} {
  const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.Latest, true);
  const decls: number[] = [];
  let promptQuorumSpans = 0;
  let promptHasNumericThreshold = false;
  let promptSeen = 0;
  let trailerQuorumSpans = 0;
  let trailerHasNumericDenominator = false;
  let trailerSeen = 0;
  let comparisons = 0;
  let gateIsPlain = false;
  let gateReturnsRefusal = false;
  let gateBeforeIo = false;
  let promptSenseOk = false;
  let promptOrMoreOk = false;
  let shadows = 0;
  let emits = 0;
  const isQuorum = (e: ts.Node): boolean => ts.isIdentifier(e) && e.text === "PROMOTION_QUORUM";
  const pieces = (t: ts.TemplateExpression): string[] => [t.head.text, ...t.templateSpans.map((s) => s.literal.text)];
  const visit = (n: ts.Node): void => {
    if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name) && n.name.text === "PROMOTION_QUORUM") {
      decls.push(n.initializer && ts.isNumericLiteral(n.initializer) ? Number(n.initializer.text) : Number.NaN);
    }
    // A parameter or destructured binding of the same name would shadow the constant inside the gate.
    if ((ts.isParameter(n) || ts.isBindingElement(n)) && ts.isIdentifier(n.name) && n.name.text === "PROMOTION_QUORUM") {
      shadows++;
    }
    if (ts.isTemplateExpression(n)) {
      for (const span of n.templateSpans) {
        if (isQuorum(span.expression) && span.literal.text.startsWith(" or more distinct")) promptOrMoreOk = true;
      }
      if (n.head.text.includes("clustering agent")) {
        promptSeen++;
        promptQuorumSpans += n.templateSpans.filter((s) => isQuorum(s.expression)).length;
        n.templateSpans.forEach((span, i) => {
          const before = i === 0 ? n.head.text : n.templateSpans[i - 1].literal.text;
          if (isQuorum(span.expression) && before.endsWith(">=")) promptSenseOk = true;
        });
        if (pieces(n).some((p) => />=\s*\d/.test(p))) promptHasNumericThreshold = true;
      }
      if (n.head.text.startsWith("Threshold-Hit:")) {
        trailerSeen++;
        const last = n.templateSpans[n.templateSpans.length - 1];
        if (last && isQuorum(last.expression)) trailerQuorumSpans++;
        if (pieces(n).some((p) => /\/\s*\d/.test(p))) trailerHasNumericDenominator = true;
      }
    }
    // Either operand order: `sources.length < Q` and `Q > sources.length` are the same gate.
    if (
      ts.isBinaryExpression(n) &&
      ((n.operatorToken.kind === ts.SyntaxKind.LessThanToken &&
        n.left.getText(sf) === "sources.length" &&
        isQuorum(n.right)) ||
        (n.operatorToken.kind === ts.SyntaxKind.GreaterThanToken &&
          n.right.getText(sf) === "sources.length" &&
          isQuorum(n.left)))
    ) {
      comparisons++;
      // The gate must be (1) an `if` whose condition IS the comparison (no `&&`/`||` that could
      // skip it for a subset of clusters), (2) a TOP-LEVEL statement of `draftAdditiveEdit`
      // (not nested under another condition, not in a helper or a never-called closure),
      // (3) returning the refusal as a direct statement of its body, with `ok: false`, the
      // reason literal and `sourceCount`, and (4) preceded in that function only by pure
      // statements: every call before it must be on an allowlist of in-memory helpers, so a
      // new read or model call placed above it (under any spelling) turns this RED. At least
      // two `readEditTarget(`/`post(` calls must follow it, so renaming the I/O cannot make
      // the "before" scan vacuous.
      const unparen = (e: ts.Expression): ts.Expression => (ts.isParenthesizedExpression(e) ? unparen(e.expression) : e);
      let gate: ts.Node | undefined = n;
      while (gate && !ts.isIfStatement(gate)) gate = gate.parent;
      let fn: ts.Node | undefined = n;
      while (fn && !ts.isFunctionDeclaration(fn) && !ts.isFunctionExpression(fn) && !ts.isArrowFunction(fn)) fn = fn.parent;
      if (gate && ts.isIfStatement(gate) && fn && ts.isFunctionDeclaration(fn) && fn.body) {
        const conditionIsComparison = unparen(gate.expression) === n;
        const inDrafter = fn.name?.text === "draftAdditiveEdit" && gate.parent === fn.body;
        gateIsPlain = conditionIsComparison && inDrafter;
        const then = gate.thenStatement;
        const thenStmts = ts.isBlock(then) ? [...then.statements] : [then];
        gateReturnsRefusal = thenStmts.some((st) => {
          if (!ts.isReturnStatement(st) || !st.expression || !ts.isObjectLiteralExpression(st.expression)) return false;
          const props = new Map<string, string>();
          for (const p of st.expression.properties) {
            if (ts.isPropertyAssignment(p) && ts.isIdentifier(p.name)) props.set(p.name.text, p.initializer.getText(sf));
          }
          return (
            props.get("ok") === "false" && /^["']quorum-not-met["']$/.test(props.get("reason") ?? "") && props.has("sourceCount")
          );
        });
        const PURE_CALLS = new Set(["corpusSummaries.get", "sources.some", "sources.push"]);
        const gateIdx = fn.body.statements.indexOf(gate);
        let pure = gateIdx >= 0;
        let ioAfter = 0;
        const scanCalls = (m: ts.Node, before: boolean): void => {
          if (ts.isCallExpression(m)) {
            const callee = m.expression.getText(sf);
            if (before && !PURE_CALLS.has(callee)) pure = false;
            if (!before && (callee === "readEditTarget" || callee === "post")) ioAfter++;
          }
          m.forEachChild((c) => scanCalls(c, before));
        };
        fn.body.statements.forEach((st, i) => {
          if (i < gateIdx) scanCalls(st, true);
          else if (i > gateIdx) scanCalls(st, false);
        });
        gateBeforeIo = pure && ioAfter >= 2;
      }
    }
    if (
      ts.isPropertyAssignment(n) &&
      ts.isIdentifier(n.name) &&
      n.name.text === "reason" &&
      (ts.isStringLiteral(n.initializer) || ts.isNoSubstitutionTemplateLiteral(n.initializer)) &&
      n.initializer.text === "quorum-not-met"
    ) {
      emits++;
    }
    n.forEachChild(visit);
  };
  visit(sf);
  if (decls.length !== 1) throw new Error(`expected exactly 1 PROMOTION_QUORUM declaration, found ${decls.length}`);
  if (Number.isNaN(decls[0])) throw new Error("PROMOTION_QUORUM must be initialised with a numeric literal");
  if (shadows > 0) throw new Error(`PROMOTION_QUORUM is shadowed by ${shadows} parameter/binding name(s)`);
  if (promptSeen !== 1) throw new Error(`expected exactly 1 phase-1 prompt template, found ${promptSeen}`);
  if (trailerSeen !== 1) throw new Error(`expected exactly 1 Threshold-Hit template, found ${trailerSeen}`);
  return {
    declaredValue: decls[0],
    promptQuorumSpans,
    promptHasNumericThreshold,
    trailerQuorumSpans,
    trailerHasNumericDenominator,
    comparisons,
    gateIsPlain,
    gateReturnsRefusal,
    gateBeforeIo,
    promptSenseOk,
    promptOrMoreOk,
    emits,
  };
}

describe("Guard 1d -- PROMOTION_QUORUM is the single source of the quorum", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const read = () => readFileSync(SRC_PATH, "utf-8");

  it("one numeric declaration; the prompt, the trailer and the drafter's comparison each read it; exactly one emit site", () => {
    const c = censusQuorum(read());
    expect(c.declaredValue).toBeGreaterThan(0);
    expect(c.promptQuorumSpans).toBe(1);
    expect(c.promptHasNumericThreshold).toBe(false);
    expect(c.trailerQuorumSpans).toBe(1);
    expect(c.trailerHasNumericDenominator).toBe(false);
    expect(c.comparisons).toBe(1);
    expect(c.emits).toBe(1);
    // The wire, not only the endpoints: the comparison IS the `if` condition of a top-level
    // statement of draftAdditiveEdit, that `if` directly returns the refusal, only pure
    // in-memory calls precede it, and the prompt says `>=` Q and "Q or more distinct".
    expect(c.gateIsPlain).toBe(true);
    expect(c.gateReturnsRefusal).toBe(true);
    expect(c.gateBeforeIo).toBe(true);
    expect(c.promptSenseOk).toBe(true);
    expect(c.promptOrMoreOk).toBe(true);
  });

  it("quorum-not-met is NOT an edit-* member: EDIT_REFUSAL_REASONS stays at seven", () => {
    const { declared } = censusEditReasons(read());
    expect(declared).toHaveLength(7);
    expect(declared).not.toContain("quorum-not-met");
  });

  // Each mutation is an in-file row (a PR-body table does not run in CI), one `it` per member
  // so a failure names the member. The anchor must LAND or the row is vacuous.
  const mutate = (anchor: string, replacement: string): string => {
    const src = read();
    expect(src, `anchor must land: ${anchor}`).toContain(anchor);
    const out = src.replace(anchor, replacement);
    expect(out).not.toBe(src);
    return out;
  };

  it("mutation: the phase-1 prompt back to a literal threshold is RED", () => {
    const c = censusQuorum(mutate("(each with >=${PROMOTION_QUORUM} source learnings", "(each with >=5 source learnings"));
    expect(c.promptQuorumSpans === 1 && !c.promptHasNumericThreshold).toBe(false);
  });

  it("mutation: the trailer denominator back to a literal /5 is RED", () => {
    const c = censusQuorum(mutate("/${PROMOTION_QUORUM}`,", "/5`,"));
    expect(c.trailerQuorumSpans === 1 && !c.trailerHasNumericDenominator).toBe(false);
  });

  it("mutation: deleting the drafter's comparison is RED", () => {
    const c = censusQuorum(mutate("sources.length < PROMOTION_QUORUM", "sources.length < 0"));
    expect(c.comparisons).toBe(0);
  });

  it("mutation: the gate moved below readEditTarget is RED", () => {
    const c = censusQuorum(
      mutate(
        "  if (sources.length < PROMOTION_QUORUM) {",
        // Parsed, never executed: the arguments are irrelevant (and must not spell the repo-root
        // helper name, which repo-wide-containment reads as an escape from the app).
        "  const _t0 = await readEditTarget(cluster.target_path, cluster.target_path);\n  if (sources.length < PROMOTION_QUORUM) {",
      ),
    );
    expect(c.comparisons).toBe(1);
    expect(c.gateBeforeIo).toBe(false);
  });

  it("mutation: a gate that skips a subset of clusters (extra && operand) is RED", () => {
    const c = censusQuorum(
      mutate("sources.length < PROMOTION_QUORUM", "sources.length < PROMOTION_QUORUM && cluster.rationale.length > 0"),
    );
    expect(c.comparisons).toBe(1);
    expect(c.gateIsPlain).toBe(false);
  });

  it("mutation: the gate nested under another condition is RED", () => {
    const c = censusQuorum(
      mutate(
        "  if (sources.length < PROMOTION_QUORUM) {",
        "  if (cluster.rationale.length > 0) if (sources.length < PROMOTION_QUORUM) {",
      ),
    );
    expect(c.gateIsPlain).toBe(false);
  });

  it("mutation: an I/O call placed above the gate under another spelling is RED", () => {
    for (const spelling of ["await args.post({})", "await readFile(cluster.target_path)", "await (0, readEditTarget)(cluster.target_path, '')"]) {
      const c = censusQuorum(
        mutate("  if (sources.length < PROMOTION_QUORUM) {", `  ${spelling};\n  if (sources.length < PROMOTION_QUORUM) {`),
      );
      expect(c.gateBeforeIo, spelling).toBe(false);
    }
  });

  it("mutation: the I/O helpers renamed (so 'before' would be vacuous) is RED", () => {
    const c = censusQuorum(read().replaceAll("readEditTarget(", "readTarget(").replaceAll("await post({", "await send({"));
    expect(c.gateBeforeIo).toBe(false);
  });

  it("mutation: the gate's body emptied (no refusal returned) is RED", () => {
    const c = censusQuorum(
      mutate(
        'return { ok: false, reason: "quorum-not-met", cause: "below-quorum", sourceCount: sources.length };',
        "void 0;",
      ),
    );
    expect(c.gateReturnsRefusal).toBe(false);
  });

  it("mutation: a refusal-shaped string returned from an unrelated place is not the gate's refusal", () => {
    const c = censusQuorum(
      mutate(
        'return { ok: false, reason: "quorum-not-met", cause: "below-quorum", sourceCount: sources.length };',
        'return { ok: true, diff: "quorum-not-met" };',
      ),
    );
    expect(c.gateReturnsRefusal).toBe(false);
  });

  it("mutation: the second prompt line's sense changed ('or more' becomes 'or fewer') is RED", () => {
    const c = censusQuorum(mutate("${PROMOTION_QUORUM} or more distinct ones", "${PROMOTION_QUORUM} or fewer distinct ones"));
    expect(c.promptOrMoreOk).toBe(false);
  });

  it("dispatch: a parameter that shadows the constant THROWS", () => {
    expect(() => censusQuorum(read() + "\nexport function _s(PROMOTION_QUORUM: number) { return PROMOTION_QUORUM; }\n")).toThrow(/shadowed/);
  });

  it("mutation: the prompt's sense flipped (>= becomes >) is RED", () => {
    const c = censusQuorum(mutate("(each with >=${PROMOTION_QUORUM} source learnings", "(each with >${PROMOTION_QUORUM} source learnings"));
    expect(c.promptSenseOk).toBe(false);
  });

  it("refactor-tolerance: the operand-swapped spelling of the same gate stays GREEN", () => {
    const c = censusQuorum(mutate("sources.length < PROMOTION_QUORUM", "PROMOTION_QUORUM > sources.length"));
    expect(c.comparisons).toBe(1);
    expect(c.gateIsPlain).toBe(true);
    expect(c.gateReturnsRefusal).toBe(true);
    expect(c.gateBeforeIo).toBe(true);
  });

  it("mutation: a second emit site for the reason is RED", () => {
    const c = censusQuorum(read() + '\nexport const _second = { reason: "quorum-not-met" };\n');
    expect(c.emits).toBe(2);
  });

  it("mutation: the emit site removed is RED", () => {
    // Anchor on the return, not the bare literal: the QuorumRefusal TYPE also spells it.
    const c = censusQuorum(mutate('return { ok: false, reason: "quorum-not-met"', 'return { ok: false, reason: "edit-invalid"'));
    expect(c.emits).toBe(0);
  });

  it("dispatch: zero or two declarations THROW, never read clean", () => {
    // Anchors are derived from the source (any numeric value), never a literal 5: the census
    // must keep working if the constant legitimately changes (the value pin owns the value).
    const decl = /export const PROMOTION_QUORUM = \d+;/;
    expect(read()).toMatch(decl);
    expect(() => censusQuorum(read().replace(decl, ""))).toThrow(/found 0/);
    expect(() => censusQuorum(read() + "\nconst PROMOTION_QUORUM = 4;\n")).toThrow(/found 2/);
    expect(() => censusQuorum(read().replace(decl, "export const PROMOTION_QUORUM = Number('5');"))).toThrow(/numeric literal/);
  });
});

// ---------------------------------------------------------------------------
// #10550 -- the gated create arm's censuses.
//
//   Guard 1e  CREATE_REFUSAL_CLASSES is declared once and every member is EMITTED by a refusal site in the create
//             modules (and every emitted class is declared): a dead class or an undeclared one is RED.
//   Guard 3d  The create steps' callbacks accumulate nothing (they return a verdict); every outcome is recorded in
//             the handler body from the MEMOIZED return, so a replay still reports it.
//   Guard 1f  `create-refused` has exactly one emit site in the handler, every create refusal in the arm goes through
//             a mirroring helper (no bare returned refusal), and the marker spreads the create fields only where the
//             arm could have run.
// ---------------------------------------------------------------------------
const SERVER_DIR = join(__dirname, "..", "..", "..", "server");
const CREATE_MODULE = join(SERVER_DIR, "compound-promote-create.ts");
const CREATE_ARM = join(SERVER_DIR, "compound-promote-create-arm.ts");
const CREATE_GATES = join(SERVER_DIR, "compound-promote-create-gates.ts");

/**
 * window-assembly: censusCreateClasses -- complete against the three create modules, each parsed whole: every
 * CallExpression whose callee is one of the refusal constructors and whose first argument is a string literal, plus
 * every `class: "<literal>"` property of a returned object. The declared side is the array literal assigned to
 * `CREATE_REFUSAL_CLASSES`. Throws when either side is empty so a census that found nothing can never read clean.
 */
export function censusCreateClasses(sources: string[]): { declared: string[]; emitted: string[] } {
  const declared: string[] = [];
  const emitted: string[] = [];
  const CTORS = new Set(["refuse", "refusal", "refuseAndMirror"]);
  for (const src of sources) {
    const sf = ts.createSourceFile("t.ts", src, ts.ScriptTarget.Latest, true);
    const visit = (n: ts.Node): void => {
      if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name) && n.name.text === "CREATE_REFUSAL_CLASSES" && n.initializer) {
        let init: ts.Node = n.initializer;
        if (ts.isAsExpression(init)) init = init.expression;
        if (ts.isArrayLiteralExpression(init)) {
          for (const el of init.elements) if (ts.isStringLiteral(el)) declared.push(el.text);
        }
      }
      if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && CTORS.has(n.expression.text)) {
        const a0 = n.arguments[0];
        if (a0 && (ts.isStringLiteral(a0) || ts.isNoSubstitutionTemplateLiteral(a0))) emitted.push(a0.text);
      }
      if (ts.isPropertyAssignment(n) && ts.isIdentifier(n.name) && n.name.text === "class" && ts.isStringLiteral(n.initializer)) {
        emitted.push(n.initializer.text);
      }
      n.forEachChild(visit);
    };
    visit(sf);
  }
  if (declared.length === 0) throw new Error("census found no declared create refusal classes");
  if (emitted.length === 0) throw new Error("census found no emitted create refusal classes");
  return { declared, emitted };
}

describe("Guard 1e (#10550) -- every create refusal class is declared once and emitted by a site", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const read = () => [CREATE_MODULE, CREATE_ARM, CREATE_GATES].map((f) => readFileSync(f, "utf-8"));

  it("the declared set equals the emitted set, in both directions (the gates' `class:` literals included)", () => {
    const { declared, emitted } = censusCreateClasses(read());
    expect(declared).toHaveLength(13);
    expect(new Set(declared).size).toBe(13);
    expect(sortedUnique(emitted)).toEqual(sortedUnique(declared));
  });

  it("mutation: a declared-but-unemitted class is RED", () => {
    const [create, arm, gates] = read();
    const mutated = create.replace('"stub-drift",\n  "persist",', '"stub-drift",\n  "persist",\n  "ghost-class",');
    expect(mutated).not.toBe(create); // the mutation must LAND, or the row is vacuous
    const { declared, emitted } = censusCreateClasses([mutated, arm, gates]);
    expect(sortedUnique(emitted)).not.toEqual(sortedUnique(declared));
  });

  it("mutation: an emitted-but-undeclared class is RED", () => {
    const [create, arm, gates] = read();
    const mutated = arm.replace('refuseAndMirror("week-cap", "no-slot"', 'refuseAndMirror("ghost-class", "no-slot"');
    expect(mutated).not.toBe(arm);
    const { declared, emitted } = censusCreateClasses([create, mutated, gates]);
    expect(sortedUnique(emitted)).not.toEqual(sortedUnique(declared));
  });

  it("mutation: retargeting the ONLY week-cap site leaves week-cap declared-but-unemitted (RED)", () => {
    const [create, arm, gates] = read();
    const mutated = arm.replace('refuseAndMirror("week-cap", "no-slot"', 'refuseAndMirror("budget", "no-slot"');
    expect(mutated).not.toBe(arm);
    const { declared, emitted } = censusCreateClasses([create, mutated, gates]);
    expect(sortedUnique(declared).filter((c) => !emitted.includes(c))).toEqual(["week-cap"]);
  });

  it("dispatch: a census finding nothing THROWS, never reads clean", () => {
    expect(() => censusCreateClasses(["export const x = 1;\n"])).toThrow(/found no declared/);
    expect(() => censusCreateClasses(['export const CREATE_REFUSAL_CLASSES = ["a"] as const;\n'])).toThrow(/found no emitted/);
  });

  it("refactor-tolerance: the same refusal through the other constructor spelling stays GREEN", () => {
    const { emitted } = censusCreateClasses([
      'export const CREATE_REFUSAL_CLASSES = ["a", "b"] as const;\nconst r = refuse("a", "d");\nconst q = refusal("b", "d");\n',
    ]);
    expect(sortedUnique(emitted)).toEqual(["a", "b"]);
  });
});

/** The text of every `step.run("<name>", ...)` callback body in the handler (until the matching close of the call). */
function stepBodies(src: string, name: string): string[] {
  const handler = src.slice(src.indexOf("export async function cronCompoundPromoteHandler"));
  const out: string[] = [];
  let from = 0;
  const needle = `step.run("${name}"`;
  for (;;) {
    const i = handler.indexOf(needle, from);
    if (i === -1) break;
    let depth = 0;
    let j = handler.indexOf("(", i);
    const start = j;
    for (; j < handler.length; j++) {
      if (handler[j] === "(") depth++;
      else if (handler[j] === ")") {
        depth--;
        if (depth === 0) break;
      }
    }
    out.push(
      handler
        .slice(start, j + 1)
        .split("\n")
        .map((l) => l.replace(/^\s*\/\/.*$/, ""))
        .join("\n"),
    );
    from = j;
  }
  return out;
}

describe("Guard 3d (#10550) -- the create steps accumulate nothing; outcomes are recorded from the memoized return", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const MUTATED = ["refusals.push(", "refusalDetail.push(", "clustersOpened++", "ledgerSuppressed++", "createOutcome =", "createRefusal =", "createPr =", "createNoAction =", "createArmRan ="];

  it.each(["create-propose", "create-persist"])("%s: exactly one step, and no handler-scope accumulator is mutated inside its callback", (name) => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const bodies = stepBodies(src, name);
    expect(bodies).toHaveLength(1);
    expect(bodies[0].length).toBeGreaterThan(40); // non-vacuity: the window is the callback, not an empty span
    expect(MUTATED.filter((m) => bodies[0].includes(m))).toEqual([]);
  });

  it("non-vacuity: the accumulation DOES happen, in the handler body outside both callbacks", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const inside = [...stepBodies(src, "create-propose"), ...stepBodies(src, "create-persist")].join("\n");
    for (const m of ["createOutcome =", "createRefusal =", "createPr =", "createNoAction =", "createArmRan =", "refusals.push("]) {
      expect(src).toContain(m);
      expect(inside).not.toContain(m);
    }
  });

  it("mutation: a createOutcome assignment moved INTO the create-propose callback is caught", () => {
    const src = readFileSync(SRC_PATH, "utf-8");
    const mutated = src.replace('return runCreateProposeStep({', 'createOutcome = "refused";\n        return runCreateProposeStep({');
    expect(mutated).not.toBe(src);
    expect(stepBodies(mutated, "create-propose")[0]).toContain("createOutcome =");
  });

  it("dispatch: a handler with no / two create-propose steps is detected by the count, never read clean", () => {
    expect(stepBodies("export async function cronCompoundPromoteHandler() {}", "create-propose")).toHaveLength(0);
    const twice = 'export async function cronCompoundPromoteHandler() { await step.run("create-propose", () => 1); await step.run("create-propose", () => 2); }';
    expect(stepBodies(twice, "create-propose")).toHaveLength(2);
  });
});

describe("Guard 1f (#10550) -- one emit site for `create-refused`, every create refusal is mirrored, the marker spreads where the arm ran", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const code = (f: string) => readFileSync(f, "utf-8").split("\n").map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/^\s*\*.*$/, "")).join("\n");

  it("the handler has exactly ONE `create-refused` literal (the refusals[] push); the arm owns the Sentry op constant once", () => {
    const handler = code(SRC_PATH);
    expect(handler.split('"create-refused"').length - 1).toBe(1);
    expect(handler).toMatch(/refusals\.push\("create-refused"\)/);
    const arm = code(CREATE_ARM);
    expect(arm.split('CREATE_REFUSED_OP = "create-refused"').length - 1).toBe(1);
    expect(arm.split('"create-refused"').length - 1).toBe(1);
  });

  it("no bare `return refusal(` / `return refuse(` in the arm: every returned refusal passes a mirroring helper", () => {
    const arm = code(CREATE_ARM);
    expect(arm).not.toMatch(/return refusal\(/);
    expect(arm).not.toMatch(/return refuse\(/);
    // non-vacuity: the helpers are used many times
    expect((arm.match(/refuseAndMirror\(|mirrorAndReturn\(/g) ?? []).length).toBeGreaterThanOrEqual(20);
  });

  it("every returned refusal in the arm's step bodies is one of the helper spellings (no `return {` with kind refused)", () => {
    const arm = code(CREATE_ARM);
    expect(arm).not.toMatch(/return \{ kind: "refused"/);
  });

  it("the three markers that can follow the arm spread createMarker(); the early terminal rows do not", () => {
    const handler = code(SRC_PATH);
    expect(handler.split("...createMarker()").length - 1).toBe(3);
    for (const status of ['status: "disabled"', 'status: "deduped"', 'status: "week-cap-reached"', 'status: "empty-corpus"']) {
      const i = handler.indexOf(`emitOutcomeMarker({ trigger, run_id: runId, ${status}`);
      expect(i, status).toBeGreaterThan(-1);
      expect(handler.slice(i, handler.indexOf(");", i))).not.toContain("createMarker");
    }
  });

  it("createMarker() returns nothing unless the arm ran (the scheduled path gains no field)", () => {
    const handler = code(SRC_PATH);
    const i = handler.indexOf("const createMarker = ");
    expect(i).toBeGreaterThan(-1);
    expect(handler.slice(i, i + 140)).toMatch(/if \(!createArmRan\) return \{\};/);
  });

  it("the arm sets createArmRan only inside runCreateArm, which is called under `allowCreate` at both sites", () => {
    const handler = code(SRC_PATH);
    expect(handler.split("createArmRan = true").length - 1).toBe(1);
    const calls = [...handler.matchAll(/await runCreateArm\(\)/g)];
    expect(calls).toHaveLength(2);
    for (const m of calls) {
      expect(handler.slice(Math.max(0, (m.index ?? 0) - 60), m.index)).toMatch(/allowCreate/);
    }
  });
});
