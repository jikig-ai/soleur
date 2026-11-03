import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  DECISION_FILTERS,
  DEFAULT_TIME_WINDOW,
  TIME_WINDOWS,
  WINDOW_LABEL,
  parseTimeWindow,
  windowPhrase,
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

// window-assembly: parseTimeWindow — not a regex-extracted source region: it
// parses the ?window= URL parameter. The closure assertions below are complete
// against TIME_WINDOWS (the allowlist the chips and the SQL CASE map share).
describe("parseTimeWindow", () => {
  it("accepts each of the three spellings the chips use, in chip order", () => {
    expect([...TIME_WINDOWS]).toEqual(["24h", "7d", "30d"]);
    for (const w of TIME_WINDOWS) expect(parseTimeWindow(w)).toBe(w);
  });

  it("the default is 30 days", () => {
    expect(DEFAULT_TIME_WINDOW).toBe("30d");
  });

  it("falls back to the default for absent, empty, unknown, differently-cased and padded values (never a 400)", () => {
    for (const v of [undefined, "", "bogus", "30D", " 7d", "7d ", "24H", "90d", "1h", "all"]) expect([v, parseTimeWindow(v)]).toEqual([v, "30d"]);
  });

  it("uses the first of a repeated value, and falls back only when the first is unknown", () => {
    expect(parseTimeWindow(["7d", "24h"])).toBe("7d");
    expect(parseTimeWindow(["24h", "bogus"])).toBe("24h");
    expect(parseTimeWindow(["bogus", "7d"])).toBe("30d");
    expect(parseTimeWindow([])).toBe("30d");
  });
});

describe("WINDOW_LABEL and windowPhrase", () => {
  it("labels all three windows", () => {
    expect(WINDOW_LABEL).toEqual({ "24h": "24 hours", "7d": "7 days", "30d": "30 days" });
  });

  it("the phrase is hedged ('about the last N'): 15-minute buckets straddling the window start are counted whole", () => {
    expect(windowPhrase("24h")).toBe("about the last 24 hours");
    expect(windowPhrase("7d")).toBe("about the last 7 days");
    expect(windowPhrase("30d")).toBe("about the last 30 days");
  });
});

describe("TypeScript/SQL allowlist drift", () => {
  it("the keys of the `CASE p_window` map in migration 183 equal TIME_WINDOWS (otherwise a drift surfaces only as a runtime 22023)", () => {
    const file = path.join(__dirname, "..", "supabase", "migrations", "183_egress_audit_window_summary.sql");
    const sql = readFileSync(file, "utf8")
      .split("\n")
      .map((l) => l.replace(/--.*$/, ""))
      .join("\n");
    const caseBlock = /CASE\s+p_window\b([\s\S]*?)\bEND\b/i.exec(sql);
    expect(caseBlock, "a `CASE p_window ... END` map must exist in migration 183").not.toBeNull();
    const keys = [...(caseBlock?.[1] ?? "").matchAll(/WHEN\s+'([^']+)'\s+THEN/gi)].map((m) => m[1]);
    expect(keys.length).toBeGreaterThan(0);
    expect([...keys].sort()).toEqual([...TIME_WINDOWS].sort());
  });
});
