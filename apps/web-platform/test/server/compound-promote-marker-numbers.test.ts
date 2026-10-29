// WikiSkill Phase 2 (#10550) -- every number a create refusal can carry is either forwarded to the marker through the
// reviewed allowlist (`CREATE_MARKER_NUMBERS`) or is deliberately Sentry-only (`CREATE_SENTRY_ONLY_NUMBERS`).
//
// The handler forwards ONLY the allowlisted keys, so a number added to a refusal without a decision about the marker is
// silently Sentry-only today. This census makes that decision explicit: it reads the three create modules, finds the
// keys of every `numbers` object a refusal is built with, and fails on a key that is in neither set. Window: the
// three create modules, each read whole, comments stripped.
import { beforeEach, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { CREATE_MARKER_NUMBERS, CREATE_SENTRY_ONLY_NUMBERS } from "@/server/compound-promote-marker";

const SERVER_DIR = join(__dirname, "..", "..", "server");
const MODULES = ["compound-promote-create.ts", "compound-promote-create-arm.ts", "compound-promote-create-gates.ts"].map((f) => join(SERVER_DIR, f));

const stripComments = (src: string): string =>
  src.split("\n").map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/^\s*\*.*$/, "").replace(/^\s*\/\*\*.*$/, "")).join("\n");

/** The text between a balanced pair that opens at `open` (exclusive of the pair), or null. */
function balanced(src: string, open: number, o: string, c: string): string | null {
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === o) depth += 1;
    else if (src[i] === c && --depth === 0) return src.slice(open + 1, i);
  }
  return null;
}

/** Remove every `extra: { ... }` object (Sentry free-form extras are not numbers and are not under this census). */
function dropExtras(text: string): string {
  let out = text;
  for (;;) {
    const m = /\bextra:\s*\{/.exec(out);
    if (!m) return out;
    const open = m.index + m[0].length - 1;
    const inner = balanced(out, open, "{", "}");
    if (inner === null) return out;
    out = out.slice(0, m.index) + out.slice(open + inner.length + 2);
  }
}

/** Property names of every object literal in `text` (keyed or shorthand), without descending into strings. */
function objectKeys(text: string): string[] {
  const keys: string[] = [];
  for (const m of text.matchAll(/[{,]\s*([a-z][a-z0-9]*(?:_[a-z0-9]+)*)\s*(?=[:,}])/g)) keys.push(m[1]);
  return keys;
}

export function numberKeysOf(src: string): string[] {
  const code = stripComments(src);
  const found = new Set<string>();
  // (1) the object passed to a refusal constructor: `refuse(cls, detail, { .. })`, `fail(cls, detail, { numbers: { .. } })`, `refusal(.., { .. })`
  for (const m of code.matchAll(/\b(refuse|refusal|fail|mirrored)\(/g)) {
    const open = m.index + m[0].length - 1;
    const call = balanced(code, open, "(", ")");
    if (call === null) continue;
    const withoutExtra = dropExtras(call);
    // `numbers:` may be a literal or a conditional (`x === undefined ? undefined : { pr }`): read every object after it
    const at = withoutExtra.search(/\bnumbers:/);
    if (at >= 0) {
      const rest = withoutExtra.slice(at + "numbers:".length);
      for (let i = rest.indexOf("{"); i >= 0; i = rest.indexOf("{", i + 1)) {
        const inner = balanced(rest, i, "{", "}");
        if (inner !== null) for (const k of objectKeys(`{${inner}}`)) found.add(k);
      }
    }
    // the third positional argument of refuse()/refusal() IS the numbers object (fail() takes an options object instead)
    const third = m[1] === "fail" || m[1] === "mirrored" ? null : /^\s*"[^"]*"\s*,\s*(?:`[^`]*`|"[^"]*")\s*,\s*\{/.exec(call);
    if (third) {
      const inner = balanced(call, third[0].length - 1, "{", "}");
      if (inner !== null) for (const k of objectKeys(`{${inner}}`)) found.add(k);
    }
  }
  // (2) the typed number builders: `const numbers: Record<string, number> = { ... }`
  for (const m of code.matchAll(/numbers:\s*Record<string,\s*number>\s*=\s*\{/g)) {
    const inner = balanced(code, m.index + m[0].length - 1, "{", "}");
    if (inner !== null) for (const k of objectKeys(`{${inner}}`)) found.add(k);
  }
  found.delete("numbers");
  return [...found].sort();
}

beforeEach(() => {
  expect.hasAssertions();
});

describe("refusal numbers: marker allowlist or an explicit Sentry-only set", () => {
  const forwarded = new Set<string>(Object.keys(CREATE_MARKER_NUMBERS));
  const sentryOnly = new Set<string>(CREATE_SENTRY_ONLY_NUMBERS);
  const census = [...new Set(MODULES.flatMap((f) => numberKeysOf(readFileSync(f, "utf-8"))))].sort();

  it("the census is not vacuous: it finds the keys every module is known to pass", () => {
    for (const k of ["words", "total", "cap", "min_words", "max_words", "tokens", "max", "bytes", "nearest_rank", "top1", "threshold", "path_index", "file_index", "exit_code", "missing_tools", "changed_count", "pr", "headroom"]) {
      expect(census, k).toContain(k);
    }
  });

  it("every number key a create refusal carries is forwarded to the marker OR explicitly Sentry-only", () => {
    expect(census.filter((k) => !forwarded.has(k) && !sentryOnly.has(k))).toEqual([]);
  });

  it("the two sets are disjoint, and every Sentry-only key is really passed (no stale entry)", () => {
    expect([...sentryOnly].filter((k) => forwarded.has(k))).toEqual([]);
    expect([...sentryOnly].filter((k) => !census.includes(k))).toEqual([]);
  });

  it("nearest_in_offered is Sentry-only: read from the source, absent from the marker shape (Ref #10550)", () => {
    expect([...sentryOnly]).toContain("nearest_in_offered");
    expect(Object.keys(CREATE_MARKER_NUMBERS)).not.toContain("nearest_in_offered");
    expect(census).toContain("nearest_in_offered");
  });

  it("every forwarded key is really passed (no stale allowlist entry)", () => {
    expect([...forwarded].filter((k) => !census.includes(k))).toEqual([]);
  });

  it("mutation: a number key outside both sets is found by the extractor and would fail the census", () => {
    const mutated = 'return refuse("budget", "x", { words, brand_new_number: 3 });';
    expect(numberKeysOf(mutated)).toEqual(["brand_new_number", "words"]);
    expect(numberKeysOf('fail("persist", "x", { numbers: { another_one: 1 }, extra: { cause: "c", not_a_number: 2 } })')).toEqual(["another_one"]);
  });
});
