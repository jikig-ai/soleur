/**
 * #12011 PR-C task B3: deriveLegalCardState maps (the card's text hash, the registry's current hash, the founder's rows,
 * `valid_until`, an injected `now`) to exactly one of six states. Pure: no clock, no I/O.
 */
import { describe, expect, it } from "vitest";
import { LEGAL_CARD_STATES } from "@/lib/legal-acceptance-wire";
import { deriveLegalCardState, legalValidUntilPassed, type LegalCardStateInput } from "@/lib/approval-card-state";

const H3 = "a".repeat(64);
const H4 = "b".repeat(64);
const NOW = new Date("2026-11-05T12:00:00Z");

const base: LegalCardStateInput = { cardHash: H4, currentHash: H4, validUntil: null, rows: [], now: NOW };
const d = (o: Partial<LegalCardStateInput>) => deriveLegalCardState({ ...base, ...o });

describe("deriveLegalCardState (wireframe 16)", () => {
  it("pending: no row for the current text and the entry is current", () => {
    expect(d({})).toBe("pending");
    expect(d({ validUntil: "2026-11-05" })).toBe("pending");
    expect(d({ rows: [{ textHash: H3, choice: "accept" }] })).toBe("pending");
  });

  it("a row for the current hash gives accepted, declined or changes_requested", () => {
    expect(d({ rows: [{ textHash: H4, choice: "accept" }] })).toBe("accepted");
    expect(d({ rows: [{ textHash: H4, choice: "decline" }] })).toBe("declined");
    expect(d({ rows: [{ textHash: H4, choice: "request_changes" }] })).toBe("changes_requested");
  });

  it("an answer outlives valid_until: the row wins over expiry", () => {
    expect(d({ validUntil: "2026-11-01", rows: [{ textHash: H4, choice: "accept" }] })).toBe("accepted");
  });

  it("replaced: the card's hash is an older text and a row exists for it", () => {
    expect(d({ cardHash: H3, rows: [{ textHash: H3, choice: "request_changes" }] })).toBe("replaced");
    expect(d({ cardHash: H3, rows: [{ textHash: H3, choice: "accept" }, { textHash: H4, choice: "decline" }] })).toBe("replaced");
  });

  it("expired: no row for the current hash and valid_until has passed (the whole of that day, UTC, is still open)", () => {
    expect(d({ validUntil: "2026-11-04" })).toBe("expired");
    expect(d({ validUntil: "2026-11-05" })).toBe("pending");
    expect(d({ validUntil: "2026-11-05", now: new Date("2026-11-05T23:59:59.999Z") })).toBe("pending");
    expect(d({ validUntil: "2026-11-05", now: new Date("2026-11-06T00:00:00Z") })).toBe("expired");
  });

  it("an older answer does not stop the current text from expiring", () => {
    expect(d({ validUntil: "2026-11-01", rows: [{ textHash: H3, choice: "accept" }] })).toBe("expired");
  });

  it("uses the injected now, never the wall clock", () => {
    expect(d({ validUntil: "2026-11-05", now: new Date("2030-01-01T00:00:00Z") })).toBe("expired");
    expect(d({ validUntil: "2026-11-05", now: new Date("2020-01-01T00:00:00Z") })).toBe("pending");
  });

  it("reaches every one of the six states and only those", () => {
    const seen = new Set([
      d({}),
      d({ rows: [{ textHash: H4, choice: "accept" }] }),
      d({ rows: [{ textHash: H4, choice: "decline" }] }),
      d({ rows: [{ textHash: H4, choice: "request_changes" }] }),
      d({ cardHash: H3, rows: [{ textHash: H3, choice: "accept" }] }),
      d({ validUntil: "2026-01-01" }),
    ]);
    expect([...seen].sort()).toEqual([...LEGAL_CARD_STATES].sort());
  });
});

describe("legalValidUntilPassed", () => {
  it("is false without a date and true only from the start of the next UTC day", () => {
    expect(legalValidUntilPassed(null, NOW)).toBe(false);
    expect(legalValidUntilPassed("2026-11-05", NOW)).toBe(false);
    expect(legalValidUntilPassed("2026-11-04", NOW)).toBe(true);
  });
});
