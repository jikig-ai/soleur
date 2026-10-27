import { describe, expect, it } from "vitest";
import {
  DECISION_FILTERS,
  formatAgo,
  formatAtLeast,
  isEgressAuditPayload,
  outcomeOf,
  parseDecisionFilter,
  toRpcDecision,
} from "@/lib/egress-audit/summary";

// #9545 PR2 — the pure, client-safe helpers behind the egress audit view.

describe("parseDecisionFilter", () => {
  it("accepts each of the four spellings the chips use", () => {
    for (const f of DECISION_FILTERS) expect(parseDecisionFilter(f)).toBe(f);
  });

  it("falls back to `all` for absent, empty, unknown and differently-cased values (never a 400)", () => {
    for (const v of [undefined, "", "bogus", "denied", "BLOCKED", " blocked"]) expect(parseDecisionFilter(v)).toBe("all");
  });

  it("uses the first of a repeated value", () => {
    expect(parseDecisionFilter(["allowed", "blocked"])).toBe("allowed");
    expect(parseDecisionFilter(["bogus", "blocked"])).toBe("all");
    expect(parseDecisionFilter([])).toBe("all");
  });
});

describe("toRpcDecision", () => {
  it("all -> null (every outcome)", () => expect(toRpcDecision("all")).toBeNull());
  it("blocked -> denied (the stored spelling)", () => expect(toRpcDecision("blocked")).toBe("denied"));
  it("allowed -> allowed", () => expect(toRpcDecision("allowed")).toBe("allowed"));
  it("other -> other", () => expect(toRpcDecision("other")).toBe("other"));
});

describe("outcomeOf", () => {
  it("maps the stored decisions and tolerates an unknown one as Other", () => {
    expect(outcomeOf("denied")).toBe("Blocked");
    expect(outcomeOf("allowed")).toBe("Allowed");
    expect(outcomeOf("quarantined")).toBe("Other");
    expect(outcomeOf("")).toBe("Other");
  });
});

describe("formatAgo", () => {
  const now = Date.parse("2026-10-26T12:00:00Z");
  it("reads long-form relative time and clamps a future timestamp", () => {
    expect(formatAgo("2026-10-26T11:59:40Z", now)).toBe("just now");
    expect(formatAgo("2026-10-26T11:56:00Z", now)).toBe("4 minutes ago");
    expect(formatAgo("2026-10-26T11:00:00Z", now)).toBe("1 hour ago");
    expect(formatAgo("2026-10-25T11:00:00Z", now)).toBe("yesterday");
    expect(formatAgo("2026-10-20T12:00:00Z", now)).toBe("6 days ago");
    expect(formatAgo("2026-10-26T13:00:00Z", now)).toBe("just now");
  });

  it("never prints NaN for an unparseable input", () => {
    for (const bad of ["", "not a time", "2026-13-45"]) {
      expect(formatAgo(bad, now)).not.toMatch(/NaN/);
      expect(formatAgo(bad, now)).toBe("at an unknown time");
    }
  });

  it("formatAtLeast keeps the minimum framing", () => {
    expect(formatAtLeast(4812)).toBe("at least 4,812");
  });
});

describe("isEgressAuditPayload", () => {
  const ok = () => ({
    window: { start: "2026-09-26T00:00:00Z", end: "2026-10-26T00:00:00Z" },
    truncated: false,
    summary: { request_count_min: null, blocked_request_count_min: null, last_request_at: null },
    rows: [{ host: "a.example.test", decision: "allowed", request_count: 0, last_seen: "2026-10-26T12:00:00.123456+00:00" }],
    overflow: [{ decision: "other", request_count: 3, last_seen: "2026-10-26T12:00:00Z" }],
  });

  it("accepts the RPC's shape (null counts, microsecond timestamps with an offset, an empty log)", () => {
    expect(isEgressAuditPayload(ok())).toBe(true);
    expect(isEgressAuditPayload({ ...ok(), rows: [], overflow: [] })).toBe(true);
  });

  it("rejects a body that differs from the shape in exactly one field", () => {
    const cases: Record<string, unknown> = {
      "no window": { ...ok(), window: undefined },
      "truncated absent": (() => {
        const p: Record<string, unknown> = ok();
        delete p.truncated;
        return p;
      })(),
      "overflow an object": { ...ok(), overflow: {} },
      "no last_request_at key": { ...ok(), summary: { request_count_min: 1, blocked_request_count_min: 0 } },
      "rows a string": { ...ok(), rows: "no" },
      "a null row element": { ...ok(), rows: [null] },
      "a NaN count": { ...ok(), rows: [{ ...ok().rows[0], request_count: Number.NaN }] },
      "a negative summary count": { ...ok(), summary: { request_count_min: -1, blocked_request_count_min: null, last_request_at: null } },
      "an unparseable last_request_at": { ...ok(), summary: { request_count_min: 1, blocked_request_count_min: 0, last_request_at: "soon" } },
      "window.start absent": { ...ok(), window: { end: "2026-10-26T00:00:00Z" } },
      "window.start a number": { ...ok(), window: { start: 1, end: "2026-10-26T00:00:00Z" } },
      "an overflow element with a non-string decision": { ...ok(), overflow: [{ decision: 1, request_count: 3, last_seen: "2026-10-26T12:00:00Z" }] },
      "an overflow element without a decision": { ...ok(), overflow: [{ request_count: 3, last_seen: "2026-10-26T12:00:00Z" }] },
      "an unparseable last_seen": { ...ok(), overflow: [{ decision: "other", request_count: 1, last_seen: "soon" }] },
    };
    for (const [label, body] of Object.entries(cases)) expect([label, isEgressAuditPayload(body)]).toEqual([label, false]);
  });
});
