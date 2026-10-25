// #8293 -- the proposal ledger reader. Only `octokit.request` is faked, by a fake that ROUTES on the
// search query and asserts the exact params it receives (a stub that answers every request the same
// would let a wrong query read the right fixture). Item shapes follow a recorded GitHub search
// response: merged -> `pull_request.merged_at` set; closed-unmerged -> `merged_at: null`.
import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

vi.hoisted(() => {
  // _cron-shared (the shared fetchAllPages / bot login) is imported by the module under test.
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  LEDGER_BOT_LOGIN,
  LEDGER_MAX_SEARCH_PAGES,
  LEDGER_TTL_DAYS,
  PROMOTE_BRANCH_PREFIX,
  LedgerReadError,
  PROMOTE_PR_TITLE_RE,
  decideSuppression,
  promotePrTitle,
  readLedger,
  type LedgerEntry,
  type LedgerFailureCause,
  type LedgerOctokit,
} from "@/server/compound-promote-ledger";
import { BOT_PR_HEAD_PREFIXES } from "@/server/inngest/functions/cron-cloud-task-heartbeat";

const HERE = dirname(fileURLToPath(import.meta.url));
const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date("2026-12-01T00:00:00.000Z");
const hex = (c: string) => c.repeat(64);
const H1 = hex("a");
const H2 = hex("b");
const OWNER = "acme-org";
const REPO = "widgets";
const Q = `repo:${OWNER}/${REPO} is:pr author:app/soleur-ai head:self-healing/auto-`;
const mkItems = (n: number) => Array.from({ length: n }, () => item({ hash: hex("0") }));

type Item = {
  title: string;
  state: "open" | "closed";
  closed_at: string | null;
  user: { login: string } | null;
  pull_request: { merged_at: string | null };
};

function item(o: {
  hash?: string;
  date?: string;
  state?: "open" | "closed";
  merged?: boolean;
  closedAt?: string | null;
  login?: string;
  title?: string;
}): Item {
  const state = o.state ?? "open";
  return {
    title: o.title ?? promotePrTitle(o.hash ?? H1, o.date ?? "2026-10-04"),
    state,
    closed_at: o.closedAt === undefined ? (state === "closed" ? "2026-11-01T00:00:00Z" : null) : o.closedAt,
    user: { login: o.login ?? LEDGER_BOT_LOGIN },
    pull_request: { merged_at: o.merged ? "2026-10-05T00:00:00Z" : null },
  };
}

/** A q-routing fake: refuses any request whose route or params differ from the contract. */
function fakeOctokit(
  pages: Item[][],
  over: { total_count?: number; incomplete_results?: boolean; failOn?: number; error?: unknown; data?: unknown } = {},
) {
  const calls: Array<{ route: string; params: Record<string, unknown> }> = [];
  const total = over.total_count ?? pages.reduce((n, p) => n + p.length, 0);
  const octokit: LedgerOctokit = {
    request: async (route, params) => {
      calls.push({ route, params });
      if (route !== "GET /search/issues") throw new Error(`unexpected route ${route}`);
      if (params.q !== Q) throw new Error(`unexpected q ${String(params.q)}`);
      if (params.per_page !== 100) throw new Error(`unexpected per_page ${String(params.per_page)}`);
      const page = params.page as number;
      if (over.failOn === page) throw over.error;
      if (over.data !== undefined) return { data: over.data };
      return { data: { total_count: total, incomplete_results: over.incomplete_results ?? false, items: pages[page - 1] ?? [] } };
    },
  };
  return { octokit, calls };
}

const read = (o: LedgerOctokit) => readLedger({ octokit: o, owner: OWNER, repo: REPO });
const causeOf = async (p: Promise<unknown>): Promise<LedgerFailureCause | "no-throw"> => {
  try {
    await p;
    return "no-throw";
  } catch (e) {
    if (e instanceof LedgerReadError) return e.ledgerCause;
    throw e;
  }
};

describe("title builder and parser are one pair", () => {
  it("a title built by promotePrTitle parses back to the same hash and date", () => {
    const m = PROMOTE_PR_TITLE_RE.exec(promotePrTitle(H1, "2026-10-04"));
    expect(m?.[1]).toBe(H1);
    expect(m?.[2]).toBe("2026-10-04");
  });

  it("the builder still yields the literal the apply step used before this change", () => {
    expect(promotePrTitle(H1, "2026-10-04")).toBe(`self-healing(auto): promote cluster ${H1} 2026-10-04`);
  });

  it("round-trips a sweep of generated hashes and dates; rejects case, whitespace and extra text", () => {
    let seed = 12345;
    const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
    for (let i = 0; i < 200; i++) {
      const h = Array.from({ length: 64 }, () => "0123456789abcdef"[Math.floor(rnd() * 16)]).join("");
      const d = `20${20 + Math.floor(rnd() * 10)}-0${1 + Math.floor(rnd() * 9)}-1${Math.floor(rnd() * 10)}`;
      const t = promotePrTitle(h, d);
      expect(PROMOTE_PR_TITLE_RE.exec(t)?.slice(1, 3)).toEqual([h, d]);
      expect(PROMOTE_PR_TITLE_RE.test(`${t} `)).toBe(false);
      expect(PROMOTE_PR_TITLE_RE.test(` ${t}`)).toBe(false);
      expect(PROMOTE_PR_TITLE_RE.test(t.toUpperCase())).toBe(false);
      expect(PROMOTE_PR_TITLE_RE.test(`${t} extra`)).toBe(false);
    }
  });

  it("LEDGER_BOT_LOGIN equals the BOT_LOGIN literal in cron-bot-pr-reaper.ts (source-read pin)", () => {
    const src = readFileSync(join(HERE, "../../server/inngest/functions/cron-bot-pr-reaper.ts"), "utf-8");
    const m = /^const BOT_LOGIN = "([^"]+)";/m.exec(src);
    expect(m, "reaper BOT_LOGIN literal not found").not.toBeNull();
    expect(LEDGER_BOT_LOGIN).toBe(m?.[1]);
  });
});

