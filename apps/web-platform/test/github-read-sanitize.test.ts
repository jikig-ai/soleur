/**
 * #12469: the pure hardening of cc GitHub read results. Redaction is per FIELD (never over stringified JSON, which would corrupt
 * ids, timestamps and URLs), caps count characters, and the whole response is held to its size budget.
 */
import { describe, expect, it, vi } from "vitest";

// Wrap (not replace) the real redactor so a test can COUNT how often it runs.
const redactSpy = vi.hoisted(() => ({ fn: null as null | ((...a: unknown[]) => unknown) }));
vi.mock("@/lib/safety/redaction-allowlist", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/safety/redaction-allowlist")>();
  const wrapped = vi.fn((...a: Parameters<typeof actual.redactGithubSourcedText>) => actual.redactGithubSourcedText(...a));
  redactSpy.fn = wrapped as unknown as (...a: unknown[]) => unknown;
  return { ...actual, redactGithubSourcedText: wrapped };
});

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

  it("redaction runs ONCE per body field regardless of how many cap passes the budget needs (the secret sits at the START, so truncation cannot hide a missing pass)", () => {
    const spy = redactSpy.fn as unknown as ReturnType<typeof vi.fn>;
    spy.mockClear();
    const rows = Array.from({ length: 50 }, (_v, i) => ({ id: i, body: "a@b.example " + "z".repeat(20_000), html_url: "https://github.com/o/r/1" }));
    const out = hardenReadResult(rows, { redact: true });
    expect(JSON.stringify(out)).not.toContain("a@b.example");
    // 50 bodies, several halving passes: still exactly one redaction per body.
    expect(spy).toHaveBeenCalledTimes(50);
  });

  it("with redact:false the redactor is never called and the secret survives (the instrument can tell the arms apart)", () => {
    const spy = redactSpy.fn as unknown as ReturnType<typeof vi.fn>;
    spy.mockClear();
    const out = hardenReadResult([{ body: "a@b.example short" }], { redact: false });
    expect(spy).not.toHaveBeenCalled();
    expect(JSON.stringify(out)).toContain("a@b.example");
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

  it("last resort, LIST shape: trailing rows are dropped, the list keeps its own shape, has_more stays what GitHub said and `truncated` says rows were cut", () => {
    const out = hardenReadResult({ summary: "50 pull requests (state=open)", has_more: false, pull_requests: bigRows() }, { redact: false }) as {
      truncated?: boolean; note?: string; summary: string; has_more: boolean; pull_requests: unknown[];
    };
    expect(out.truncated).toBe(true);
    expect(out.pull_requests.length).toBeGreaterThanOrEqual(1);
    expect(out.pull_requests.length).toBeLessThan(50);
    expect(out.has_more).toBe(false); // GitHub said there is no further page; cutting rows must not claim there is
    expect(out.summary).toBe(`50 pull requests (state=open); ${out.pull_requests.length} of 50 shown (response size budget)`);
    expect(out.note).toMatch(new RegExp(`showing ${out.pull_requests.length} of 50 items. Call again with a smaller per_page`));
    expect(JSON.stringify(out).length).toBeLessThanOrEqual(RESPONSE_BUDGET_CHARS + 400);
  });

  it("a list that GitHub says has more keeps has_more true when rows are cut", () => {
    const out = hardenReadResult({ summary: "50 pull requests (state=open), more available", has_more: true, pull_requests: bigRows() }, { redact: false }) as {
      has_more: boolean; truncated: boolean;
    };
    expect(out.has_more).toBe(true);
    expect(out.truncated).toBe(true);
  });

  it("a single row that is still over budget is NOT reported as cut (nothing was dropped): truncated false, no note, summary untouched", () => {
    const huge = { id: 1, a: "a".repeat(512), b: "b".repeat(512), c: "c".repeat(512) };
    const wide = Object.fromEntries(Array.from({ length: 200 }, (_v, i) => [`k${i}`, "v".repeat(500)]));
    const out = hardenReadResult({ summary: "1 pull request (state=open)", has_more: false, pull_requests: [{ ...huge, ...wide }] }, { redact: false }) as {
      truncated: boolean; note?: string; summary: string; pull_requests: unknown[];
    };
    expect(out.pull_requests).toHaveLength(1);
    expect(out.truncated).toBe(false);
    expect(out.note).toBeUndefined();
    expect(out.summary).toBe("1 pull request (state=open)");
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
