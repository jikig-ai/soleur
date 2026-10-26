import { beforeEach, describe, expect, it, vi } from "vitest";

// #9545 PR2 — server loader for the egress audit view and the card hint. The RPC (migration 177) is
// the only authz gate: the loader's own jobs are (1) take the workspace id ONLY from the fail-loud
// reader, never from request input, (2) never call the RPC when that read fails, (3) map outcomes to a
// tagged result so an error is never rendered as an empty log, (4) mirror faults with reason codes in
// `op` and a static message (err = null), and never mirror the expected 42501 denial.
//
// The real database behaviour (membership, tenant filter, aggregation) is in
// test/rls-fuzz/egress-audit-rollup.integration.test.ts; mocked clients cannot prove it.

const h = vi.hoisted(() => ({
  readWorkspaceIdFromDb: vi.fn(),
  isEgressAuditCollectionOn: vi.fn(),
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

vi.mock("@/server/workspace-resolver", () => ({ readWorkspaceIdFromDb: h.readWorkspaceIdFromDb }));
vi.mock("@/server/egress-audit-collection", () => ({ isEgressAuditCollectionOn: h.isEgressAuditCollectionOn }));
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

// supabase-js query builder stand-in: thenable, with abortSignal() like the real PostgREST builder.
const builder = (reply: RpcReply | (() => RpcReply | Promise<RpcReply>)) => {
  const run = async () => (typeof reply === "function" ? reply() : reply);
  const b: { abortSignal: () => unknown; then: PromiseLike<RpcReply>["then"] } = {
    abortSignal: () => b,
    then: (res, rej) => run().then(res, rej),
  };
  return b;
};

function client(opts: {
  summary?: RpcReply | (() => RpcReply | Promise<RpcReply>);
  webEgress?: RpcReply;
  workspaceRow?: RpcReply;
}) {
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

const rpcArgs = (c: { rpc: ReturnType<typeof vi.fn> }, fn: string) =>
  c.rpc.mock.calls.filter((call) => call[0] === fn).map((call) => call[1]);

beforeEach(() => {
  vi.clearAllMocks();
  h.readWorkspaceIdFromDb.mockResolvedValue(WS);
  h.isEgressAuditCollectionOn.mockResolvedValue(true);
});

describe("loadEgressAudit", () => {
  it("exports the Sentry feature tag the alert rule filters on", () => {
    expect(EGRESS_AUDIT_READ_FEATURE).toBe("egress-audit-read");
  });

  it("an absent workspace pointer is `unbound` and the RPC is never called", async () => {
    h.readWorkspaceIdFromDb.mockResolvedValue(null);
    const c = client({});
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unbound" });
    expect((c as never as { rpc: ReturnType<typeof vi.fn> }).rpc).not.toHaveBeenCalled();
  });

  it("a throwing pointer read is `unavailable`, mirrored once with a reason code, and the RPC is never called", async () => {
    h.readWorkspaceIdFromDb.mockRejectedValue(new Error("db down"));
    const c = client({});
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect((c as never as { rpc: ReturnType<typeof vi.fn> }).rpc).not.toHaveBeenCalled();
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = h.reportSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({ feature: "egress-audit-read", op: "workspace_read_error" });
    expect(JSON.stringify(opts)).not.toContain(WS);
  });

  it("a 42501 from the RPC is `forbidden` and is NOT mirrored (expected denial)", async () => {
    const c = client({ summary: { data: null, error: { code: "42501", message: "egress audit: workspace membership required" } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "forbidden" });
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("any other RPC error is `unavailable` and mirrored with op rpc_error, err null and a static message", async () => {
    const c = client({ summary: { data: null, error: { code: "XX000", message: "boom for workspace " + WS } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = h.reportSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({ feature: "egress-audit-read", op: "rpc_error" });
    expect(typeof opts.message).toBe("string");
    expect(JSON.stringify(opts)).not.toContain(WS);
  });

  it("an aborted RPC is `unavailable` with op rpc_timeout", async () => {
    const c = client({ summary: { data: null, error: { name: "AbortError", message: "The operation was aborted" } } });
    await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
    expect(h.reportSilentFallback.mock.calls[0][1]).toMatchObject({ op: "rpc_timeout" });
  });

  it("a malformed RPC body is `unavailable`, never an empty `ready`", async () => {
    for (const data of [null, "x", { rows: "no" }, { rows: [], overflow: null, summary: {} }]) {
      h.reportSilentFallback.mockClear();
      const c = client({ summary: { data, error: null } });
      await expect(loadEgressAudit(c, USER, "all")).resolves.toEqual({ kind: "unavailable" });
      expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    }
  });

  it("calls the RPC with the pointer's workspace id and only the documented arguments; `blocked` maps to `denied`", async () => {
    const c = client({});
    await loadEgressAudit(c, USER, "blocked");
    const args = rpcArgs(c as never, "get_egress_audit_summary");
    expect(args).toEqual([{ p_workspace_id: WS, p_limit: 200, p_decision: "denied" }]);
    h.readWorkspaceIdFromDb.mockResolvedValue(WS);
    const c2 = client({});
    await loadEgressAudit(c2, USER, "all");
    expect(rpcArgs(c2 as never, "get_egress_audit_summary")).toEqual([{ p_workspace_id: WS, p_limit: 200, p_decision: null }]);
  });

  it("ready: carries the payload, the workspace name, collection and web access", async () => {
    const c = client({});
    const out = await loadEgressAudit(c, USER, "all");
    expect(out).toMatchObject({ kind: "ready", collection: true, webAccess: true, workspaceName: "Acme" });
    if (out.kind === "ready") expect(out.data.rows[0].host).toBe("a.example.test");
  });

  it("collection is false when the flag is off, and `unknown` when the org read or the flag read fails", async () => {
    h.isEgressAuditCollectionOn.mockResolvedValue(false);
    expect(await loadEgressAudit(client({}), USER, "all")).toMatchObject({ kind: "ready", collection: false });

    h.isEgressAuditCollectionOn.mockRejectedValue(new Error("flagsmith"));
    expect(await loadEgressAudit(client({}), USER, "all")).toMatchObject({ kind: "ready", collection: "unknown" });

    h.isEgressAuditCollectionOn.mockResolvedValue(true);
    const bad = client({ workspaceRow: { data: null, error: { message: "rls" } } });
    expect(await loadEgressAudit(bad, USER, "all")).toMatchObject({ kind: "ready", collection: "unknown", workspaceName: null });
  });

  it("web access is null (unknown) when its RPC returns null or errors, and false/true are passed through", async () => {
    expect(await loadEgressAudit(client({ webEgress: { data: null, error: null } }), USER, "all")).toMatchObject({ webAccess: null });
    expect(await loadEgressAudit(client({ webEgress: { data: null, error: { message: "x" } } }), USER, "all")).toMatchObject({ webAccess: null });
    expect(await loadEgressAudit(client({ webEgress: { data: false, error: null } }), USER, "all")).toMatchObject({ webAccess: false });
  });
});

describe("loadEgressCardState", () => {
  it("returns the last request and the collection state, calling the RPC with p_limit = 0 only", async () => {
    const c = client({ summary: { data: payload({ rows: [], summary: { request_count_min: null, blocked_request_count_min: null, last_request_at: "2026-10-26T11:00:00Z" } }), error: null } });
    const out = await loadEgressCardState(c, USER);
    expect(out).toEqual({ lastRequestAt: "2026-10-26T11:00:00Z", collection: true });
    expect(rpcArgs(c as never, "get_egress_audit_summary")).toEqual([{ p_workspace_id: WS, p_limit: 0, p_decision: null }]);
  });

  it("on a null pointer, a throw, a 42501 or an error it hides the hint and never throws; only faults are mirrored, and at warning level", async () => {
    h.readWorkspaceIdFromDb.mockResolvedValue(null);
    expect(await loadEgressCardState(client({}), USER)).toEqual({ lastRequestAt: null, collection: "unknown" });

    h.readWorkspaceIdFromDb.mockRejectedValue(new Error("down"));
    expect(await loadEgressCardState(client({}), USER)).toEqual({ lastRequestAt: null, collection: "unknown" });

    h.readWorkspaceIdFromDb.mockResolvedValue(WS);
    h.mirrorWarnWithDebounce.mockClear();
    const denied = client({ summary: { data: null, error: { code: "42501", message: "x" } } });
    expect((await loadEgressCardState(denied, USER)).lastRequestAt).toBeNull();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();

    const broken = client({ summary: { data: null, error: { code: "XX000", message: "x" } } });
    expect((await loadEgressCardState(broken, USER)).lastRequestAt).toBeNull();
    expect(h.mirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    expect(h.mirrorWarnWithDebounce.mock.calls[0][1]).toMatchObject({ feature: "egress-audit-read", op: "hint_rpc_error" });
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a hint that outlives its time bound is hidden and mirrored as hint_timeout", async () => {
    vi.useFakeTimers();
    try {
      const never = client({ summary: () => new Promise<RpcReply>(() => {}) });
      const p = loadEgressCardState(never, USER);
      await vi.advanceTimersByTimeAsync(5_000);
      await expect(p).resolves.toEqual({ lastRequestAt: null, collection: true });
      expect(h.mirrorWarnWithDebounce.mock.calls[0][1]).toMatchObject({ op: "hint_timeout" });
    } finally {
      vi.useRealTimers();
    }
  });
});
