/**
 * PR-H (#4077) — rg-based lint test asserting that every call site of
 * `isGranted(`, `isDenied(`, and `inngest.send(` passes a TYPED
 * `ActionClass` argument: a string literal, a `ts as const` value, or
 * a narrowed-union expression (`flag ? "a" : "b"`). Raw `string`/`any`
 * arguments — typically introduced by `as string` / `as any` casts or
 * by widening a const to a `string`-typed variable — are rejected.
 *
 * Why this exists in addition to `tsc --noEmit`:
 *
 *   1. `tsc` catches type mismatches once the signature is tight, but
 *      type *assertions* (`x as string`) silently bypass the check.
 *   2. The action-class registry is the brand-survival load-bearing
 *      contract per #3244 (single-user-incident threshold). A regression
 *      that widens an arg back to `string` would compile cleanly.
 *   3. This test enforces ADR-034 §1 "code-static, literal-or-narrowed
 *      at producer call sites". Narrowed-union exception per Arch F2
 *      (multi-class producers like Bluesky adapter).
 *
 * Pattern fixtures (pass/fail) sit at the bottom — they validate that
 * the regex actually discriminates. Per learning
 * `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md`,
 * source-reading regex tests must ship with both sides.
 */

import { describe, expect, test } from "vitest";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { sync as globSync } from "fast-glob";

const ROOTS = ["app", "server", "lib"];
// Match `isGranted(`, `isDenied(`, and `inngest.send(` invocations.
// The lint applies to source files only — test files use mocks where
// raw-string args are expected and harmless.
const CALL_PATTERNS = [
  /\bisGranted\s*\(/g,
  /\bisDenied\s*\(/g,
  /\binngest\s*\.\s*send\s*\(/g,
];

// Reject these substrings within 8 lines of any matched call. The list
// is intentionally narrow: only patterns that explicitly widen an
// `ActionClass`-typed value to `string`/`any`. Plain identifiers are
// allowed (they get TS-checked at the function signature).
const FORBIDDEN_NEAR_CALL = [
  /\bas\s+string\b/,
  /\bas\s+any\b/,
  /:\s*string\b.*action[_-]?class/i,
];

function listSourceFiles(): string[] {
  const cwd = process.cwd();
  const patterns = ROOTS.map((r) => `${r}/**/*.{ts,tsx}`);
  return globSync(patterns, {
    cwd,
    absolute: true,
    ignore: [
      "**/*.test.ts",
      "**/*.test.tsx",
      "**/*.test-d.ts",
      "**/node_modules/**",
      "**/.next/**",
    ],
  });
}

interface Violation {
  file: string;
  line: number;
  excerpt: string;
  reason: string;
}

function scanFile(file: string, content: string): Violation[] {
  const lines = content.split("\n");
  const violations: Violation[] = [];

  for (const pattern of CALL_PATTERNS) {
    const matches = [...content.matchAll(pattern)];
    for (const m of matches) {
      const before = content.slice(0, m.index ?? 0);
      const callLine = before.split("\n").length;
      // Look 4 lines BEFORE (adjacent variable declarations with
      // `as string` casts) and 8 lines AFTER (multi-line call arg
      // lists; the largest current call site is inngest.send with
      // ~12 fields). callLine is 1-indexed so subtract 1 for slice.
      const windowStart = Math.max(0, callLine - 1 - 4);
      const windowEnd = Math.min(lines.length, callLine + 8);
      const windowText = lines.slice(windowStart, windowEnd).join("\n");
      for (const forbid of FORBIDDEN_NEAR_CALL) {
        if (forbid.test(windowText)) {
          violations.push({
            file: path.relative(process.cwd(), file),
            line: callLine,
            excerpt: lines[callLine - 1]?.trim() ?? "",
            reason: `forbidden pattern ${forbid} near call`,
          });
        }
      }
    }
  }
  return violations;
}

describe("action-class typed-literal lint (PR-H #4077)", () => {
  test("source-tree call sites of isGranted/isDenied/inngest.send pass typed action_class", async () => {
    const files = listSourceFiles();
    expect(files.length).toBeGreaterThan(0);

    const allViolations: Violation[] = [];
    for (const file of files) {
      const content = await readFile(file, "utf8");
      allViolations.push(...scanFile(file, content));
    }

    if (allViolations.length > 0) {
      const summary = allViolations
        .map((v) => `  ${v.file}:${v.line} — ${v.reason}\n    > ${v.excerpt}`)
        .join("\n");
      throw new Error(
        `Found ${allViolations.length} action-class lint violations:\n${summary}\n\nSee ADR-034 §1 (code-static literals + narrowed-union carveout).`,
      );
    }
    expect(allViolations).toEqual([]);
  });

  test("is-granted.ts signature is tightened to ActionClass (negative-space gate)", async () => {
    const file = path.join(
      process.cwd(),
      "server/scope-grants/is-granted.ts",
    );
    const src = await readFile(file, "utf8");
    // Negative-space gates only (per learning
    // 2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md):
    // assert what MUST NOT exist post-tightening. tsc catches the
    // positive side once signatures are tight.
    expect(
      /\bisDenied\s*\(\s*actionClass\s*:\s*string\b/.test(src),
      "isDenied(actionClass: string) — must be ActionClass per PR-H Phase 1.4",
    ).toBe(false);
    expect(
      /\bisGranted\s*\([\s\S]*?actionClass\s*:\s*string\b/.test(src),
      "isGranted(... actionClass: string) — must be ActionClass per PR-H Phase 1.4",
    ).toBe(false);
    expect(
      /ACTION_CLASS_DENYLIST\s*:\s*ReadonlySet<string>/.test(src),
      "ACTION_CLASS_DENYLIST: ReadonlySet<string> — must be ReadonlySet<ActionClass>",
    ).toBe(false);
  });

  // Fixture pass/fail to validate the regex discriminates correctly.
  // Per learning 2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md.
  describe("regex fixture pass/fail", () => {
    test("rejects `as string` near call (FAIL fixture)", () => {
      const fixture = `
        const ac = someValue as string;
        const grant = await isGranted(client, founderId, ac);
      `;
      const violations = scanFile("fixture.ts", fixture);
      expect(violations.length).toBeGreaterThan(0);
    });

    test("rejects `as any` near call (FAIL fixture)", () => {
      const fixture = `
        await inngest.send({
          name: payload as any,
          data: {},
        });
      `;
      const violations = scanFile("fixture.ts", fixture);
      expect(violations.length).toBeGreaterThan(0);
    });

    test("accepts string literal (PASS fixture)", () => {
      const fixture = `
        const grant = await isGranted(client, founderId, "finance.payment_failed");
      `;
      const violations = scanFile("fixture.ts", fixture);
      expect(violations).toEqual([]);
    });

    test("accepts narrowed-union ternary (PASS fixture)", () => {
      // Arch F2 / ADR-034 §1 — multi-class producer pattern.
      const fixture = `
        const ac = source === "soleur_handle"
          ? "external.brand_critical.bluesky_reply_soleur_handle"
          : "external.low_stakes.bluesky_reply_personal";
        const grant = await isGranted(client, founderId, ac);
      `;
      const violations = scanFile("fixture.ts", fixture);
      expect(violations).toEqual([]);
    });
  });
});
