import { describe, expect, it } from "vitest";

import {
  RAIL_ASSERT_TOTAL_BUDGET_MS,
  assertRailRowVisible,
  emitLine,
  railRowState,
  railVerdictToResult,
} from "../../scripts/live-verify/run";

// #9581. The rail assertion was a single `railRow.waitFor({timeout: 20_000})`
// with no retry and no reload: any rail-listing lag longer than 20s on prod —
// a realtime pre-SUBSCRIBED miss, the rail's own bounded event-retry
// exhausting, or a slow RPC — read as a blocking RESULT: FAIL even though the
// conversation was committed (observed: run 37426735876, web-v0.323.2).
//
// These cases pin the observe -> scope-probe -> one reload -> observe seam:
// the recovery path is MEASURED (via=/elapsed= land in the RESULT detail), the
// scope probe separates "data late" from "out of scope" (rpc_row=no fails
// fast WITHOUT burning the reload), and a row that never appears still FAILs.

const CONV_ID = "11111111-2222-4333-8444-555555555555";
const WS_ID = "66666666-7777-4888-8999-000000000000";

const FAST = {
  observeMs: 60,
  pollMs: 2,
  totalMs: 400,
  probeMs: 50,
  reloadMs: 30,
} as const;

/** Minimal railRow locator: only isVisible(), scripted per call. */
function fakeRailRow(opts: {
  seq?: boolean[];
  err?: Error;
  visibleWhen?: () => boolean;
}) {
  let i = 0;
  let calls = 0;
  const railRow = {
    isVisible: async () => {
      calls++;
      if (opts.err) throw opts.err;
      if (opts.visibleWhen) return opts.visibleWhen();
      const seq = opts.seq ?? [false];
      const v = seq[Math.min(i, seq.length - 1)];
      i++;
      return v;
    },
  };
  return { railRow, stats: () => ({ calls }) };
}

/** Minimal Page stand-in: every surface the seam + its diagnostics touch. */
function fakePage(opts: {
  railCounts?: { error?: number; empty?: number; rail?: number; rows?: number };
  reloadCalls?: { n: number };
  reloadErr?: Error;
  activeRepo?:
    | { ok: true; body: unknown }
    | { ok: false; status: number }
    | { throws: Error };
}) {
  const counters = opts.reloadCalls ?? { n: 0 };
  // One keyed count per probe the harness makes: error branch, empty branch,
  // the rows anchor map, the rail wrapper itself. The rows selector contains
  // the wrapper selector verbatim, so a substring scan would misattribute —
  // disambiguate on the trailing `a[href` instead.
  const counts = (sel: string): number => {
    const rc = opts.railCounts ?? {};
    if (sel.includes("conversations-rail-error")) return rc.error ?? 0;
    if (sel.includes("conversations-rail-empty")) return rc.empty ?? 0;
    if (sel.includes("a[href")) return rc.rows ?? 0;
    if (sel === '[data-testid="conversations-rail"]') return rc.rail ?? 0;
    return 0;
  };
  return {
    url: () => "https://app.example.com/dashboard/chat/new",
    title: async () => "Soleur",
    getByRole: (_role: string) => ({
      count: async () => 1,
      first: () => ({ isVisible: async () => true }),
    }),
    locator: (sel: string) => ({ count: async () => counts(sel) }),
    reload: async () => {
      counters.n++;
      if (opts.reloadErr) throw opts.reloadErr;
      return null;
    },
    request: {
      get: async () => {
        const r = opts.activeRepo ?? {
          ok: true as const,
          body: { workspaceId: WS_ID, repoUrl: "https://example.invalid/repo" },
        };
        if ("throws" in r) throw r.throws;
        if (!r.ok) {
          return { ok: () => false, status: () => r.status, json: async () => null };
        }
        return { ok: () => true, status: () => 200, json: async () => r.body };
      },
    },
  } as unknown as Parameters<typeof assertRailRowVisible>[0]["page"];
}