describe("readLedger", () => {
  it("zero hits -> no entries, scanned 0", async () => {
    const { octokit, calls } = fakeOctokit([[]]);
    expect(await read(octokit)).toEqual({ entries: [], scanned: 0, titleSkipped: 0 });
    expect(calls).toHaveLength(1);
    expect(calls[0]).toEqual({ route: "GET /search/issues", params: { q: Q, per_page: 100, page: 1 } });
  });

  it("maps open, merged and closed items to entries and scans the RAW count", async () => {
    const { octokit } = fakeOctokit([
      [
        item({ hash: H1 }),
        item({ hash: H2, state: "closed", merged: true, closedAt: "2026-10-05T00:00:00Z" }),
        item({ hash: hex("c"), state: "closed", closedAt: "2026-11-20T00:00:00Z" }),
      ],
    ]);
    const r = await read(octokit);
    expect(r.scanned).toBe(3);
    expect(r.entries).toEqual([
      { hash: H1, state: "open" },
      { hash: H2, state: "merged" },
      { hash: hex("c"), state: "closed", closed_at: "2026-11-20T00:00:00Z" },
    ]);
  });

  it("a hash on page 2 only is still read (the walk pages to completion)", async () => {
    const filler = Array.from({ length: 100 }, (_, i) => item({ hash: hex("0"), date: `2026-01-${String((i % 28) + 1).padStart(2, "0")}` }));
    const { octokit, calls } = fakeOctokit([filler, [item({ hash: H2 })]]);
    const r = await read(octokit);
    expect(calls.map((c) => c.params.page)).toEqual([1, 2]);
    expect(decideSuppression({ entries: r.entries, hash: H2, now: NOW })).toBe(true);
  });

  it("999 items pass; a full 10th page (1,000) throws page-cap", async () => {
    const nine = Array.from({ length: 9 }, () => mkItems(100));
    const ok = fakeOctokit([...nine, mkItems(99)]);
    expect((await read(ok.octokit)).scanned).toBe(999);
    const cap = fakeOctokit([...nine, mkItems(100)], { total_count: 1000 });
    expect(await causeOf(read(cap.octokit))).toBe("page-cap");
    expect(LEDGER_MAX_SEARCH_PAGES).toBe(10);
  });

  it("the query is bounded to the App's own PRs: a word-prefix head: alone would match other authors", () => {
    expect(Q).toContain("author:app/soleur-ai");
    expect(LEDGER_BOT_LOGIN).toBe("soleur-ai[bot]");
  });

  it("the query's head: prefix is the shared branch prefix the apply step builds on", () => {
    expect(PROMOTE_BRANCH_PREFIX).toBe("self-healing/auto-");
    // The stale-bot-PR watchdog keys on the same prefix as an independent literal: renaming one must red here.
    expect(BOT_PR_HEAD_PREFIXES).toContain(PROMOTE_BRANCH_PREFIX);
    expect(Q).toContain(`head:${PROMOTE_BRANCH_PREFIX}`);
  });

  it.each([
    ["502", { status: 502 }, "http-5xx"],
    ["a rate limit (403)", { status: 403 }, "rate-limit"],
    ["a secondary limit (429)", { status: 429 }, "rate-limit"],
    ["a 422 (the query itself rejected; page 11 is never requested)", { status: 422 }, "transport"],
    ["a bare network error", new Error("socket hang up with a body that must not be echoed"), "transport"],
  ] as const)("a search that fails with %s throws a typed error", async (_n, error, cause) => {
    const { octokit } = fakeOctokit([[]], { failOn: 1, error });
    const err = await read(octokit).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(LedgerReadError);
    expect((err as LedgerReadError).ledgerCause).toBe(cause);
    expect((err as LedgerReadError).message).not.toContain("body that must not be echoed");
  });

  it("incomplete_results, total_count over 1000, total_count over the items seen -> incomplete", async () => {
    expect(await causeOf(read(fakeOctokit([[item({})]], { incomplete_results: true }).octokit))).toBe("incomplete");
    expect(await causeOf(read(fakeOctokit([[item({})]], { total_count: 1001 }).octokit))).toBe("incomplete");
    expect(await causeOf(read(fakeOctokit([[item({})]], { total_count: 7 }).octokit))).toBe("incomplete");
  });

  it("an unparseable closed_at on a closed item -> unparseable", async () => {
    const bad = item({ state: "closed", closedAt: "not-a-date" });
    expect(await causeOf(read(fakeOctokit([[bad]]).octokit))).toBe("unparseable");
    const missing = item({ state: "closed", closedAt: null });
    expect(await causeOf(read(fakeOctokit([[missing]]).octokit))).toBe("unparseable");
  });

  it("an item without a pull_request object, or with a state other than open/closed -> unparseable (a merged PR must not degrade to a 60-day closed one)", async () => {
    const noPr = { ...item({ state: "closed", closedAt: "2026-01-01T00:00:00Z" }) } as Partial<Item>;
    delete noPr.pull_request;
    expect(await causeOf(read(fakeOctokit([[noPr as Item]]).octokit))).toBe("unparseable");
    // Everything else about this item is valid (ISO closed_at, merged_at set): only the state enum can reject it.
    const weird = { ...item({ state: "closed", closedAt: "2026-01-01T00:00:00Z", merged: true }), state: "merged" } as unknown as Item;
    expect(await causeOf(read(fakeOctokit([[weird]]).octokit))).toBe("unparseable");
  });

  it("closed_at must look like an ISO timestamp, not merely parse", async () => {
    for (const bad of ["2026", "1", "Jan 5 2026", "2026-1", "2026-01-05", "2026-11-01 00:00:00"]) {
      expect(await causeOf(read(fakeOctokit([[item({ state: "closed", closedAt: bad })]]).octokit)), bad).toBe("unparseable");
    }
  });

  it("a malformed response or item -> unparseable", async () => {
    expect(await causeOf(read(fakeOctokit([[]], { data: { items: "nope" } }).octokit))).toBe("unparseable");
    expect(await causeOf(read(fakeOctokit([[]], { data: { items: [], total_count: "3" } }).octokit))).toBe("unparseable");
    expect(await causeOf(read(fakeOctokit([[{ nope: 1 } as unknown as Item]]).octokit))).toBe("unparseable");
  });

  it("foreign-only hits (a fork or human PR on the branch prefix) read as an empty ledger, never as drift", async () => {
    const r = await read(fakeOctokit([[item({ login: "a-human" }), item({ login: "another-bot[bot]", hash: H2 })]]).octokit);
    expect(r).toEqual({ entries: [], scanned: 2, titleSkipped: 0 });
  });

  it("a foreign PR does not hide a real bot entry beside it", async () => {
    const r = await read(fakeOctokit([[item({ login: "a-human", hash: H1 }), item({ hash: H2 })]]).octokit);
    expect(r.entries).toEqual([{ hash: H2, state: "open" }]);
  });

  it("every bot PR carrying a drifted title -> drift (nothing usable is not 'nothing to suppress')", async () => {
    expect(await causeOf(read(fakeOctokit([[item({ title: `Promote ${H1}` })]]).octokit))).toBe("drift");
  });

  it("title drift on a bot PR is counted and does not suppress; with a valid sibling the read still succeeds", async () => {
    const { octokit } = fakeOctokit([[item({ title: `Promote ${H1}` }), item({ hash: H2 })]]);
    const r = await read(octokit);
    expect(r.titleSkipped).toBe(1);
    expect(r.entries).toEqual([{ hash: H2, state: "open" }]);
  });

  it("a human-authored PR with the same hash never becomes an entry", async () => {
    const { octokit } = fakeOctokit([[item({ hash: H1, login: "a-human" }), item({ hash: H2 })]]);
    const r = await read(octokit);
    expect(r.entries.map((e) => e.hash)).toEqual([H2]);
    expect(r.scanned).toBe(2);
  });

  it("a title that differs only in case or by trailing whitespace is skipped, not matched", async () => {
    const { octokit } = fakeOctokit([
      [item({ title: `${promotePrTitle(H1, "2026-10-04")} ` }), item({ title: promotePrTitle(H1, "2026-10-04").replace(H1, H1.toUpperCase()) }), item({ hash: H2 })],
    ]);
    const r = await read(octokit);
    expect(r.entries.map((e) => e.hash)).toEqual([H2]);
    expect(r.titleSkipped).toBe(2);
  });

  it("an empty-page fake cannot see a prior PR (instrument self-check: suppression depends on the read)", async () => {
    const blind = await read(fakeOctokit([[]]).octokit);
    expect(decideSuppression({ entries: blind.entries, hash: H1, now: NOW })).toBe(false);
    const seen = await read(fakeOctokit([[item({ hash: H1 })]]).octokit);
    expect(decideSuppression({ entries: seen.entries, hash: H1, now: NOW })).toBe(true);
  });
});

