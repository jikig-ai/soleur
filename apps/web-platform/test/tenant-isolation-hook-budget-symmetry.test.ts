import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import vitestConfig from "../vitest.config";

/**
 * #7101 — a teardown hook must not get a smaller budget than the setup hook
 * whose fixtures it tears down.
 *
 * `workspace-member-revocation.tenant-isolation.test.ts` gave its `beforeAll` an
 * explicit 60s override (fixture setup against dev-Supabase is slow) while its
 * `afterAll` silently inherited the 20s global — for strictly MORE work, since
 * teardown walks FK-RESTRICT-ordered deletes across both fixtures. Every
 * assertion passed and the suite still red-lined `main` on the teardown hook
 * alone, because `tenant-integration-required` is a required check.
 *
 * The rule enforced here is a deliberate PROXY, not a measurement: budget
 * symmetry is a LOWER BOUND on what teardown needs. It cannot know the real
 * cost of either hook. The known false-positive shape is a heavy setup with a
 * genuinely trivial teardown (e.g. setup builds fixtures remotely, teardown
 * only clears an in-memory map) — such a file must raise its `afterAll`
 * budget to match, or move the cheap teardown out of the symmetric pair. That
 * cost is deliberate: an over-generous teardown budget wastes seconds only when
 * a hook is already failing, whereas an under-provisioned one reds `main` on a
 * diff that never touched the code.
 *
 * NOT the fix: raising the global `hookTimeout` in `vitest.config.ts`. That
 * value is a deliberate 2x-default for pdfjs cold-start, and widening it
 * globally would mask genuinely-hung hooks across the whole suite.
 */

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER_TEST_DIR = path.join(HERE, "server");
const SUITE_GLOB_SUFFIX = ".tenant-isolation.test.ts";

type HookName = "beforeAll" | "afterAll";

interface ParsedHook {
  hook: HookName;
  /** Explicit per-hook timeout override, or null when the hook inherits the global. */
  budget: number | null;
  indent: string;
  line: number;
}

interface HookPair {
  before: ParsedHook;
  after: ParsedHook | null;
}

/**
 * Pair `beforeAll`/`afterAll` with their closing `}, <n>);` STRUCTURALLY, by
 * matching indentation — never by grepping the `}, 60_000);` literal, which is
 * also the closing form of a per-test timeout (`it("…", async () => {…}, 60_000)`)
 * and would mis-attribute those to the nearest hook.
 */
export function parseHooks(source: string): ParsedHook[] {
  const lines = source.split("\n");
  const hooks: ParsedHook[] = [];

  for (let i = 0; i < lines.length; i++) {
    const open = lines[i].match(/^(\s*)(beforeAll|afterAll)\(/);
    if (!open) continue;
    const [, indent, hook] = open;

    for (let j = i + 1; j < lines.length; j++) {
      const close = lines[j].match(/^(\s*)\}(?:,\s*([0-9][0-9_]*))?\s*\);/);
      if (!close || close[1] !== indent) continue;
      hooks.push({
        hook: hook as HookName,
        // Strip `_` before Number(): `Number("60_000")` is NaN and
        // `parseInt("60_000")` is 60 — both silently break the comparison.
        budget: close[2] ? Number(close[2].replace(/_/g, "")) : null,
        indent,
        line: j + 1,
      });
      break;
    }
  }

  return hooks;
}

/**
 * Group hooks into per-scope pairs. Scope is approximated by indentation: a
 * `beforeAll` pairs with the next `afterAll` at the SAME indentation that
 * occurs before the next `beforeAll` at that indentation. This handles a file
 * with several sibling `describe` blocks each carrying its own hook pair.
 */
export function pairHooks(hooks: ParsedHook[]): HookPair[] {
  const pairs: HookPair[] = [];

  for (let i = 0; i < hooks.length; i++) {
    const before = hooks[i];
    if (before.hook !== "beforeAll") continue;

    let after: ParsedHook | null = null;
    for (let j = i + 1; j < hooks.length; j++) {
      const candidate = hooks[j];
      if (candidate.indent !== before.indent) continue;
      if (candidate.hook === "beforeAll") break; // next scope started
      after = candidate;
      break;
    }
    pairs.push({ before, after });
  }

  return pairs;
}

/**
 * The rule itself, exported so fixtures can drive it directly.
 *
 * This MUST NOT live inline in the `it.each` arm. Its only input there is the
 * real corpus, which is symmetric-by-construction once the fix has landed — so
 * a clean corpus can prove "zero violations today" but can never prove the rule
 * still DISCRIMINATES. Measured: with the rule inline, changing the `afterAll`
 * fallback to `?? Infinity` kept the whole suite green while no longer
 * detecting the original #7101 regression at all. The corpus cannot contain the
 * shapes the rule exists to reject, so the rule needs synthetic ones.
 */