/** Fake supabase whose .rpc resolves PostgREST's {data, error} shape. */
function fakeSupabase(behavior: {
  data?: unknown[];
  error?: { message?: string; code?: string; name?: string };
  throws?: Error;
  calls?: { n: number };
}) {
  const counters = behavior.calls ?? { n: 0 };
  return {
    rpc: async () => {
      counters.n++;
      if (behavior.throws) throw behavior.throws;
      return { data: behavior.data ?? [], error: behavior.error ?? null };
    },
  } as unknown as Parameters<typeof assertRailRowVisible>[0]["supabase"];
}

const nav = () => ({ status: () => 200 });

function deps(over: {
  seq?: boolean[];
  railRowErr?: Error;
  visibleWhen?: () => boolean;
  page?: ReturnType<typeof fakePage>;
  supabase?: ReturnType<typeof fakeSupabase>;
}) {
  const row = fakeRailRow({
    seq: over.seq,
    err: over.railRowErr,
    visibleWhen: over.visibleWhen,
  });
  return {
    seam: {
      railRow: row.railRow,
      page: over.page ?? fakePage({}),
      nav: nav(),
      supabase: over.supabase ?? fakeSupabase({ data: [{ id: CONV_ID }] }),
      convId: CONV_ID,
      productionUrl: "https://app.example.com",
      budget: { ...FAST },
    },
    row,
  };
}

