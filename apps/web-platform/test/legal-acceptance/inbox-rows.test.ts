/**
 * Inbox row for the founder's legal texts (CPO ruling P3, CTO ruling T7, 2026-11-08; Ref #12197).
 *
 * `loadLegalInboxRows` derives one row per DECLARED legal text for the configured founder. A mutant is a one-line change to
 * `server/legal-acceptance/inbox-rows.ts` that must turn a test red. The suites tagged below (M1..M7, A1..A5) name the mutant
 * they kill; the untagged ones pin a contract (key shape, registry facts, merge arithmetic):
 *   M1 gate dropped (rows for a non-founder, a legal_acceptance read before the gate)
 *   M2 pending rendered as `info`
 *   M3 answered rendered as `action_required`
 *   M4 a read failure throws instead of omitting the rows
 *   M5 an undeclared key included
 *   M6 `requested_edit`, the hash or a timestamp reaches the payload (or is selected)
 *   M7 the founder's accepted row compared against the wrong hash (an accepted founder would see a NEEDS YOU row)
 *   A1 the gate called with any id other than the user's
 *   A2 the read not narrowed with `.eq("founder_id", <user id>)` (wrong id or the call dropped)
 *   A3 the read not narrowed with `.in("key", <declared keys>)` (dropped or widened)
 *   A4 a row's state taken from ANOTHER key's decisions (`decisions.filter((d) => d.key === entry.key)` dropped)
 *   A5 one malformed or missing sibling text takes every legal row down (`loadLegalTexts` instead of `getLegalText` per key)
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  enabled: { value: true as boolean | Error },
  gateCalls: [] as unknown[][],
  reports: [] as unknown[][],
  calls: { from: [] as string[], select: [] as string[], eq: [] as unknown[][], in: [] as unknown[][] },
  result: { value: { data: [] as unknown, error: null as unknown } },
  throwOnRead: { value: false },
}));

vi.mock("@/server/legal-acceptance/surface", () => ({
  isLegalSurfaceEnabled: async (...args: unknown[]) => {
    h.gateCalls.push(args);
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
import { KEY_RE, LegalTextError, loadLegalTexts, type LegalTextEntry } from "@/server/legal-acceptance/canonical";
import { LEGAL_KEY_RE } from "@/lib/legal-acceptance-wire";
import { LEGAL_TEXT_KIND, type LegalTextKind } from "@/lib/legal-acceptance-copy";
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
  h.gateCalls.length = 0;
  h.calls.from.length = 0;
  h.calls.select.length = 0;
  h.calls.eq.length = 0;
  h.calls.in.length = 0;
  h.result.value = { data: [], error: null };
  h.throwOnRead.value = false;
});

/** Serve a Map as the registry through the per-key seams (a missing key throws as `getLegalText` does). No Map: the real registry. */
function registrySeams(texts: Map<string, LegalTextEntry>) {
  return {
    getText: (key: string) => {
      const e = texts.get(key);
      if (!e) throw new LegalTextError("unknown_key", "no such legal text");
      return e;
    },
    listKeys: () => [...texts.keys()],
  };
}

const load = (texts?: Map<string, LegalTextEntry>, declared: Readonly<Record<string, LegalTextKind>> = LEGAL_TEXT_KIND) =>
  loadLegalInboxRows(fakeSupabase(), FOUNDER, { now: NOW, ...(texts ? registrySeams(texts) : {}), declared });

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

