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
  readMs: 10,
  totalMs: 400,
  probeMs: 50,
  reloadMs: 30,
} as const;

/** Minimal railRow locator: only isVisible(), scripted per call. */
function fakeRailRow(opts: {
  seq?: boolean[];
  err?: Error | Error[];
  throwAfter?: { at: number; err: Error };
  throwWhen?: () => Error | null;
  visibleWhen?: (calls: number) => boolean;
  hang?: boolean;
  hangWhen?: () => boolean;
}) {
  let i = 0;
  let calls = 0;
  const errs = Array.isArray(opts.err) ? opts.err : opts.err ? [opts.err] : null;
  const railRow = {
    isVisible: async (): Promise<boolean> => {
      calls++;
      if (opts.hang || opts.hangWhen?.()) return new Promise<boolean>(() => {});
      const te = opts.throwWhen?.();
      if (te) throw te;
      if (opts.throwAfter && calls > opts.throwAfter.at) throw opts.throwAfter.err;
      if (errs && i < errs.length) {
        i++;
        throw errs[i - 1];
      }
      if (errs && !Array.isArray(opts.err)) throw errs[0];
      // The call count is passed so a predicate can key visibility to the
      // Nth READ, not to elapsed wall-clock — deterministic under CI jitter
      // where a timed seq's index drifts with event-loop stalls.
      if (opts.visibleWhen) return opts.visibleWhen(calls);
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
  countsThrow?: boolean;
  reloadCalls?: { n: number };
  reloadErr?: Error;
  reloadHang?: boolean;
  reloadNav?: { status(): number; url(): string };
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
    if (opts.countsThrow) throw new Error("renderer wedged");
    const rc = opts.railCounts ?? {};
    if (sel.includes("conversations-rail-error")) return rc.error ?? 0;
    if (sel.includes("conversations-rail-empty")) return rc.empty ?? 0;
    if (sel.includes("a[href")) return rc.rows ?? 0;
    if (sel === '[data-testid="conversations-rail"]') return rc.rail ?? 0;
    return 0;
  };
  const recordedGetUrls: string[] = [];
  const reloadArgs: ({ waitUntil?: string; timeout?: number } | undefined)[] = [];
  return {
    url: () => "https://app.example.com/dashboard/chat/new",
    title: async () => "Soleur",
    getByRole: (_role: string) => ({
      count: async () => 1,
      first: () => ({ isVisible: async () => true }),
    }),
    locator: (sel: string) => ({ count: async () => counts(sel) }),
    reload: async (arg?: { waitUntil?: string; timeout?: number }) => {
      counters.n++;
      reloadArgs.push(arg);
      if (opts.reloadHang) return new Promise<never>(() => {});
      if (opts.reloadErr) throw opts.reloadErr;
      return opts.reloadNav ?? null;
    },
    recordedGetUrls,
    reloadArgs,
    request: {
      get: async (url: string) => {
        recordedGetUrls.push(url);
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
  } as unknown as Parameters<typeof assertRailRowVisible>[0]["page"] &
    {
      recordedGetUrls: string[];
      reloadArgs: ({ waitUntil?: string; timeout?: number } | undefined)[];
    };
}

/** Fake supabase whose .rpc resolves PostgREST's {data, error} shape. */
function fakeSupabase(behavior: {
  data?: unknown;
  error?: { message?: string; code?: string; name?: string };
  throws?: Error;
  calls?: { n: number };
  rpcCalls?: { fn: string; args: Record<string, unknown> }[];
}) {
  const counters = behavior.calls ?? { n: 0 };
  const rpcCalls = behavior.rpcCalls ?? [];
  return {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      counters.n++;
      rpcCalls.push({ fn, args });
      if (behavior.throws) throw behavior.throws;
      return { data: behavior.data ?? [], error: behavior.error ?? null };
    },
    rpcCalls,
  } as unknown as Parameters<typeof assertRailRowVisible>[0]["supabase"] &
    { rpcCalls: { fn: string; args: Record<string, unknown> }[] };
}

const nav = () => ({ status: () => 200 });

function deps(over: {
  seq?: boolean[];
  railRowErr?: Error | Error[];
  throwAfter?: { at: number; err: Error };
  throwWhen?: () => Error | null;
  visibleWhen?: (calls: number) => boolean;
  hang?: boolean;
  hangWhen?: () => boolean;
  page?: ReturnType<typeof fakePage>;
  supabase?: ReturnType<typeof fakeSupabase>;
  budget?: { [K in keyof typeof FAST]: number };
}) {
  const row = fakeRailRow({
    seq: over.seq,
    err: over.railRowErr,
    throwAfter: over.throwAfter,
    throwWhen: over.throwWhen,
    visibleWhen: over.visibleWhen,
    hang: over.hang,
    hangWhen: over.hangWhen,
  });
  return {
    seam: {
      railRow: row.railRow,
      page: over.page ?? fakePage({}),
      nav: nav(),
      supabase: over.supabase ?? fakeSupabase({ data: [{ id: CONV_ID }] }),
      convId: CONV_ID,
      productionUrl: "https://app.example.com",
      budget: { ...(over.budget ?? FAST) },
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
    const rpcCalls = { n: 0 };
    const { seam, row } = deps({
      // Call-count keyed, not wall-clock: the row lands on the third READ
      // regardless of event-loop jitter (a timed seq's index would drift
      // under CI contention and flip this to via=reload + reloadCalls=1).
      visibleWhen: (n) => n >= 3,
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ calls: rpcCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "appeared", via: "direct" });
    expect(row.stats().calls).toBe(3);
    expect(reloadCalls.n).toBe(0);
    // An early PASS never reaches the scope probe.
    expect(rpcCalls.n).toBe(0);
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

  it("passes reload the MANDATORY bounded options — an explicit waitUntil and a positive timeout", async () => {
    // Playwright's .d.ts documents a default timeout of 0 (unbounded) — a
    // mutation dropping `timeout: reloadMs` or `waitUntil` is the exact
    // defect RAIL_RELOAD_TIMEOUT_MS exists to prevent, and a fake that
    // ignores its args cannot see it.
    const page = fakePage({});
    const { seam } = deps({ seq: [false], page });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(page.reloadArgs).toHaveLength(1);
    expect(page.reloadArgs[0]).toMatchObject({ waitUntil: "domcontentloaded" });
    expect(page.reloadArgs[0]?.timeout).toBe(FAST.reloadMs);
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

  it("resolves rpc_row=no when the list is populated but THIS id is absent — membership, not emptiness", async () => {
    // `data: []` returns "no" for ANY membership predicate — a mutation to
    // `data.length > 0` would stay green. A populated list missing convId
    // is the discriminating fixture.
    const OTHER_ID = "99999999-8888-4777-8666-111111111111";
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ data: [{ id: OTHER_ID }, { id: OTHER_ID }] }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "absent", rpcRow: "no" });
    expect(reloadCalls.n).toBe(0);
  });

  it("probes the rail's OWN data path — active-repo endpoint and the enriched RPC with rail-parity args", async () => {
    // The discriminator's whole value is scope parity with the rail's SWR
    // fetch. Fakes that ignore their args can't pin it — record and assert.
    const page = fakePage({});
    const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
    const { seam } = deps({
      seq: [false],
      page,
      supabase: fakeSupabase({ data: [{ id: CONV_ID }], rpcCalls }),
    });
    await assertRailRowVisible(seam);
    expect(page.recordedGetUrls[0]).toMatch(/\/api\/workspace\/active-repo$/);
    expect(rpcCalls).toHaveLength(1);
    expect(rpcCalls[0]?.fn).toBe("list_conversations_enriched");
    expect(rpcCalls[0]?.args).toMatchObject({
      p_repo_url: "https://example.invalid/repo",
      p_workspace_id: WS_ID,
      p_archive: "active",
      p_status: null,
      p_domain: null,
      p_limit: 15,
    });
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
    expect(v).toMatchObject({ rpcRow: "n/a:repo-null" });
    expect(reloadCalls.n).toBe(0);
    expect(rpcCalls.n).toBe(0);
  });

  it("FAIL-fasts when workspaceId resolves null — a null scope is out-of-scope, tagged honestly", async () => {
    const reloadCalls = { n: 0 };
    const rpcCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({
        reloadCalls,
        activeRepo: { ok: true, body: { workspaceId: null, repoUrl: "https://example.invalid/repo" } },
      }),
      supabase: fakeSupabase({ calls: rpcCalls }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(v).toMatchObject({ rpcRow: "n/a:workspace-null" });
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
    expect(line).toContain("active_repo=resolved");
    expect(line).toContain("read_errors=");
    expect(line).toContain("budget=");
    expect(line).toContain("elapsed=");
    expect(reloadCalls.n).toBe(1);
  });

  it("tags an unreadable active-repo probe with the HTTP status, or bare on transport failure", async () => {
    for (const [fixture, tag] of [
      [{ ok: false, status: 503 } as const, "unreadable:active-repo:503"],
      [{ throws: new Error("socket reset") } as const, "unreadable:active-repo"],
    ] as const) {
      const reloadCalls = { n: 0 };
      const { seam } = deps({
        seq: [false],
        page: fakePage({ reloadCalls, activeRepo: fixture }),
      });
      const v = await assertRailRowVisible(seam);
      expect(v.kind).toBe("absent");
      expect(v).toMatchObject({ rpcRow: tag, activeRepo: "unreadable" });
      expect(reloadCalls.n).toBe(1);
    }
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
    // The tag carries the PostgREST code — `unreadable:` alone would let a
    // name-preferred or dropped-tag mutation stay green.
    expect(v).toMatchObject({ rpcRow: "unreadable:57014" });
    expect(reloadCalls.n).toBe(1);
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toContain("rpc_row=unreadable:57014");
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
    expect(v).toMatchObject({ reloads: 1 });
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toContain("reload_err=TimeoutError");
  });

  it("maps the name-only arm (TargetClosedError name, unrelated message) to CANT-RUN", async () => {
    // Arm 1 of CLOSED_TARGET_RE (target.{0,30}closed) must work ALONE — the
    // other tests' messages all contain "has been closed" and would mask a
    // deleted arm 1.
    const closed = new Error("socket hangup");
    closed.name = "TargetClosedError";
    const { seam } = deps({ railRowErr: closed });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
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

  it("maps page death AFTER a clean read to CANT-RUN via the dead classification — not absent", async () => {
    // First read resolves clean (sawCleanRead=true), then the page dies.
    // The `dead` arm — not the `!sawCleanRead` backstop — must produce this
    // verdict, or a crashed browser emits BLOCK=1 FAIL for a rail it could
    // never have rendered.
    const closed = new Error("Target page, context or browser has been closed");
    const { seam } = deps({
      seq: [false],
      throwAfter: { at: 1, err: closed },
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
  });

  it("maps a crash-class message (Playwright's real strings) to CANT-RUN", async () => {
    // "Navigation failed because page crashed!" / "Page crashed" /
    // "Target crashed" are the vendor's crash messages — none contain
    // "closed". Name is plain "Error" (client-side TargetClosedError
    // doesn't set .name either).
    const { seam } = deps({
      railRowErr: new Error("Navigation failed because page crashed!"),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
  });

  it("maps a closed-target throw from page.reload to CANT-RUN", async () => {
    const reloadCalls = { n: 0 };
    const closed = new Error("Target page, context or browser has been closed");
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls, reloadErr: closed }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
  });

  it("treats `execution context was destroyed` as a missed tick, not page death — it is the retriable navigation race", async () => {
    const navRace = new Error(
      "Execution context was destroyed, most likely because of a navigation",
    );
    // Two nav-race throws, then the locator resolves visible — the verdict
    // must be appeared, not unverifiable.
    const { seam } = deps({
      railRowErr: [navRace, navRace],
      visibleWhen: () => true,
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({ kind: "appeared", via: "direct" });
  });

  it("a wedged renderer (isVisible never settles) cannot out-wait the budget — the read is bounded, the verdict unverifiable", async () => {
    // Fixture the HANG, not only the rejection: an unbounded isVisible()
    // would stall past every deadline and emit NO RESULT line at all —
    // the workflow then escalates the absence to BLOCK=1 with zero
    // diagnostics, worse than the FAIL the seam replaced.
    const started = Date.now();
    const { seam } = deps({ hang: true });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
    expect(Date.now() - started).toBeLessThan(FAST.totalMs + 500);
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toMatch(/^RESULT: CANT-RUN:/);
  });

  it("a malformed RPC payload (non-array data) reads unreadable:shape — never a false rpc_row=no fail-fast", async () => {
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ data: { bogus: true } }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("absent");
    expect(v).toMatchObject({ rpcRow: "unreadable:shape" });
    expect(reloadCalls.n).toBe(1);
  });

  it("guarantees phase B a full observe window — probe/reload latency cannot starve it", async () => {
    // The mutation this pins: `pollWindow(totalDeadline, "reload")` lets
    // phase B extend past `phaseBStart + observeMs`; with the floor, a row
    // landing BETWEEN the floor deadline and the ceiling stays absent.
    // Budgets: observe=80, probes ~4ms each, reload ~4ms -> phase B starts
    // ~90ms in, floor ends ~170ms, ceiling 1000ms. Row lands at ~300ms —
    // inside a starved-extended window, outside the floored one.
    const marker = { at: 0 };
    const { seam } = deps({
      visibleWhen: () => marker.at !== 0 && Date.now() >= marker.at,
      budget: { observeMs: 80, pollMs: 2, readMs: 10, totalMs: 1000, probeMs: 60, reloadMs: 60 },
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
    });
    const pending = assertRailRowVisible(seam);
    marker.at = Date.now() + 300;
    const v = await pending;
    expect(v.kind).toBe("absent");
  });

  it("a reload wedged at the driver level (past its own timeout) yields the __wedge__ draw — then absent on settled reads", async () => {
    // page.reload's `timeout` bounds the navigation; a wedged CDP transport
    // cannot even fire it. The manual race's backstop (reloadMs + 5s —
    // 5035ms under FAST) records `reload-unbounded-wedge` and keeps polling:
    // with a ceiling that still leaves phase B headroom, the settled reads
    // keep the absent verdict honest.
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      seq: [false],
      page: fakePage({ reloadCalls, reloadHang: true }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
      // ~5s of wedge backstop + observe windows still inside the ceiling.
      budget: { ...FAST, totalMs: 6_000 },
    });
    const v = await assertRailRowVisible(seam);
    expect(v).toMatchObject({
      kind: "absent",
      reloadErr: "reload-unbounded-wedge",
    });
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toContain("reload_err=reload-unbounded-wedge");
  });

  it("a wedged post-reload read stream — reload ran but NO post-reload read settled — is CANT-RUN, not FAIL", async () => {
    // `absent` would assert "did not appear" on reads that never executed
    // in the window that counted. Phase A produced clean reads, so the
    // `!sawCleanRead` net alone cannot catch this — the post-reload
    // clean-read requirement does.
    const reloadCalls = { n: 0 };
    const { seam } = deps({
      hangWhen: () => reloadCalls.n > 0,
      page: fakePage({ reloadCalls }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
    const line = emitLine(railVerdictToResult(v, CONV_ID));
    expect(line).toMatch(/^RESULT: CANT-RUN:/);
    expect(line).toContain("read_errors=");
  });

  it("a post-reload CANT-RUN reports the RELOAD's navigation, not the stale pre-send one", async () => {
    const reloadCalls = { n: 0 };
    const reNav = {
      status: () => 503,
      url: () => "https://app.example.com/dashboard/chat/new",
    };
    const closed = new Error("Target page, context or browser has been closed");
    const { seam } = deps({
      throwWhen: () => (reloadCalls.n > 0 ? closed : null),
      page: fakePage({ reloadCalls, reloadNav: reNav }),
      supabase: fakeSupabase({ data: [{ id: CONV_ID }] }),
    });
    const v = await assertRailRowVisible(seam);
    expect(v.kind).toBe("unverifiable");
    if (v.kind === "unverifiable") expect(v.reason).toContain("http=503");
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
    // A thrown-but-recovered reload annotates the PASS — the anomaly rides
    // the wire, it isn't dropped as a "clean" draw.
    const appearedWithWedge = emitLine(
      railVerdictToResult(
        {
          kind: "appeared",
          via: "reload",
          elapsedMs: 55_000,
          checks: 40,
          reloadErr: "TimeoutError",
        },
        CONV_ID,
      ),
    );
    expect(appearedWithWedge).toContain("reload_err=TimeoutError");
    const absent = emitLine(
      railVerdictToResult(
        {
          kind: "absent",
          checks: 90,
          readErrs: 0,
          reloads: 1,
          elapsedMs: 95_000,
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

  it("reports unreadable when a count probe throws — never a misleading rows:K", async () => {
    const page = fakePage({ countsThrow: true });
    expect(await railRowState(page)).toBe("unreadable");
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
