/**
 * Inbox row for the founder's legal texts (CPO ruling P3, CTO ruling T7, 2026-11-08; Ref #12197).
 *
 * `loadLegalInboxRows` derives one row per DECLARED legal text for the configured founder. Each `it` below names the mutant it
 * kills; a mutant here is a one-line change to `server/legal-acceptance/inbox-rows.ts` that must turn the test red:
 *   M1 gate dropped (rows for a non-founder, a legal_acceptance read before the gate)
 *   M2 pending rendered as `info`
 *   M3 answered rendered as `action_required`
 *   M4 a read failure throws instead of omitting the rows
 *   M5 an undeclared key included
 *   M6 `requested_edit`, the hash or a timestamp reaches the payload (or is selected)
 *   M7 the founder's accepted row compared against the wrong hash (an accepted founder would see a NEEDS YOU row)
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  enabled: { value: true as boolean | Error },
  reports: [] as unknown[][],
  calls: { from: [] as string[], select: [] as string[], eq: [] as unknown[][], in: [] as unknown[][] },
  result: { value: { data: [] as unknown, error: null as unknown } },
  throwOnRead: { value: false },
}));

vi.mock("@/server/legal-acceptance/surface", () => ({
  isLegalSurfaceEnabled: async () => {
    if (h.enabled.value instanceof Error) throw h.enabled.value;
    return h.enabled.value;
  },
}));
vi.mock("@/server/approval/ops", () => ({
  reportLegalOp: (...args: unknown[]) => {
    h.reports.push(args);
  },
}));

import { loadLegalInboxRows } from "@/server/legal-acceptance/inbox-rows";
import { KEY_RE, loadLegalTexts, type LegalTextEntry } from "@/server/legal-acceptance/canonical";
import { LEGAL_KEY_RE } from "@/lib/legal-acceptance-wire";
import { LEGAL_TEXT_KIND } from "@/lib/legal-acceptance-copy";
import { mergeAndRank } from "@/lib/inbox-severity";

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const NOW = new Date("2026-11-09T12:00:00Z");
const COMMITTED_HASH = "10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287";
const KEY = "founder-acceptance-record";

function fakeSupabase() {
  const builder: Record<string, unknown> = {};
  builder.select = (cols: string) => {
    h.calls.select.push(cols);
    return builder;
  };
  builder.eq = (...a: unknown[]) => {
    h.calls.eq.push(a);
    return builder;
  };
  builder.in = (...a: unknown[]) => {
    h.calls.in.push(a);
    if (h.throwOnRead.value) throw new Error("boom");
    return Promise.resolve(h.result.value);
  };
  return {
    from: (t: string) => {
      h.calls.from.push(t);
      return builder;
    },
  } as never;
}

function entry(over: Partial<LegalTextEntry> & { key: string }): LegalTextEntry {
  return { version: "2026-11-07", validUntil: null, textHash: "a".repeat(64), raw: "", body: "A text title\n\nbody", ...over };
}

beforeEach(() => {
  h.enabled.value = true;
  h.reports.length = 0;
  h.calls.from.length = 0;
  h.calls.select.length = 0;
  h.calls.eq.length = 0;
  h.calls.in.length = 0;
  h.result.value = { data: [], error: null };
  h.throwOnRead.value = false;
});

const load = (texts?: Map<string, LegalTextEntry>, declared = LEGAL_TEXT_KIND) =>
  loadLegalInboxRows(fakeSupabase(), FOUNDER, { now: NOW, ...(texts ? { texts: () => texts } : {}), declared });

describe("registry facts the row relies on", () => {
  it("the committed text still has the pinned hash and every registry version is an ISO date (sort time is Date.parse(version))", () => {
    const all = loadLegalTexts();
    expect(all.get(KEY)?.textHash).toBe(COMMITTED_HASH);
    for (const e of all.values()) expect(Number.isNaN(Date.parse(e.version)), `${e.key} ${e.version}`).toBe(false);
  });
});

describe("client-safe key shape", () => {
  it("is the registry's KEY_RE character for character (the row builds a path from it; 63 accepted, 64 refused)", () => {
    expect(LEGAL_KEY_RE.source).toBe(KEY_RE.source);
    for (const [v, ok] of [
      ["a".repeat(63), true],
      ["a".repeat(64), false],
      ["-leading", false],
      ["Upper", false],
      ["../admin", false],
      ["founder-acceptance-record", true],
    ] as const) {
      expect(LEGAL_KEY_RE.test(v), v).toBe(ok);
    }
  });
});

describe("gate (M1)", () => {
  it("a non-founder or flag-off user gets no rows and NO legal_acceptance read", async () => {
    h.enabled.value = false;
    expect(await load()).toEqual([]);
    expect(h.calls.from).toEqual([]);
    expect(h.reports).toEqual([]);
  });

  it("a throwing gate omits the rows and reports pageReadFailed (never throws)", async () => {
    h.enabled.value = new Error("flag service down");
    expect(await load()).toEqual([]);
    expect(h.reports.map((r) => r[0])).toEqual(["pageReadFailed"]);
  });
});

describe("states", () => {
  it("pending (no row) is action_required and outstanding (M2)", async () => {
    const rows = await load();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ key: KEY, state: "pending", severity: "action_required", outstanding: true });
  });

  it("the founder's accepted row for the registry hash is FYI, not outstanding (M3, M7)", async () => {
    h.result.value = { data: [{ key: KEY, text_hash: COMMITTED_HASH, choice: "accept" }], error: null };
    const rows = await load();
    expect(rows[0]).toMatchObject({ state: "accepted", severity: "info", outstanding: false });
    // The badge arithmetic that matters to an accepted founder: no NEEDS YOU, nothing outstanding.
    const merged = mergeAndRank([], [], rows);
    expect(merged.filter((m) => m.severity === "action_required")).toEqual([]);
    expect(merged.filter((m) => m.outstanding)).toEqual([]);
  });

  it.each([
    ["decline", "declined"],
    ["request_changes", "changes_requested"],
  ] as const)("%s is FYI (%s) (M3)", async (choice, state) => {
    h.result.value = { data: [{ key: KEY, text_hash: COMMITTED_HASH, choice }], error: null };
    const rows = await load();
    expect(rows[0]).toMatchObject({ state, severity: "info", outstanding: false });
  });

  it("a row for an OLDER hash does not answer the current text: back to NEEDS YOU for the new version (replaced)", async () => {
    h.result.value = { data: [{ key: KEY, text_hash: "b".repeat(64), choice: "accept" }], error: null };
    const rows = await load(new Map([[KEY, entry({ key: KEY, version: "2026-12-01" })]]));
    expect(rows[0]).toMatchObject({ state: "pending", severity: "action_required", version: "2026-12-01" });
  });

  it("an expired text with no answer is FYI and not outstanding (no prompt)", async () => {
    const rows = await load(new Map([[KEY, entry({ key: KEY, validUntil: "2026-11-01" })]]));
    expect(rows[0]).toMatchObject({ state: "expired", severity: "info", outstanding: false });
  });

  it("a text still open carries its valid_until for the expiry chip; an open-ended one carries null", async () => {
    const open = await load(new Map([[KEY, entry({ key: KEY, validUntil: "2026-12-31" })]]));
    expect(open[0].validUntil).toBe("2026-12-31");
    const endless = await load(new Map([[KEY, entry({ key: KEY })]]));
    expect(endless[0].validUntil).toBeNull();
  });
});

describe("what is read (M5, M6)", () => {
  it("selects only key, text_hash, choice for this founder and the declared keys, from legal_acceptance", async () => {
    await load();
    expect(h.calls.from).toEqual(["legal_acceptance"]);
    expect(h.calls.select).toEqual(["key, text_hash, choice"]);
    expect(h.calls.eq).toEqual([["founder_id", FOUNDER]]);
    expect(h.calls.in).toEqual([["key", [KEY]]]);
  });

  it("an undeclared key (a registry text with no card kind) is omitted and never queried (M5)", async () => {
    const texts = new Map([
      [KEY, entry({ key: KEY })],
      ["unlisted-text", entry({ key: "unlisted-text" })],
    ]);
    const rows = await load(texts);
    expect(rows.map((r) => r.key)).toEqual([KEY]);
    expect(h.calls.in).toEqual([["key", [KEY]]]);
  });

  it("with no declared text at all there is no read", async () => {
    expect(await load(new Map([["unlisted-text", entry({ key: "unlisted-text" })]]))).toEqual([]);
    expect(h.calls.from).toEqual([]);
  });

  it("the payload carries no hash, note, timestamp or founder id even if the store returned them (M6)", async () => {
    h.result.value = {
      data: [
        {
          key: KEY,
          text_hash: COMMITTED_HASH,
          choice: "request_changes",
          requested_edit: "SECRET-NOTE-TEXT",
          created_at: "2026-11-08T10:00:00Z",
          founder_id: FOUNDER,
        },
      ],
      error: null,
    };
    const rows = await load();
    const wire = JSON.stringify(rows);
    for (const leaked of ["SECRET-NOTE-TEXT", "requested_edit", COMMITTED_HASH, "2026-11-08T10", FOUNDER, "founder_id", "created_at", "text_hash"]) {
      expect(wire, leaked).not.toContain(leaked);
    }
    expect(Object.keys(rows[0]).sort()).toEqual(["key", "label", "outstanding", "severity", "state", "validUntil", "version"]);
  });
});

describe("read failures omit the rows and report, never throw (M4)", () => {
  const readLabel = { read: "legal_acceptance_inbox" };

  it.each([
    ["an error from the store", () => (h.result.value = { data: null, error: { code: "42501" } })],
    ["a thrown error", () => (h.throwOnRead.value = true)],
    ["a non-array payload", () => (h.result.value = { data: { not: "an array" }, error: null })],
    ["a malformed row", () => (h.result.value = { data: [{ key: KEY, text_hash: COMMITTED_HASH, choice: "maybe" }], error: null })],
    ["a row missing text_hash", () => (h.result.value = { data: [{ key: KEY, choice: "accept" }], error: null })],
  ])("%s", async (_name, arrange) => {
    arrange();
    expect(await load()).toEqual([]);
    expect(h.reports).toHaveLength(1);
    expect(h.reports[0][0]).toBe("pageReadFailed");
    expect(h.reports[0][2]).toMatchObject({ userId: FOUNDER, extra: readLabel });
  });
});

describe("mergeAndRank with legal rows", () => {
  it("a pending legal row is a kind:legal NEEDS YOU item that counts as outstanding; sort time is the version date", async () => {
    const rows = await load();
    const merged = mergeAndRank([], [], rows);
    expect(merged).toHaveLength(1);
    expect(merged[0]).toMatchObject({
      kind: "legal",
      id: KEY,
      severity: "action_required",
      pinned: false,
      outstanding: true,
      legal: { key: KEY, state: "pending" },
    });
  });

  it("two arguments still work (the agent tool keeps the two-argument call)", () => {
    expect(mergeAndRank([], [])).toEqual([]);
  });
});
