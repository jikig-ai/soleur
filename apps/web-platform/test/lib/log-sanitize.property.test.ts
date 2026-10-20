import { describe, expect, it } from "vitest";
import fc from "fast-check";
import { sanitizeForLog } from "@/lib/log-sanitize";

// Property-based suite (fast-check) — idempotency + output-contract classes
// over sanitizeForLog. Convention: on failure, shrink and pin the
// counterexample as a permanent it() labelled
// `// regression fixture: fast-check seed <seed> path <path>`.
// See apps/web-platform/test/README.md "Property-based tests".

// The class the function exists to strip: C0 controls, DEL, and the Unicode
// line/paragraph separators. Biased toward them so the interesting domain is
// dense rather than one codepoint per few-thousand chars of prose.
const FORBIDDEN = /[\x00-\x1f\x7f\u2028\u2029]/;
const payloadArb = fc.oneof(
  fc.string(),
  fc.string({
    unit: fc.constantFrom(
      "\x00",
      "\x1f",
      "\x7f",
      "\u2028",
      "\u2029",
      "a",
      "Z",
      "9",
      " ",
      "\n",
      "ok",
    ),
  }),
);
const capArb = fc.integer({ min: 0, max: 2000 });

describe("sanitizeForLog — idempotency (property)", () => {
  it("sanitize(sanitize(x, n), n) === sanitize(x, n)", () => {
    fc.assert(
      fc.property(payloadArb, capArb, (x, n) => {
        const once = sanitizeForLog(x, n);
        expect(sanitizeForLog(once, n)).toBe(once);
      }),
    );
  });
});

describe("sanitizeForLog — output contract (property)", () => {
  it("output never exceeds the cap and never contains a stripped character", () => {
    fc.assert(
      fc.property(payloadArb, capArb, (x, n) => {
        const out = sanitizeForLog(x, n);
        expect(out.length).toBeLessThanOrEqual(n);
        expect(FORBIDDEN.test(out)).toBe(false);
      }),
    );
  });
});

// Negative control (anti-vacuity, AC6): the harness must be able to fail.
describe("log-sanitize property suite — negative control", () => {
  it("a deliberately-false property throws", () => {
    expect(() =>
      fc.assert(fc.property(capArb, () => false)),
    ).toThrow();
  });
});