export function violationsFor(
  pairs: HookPair[],
  globalTimeout: number,
): string[] {
  return pairs
    .map(({ before, after }) => {
      // A scope with setup but NO teardown hook has no teardown budget to get
      // wrong — there is no `afterAll` that can time out. Flagging it would be
      // a false positive against a legitimate shape (heavy remote setup,
      // nothing to tear down), so it is out of scope for this guard.
      if (!after) return null;
      // Primary rule — needs no global value when both are explicit: an
      // explicit setup override obliges an explicit teardown override at least
      // as large. The global only fills in for an INHERITED budget.
      const beforeBudget = before.budget ?? globalTimeout;
      const afterBudget = after.budget ?? globalTimeout;
      if (afterBudget >= beforeBudget) return null;
      return (
        `beforeAll (line ${before.line}) has ${beforeBudget}ms but ` +
        `afterAll (line ${after.line}) has ` +
        `${after.budget === null ? `the ${globalTimeout}ms global` : `${afterBudget}ms`}`
      );
    })
    .filter((v): v is string => v !== null);
}

const GLOBAL_HOOK_TIMEOUT = vitestConfig.test?.hookTimeout;

const suiteFiles = readdirSync(SERVER_TEST_DIR)
  .filter((f) => f.endsWith(SUITE_GLOB_SUFFIX))
  .sort();