describe("gate (M1, A1)", () => {
  it("a non-founder or flag-off user gets no rows and NO legal_acceptance read", async () => {
    h.enabled.value = false;
    expect(await load()).toEqual([]);
    expect(h.gateCalls).toEqual([[FOUNDER]]);
    expect(h.calls.from).toEqual([]);
    expect(h.reports).toEqual([]);
  });

  it("the gate is asked about THE USER whose rows these are, exactly once, and before any read (A1)", async () => {
    await load();
    expect(h.gateCalls).toEqual([[FOUNDER]]);
    const other = "00000000-0000-4000-8000-0000000000bb";
    h.gateCalls.length = 0;
    await loadLegalInboxRows(fakeSupabase(), other, { now: NOW });
    expect(h.gateCalls).toEqual([[other]]);
  });

  it("a throwing gate omits the rows and reports pageReadFailed (never throws)", async () => {
    h.enabled.value = new Error("flag service down");
    expect(await load()).toEqual([]);
    expect(h.reports.map((r) => r[0])).toEqual(["pageReadFailed"]);
    expect(h.reports[0][2]).toMatchObject({ userId: FOUNDER, extra: { read: "legal_acceptance_inbox", step: "gate" } });
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
  it("selects only key, text_hash, choice for this founder and the declared keys, from legal_acceptance (A2, A3)", async () => {
    await load();
    expect(h.calls.from).toEqual(["legal_acceptance"]);
    expect(h.calls.select).toEqual(["key, text_hash, choice"]);
    // Exact values: a different id, a dropped `.eq` or a dropped/widened `.in` each fails here.
    expect(h.calls.eq).toEqual([["founder_id", FOUNDER]]);
    expect(h.calls.in).toEqual([["key", [KEY]]]);
  });

  it("the narrowing follows the user the rows are for, not a constant (A2)", async () => {
    const other = "00000000-0000-4000-8000-0000000000bb";
    await loadLegalInboxRows(fakeSupabase(), other, { now: NOW });
    expect(h.calls.eq).toEqual([["founder_id", other]]);
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

  it("an undeclared registry text is REPORTED (kindUndeclared, tags.key, the user id), not silently dropped; nothing else rides along", async () => {
    await load(
      new Map([
        [KEY, entry({ key: KEY })],
        ["unlisted-text", entry({ key: "unlisted-text" })],
      ]),
    );
    expect(h.reports).toHaveLength(1);
    expect(h.reports[0][0]).toBe("kindUndeclared");
    expect(h.reports[0][1]).toBeNull();
    expect(h.reports[0][2]).toEqual({ userId: FOUNDER, tags: { key: "unlisted-text" } });
  });

  it("no undeclared text, no kindUndeclared report; and none before the gate has passed", async () => {
    await load(new Map([[KEY, entry({ key: KEY })]]));
    expect(h.reports).toEqual([]);
    h.enabled.value = false;
    await load(new Map([["unlisted-text", entry({ key: "unlisted-text" })]]));
    expect(h.reports).toEqual([]);
  });

  it("with no declared text served at all there is no read, and the missing declared text is reported", async () => {
    expect(await load(new Map([["unlisted-text", entry({ key: "unlisted-text" })]]))).toEqual([]);
    expect(h.calls.from).toEqual([]);
    expect(h.reports.map((r) => r[0]).sort()).toEqual(["kindUndeclared", "pageReadFailed"]);
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

describe("two declared texts: each row takes only ITS OWN key's decisions (A4)", () => {
  // Both texts share one hash on purpose: a decision for the OTHER key would then answer this one, which is the mutant.
  const A = "alpha-text";
  const B = "beta-text";
  const declared = { [A]: "terms", [B]: "acknowledgement" } as const;
  const texts = () =>
    new Map([
      [A, entry({ key: A, body: "Alpha title\n\nbody" })],
      [B, entry({ key: B, body: "Beta title\n\nbody" })],
    ]);
  const hash = "a".repeat(64);

  it("A answered, B not: A is accepted/FYI, B is pending/NEEDS YOU", async () => {
    h.result.value = { data: [{ key: A, text_hash: hash, choice: "accept" }], error: null };
    const rows = await load(texts(), declared);
    expect(rows.map((r) => [r.key, r.state, r.severity, r.outstanding])).toEqual([
      [A, "accepted", "info", false],
      [B, "pending", "action_required", true],
    ]);
    expect(h.calls.in).toEqual([["key", [A, B]]]);
  });

  it("B answered, A not: the reverse", async () => {
    h.result.value = { data: [{ key: B, text_hash: hash, choice: "decline" }], error: null };
    const rows = await load(texts(), declared);
    expect(rows.map((r) => [r.key, r.state, r.severity, r.outstanding])).toEqual([
      [A, "pending", "action_required", true],
      [B, "declined", "info", false],
    ]);
  });
});

describe("one malformed or missing sibling text loses only its own row (A5)", () => {
  const A = "alpha-text";
  const B = "beta-text";
  const declared = { [A]: "terms", [B]: "acknowledgement" } as const;

  it("a declared text that fails to parse is reported (registry step, its key) and the other row is still derived; the read names only the good key", async () => {
    const good = entry({ key: A });
    const rows = await loadLegalInboxRows(fakeSupabase(), FOUNDER, {
      now: NOW,
      declared,
      getText: (key) => {
        if (key === B) throw new LegalTextError("bad_version", "legal text version is missing or too long");
        return good;
      },
      listKeys: () => [A, B],
    });
    expect(rows.map((r) => r.key)).toEqual([A]);
    expect(h.calls.in).toEqual([["key", [A]]]);
    expect(h.reports).toHaveLength(1);
    expect(h.reports[0][0]).toBe("pageReadFailed");
    expect(h.reports[0][2]).toMatchObject({ userId: FOUNDER, extra: { read: "legal_acceptance_inbox", step: "registry", key: B } });
  });

  it("a registry listing that fails costs nothing: the declared rows are still derived, and the failure is reported", async () => {
    const rows = await loadLegalInboxRows(fakeSupabase(), FOUNDER, {
      now: NOW,
      declared: { [A]: "terms" },
      getText: () => entry({ key: A }),
      listKeys: () => {
        throw new Error("EACCES");
      },
    });
    expect(rows.map((r) => r.key)).toEqual([A]);
    expect(h.reports.map((r) => [r[0], (r[2] as { extra: { step: string } }).extra.step])).toEqual([["pageReadFailed", "registry"]]);
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

  it.each([
    ["an error from the store", () => (h.result.value = { data: null, error: { code: "42501" } }), "read"],
    ["a thrown error", () => (h.throwOnRead.value = true), "read"],
    ["a non-array payload", () => (h.result.value = { data: { not: "an array" }, error: null }), "shape"],
    ["a malformed row", () => (h.result.value = { data: [{ key: KEY, text_hash: COMMITTED_HASH, choice: "maybe" }], error: null }), "shape"],
  ])("%s reports the step it stopped at (%#)", async (_name, arrange, step) => {
    arrange();
    await load();
    expect((h.reports[0][2] as { extra: { step: string } }).extra.step).toBe(step);
  });

  it("no report from this module carries a hash, a note or the answer (only ids, labels and the static step)", async () => {
    h.result.value = { data: [{ key: KEY, text_hash: COMMITTED_HASH, choice: "maybe", requested_edit: "SECRET-NOTE-TEXT" }], error: null };
    await load();
    const wire = JSON.stringify(h.reports);
    for (const leaked of ["SECRET-NOTE-TEXT", COMMITTED_HASH, "requested_edit", "text_hash"]) expect(wire, leaked).not.toContain(leaked);
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
