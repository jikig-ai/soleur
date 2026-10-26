import { beforeEach, describe, expect, it, vi } from "vitest";

// #9545 PR2 — server loader for the egress audit view and the card hint. The RPC (migration 177) is
// the only authz gate: the loader's own jobs are (1) take the workspace id ONLY from the fail-loud
// reader, never from request input, (2) never call the RPC when that read fails, (3) map outcomes to a
// tagged result so an error is never rendered as an empty log, (4) mirror faults with reason codes in
// `op` and a static message (err = null), never mirror the in-body 42501 denial, and tell it apart from
// the engine's own 42501 (a lost grant), (5) report a Flagsmith outage as `unknown`, never as `off`.
//
// The real database behaviour (membership, tenant filter, aggregation) is in
// test/rls-fuzz/egress-audit-rollup.integration.test.ts; mocked clients cannot prove it.

const h = vi.hoisted(() => ({
  readWorkspaceIdFromDb: vi.fn(),
  readEgressAuditCollectionState: vi.fn(),
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

vi.mock("@/server/workspace-resolver", () => ({ readWorkspaceIdFromDb: h.readWorkspaceIdFromDb }));
vi.mock("@/server/egress-audit-collection", () => ({ readEgressAuditCollectionState: h.readEgressAuditCollectionState }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: h.reportSilentFallback,
  mirrorWarnWithDebounce: h.mirrorWarnWithDebounce,
}));

import { EGRESS_AUDIT_READ_FEATURE, loadEgressAudit, loadEgressCardState } from "@/server/egress-audit-read";

const WS = "11111111-1111-4111-8111-111111111111";
const ORG = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";

const payload = (over: Record<string, unknown> = {}) => ({
  window: { start: "2026-09-26T00:00:00Z", end: "2026-10-26T00:00:00Z" },
  truncated: false,
  summary: { request_count_min: 21, blocked_request_count_min: 4, last_request_at: "2026-10-26T12:00:00Z" },
  rows: [{ host: "a.example.test", decision: "allowed", request_count: 15, last_seen: "2026-10-26T12:00:00Z" }],
  overflow: [],
  ...over,
});

type RpcReply = { data: unknown; error: null | { code?: string; message?: string; name?: string } };
type ReplySource = RpcReply | (() => RpcReply | Promise<RpcReply>);

// supabase-js query builder stand-in: thenable, with abortSignal() like the real PostgREST builder.
const builder = (reply: ReplySource) => {
  const run = async () => (typeof reply === "function" ? reply() : reply);
  const b: { abortSignal: () => unknown; then: PromiseLike<RpcReply>["then"] } = {
    abortSignal: () => b,
    then: (res, rej) => run().then(res, rej),
  };
  return b;
};

function client(opts: { summary?: ReplySource; webEgress?: ReplySource; workspaceRow?: ReplySource }) {
  const rpc = vi.fn((fn: string) => {
    if (fn === "get_egress_audit_summary") return builder(opts.summary ?? { data: payload(), error: null });
    if (fn === "get_workspace_web_egress") return builder(opts.webEgress ?? { data: true, error: null });
    throw new Error(`unexpected rpc ${fn}`);
  });
  const from = vi.fn((table: string) => {
    if (table !== "workspaces") throw new Error(`unexpected table ${table}`);
    const chain = {
      select: () => chain,
      eq: () => chain,
      maybeSingle: () => builder(opts.workspaceRow ?? { data: { organization_id: ORG, name: "Acme" }, error: null }),
    };
    return chain;
  });
  return { rpc, from } as never;
}

type Spied = { rpc: ReturnType<typeof vi.fn>; from: ReturnType<typeof vi.fn> };
const spied = (c: unknown) => c as Spied;
const rpcArgs = (c: unknown, fn: string) => spied(c).rpc.mock.calls.filter((call) => call[0] === fn).map((call) => call[1]);

const faults = () => h.reportSilentFallback.mock.calls.map((c) => c[1] as { feature: string; op: string; message: string; tags?: Record<string, string> });
const warns = () => h.mirrorWarnWithDebounce.mock.calls.map((c) => c[1] as { feature: string; op: string; message: string; tags?: Record<string, string> });
const neverRpc = (): Promise<RpcReply> => new Promise<RpcReply>(() => {});

beforeEach(() => {
  vi.clearAllMocks();
  h.readWorkspaceIdFromDb.mockResolvedValue(WS);
  h.readEgressAuditCollectionState.mockResolvedValue(true);
});

describe("loadEgressAudit: pointer", () => {
  it("exports the Sentry feature tag the alert rule filters on", () => {
    expect(EGRESS_AUDIT_READ_FEATURE).toBe("egress-audit-read");
  });

  it("an absent workspace pointer is `unbound` and the RPC is never called", async () => {
    h.readWorkspaceIdFromDb.mockResolvedValue(null);
    const c = client({});
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unbound" });
    expect(spied(c).rpc).not.toHaveBeenCalled();
  });

  it("a throwing pointer read is `unavailable`, mirrored once as a paged workspace_read_error, and the RPC is never called", async () => {
    h.readWorkspaceIdFromDb.mockRejectedValue(new Error("db down"));
    const c = client({});
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(spied(c).rpc).not.toHaveBeenCalled();
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = h.reportSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({ feature: "egress-audit-read", op: "workspace_read_error" });
    expect(JSON.stringify(opts)).not.toContain(WS);
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("a pointer read that outlives its 2 s bound is `unavailable` with a paged workspace_read_error, and the RPC is never called", async () => {
    vi.useFakeTimers();
    try {
      h.readWorkspaceIdFromDb.mockReturnValue(new Promise(() => {}));
      const c = client({});
      const p = loadEgressAudit(c, USER, "all");
      await vi.advanceTimersByTimeAsync(1_999);
      expect(h.reportSilentFallback).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toEqual({ kind: "unavailable" });
      expect(spied(c).rpc).not.toHaveBeenCalled();
      expect(faults()).toHaveLength(1);
      expect(faults()[0]).toMatchObject({ op: "workspace_read_error", message: "egress audit read: current workspace pointer read timed out" });
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("loadEgressAudit: 42501 discrimination", () => {
  it.each([
    ["membership", "egress audit: workspace membership required"],
    ["revoked token", "egress audit: token denied"],
  ])("the RPC's in-body %s denial is `forbidden` and is NOT mirrored", async (_label, message) => {
    const c = client({ summary: { data: null, error: { code: "42501", message } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "forbidden" });
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("the engine's own 42501 (a lost grant) is `unavailable` with exactly one paged rpc_error tagged pg_code=42501", async () => {
    const c = client({ summary: { data: null, error: { code: "42501", message: "permission denied for function get_egress_audit_summary" } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(faults()).toHaveLength(1);
    expect(faults()[0]).toMatchObject({
      feature: "egress-audit-read",
      op: "rpc_error",
      message: "egress audit read: summary call was refused by the database",
      tags: { pg_code: "42501" },
    });
    expect(h.reportSilentFallback.mock.calls[0][0]).toBeNull();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it.each([
    ["a message that is not the RPC's", { code: "42501", message: "x" }],
    ["no message", { code: "42501" }],
    ["a prefix that only appears mid-message", { code: "42501", message: "denied: egress audit: workspace membership required" }],
    ["the right message with a different SQLSTATE", { code: "P0001", message: "egress audit: workspace membership required" }],
  ])("42501 with %s is a fault: `unavailable` plus one paged mirror", async (_label, error) => {
    const c = client({ summary: { data: null, error } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(faults()).toHaveLength(1);
    expect(faults()[0].op).toBe("rpc_error");
  });
});

describe("loadEgressAudit: RPC faults", () => {
  it("any other RPC error is `unavailable` and mirrored with op rpc_error, err null, a static message and the pg_code tag", async () => {
    const c = client({ summary: { data: null, error: { code: "XX000", message: "boom for workspace " + WS } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = h.reportSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({ feature: "egress-audit-read", op: "rpc_error", message: "egress audit read: summary call failed", tags: { pg_code: "XX000" } });
    expect(JSON.stringify(opts)).not.toContain(WS);
  });

  it("pg_code is low-cardinality: PostgREST codes pass, an absent code is `none`, anything else is `other`", async () => {
    const tagFor = async (error: { code?: string; message?: string }) => {
      h.reportSilentFallback.mockClear();
      await loadEgressAudit(client({ summary: { data: null, error } }), USER, "all");
      return faults()[0].tags;
    };
    expect(await tagFor({ code: "PGRST301", message: "jwt" })).toEqual({ pg_code: "PGRST301" });
    expect(await tagFor({ message: "no code" })).toEqual({ pg_code: "none" });
    expect(await tagFor({ code: "weird code for " + WS, message: "x" })).toEqual({ pg_code: "other" });
    expect(await tagFor({ code: "22p02", message: "lowercase" })).toEqual({ pg_code: "other" });
  });

  it("an aborted RPC is `unavailable` with op rpc_timeout", async () => {
    const c = client({ summary: { data: null, error: { name: "AbortError", message: "The operation was aborted" } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(faults()).toHaveLength(1);
    expect(faults()[0]).toMatchObject({ op: "rpc_timeout", tags: { pg_code: "none" } });
  });

  it("an RPC that never answers is bounded: `unavailable` with a paged rpc_timeout", async () => {
    vi.useFakeTimers();
    try {
      const c = client({ summary: neverRpc });
      const p = loadEgressAudit(c, USER, "all");
      await vi.advanceTimersByTimeAsync(7_999);
      expect(h.reportSilentFallback).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toEqual({ kind: "unavailable" });
      expect(faults()).toHaveLength(1);
      expect(faults()[0]).toMatchObject({ op: "rpc_timeout", message: "egress audit read: summary call timed out" });
    } finally {
      vi.useRealTimers();
    }
  });

  it("a throwing RPC is `unavailable` with a paged rpc_error", async () => {
    const c = client({
      summary: () => {
        throw new Error("fetch failed");
      },
    });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(faults().map((f) => f.op)).toEqual(["rpc_error"]);
  });

  it("collection and web access are not read before the RPC succeeds", async () => {
    const c = client({ summary: { data: null, error: { code: "XX000", message: "x" } } });
    await loadEgressAudit(c, USER, "all");
    expect(rpcArgs(c, "get_workspace_web_egress")).toEqual([]);
    expect(spied(c).from).not.toHaveBeenCalled();
    expect(h.readEgressAuditCollectionState).not.toHaveBeenCalled();
  });
});

describe("loadEgressAudit: payload validation", () => {
  const base = () => payload();
  const without = (key: string) => {
    const p: Record<string, unknown> = base();
    delete p[key];
    return p;
  };
  const row = (over: Record<string, unknown> = {}) => ({ host: "a.example.test", decision: "allowed", request_count: 15, last_seen: "2026-10-26T12:00:00Z", ...over });
  const summaryWithout = (key: string) => {
    const s: Record<string, unknown> = { request_count_min: 21, blocked_request_count_min: 4, last_request_at: "2026-10-26T12:00:00Z" };
    delete s[key];
    return s;
  };

  it("control: the near-valid payload the cases below mutate is `ready`", async () => {
    expect(await loadEgressAudit(client({ summary: { data: base(), error: null } }), USER, "all")).toMatchObject({ kind: "ready" });
  });

  it("a stored decision the view does not know is still accepted (the view maps it to Other)", async () => {
    const data = payload({ rows: [row({ decision: "quarantined" })], overflow: [{ decision: "weird", request_count: 2, last_seen: "2026-10-26T12:00:00Z" }] });
    expect(await loadEgressAudit(client({ summary: { data, error: null } }), USER, "all")).toMatchObject({ kind: "ready" });
  });

  it.each<[string, unknown]>([
    ["null body", null],
    ["a string body", "x"],
    ["an array body", []],
    ["window absent", without("window")],
    ["window.end a number", payload({ window: { start: "2026-09-26T00:00:00Z", end: 1 } })],
    ["truncated absent", without("truncated")],
    ["truncated a string", payload({ truncated: "false" })],
    ["summary absent", without("summary")],
    ["no last_request_at key", payload({ summary: summaryWithout("last_request_at") })],
    ["last_request_at unparseable", payload({ summary: { request_count_min: 1, blocked_request_count_min: 0, last_request_at: "not a time" } })],
    ["request_count_min a string", payload({ summary: { request_count_min: "21", blocked_request_count_min: 4, last_request_at: null } })],
    ["blocked_request_count_min negative", payload({ summary: { request_count_min: 21, blocked_request_count_min: -1, last_request_at: null } })],
    ["rows absent", without("rows")],
    ["rows a string", payload({ rows: "no" })],
    ["a null row element", payload({ rows: [row(), null] })],
    ["a row without a host", payload({ rows: [row({ host: undefined })] })],
    ["a row decision a number", payload({ rows: [row({ decision: 1 })] })],
    ["a NaN count", payload({ rows: [row({ request_count: Number.NaN })] })],
    ["a fractional count", payload({ rows: [row({ request_count: 1.5 })] })],
    ["a count above the safe integer range", payload({ rows: [row({ request_count: 2 ** 60 })] })],
    ["a row last_seen unparseable", payload({ rows: [row({ last_seen: "yesterday-ish" })] })],
    ["overflow absent", without("overflow")],
    ["overflow an object", payload({ overflow: {} })],
    ["an overflow element with a negative count", payload({ overflow: [{ decision: "allowed", request_count: -3, last_seen: "2026-10-26T12:00:00Z" }] })],
  ])("a malformed body (%s) is `unavailable` with one paged rpc_error, never an empty `ready`", async (_label, data) => {
    const c = client({ summary: { data, error: null } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(faults()).toHaveLength(1);
    expect(faults()[0]).toMatchObject({ op: "rpc_error", message: "egress audit read: summary body was malformed" });
  });
});

describe("loadEgressAudit: ready", () => {
  it("calls the RPC with the pointer's workspace id and only the documented arguments; `blocked` maps to `denied`", async () => {
    const c = client({});
    await loadEgressAudit(c, USER, "blocked");
    expect(rpcArgs(c, "get_egress_audit_summary")).toEqual([{ p_workspace_id: WS, p_limit: 200, p_decision: "denied" }]);
    const c2 = client({});
    await loadEgressAudit(c2, USER, "all");
    expect(rpcArgs(c2, "get_egress_audit_summary")).toEqual([{ p_workspace_id: WS, p_limit: 200, p_decision: null }]);
  });

  it("carries the payload, the workspace name, collection and web access", async () => {
    const out = await loadEgressAudit(client({}), USER, "all");
    expect(out).toMatchObject({ kind: "ready", collection: true, webAccess: true, workspaceName: "Acme" });
    if (out.kind === "ready") expect(out.data.rows[0].host).toBe("a.example.test");
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });
});

describe("loadEgressAudit: collection state", () => {
  it.each<[true | false | "unknown"]>([[true], [false], ["unknown"]])("passes the tri-state %s through unchanged", async (state) => {
    h.readEgressAuditCollectionState.mockResolvedValue(state);
    expect(await loadEgressAudit(client({}), USER, "all")).toMatchObject({ kind: "ready", collection: state });
    expect(h.readEgressAuditCollectionState).toHaveBeenCalledWith(ORG);
  });

  it("a throwing flag read is `unknown` with an unpaged flag_eval warning", async () => {
    h.readEgressAuditCollectionState.mockRejectedValue(new Error("flagsmith"));
    expect(await loadEgressAudit(client({}), USER, "all")).toMatchObject({ kind: "ready", collection: "unknown", workspaceName: "Acme" });
    expect(warns().map((w) => w.op)).toEqual(["flag_eval"]);
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("an org read that errors is `unknown` with an unpaged org_read warning, and the flag is not asked", async () => {
    const bad = client({ workspaceRow: { data: null, error: { message: "rls" } } });
    expect(await loadEgressAudit(bad, USER, "all")).toMatchObject({ kind: "ready", collection: "unknown", workspaceName: null });
    expect(warns().map((w) => w.op)).toEqual(["org_read"]);
    expect(h.readEgressAuditCollectionState).not.toHaveBeenCalled();
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("an org read that throws is `unknown` with an org_read warning", async () => {
    const bad = client({
      workspaceRow: () => {
        throw new Error("net");
      },
    });
    expect(await loadEgressAudit(bad, USER, "all")).toMatchObject({ collection: "unknown", workspaceName: null });
    expect(warns().map((w) => w.op)).toEqual(["org_read"]);
  });

  it("an org read that outlives 1.5 s is `unknown` with an org_read warning; the page still renders", async () => {
    vi.useFakeTimers();
    try {
      const c = client({ workspaceRow: neverRpc });
      const p = loadEgressAudit(c, USER, "all");
      await vi.advanceTimersByTimeAsync(1_499);
      expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toMatchObject({ kind: "ready", collection: "unknown", webAccess: true });
      expect(warns().map((w) => w.op)).toEqual(["org_read"]);
    } finally {
      vi.useRealTimers();
    }
  });

  it("a flag read that outlives 1.5 s is `unknown` with a flag_eval warning", async () => {
    vi.useFakeTimers();
    try {
      h.readEgressAuditCollectionState.mockReturnValue(new Promise(() => {}));
      const p = loadEgressAudit(client({}), USER, "all");
      await vi.advanceTimersByTimeAsync(1_500);
      await expect(p).resolves.toMatchObject({ kind: "ready", collection: "unknown", workspaceName: "Acme" });
      expect(warns().map((w) => w.op)).toEqual(["flag_eval"]);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("loadEgressAudit: web access", () => {
  it("true and false are passed through without a mirror", async () => {
    expect(await loadEgressAudit(client({ webEgress: { data: false, error: null } }), USER, "all")).toMatchObject({ webAccess: false });
    expect(await loadEgressAudit(client({ webEgress: { data: true, error: null } }), USER, "all")).toMatchObject({ webAccess: true });
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("an RPC error is null with an unpaged web_access_read warning carrying the pg_code tag", async () => {
    const out = await loadEgressAudit(client({ webEgress: { data: null, error: { code: "42501", message: "x" } } }), USER, "all");
    expect(out).toMatchObject({ kind: "ready", webAccess: null });
    expect(warns()).toHaveLength(1);
    expect(warns()[0]).toMatchObject({ op: "web_access_read", tags: { pg_code: "42501" } });
    expect(h.mirrorWarnWithDebounce.mock.calls[0][0]).toBeNull();
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("non-boolean data (null, a string) is null with a web_access_read warning", async () => {
    for (const data of [null, "true"]) {
      h.mirrorWarnWithDebounce.mockClear();
      expect(await loadEgressAudit(client({ webEgress: { data, error: null } }), USER, "all")).toMatchObject({ webAccess: null });
      expect(warns().map((w) => w.op)).toEqual(["web_access_read"]);
    }
  });

  it("a throwing web-access RPC is null with a web_access_read warning", async () => {
    const c = client({
      webEgress: () => {
        throw new Error("net");
      },
    });
    expect(await loadEgressAudit(c, USER, "all")).toMatchObject({ kind: "ready", webAccess: null });
    expect(warns().map((w) => w.op)).toEqual(["web_access_read"]);
  });

  it("a web-access RPC that outlives 1.5 s is null with a web_access_read warning; the page still renders", async () => {
    vi.useFakeTimers();
    try {
      const p = loadEgressAudit(client({ webEgress: neverRpc }), USER, "all");
      await vi.advanceTimersByTimeAsync(1_500);
      await expect(p).resolves.toMatchObject({ kind: "ready", webAccess: null, collection: true });
      expect(warns().map((w) => w.op)).toEqual(["web_access_read"]);
      expect(h.reportSilentFallback).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("loadEgressCardState", () => {
  const hide = { lastRequestAt: null, collection: "unknown", workspaceId: null };
  const hintPayload = (last: string | null) =>
    payload({ rows: [], summary: { request_count_min: null, blocked_request_count_min: null, last_request_at: last } });

  it("returns the last request, the collection state and the workspace it read, calling the RPC with p_limit = 0 only", async () => {
    const c = client({ summary: { data: hintPayload("2026-10-26T11:00:00Z"), error: null } });
    const out = await loadEgressCardState(c, USER);
    expect(out).toEqual({ lastRequestAt: "2026-10-26T11:00:00Z", collection: true, workspaceId: WS });
    expect(rpcArgs(c, "get_egress_audit_summary")).toEqual([{ p_workspace_id: WS, p_limit: 0, p_decision: null }]);
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("an unbound pointer hides the hint and mirrors nothing", async () => {
    h.readWorkspaceIdFromDb.mockResolvedValue(null);
    const c = client({});
    expect(await loadEgressCardState(c, USER)).toEqual(hide);
    expect(spied(c).rpc).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("a throwing pointer read hides the hint with an UNPAGED hint_workspace_read warning (never the paged op)", async () => {
    h.readWorkspaceIdFromDb.mockRejectedValue(new Error("down"));
    expect(await loadEgressCardState(client({}), USER)).toEqual(hide);
    expect(warns().map((w) => w.op)).toEqual(["hint_workspace_read"]);
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a pointer read that outlives 600 ms hides the hint with a hint_workspace_read warning", async () => {
    vi.useFakeTimers();
    try {
      h.readWorkspaceIdFromDb.mockReturnValue(new Promise(() => {}));
      const c = client({});
      const p = loadEgressCardState(c, USER);
      await vi.advanceTimersByTimeAsync(599);
      expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toEqual(hide);
      expect(warns().map((w) => w.op)).toEqual(["hint_workspace_read"]);
      expect(spied(c).rpc).not.toHaveBeenCalled();
    } finally {
      vi.useRealTimers();
    }
  });

  it.each([
    ["membership", "egress audit: workspace membership required"],
    ["revoked token", "egress audit: token denied"],
  ])("the in-body %s denial hides the hint and is NOT mirrored", async (_label, message) => {
    const denied = client({ summary: { data: null, error: { code: "42501", message } } });
    expect((await loadEgressCardState(denied, USER)).lastRequestAt).toBeNull();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("the engine's 42501 hides the hint with an unpaged hint_rpc_error warning tagged pg_code=42501", async () => {
    const lostGrant = client({ summary: { data: null, error: { code: "42501", message: "permission denied for function get_egress_audit_summary" } } });
    expect((await loadEgressCardState(lostGrant, USER)).lastRequestAt).toBeNull();
    expect(warns()).toHaveLength(1);
    expect(warns()[0]).toMatchObject({ feature: "egress-audit-read", op: "hint_rpc_error", tags: { pg_code: "42501" } });
    expect(h.mirrorWarnWithDebounce.mock.calls[0][0]).toBeNull();
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("any other RPC error hides the hint with a tagged hint_rpc_error warning; an abort is hint_timeout", async () => {
    const broken = client({ summary: { data: null, error: { code: "XX000", message: "x" } } });
    expect((await loadEgressCardState(broken, USER)).lastRequestAt).toBeNull();
    expect(warns()[0]).toMatchObject({ op: "hint_rpc_error", tags: { pg_code: "XX000" } });

    h.mirrorWarnWithDebounce.mockClear();
    const aborted = client({ summary: { data: null, error: { name: "AbortError", message: "aborted" } } });
    expect((await loadEgressCardState(aborted, USER)).lastRequestAt).toBeNull();
    expect(warns()[0]).toMatchObject({ op: "hint_timeout" });
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a malformed hint body hides the hint", async () => {
    const c = client({ summary: { data: { rows: "no" }, error: null } });
    expect((await loadEgressCardState(c, USER)).lastRequestAt).toBeNull();
  });

  it("a hint that outlives its 800 ms bound is hidden and mirrored as hint_timeout; the collection state survives", async () => {
    vi.useFakeTimers();
    try {
      const p = loadEgressCardState(client({ summary: neverRpc }), USER);
      await vi.advanceTimersByTimeAsync(799);
      expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toEqual({ lastRequestAt: null, collection: true, workspaceId: WS });
      expect(warns()[0]).toMatchObject({ op: "hint_timeout" });
    } finally {
      vi.useRealTimers();
    }
  });

  it("an org read that outlives 800 ms makes the collection `unknown` with an org_read warning; the hint survives", async () => {
    vi.useFakeTimers();
    try {
      const c = client({ summary: { data: hintPayload("2026-10-26T11:00:00Z"), error: null }, workspaceRow: neverRpc });
      const p = loadEgressCardState(c, USER);
      await vi.advanceTimersByTimeAsync(799);
      expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toEqual({ lastRequestAt: "2026-10-26T11:00:00Z", collection: "unknown", workspaceId: WS });
      expect(warns().map((w) => w.op)).toEqual(["org_read"]);
    } finally {
      vi.useRealTimers();
    }
  });

  it("the whole load is bounded at 1.2 s: slow-but-not-timed-out stages hide the hint with a hint_timeout warning", async () => {
    vi.useFakeTimers();
    try {
      // The pointer answers at 500 ms (inside its 600 ms bound), then the hint hangs: 500 + 800 > 1200.
      h.readWorkspaceIdFromDb.mockImplementation(() => new Promise((resolve) => setTimeout(() => resolve(WS), 500)));
      const p = loadEgressCardState(client({ summary: neverRpc }), USER);
      await vi.advanceTimersByTimeAsync(1_199);
      expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(1);
      await expect(p).resolves.toEqual(hide);
      expect(warns()).toHaveLength(1);
      expect(warns()[0]).toMatchObject({ op: "hint_timeout", message: "egress audit read: card state load timed out" });
    } finally {
      vi.useRealTimers();
    }
  });

  it("an unknown collection state (Flagsmith did not answer) is carried to the card", async () => {
    h.readEgressAuditCollectionState.mockResolvedValue("unknown");
    const out = await loadEgressCardState(client({ summary: { data: hintPayload(null), error: null } }), USER);
    expect(out).toEqual({ lastRequestAt: null, collection: "unknown", workspaceId: WS });
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });
});
