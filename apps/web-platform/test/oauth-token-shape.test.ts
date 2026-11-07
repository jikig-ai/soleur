// #11086: the stored subscription-token shape predicates. The strict allowlist guards the write boundary; the negative
// predicate guards the lease boundary and claims only what the bundled CLI was MEASURED to drop (see the contract test).
import { describe, expect, it } from "vitest";

import { classifyCliDroppedValue, isAcceptableSubscriptionToken } from "@/server/oauth-token-shape";

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";

/** Deterministic pseudo-random strings (mulberry32, so the whole 32-bit state is mixed) without a seed library. */
function* generated(count: number): Generator<string> {
  let state = 11086;
  const next = (): number => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  for (let i = 0; i < count; i += 1) {
    const len = 1 + Math.floor(next() * 120);
    let tail = "";
    for (let j = 0; j < len; j += 1) tail += ALPHABET[Math.floor(next() * ALPHABET.length)];
    yield `sk-ant-oat${String(Math.floor(next() * 100)).padStart(2, "0")}-${tail}`;
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
    ["a prefix-wrapped copy (no space)", "NAME=sk-ant-oat01-AAAA"],
    ["a one-digit version", "sk-ant-oat1-AAAA"],
    ["no version digits", "sk-ant-oat-AAAA"],
    ["an upper-cased token", "SK-ANT-OAT01-AAAA"],
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
    const chars = new Set<string>();
    for (const value of generated(500)) {
      for (const c of value.slice(value.indexOf("-", 10) + 1)) chars.add(c);
      expect(isAcceptableSubscriptionToken(value)).toBe(true);
      expect(classifyCliDroppedValue(value)).toBeNull();
      seen += 1;
    }
    expect(seen).toBe(500); // the loop really ran
    // The generator really spans the alphabet (a degenerate generator would make the property vacuous).
    expect(chars.size).toBeGreaterThanOrEqual(ALPHABET.length - 2);
  });

  it("returns only members of the closed class list", () => {
    const classes = new Set(["api_key_shaped", "embedded_whitespace", "blank"]);
    for (const value of ["sk-ant-api03-A", "sk-ant-oat01-A B", " "]) {
      const out = classifyCliDroppedValue(value);
      expect(out !== null && classes.has(out)).toBe(true);
    }
  });
});
