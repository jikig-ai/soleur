// RED-first per cq-write-failing-tests-before. Phase 4.
// TS14: first-write succeeds; sanitized key (`dependabot-bot` not `dependabot[bot]`).
// TS15: duplicate-quarter returns 412.
// TS16: new-quarter writes new record.
// TS16b: github-actions[bot] DB-id 41898282 produces NO write.
import { describe, it, expect } from "vitest";
import {
  buildBypassRecord,
  bypassRecordKey,
  sanitizePrincipal,
  quarterFor,
} from "@/scripts/cla-evidence/allowlist-bypass";

describe("sanitizePrincipal", () => {
  it("replaces [bot] with -bot for safe R2 key construction (Kieran F8)", () => {
    expect(sanitizePrincipal("dependabot[bot]")).toBe("dependabot-bot");
    expect(sanitizePrincipal("renovate[bot]")).toBe("renovate-bot");
    expect(sanitizePrincipal("claude[bot]")).toBe("claude-bot");
  });

  it("leaves human logins unchanged", () => {
    expect(sanitizePrincipal("deruelle")).toBe("deruelle");
  });
});

describe("quarterFor", () => {
  it("returns yyyy-qN for a Date", () => {
    expect(quarterFor(new Date("2026-01-15T00:00:00Z"))).toBe("2026-q1");
    expect(quarterFor(new Date("2026-04-01T00:00:00Z"))).toBe("2026-q2");
    expect(quarterFor(new Date("2026-07-31T23:59:59Z"))).toBe("2026-q3");
    expect(quarterFor(new Date("2026-12-31T23:59:59Z"))).toBe("2026-q4");
  });
});

describe("bypassRecordKey", () => {
  it("uses sanitized principal in the R2 key path", () => {
    const k = bypassRecordKey("dependabot[bot]", "2026-q2");
    expect(k).toBe("allowlist/dependabot-bot/2026-q2.json");
  });

  it("preserves quarter in deterministic position", () => {
    expect(bypassRecordKey("renovate[bot]", "2026-q3")).toBe("allowlist/renovate-bot/2026-q3.json");
  });
});

describe("buildBypassRecord", () => {
  const fixed = new Date("2026-05-04T10:00:00Z");

  it("produces a record with schema_version=1.0 and sanitized + canonical principal", () => {
    const r = buildBypassRecord({
      principal: "dependabot[bot]",
      dbId: 49699333,
      now: fixed,
      firstPr: 3220,
    });
    expect(r.schema_version).toBe("1.0");
    expect(r.principal).toBe("dependabot[bot]");
    expect(r.principal_safe).toBe("dependabot-bot");
    expect(r.db_id).toBe(49699333);
    expect(r.quarter).toBe("2026-q2");
    expect(r.first_seen_at).toBe("2026-05-04T10:00:00.000Z");
    expect(r.first_pr).toBe(3220);
    expect(r.allowlist_source).toBe("cla.yml#with.allowlist");
  });

  it("never builds a record for github-actions[bot] (DB-id 41898282) — TS16b (defense-in-depth)", () => {
    expect(() =>
      buildBypassRecord({
        principal: "github-actions[bot]",
        dbId: 41898282,
        now: fixed,
        firstPr: 3220,
      }),
    ).toThrow(/41898282/);
  });
});
