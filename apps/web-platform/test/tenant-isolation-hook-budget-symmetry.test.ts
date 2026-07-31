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

  it.each(suiteFiles)(
    "%s — afterAll budget is >= beforeAll budget in every scope",
    (file) => {
      const source = readFileSync(path.join(SERVER_TEST_DIR, file), "utf8");
      const pairs = pairHooks(parseHooks(source));

      const violations = pairs
        .map(({ before, after }) => {
          // Primary rule — needs no global value: an explicit setup override
          // obliges an explicit teardown override at least as large.
          const beforeBudget = before.budget ?? GLOBAL_HOOK_TIMEOUT!;
          const afterBudget = after?.budget ?? GLOBAL_HOOK_TIMEOUT!;
          if (afterBudget >= beforeBudget) return null;
          return (
            `beforeAll (line ${before.line}) has ${beforeBudget}ms but ` +
            `afterAll (${after ? `line ${after.line}` : "absent"}) has ` +
            `${after?.budget === undefined || after?.budget === null ? `the ${GLOBAL_HOOK_TIMEOUT}ms global` : `${afterBudget}ms`}`
          );
        })
        .filter((v): v is string => v !== null);

      expect(violations).toEqual([]);
    },
  );
});