describe("decideSuppression (table-driven)", () => {
  const closed = (daysAgo: number, extraMs = 0): LedgerEntry => ({
    hash: H1,
    state: "closed",
    closed_at: new Date(NOW.getTime() - daysAgo * DAY - extraMs).toISOString(),
  });
  it.each<[string, LedgerEntry[], string, boolean]>([
    ["no entries", [], H1, false],
    ["open, same hash", [{ hash: H1, state: "open" }], H1, true],
    ["open, other hash", [{ hash: H2, state: "open" }], H1, false],
    ["merged, same hash", [{ hash: H1, state: "merged" }], H1, true],
    ["closed 59 days ago", [closed(59)], H1, true],
    ["closed 59.9 days ago", [closed(59, 0.9 * DAY)], H1, true],
    ["closed EXACTLY 60 days ago", [closed(60)], H1, false],
    ["closed 61 days ago", [closed(61)], H1, false],
    ["closed 61 days ago but another is open", [closed(61), { hash: H1, state: "open" }], H1, true],
    ["a later entry is the one that matters (mixed order)", [{ hash: H2, state: "open" }, closed(10), closed(90)], H1, true],
    ["closed in the future (clock skew) fails closed", [closed(-3)], H1, true],
    ["unparseable closed_at on a hand-built entry fails closed", [{ hash: H1, state: "closed", closed_at: "garbage" }], H1, true],
  ])("%s", (_n, entries, hash, expected) => {
    expect(decideSuppression({ entries, hash, now: NOW })).toBe(expected);
  });

  it("suppression is the EXACT hash: hashes differing only in the last character do not suppress each other", () => {
    const near = H1.slice(0, 63) + "b";
    expect(near).not.toBe(H1);
    expect(decideSuppression({ entries: [{ hash: near, state: "open" }], hash: H1, now: NOW })).toBe(false);
    expect(decideSuppression({ entries: [{ hash: H1, state: "open" }], hash: near, now: NOW })).toBe(false);
  });

  it("an unusable clock (Invalid Date) fails closed for a matching closed entry and never suppresses a non-matching one", () => {
    const bad = new Date("not-a-date");
    expect(decideSuppression({ entries: [closed(120)], hash: H1, now: bad })).toBe(true);
    expect(decideSuppression({ entries: [closed(120)], hash: H2, now: bad })).toBe(false);
  });

  it("the TTL constant is 60 days", () => {
    expect(LEDGER_TTL_DAYS).toBe(60);
  });
});