describe("assertRailRowVisible (#9581) — the observe arm", () => {
  it("returns appeared via=direct on the first tick and never reloads", async () => {
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      seq: [true],
      page: fakePage({ reloadCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "appeared", via: "direct" });
    expect(reloadCalls.n).toBe(0);
  });

  it("returns appeared via=direct when the row lands inside the observe window", async () => {
    const reloadCalls = { n: 0 };
    const { seam, row } = deps({
      seq: [false, false, true],
      page: fakePage({ reloadCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "appeared", via: "direct" });
    expect(row.stats().calls).toBe(3);
    expect(reloadCalls.n).toBe(0);
  });

  it("returns appeared via=reload when the row lands only after the reload draw", async () => {
    const reloadCalls = { n: 0 };
    // Deterministic: isVisible() flips true only once page.reload() ran —
    // no timing arithmetic in the fixture.
    const { seam } = deps({
      visibleWhen: () => reloadCalls.n > 0,
      page: fakePage({ reloadCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "appeared", via: "reload" });
    // A guard reporting "0 recoveries exercised" and passing is vacuous —
    // the suite must observe the draw itself.
    expect(reloadCalls.n).toBe(1);
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toContain("via=reload");
    expect(line).toContain("elapsed=");
  });

  it("attributes a row that lands during the scope probe to via=direct — not to the reload it never needed", async () => {
    const reloadCalls = { n: 0 };
    const rpcCalls = { n: 0 };
    const { seam } = deps({
      // The row appears only once the RPC probe has run — modeling the app's
      // own delivery arms landing it during the probe window.
      visibleWhen: () => rpcCalls.n > 0,
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }], calls: rpcCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "appeared", via: "direct" });
    expect(reloadCalls.n).toBe(0);
  });
});

describe("assertRailRowVisible (#9581) — the discriminator", () => {
  it("FAIL-fasts on rpc_row=no WITHOUT burning the reload (scope-broken is a regression, not lag)", async () => {
    const reloadCalls = { n: 0 };
    const rpcCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ data: [], calls: rpcCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(v).toMatchObject({ rpcRow: "no" });
    expect(rpcCalls.n).toBe(1);
    expect(reloadCalls.n).toBe(0);
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toMatch(/^RESULT: FAIL —/);
    expect(line).toContain("rpc_row=no");
  });

  it("FAIL-fasts when the resolved repoUrl is null (a repo-less rail cannot be helped by a reload)", async () => {
    const reloadCalls = { n: 0 };
    const rpcCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({
        reloadCalls,
        activeRepo: { ok: true, body: { workspaceId: WS_ID, repoUrl: null } },
      }),
      supabase: fakeSupabase({ calls: rpcCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(reloadCalls.n).toBe(0);
    expect(rpcCalls.n).toBe(0);
  });

  it("still FAILs — honestly — when the row is in scope (rpc_row=yes) but never renders", async () => {
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({
        reloadCalls,
        railCounts: { rail: 1, rows: 4 },
      }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toMatch(/^RESULT: FAIL —/);
    expect(line).toContain("rpc_row=yes");
    expect(line).toContain("rail_state=rows:4");
    expect(line).toContain("reloads=1");
    expect(reloadCalls.n).toBe(1);
  });

  it("treats an unreadable probe as a diagnostic, not a verdict — the reload still runs", async () => {
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ error: { message: "statement timeout", code: "57014" } }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(v).toMatchObject({ rpcRow: expect.stringContaining("unreadable") });
    expect(reloadCalls.n).toBe(1);
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toContain("rpc_row=unreadable:");
  });

  it("records reload_err but keeps polling — a thrown reload is not verdict material", async () => {
    const reloadCalls = { n: 0 };
    const navTimeout = new Error("page.reload: Timeout 30000ms exceeded");
    navTimeout.name = "TimeoutError";
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls, reloadErr: navTimeout }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toContain("reload_err=TimeoutError");
  });

  it("maps a dead page (target-closed) to CANT-RUN — never to a rail-regression FAIL", async () => {
    const closed = new Error("Target page, context or browser has been closed");
    closed.name = "TargetClosedError";
    const { seam } = deps({ railRowErr: closed });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toMatch(/^RESULT: CANT-RUN:/);
    expect(line).toContain("rail-check:");
  });
});

describe("railVerdictToResult (#9581) — the wire shape", () => {
  it("emits only the three RESULT prefixes the workflow classifier parses", () => {
    const appeared = emitLine(
      railVerdictToResult(
        { kind: "appeared", via: "direct", elapsedMs: 1234, checks: 1 },
        CONV_ID,
      ),
    );
    const absent = emitLine(
      railVerdictToResult(
        {
          kind: "absent",
          checks: 90,
          reloads: 1,
          railState: "empty",
          rpcRow: "yes",
          activeRepo: "resolved",
          budgetMs: RAIL_ASSERT_TOTAL_BUDGET_MS,
        },
        CONV_ID,
      ),
    );
    const dead = emitLine(
      railVerdictToResult(
        { kind: "unverifiable", reason: "rail-check:rail-not-visible path=/dashboard/chat/new" },
        CONV_ID,
      ),
    );
    expect(appeared).toMatch(/^RESULT: PASS —/);
    expect(absent).toMatch(/^RESULT: FAIL —/);
    expect(dead).toMatch(/^RESULT: CANT-RUN:/);
    for (const l of [appeared, absent, dead]) {
      expect(l).toMatch(/^RESULT: (PASS —|FAIL —|CANT-RUN:)/);
    }
  });

  it("carries via= in BOTH pass arms — an unmeasured recovery is the defect", () => {
    for (const via of ["direct", "reload"] as const) {
      const line = emitLine(
        railVerdictToResult(
          { kind: "appeared", via, elapsedMs: 500, checks: 3 },
          CONV_ID,
        ),
      );
      expect(line).toContain(`via=${via}`);
      expect(line).toContain("elapsed=");
      expect(line).toContain("checks=");
    }
  });
});

describe("railRowState (#9581) — which branch the rail was showing", () => {
  it("reports error when the error branch rendered", async () => {
    const page = fakePage({ railCounts: { error: 1 } });
    expect(await railRowState(page)).toBe("error");
  });

  it("reports empty when the empty-state branch rendered", async () => {
    const page = fakePage({
      railCounts: { empty: 1 },
    });
    expect(await railRowState(page)).toBe("empty");
  });

  it("reports rows:K when K anchors render", async () => {
    const page = fakePage({
      railCounts: { rail: 1, rows: 3 },
    });
    expect(await railRowState(page)).toBe("rows:3");
  });

  it("reports rail-absent when the wrapper testid is gone", async () => {
    const page = fakePage({ railCounts: {} });
    expect(await railRowState(page)).toBe("rail-absent");
  });
});

describe("budget ceiling (#9581)", () => {
  it("names ONE total ceiling, larger than the 20s single-wait it replaces", () => {
    expect(RAIL_ASSERT_TOTAL_BUDGET_MS).toBeGreaterThanOrEqual(90_000);
  });

  it("cannot out-wait its own budget even when isVisible stays false", async () => {
    const started = Date.now();
    const { seam } = deps({ seq: [false] });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(Date.now() - started).toBeLessThan(FAST.totalMs + 500);
  });
});
