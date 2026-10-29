// #11086: the stored subscription-token shape predicates. The strict allowlist guards the write boundary; the negative
// predicate guards the lease boundary and claims only what the bundled CLI was MEASURED to drop (see the contract test).
import { describe, expect, it } from "vitest";

import { classifyCliDroppedValue, isAcceptableSubscriptionToken } from "@/server/oauth-token-shape";

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";

/** Deterministic pseudo-random strings (an LCG) so the property is reproducible without a seed library. */
function* generated(count: number): Generator<string> {
  let state = 11086;
  const next = (): number => {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state;
  };
  for (let i = 0; i < count; i += 1) {
    const len = 1 + (next() % 120);
    let tail = "";
    for (let j = 0; j < len; j += 1) tail += ALPHABET[next() % ALPHABET.length];
    yield `sk-ant-oat${String(next() % 100).padStart(2, "0")}-${tail}`;
  }
}

describe("isAcceptableSubscriptionToken (write boundary)", () => {
  it("accepts the shape claude setup-token prints", () => {
    expect(isAcceptableSubscriptionToken("sk-ant-oat01-AbC_def-123")).toBe(true);
    expect(isAcceptableSubscriptionToken("  sk-ant-oat02-AbC_def-123  ")).toBe(true); // padded: trimmed first
  });

  it.each([
    ["an API key", "sk-ant-api03-AbC_def-123"],
    ["an admin key", "sk-ant-admin01-AbC_def-123"],
    ["a dash-less oat prefix", "sk-ant-oatAAAA"],
    ["an empty tail", "sk-ant-oat01-"],
    ["an embedded space", "sk-ant-oat01-AAAA BBBB"],
    ["an embedded tab", "sk-ant-oat01-AAAA\tBBBB"],
    ["an embedded newline", "sk-ant-oat01-AAAA\nBBBB"],
    ["a dotted tail", "sk-ant-oat01-A.B"],
    ["blank", "   "],
    ["empty", ""],
    ["a session token", "sk-ant-sid01-AAAA"],
    ["garbage", "garbage"],
  ])("rejects %s", (_label, value) => {
    expect(isAcceptableSubscriptionToken(value)).toBe(false);
  });
});

describe("classifyCliDroppedValue (lease boundary, measured classes only)", () => {
  it.each([
    ["sk-ant-api03-AAAA", "api_key_shaped"],
    ["sk-ant-api02-AAAA", "api_key_shaped"],
    ["sk-ant-admin01-AAAA", "api_key_shaped"],
    ["  sk-ant-api03-AAAA  ", "api_key_shaped"],
    ["sk-ant-oat01-AAAA BBBB", "embedded_whitespace"],
    ["sk-ant-oat01-AAAA\tBBBB", "embedded_whitespace"],
    ["", "blank"],
    ["   ", "blank"],
    ["\t\n ", "blank"],
  ] as const)("classifies %j as %s", (value, expected) => {
    expect(classifyCliDroppedValue(value)).toBe(expected);
  });

  it.each([
    ["a padded, dotted oat value", " sk-ant-oat01-A.B "],
    ["a session token", "sk-ant-sid01-X"],
    ["a non-sk string with a space", "garbage with space"],
    ["an embedded newline (the CLI uses it and fails loudly)", "sk-ant-oat01-AAAA\nBBBB"],
    ["a long valid-shaped token", `sk-ant-oat02-${"aB3_-".repeat(18)}`],
    ["an unmeasured sk- prefix", "sk-proj-AAAA"],
    ["a dash-less oat prefix (caught by the write allowlist only)", "sk-ant-oatAAAA"],
  ])("does not classify %s", (_label, value) => {
    expect(classifyCliDroppedValue(value)).toBeNull();
  });

  it("never classifies anything the strict allowlist accepts (consistency property)", () => {
    let seen = 0;
    for (const value of generated(500)) {
      expect(isAcceptableSubscriptionToken(value)).toBe(true);
      expect(classifyCliDroppedValue(value)).toBeNull();
      seen += 1;
    }
    expect(seen).toBe(500); // the loop really ran
  });

  it("returns only members of the closed class list", () => {
    const classes = new Set(["api_key_shaped", "embedded_whitespace", "blank"]);
    for (const value of ["sk-ant-api03-A", "sk-ant-oat01-A B", " "]) {
      const out = classifyCliDroppedValue(value);
      expect(out !== null && classes.has(out)).toBe(true);
    }
  });
});