describe("tenant-isolation hook budget symmetry (#7101)", () => {
  it("reads the global hookTimeout from vitest.config.ts, not a hardcoded copy", () => {
    // Importing the config (rather than regex-parsing it) is load-bearing: the
    // file's own comment contains the literal text `20_000ms hookTimeout`, so a
    // loose regex matches the PROSE and silently pins the guard to a stale value.
    expect(typeof GLOBAL_HOOK_TIMEOUT).toBe("number");
    expect(GLOBAL_HOOK_TIMEOUT).toBeGreaterThan(0);
  });

  it("covers every tenant-isolation suite and finds hooks in each (anti-vacuity floor)", () => {
    // A parser that silently matches nothing would report zero violations and
    // read as "the codebase is clean". Assert coverage from the data itself —
    // never a hardcoded census constant, which would rot as suites are added.
    expect(suiteFiles.length).toBeGreaterThan(0);

    const filesWithoutPairs: string[] = [];
    let totalPairs = 0;

    for (const file of suiteFiles) {
      const source = readFileSync(path.join(SERVER_TEST_DIR, file), "utf8");
      const pairs = pairHooks(parseHooks(source));
      if (pairs.length === 0) filesWithoutPairs.push(file);
      totalPairs += pairs.length;
    }

    expect(filesWithoutPairs).toEqual([]);
    expect(totalPairs).toBeGreaterThanOrEqual(suiteFiles.length);
  });

  it("reports a violation on a synthetic asymmetric fixture (parser mutation case)", () => {
    // Proves the parser can still FAIL. Without this, a parser broken into
    // always-returning-nothing would keep the suite green forever.
    const fixture = [
      'describe("synthetic", () => {',
      "  beforeAll(async () => {",
      "    await setup();",
      "  }, 60_000);",
      "",
      "  afterAll(async () => {",
      "    await teardown();",
      "  }, 30_000);",
      "});",
      "",
    ].join("\n");

    const pairs = pairHooks(parseHooks(fixture));
    expect(pairs).toHaveLength(1);
    expect(pairs[0].before.budget).toBe(60_000);
    expect(pairs[0].after?.budget).toBe(30_000);
    expect(pairs[0].after!.budget!).toBeLessThan(pairs[0].before.budget!);
  });

  it("pairs hooks structurally, not by grepping the closing-brace literal", () => {
    // A per-test timeout shares the `}, 60_000);` closing form but sits at a
    // DEEPER indentation than the hook. A literal grep would attribute it to
    // the nearest hook; the indentation match must not.
    const fixture = [
      'describe("synthetic", () => {',
      "  beforeAll(async () => {",
      "    await setup();",
      "  }, 60_000);",
      "",
      '  it("slow case", async () => {',
      "    await work();",
      "  }, 45_000);",
      "",
      "  afterAll(async () => {",
      "    await teardown();",
      "  });",
      "});",
      "",
    ].join("\n");

    const pairs = pairHooks(parseHooks(fixture));
    expect(pairs).toHaveLength(1);
    expect(pairs[0].before.budget).toBe(60_000);
    // The `it(...)` closer must NOT have been consumed as the afterAll budget.
    expect(pairs[0].after?.budget).toBeNull();
  });

  // ---------------------------------------------------------------------
  // Drive the RULE directly. The clean corpus is symmetric-by-construction,
  // so it can only ever prove "zero violations today" — never that the rule
  // still discriminates. These fixtures cover the four shapes the corpus
  // cannot contain. Fixture bodies are MULTI-LINE on purpose: `parseHooks`
  // pairs a hook to a closer on its own line at matching indentation, so a
  // one-liner `beforeAll(async () => {}, 60_000);` has no closer and is
  // dropped entirely — a fixture written that way silently tests nothing.
  // ---------------------------------------------------------------------
  const scope = (beforeTail: string, afterTail: string | null): string =>
    [
      'describe("synthetic", () => {',
      "  beforeAll(async () => {",
      "    await setup();",
      `  }${beforeTail});`,
      ...(afterTail === null
        ? []
        : ["", "  afterAll(async () => {", "    await teardown();", `  }${afterTail});`]),
      "});",
      "",
    ].join("\n");

  const G = 20_000;

  it("FLAGS the original #7101 shape: explicit setup override, inherited teardown", () => {
    // The exact regression this guard exists for. A rule whose afterAll
    // fallback is widened (e.g. `?? Infinity`) stays green on the real corpus
    // while silently no longer detecting this — so it must be pinned here.
    const v = violationsFor(pairHooks(parseHooks(scope(", 60_000", ""))), G);
    expect(v).toHaveLength(1);
    expect(v[0]).toContain("60000ms");
    expect(v[0]).toContain("global");
  });

  it("FLAGS an explicit teardown budget smaller than an explicit setup budget", () => {
    const v = violationsFor(pairHooks(parseHooks(scope(", 60_000", ", 30_000"))), G);
    expect(v).toHaveLength(1);
    expect(v[0]).toContain("30000ms");
  });

  it("does NOT flag equal explicit budgets", () => {
    expect(violationsFor(pairHooks(parseHooks(scope(", 60_000", ", 60_000"))), G)).toEqual([]);
  });

  it("does NOT flag a teardown budget larger than setup", () => {
    expect(violationsFor(pairHooks(parseHooks(scope(", 60_000", ", 90_000"))), G)).toEqual([]);
  });

  it("does NOT flag an inherited setup with an explicit teardown override", () => {
    // beforeAll inherits the global; an explicit larger teardown is fine.
    expect(violationsFor(pairHooks(parseHooks(scope("", ", 30_000"))), G)).toEqual([]);
  });

  it("does NOT flag setup-with-no-teardown (no afterAll = no budget to get wrong)", () => {
    const pairs = pairHooks(parseHooks(scope(", 60_000", null)));
    expect(pairs).toHaveLength(1);
    expect(pairs[0].after).toBeNull();
    expect(violationsFor(pairs, G)).toEqual([]);
  });

  it("pairs each describe's hooks independently when a file has several scopes", () => {
    // Sibling describes at the same indentation must not marry A's beforeAll
    // to B's afterAll.
    const fixture = [
      scope(", 60_000", ", 60_000").trimEnd(),
      scope(", 30_000", ", 30_000").trimEnd(),
      "",
    ].join("\n");
    const pairs = pairHooks(parseHooks(fixture));
    expect(pairs).toHaveLength(2);
    expect(pairs[0].before.budget).toBe(60_000);
    expect(pairs[1].before.budget).toBe(30_000);
    expect(violationsFor(pairs, G)).toEqual([]);
  });

  it.each(suiteFiles)(
    "%s — afterAll budget is >= beforeAll budget in every scope",
    (file) => {
      const source = readFileSync(path.join(SERVER_TEST_DIR, file), "utf8");
      const hooks = parseHooks(source);

      // Parse completeness. `parseHooks` scans forward for a closer at matching
      // indentation with no stop at the hook's OWN closing line, so a closer it
      // cannot parse (e.g. `}, SLOW_SETUP_MS);` — a named constant rather than a
      // numeric literal) makes it latch onto the NEXT hook's closer instead.
      // Both hooks then resolve to the same line and the asymmetry between them
      // is silently unflagged. Neither anti-vacuity floor catches that: one
      // requires >=1 pair per file, the other is a sum. Assert every declared
      // hook was parsed, and that no two share a closer.
      const declared = (source.match(/^\s*(beforeAll|afterAll)\(/gm) ?? []).length;
      expect(hooks.length).toBe(declared);
      expect(new Set(hooks.map((h) => h.line)).size).toBe(hooks.length);

      expect(violationsFor(pairHooks(hooks), GLOBAL_HOOK_TIMEOUT!)).toEqual([]);
    },
  );
});
