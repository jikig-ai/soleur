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

  it("caps body and other strings at their own limits", () => {
    const out = hardenReadResult({ body: "x".repeat(BODY_FIELD_CAP + 50), head_ref: "y".repeat(OTHER_FIELD_CAP + 50) }, { redact: false }) as Record<string, string>;
    expect(Array.from(out.body.replace(TRUNCATION_SUFFIX, ""))).toHaveLength(BODY_FIELD_CAP);
    expect(Array.from(out.head_ref.replace(TRUNCATION_SUFFIX, ""))).toHaveLength(OTHER_FIELD_CAP);
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

  it("as a last resort drops trailing rows with an explicit marker, and says how many were kept", () => {
    const rows = Array.from({ length: 50 }, (_v, i) => ({ id: i, title: "t".repeat(500), user: "u".repeat(500), head_ref: "h".repeat(500), html_url: "u".repeat(500), body: "b".repeat(500) }));
    const out = hardenReadResult({ summary: "s", has_more: false, pull_requests: rows }, { redact: false }) as { truncated?: boolean; note?: string; result?: { pull_requests: unknown[] } };
    expect(out.truncated).toBe(true);
    expect(out.note).toMatch(/showing \d+ of 50 items/);
    expect(JSON.stringify(out.result).length).toBeLessThanOrEqual(RESPONSE_BUDGET_CHARS);
    expect(out.result!.pull_requests.length).toBeGreaterThanOrEqual(1);
  });

  it("an undefined result stringifies to nothing and does not crash the size check", () => {
    expect(hardenReadResult(undefined, { redact: true })).toBeUndefined();
  });
});
