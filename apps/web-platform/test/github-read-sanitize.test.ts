/**
 * #12469: the pure hardening of cc GitHub read results. Redaction is per FIELD (never over stringified JSON, which would corrupt
 * ids, timestamps and URLs), caps count characters, and the whole response is held to its size budget.
 */
import { describe, expect, it } from "vitest";
import {
  BODY_FIELD_CAP,
  capChars,
  hardenReadResult,
  OTHER_FIELD_CAP,
  RESPONSE_BUDGET_CHARS,
  stripFormatChars,
  TRUNCATION_SUFFIX,
} from "@/server/github-read-sanitize";

describe("stripFormatChars", () => {
  it("removes tag characters, bidi controls, zero-width characters and the BOM, keeps visible text and newlines", () => {
    expect(stripFormatChars("a\u{E0041}‮b​c﻿d\ne")).toBe("abcd\ne");
  });
  it("leaves plain emoji and accented text alone", () => {
    expect(stripFormatChars("café 😀 日本")).toBe("café 😀 日本");
  });
});

describe("capChars", () => {
  it("cuts by code points and marks the cut; a short string is returned as is", () => {
    expect(capChars("abc", 5)).toBe("abc");
    expect(capChars("abcdef", 3)).toBe(`abc${TRUNCATION_SUFFIX}`);
    const out = capChars("😀".repeat(10), 4);
    expect(Array.from(out.replace(TRUNCATION_SUFFIX, ""))).toHaveLength(4);
  });
  it("a string of exactly max code points (more UTF-16 units) is NOT cut", () => {
    const s = "😀".repeat(4);
    expect(capChars(s, 4)).toBe(s);
  });
});

describe("hardenReadResult", () => {
  it("redacts title and body per field and leaves ids, timestamps and urls byte-identical", () => {
    const input = {
      number: 4_440_001_234,
      created_at: "2026-11-09T08:00:00Z",
      html_url: "https://github.com/o/r/pull/12",
      title: "mail me at a@b.example",
      body: "from host 192.0.2.7 see 123e4567-e89b-12d3-a456-426614174000",
      sha: "0123456789abcdef0123456789abcdef01234567",
    };
    const out = hardenReadResult(input, { redact: true }) as typeof input;
    expect(out.title).not.toContain("a@b.example");
    expect(out.body).not.toContain("192.0.2.7");
    expect(out.body).not.toContain("123e4567");
    expect(out.number).toBe(input.number);
    expect(out.created_at).toBe(input.created_at);
    expect(out.html_url).toBe(input.html_url);
    expect(out.sha).toBe(input.sha);
  });

  it("with redact false the text survives (format characters are still stripped and caps still apply)", () => {
    const out = hardenReadResult({ title: "a@b.example​" }, { redact: false }) as { title: string };
    expect(out.title).toBe("a@b.example");
  });

  it("caps body and other strings at their own LITERAL limits (4096 and 512; not echoed from the module's constants)", () => {
    const out = hardenReadResult({ body: "x".repeat(5000), head_ref: "y".repeat(600) }, { redact: false }) as Record<string, string>;
    expect(Array.from(out.body.replace(TRUNCATION_SUFFIX, ""))).toHaveLength(4096);
    expect(Array.from(out.head_ref.replace(TRUNCATION_SUFFIX, ""))).toHaveLength(512);
    expect(BODY_FIELD_CAP).toBe(4096);
    expect(OTHER_FIELD_CAP).toBe(512);
    expect(RESPONSE_BUDGET_CHARS).toBe(64_000);
  });

  it("redaction runs ONCE regardless of how many cap passes the budget needs", () => {
    const rows = Array.from({ length: 50 }, (_v, i) => ({ id: i, body: "z".repeat(20_000) + " a@b.example", html_url: "https://github.com/o/r/1" }));
    const out = hardenReadResult(rows, { redact: true });
    expect(JSON.stringify(out)).not.toContain("a@b.example");
  });

  it("keeps non-string leaves (numbers, booleans, null) and nested arrays untouched", () => {
    const input = { a: 1, b: true, c: null, d: [1, "two", { three: 3 }] };
    expect(hardenReadResult(input, { redact: true })).toEqual(input);
  });

  it("holds an oversize array of comments under the budget by shrinking bodies first", () => {
    const rows = Array.from({ length: 50 }, (_v, i) => ({ id: i, body: "z".repeat(20_000), html_url: "https://github.com/o/r/1" }));
    const out = hardenReadResult(rows, { redact: false });
    expect(JSON.stringify(out).length).toBeLessThanOrEqual(RESPONSE_BUDGET_CHARS);
    expect(Array.isArray(out)).toBe(true);
    expect((out as unknown[]).length).toBe(50); // all rows kept, bodies shrunk
  });

  const bigRows = () =>
    Array.from({ length: 50 }, (_v, i) => ({ id: i, title: "t".repeat(500), user: "u".repeat(500), head_ref: "h".repeat(500), html_url: "u".repeat(500), body: "b".repeat(500) }));

  it("last resort, LIST shape: trailing rows are dropped, the list keeps its own shape, summary and has_more are rewritten to match", () => {
    const out = hardenReadResult({ summary: "50 pull requests (state=open)", has_more: false, pull_requests: bigRows() }, { redact: false }) as {
      truncated?: boolean; note?: string; summary: string; has_more: boolean; pull_requests: unknown[];
    };
    expect(out.truncated).toBe(true);
    expect(out.pull_requests.length).toBeGreaterThanOrEqual(1);
    expect(out.pull_requests.length).toBeLessThan(50);
    expect(out.has_more).toBe(true);
    expect(out.summary).toBe(`${out.pull_requests.length} of 50 pull requests shown (response size budget)`);
    expect(out.note).toMatch(new RegExp(`showing ${out.pull_requests.length} of 50 items`));
    expect(JSON.stringify(out).length).toBeLessThanOrEqual(RESPONSE_BUDGET_CHARS + 400);
  });

  it("last resort, ARRAY shape: wrapped as { truncated, note, items } and within the budget", () => {
    const out = hardenReadResult(bigRows(), { redact: false }) as { truncated?: boolean; note?: string; items: unknown[] };
    expect(out.truncated).toBe(true);
    expect(Array.isArray(out.items)).toBe(true);
    expect(out.items.length).toBeLessThan(50);
    expect(JSON.stringify(out).length).toBeLessThanOrEqual(RESPONSE_BUDGET_CHARS + 400);
  });

  it("an undefined result stringifies to nothing and does not crash the size check", () => {
    expect(hardenReadResult(undefined, { redact: true })).toBeUndefined();
  });
});
