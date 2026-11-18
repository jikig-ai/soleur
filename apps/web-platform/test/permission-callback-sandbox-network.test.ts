// #12585 — the SandboxNetworkAccess arm of createCanUseTool, driven with the RAW SDK tool input (the entry point the
// transport calls). The pure decision has its own suite (sandbox-network-access.test.ts).
import { vi, describe, test, expect, beforeEach } from "vitest";

const { mockLog, mockWarnSilentFallback, mockReportSilentFallback, mockLogPermissionDecision } = vi.hoisted(() => ({
  mockLog: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarnSilentFallback: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLogPermissionDecision: vi.fn(),
}));

vi.mock("../server/logger", () => ({ createChildLogger: () => mockLog, default: mockLog }));
vi.mock("../server/permission-log", () => ({ logPermissionDecision: mockLogPermissionDecision }));
vi.mock("../server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: mockReportSilentFallback,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";
import { scrubSentryEvent } from "../server/sentry-scrub";

const TOOL = "SandboxNetworkAccess";
const NOT_AVAILABLE = "Network access from sandboxed commands is not available in this session.";
const DEFAULT_DENY = "Tool not permitted in this environment";

type Overrides = Record<string, unknown>;
function buildContext(ctxOverrides: Overrides = {}) {
  const deps = {
    abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
  };
  return {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cc_router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    deps,
    ...ctxOverrides,
  } as unknown as CanUseToolContext;
}
const opts = (agentID?: string) => ({
  signal: new AbortController().signal,
  toolUseID: "tu-1",
  requestId: "req-1",
  ...(agentID ? { agentID } : {}),
});
const entitled = (isLive: () => boolean = () => true, granted = true) =>
  buildContext({ sandboxNetworkEgress: { isLive }, webEgressGranted: granted });

async function ask(ctx: CanUseToolContext, input: unknown, agentID?: string) {
  const r = await createCanUseTool(ctx)(TOOL, input as Record<string, unknown>, opts(agentID) as never);
  if (r === null) throw new Error("canUseTool returned null");
  return r;
}
const layers = () => mockLogPermissionDecision.mock.calls.map((c) => c[0]);

beforeEach(() => {
  vi.clearAllMocks();
  process.env.SOLEUR_DEBUG_PERMISSION_LAYER = "1";
});

describe("AC1: no forwarder handle => not-entitled through the explicit arm", () => {
  test.each([
    ["cc ctx (grant off)", buildContext({ webEgressGranted: false }), undefined],
    ["legacy-runner ctx (no egress fields at all)", buildContext(), undefined],
    ["support persona", buildContext({ persona: "support" }), undefined],
    ["subagent call", buildContext(), "agent-7"],
  ])("%s", async (_label, ctx, agentID) => {
    const r = await ask(ctx, { host: "example.com" }, agentID);
    expect(r).toEqual({ behavior: "deny", message: NOT_AVAILABLE });
    expect((r as { message: string }).message).not.toBe(DEFAULT_DENY);
    // The layer proves the arm, not the deny-default branch, answered (and that no earlier branch shadowed it).
    expect(layers()).toEqual(["canUseTool-sandbox-network"]);
    expect(mockLogPermissionDecision).toHaveBeenCalledWith("canUseTool-sandbox-network", TOOL, "deny", "not-entitled");
  });

  test("a granted session whose forwarder failed to spawn gets the degraded copy, tagged granted=true (CTO T13)", async () => {
    const r = await ask(buildContext({ webEgressGranted: true }), { host: "example.com" });
    expect((r as { message: string }).message).toMatch(/web access isn't working in this session/);
    expect(mockWarnSilentFallback.mock.calls[0][1].tags).toEqual({ reason: "not-entitled", granted: "true" });
  });
});

describe("entitled sessions (row 6': deny-all, Phase 1a found the SDK caches per-host allows)", () => {
  test("AC22: an ordinary host and a public IP literal are denied gateway-unverified, never allowed", async () => {
    for (const host of ["example.com", "198.51.100.1", "2001:db8::1"]) {
      vi.clearAllMocks();
      const r = await ask(entitled(), { host });
      expect(r.behavior).toBe("deny");
      expect((r as { message: string }).message).toMatch(/`WebFetch` tool/);
      expect(mockLogPermissionDecision).toHaveBeenCalledWith("canUseTool-sandbox-network", TOOL, "deny", "gateway-unverified");
    }
  });

  test("the support persona and a subagent take the same arm (layer asserted)", async () => {
    await ask(entitled(), { host: "example.com" }, "agent-1");
    await ask(buildContext({ persona: "support", sandboxNetworkEgress: { isLive: () => true } }), { host: "example.com" });
    expect(layers()).toEqual(["canUseTool-sandbox-network", "canUseTool-sandbox-network"]);
    expect(mockWarnSilentFallback.mock.calls[0][1].extra.subagent).toBe(true);
  });

  test("AC7: a dead forwarder (or a throwing probe) => egress-not-running (CTO T4)", async () => {
    for (const isLive of [() => false, () => { throw new Error("boom"); }]) {
      vi.clearAllMocks();
      await ask(entitled(isLive), { host: "example.com" });
      expect(mockLogPermissionDecision).toHaveBeenCalledWith("canUseTool-sandbox-network", TOOL, "deny", "egress-not-running");
    }
  });

  test("isLive is evaluated per request, not once per Query (revocation mid-session)", async () => {
    let live = true;
    const cb = createCanUseTool(entitled(() => live));
    await cb(TOOL, { host: "example.com" }, opts() as never);
    live = false;
    await cb(TOOL, { host: "example.com" }, opts() as never);
    expect(mockLogPermissionDecision.mock.calls.map((c) => c[3])).toEqual(["gateway-unverified", "egress-not-running"]);
  });

  test.each([
    [{ host: "x.supabase.co" }, "no-proxy-match"],
    [{ host: "github.com" }, "no-proxy-match"], // AC19
    [{ host: "LOCALHOST." }, "no-proxy-match"],
    [{ host: "127.0.0.2" }, "loopback-literal"],
    [{ host: "[::1]" }, "loopback-literal"],
    [{ host: "0:0::1" }, "loopback-literal"],
    [{ host: "2130706433" }, "malformed-host"],
    [{ host: "0x7f000001" }, "malformed-host"],
    [{ host: "example.com:443" }, "malformed-host"], // AC27
    [{ host: "user@example.com" }, "malformed-host"],
    [{ host: "example.com", port: 443 }, "malformed-host"],
    [{ host: 7 }, "malformed-host"],
    [null, "malformed-host"],
  ])("AC3: raw SDK input %j => %s with the shared host-deny copy", async (input, reason) => {
    const r = await ask(entitled(), input);
    expect(r.behavior).toBe("deny");
    expect(mockLogPermissionDecision).toHaveBeenCalledWith("canUseTool-sandbox-network", TOOL, "deny", reason);
    if (reason !== "gateway-unverified") {
      expect((r as { message: string }).message).toBe("Commands can't connect to this host from this session.");
    }
  });

  test("an exact-name match only: a near-miss tool name falls to the normal branches", async () => {
    await createCanUseTool(entitled())("sandboxnetworkaccess", { host: "example.com" }, opts() as never);
    expect(layers()).not.toContain("canUseTool-sandbox-network");
  });
});

describe("observability: pino every deny, Sentry once per Query per (reason, matchedEntry) (AC11, AC20, AC26)", () => {
  test("AC11: the Sentry mirror carries the pinned fields", async () => {
    await ask(entitled(), { host: "x.supabase.co" });
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(null, {
      feature: "cc-permissions",
      op: "sandbox-network-denied",
      message: "sandboxed network request denied",
      tags: { reason: "no-proxy-match", granted: "true" },
      extra: { reason: "no-proxy-match", granted: true, matchedEntry: "*.supabase.co", subagent: false },
    });
  });

  test("AC26: N identical denies => 1 Sentry capture and N-1 direct pino lines (warnSilentFallback writes the first)", async () => {
    const cb = createCanUseTool(entitled());
    for (let i = 0; i < 5; i++) await cb(TOOL, { host: "example.com" }, opts() as never);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    const direct = mockLog.warn.mock.calls.filter((c) => c[1] === "sandboxed network request denied");
    expect(direct).toHaveLength(4);
    // The repeat row must be field-for-field the first row's extra: the alert reads `granted` as a JSON boolean.
    const firstExtra = mockWarnSilentFallback.mock.calls[0][1].extra;
    for (const [fields] of direct) {
      expect(fields).toEqual({ feature: "cc-permissions", op: "sandbox-network-denied", ...firstExtra });
      expect(typeof fields.granted).toBe("boolean");
    }
  });

  test("AC11: a different reason or a different matched entry reports again", async () => {
    const cb = createCanUseTool(entitled());
    for (const host of ["example.com", "example.org", "x.supabase.co", "y.supabase.co", "api.stripe.com", "127.0.0.1"]) {
      await cb(TOOL, { host }, opts() as never);
    }
    const keys = mockWarnSilentFallback.mock.calls.map((c) => `${c[1].extra.reason}|${c[1].extra.matchedEntry ?? ""}`);
    expect(keys).toEqual(["gateway-unverified|", "no-proxy-match|*.supabase.co", "no-proxy-match|api.stripe.com", "loopback-literal|"]);
  });

  test("AC20: dedup is per createCanUseTool instance (per Query), not module-global", async () => {
    await ask(entitled(), { host: "example.com" });
    await ask(entitled(), { host: "example.com" });
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(2);
  });
});

describe("review rulings: revocation (CTO R1), expected denies pino-only (R2), pino cap (R3), probe throws mirrored", () => {
  test("R1: a revoked session reports granted=false and gets the turned-off copy", async () => {
    const ctx = buildContext({
      sandboxNetworkEgress: { isLive: () => false },
      webEgressGranted: true,
      webEgressRevoked: () => true,
    });
    const r = await ask(ctx, { host: "example.com" });
    expect(r).toMatchObject({ behavior: "deny" });
    expect((r as { message: string }).message).toMatch(/^Web access was turned off for this workspace/);
    // Ungranted egress-not-running is the expected state: pino only, no Sentry, granted=false (the alert cannot page).
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
    expect(mockLog.warn.mock.calls[0][0]).toMatchObject({ reason: "egress-not-running", granted: false });
  });

  test("R2: ungranted not-entitled logs pino but skips Sentry; granted not-entitled still mirrors", async () => {
    await ask(buildContext({ webEgressGranted: false }), { host: "example.com" });
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
    expect(mockLog.warn.mock.calls[0][0]).toMatchObject({ feature: "cc-permissions", op: "sandbox-network-denied", reason: "not-entitled", granted: false });
    await ask(buildContext({ webEgressGranted: true }), { host: "example.com" });
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("R3: pino is capped at 20 rows per key, then one row per 100 repeats with an occurrences count", async () => {
    const cb = createCanUseTool(entitled());
    for (let i = 0; i < 250; i++) await cb(TOOL, { host: "example.com" }, opts() as never);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    const direct = mockLog.warn.mock.calls.filter((c) => c[1] === "sandboxed network request denied");
    expect(direct).toHaveLength(19 + 2); // rows 2..20, then rows 100 and 200
    expect(direct.slice(19).map((c) => c[0].occurrences)).toEqual([100, 200]);
    expect(direct[0][0].occurrences).toBeUndefined();
  });

  test("first-branch placement: a platform tool or plugin MCP server of that name cannot shadow the arm", async () => {
    const ctx = buildContext({ platformToolNames: [TOOL], pluginMcpServerNames: [TOOL], webEgressGranted: false });
    const r = await ask(ctx, { host: "example.com" });
    expect(r).toEqual({ behavior: "deny", message: NOT_AVAILABLE });
    expect(layers()).toEqual(["canUseTool-sandbox-network"]);
    expect(ctx.deps.abortableReviewGate).not.toHaveBeenCalled();
  });

  test("a throwing liveness or revocation probe still denies, and is mirrored", async () => {
    const ctx = buildContext({
      sandboxNetworkEgress: { isLive: () => { throw new Error("probe"); } },
      webEgressGranted: true,
      webEgressRevoked: () => { throw new Error("probe"); },
    });
    const r = await ask(ctx, { host: "example.com" });
    expect(r).toMatchObject({ behavior: "deny" });
    expect(mockReportSilentFallback.mock.calls.map((c) => c[1].op).sort()).toEqual([
      "sandbox-network-live-probe",
      "sandbox-network-revoked-probe",
    ]);
  });
});

describe("AC12: the requested host reaches no sink (CLO ruling 3)", () => {
  const CANARY = `leak-canary-${Math.random().toString(36).slice(2, 10)}.example`;

  test.each([
    ["unentitled", buildContext({ webEgressGranted: false })],
    ["entitled, live", entitled()],
    ["entitled, dead", entitled(() => false)],
  ])("%s", async (_label, ctx) => {
    const cb = createCanUseTool(ctx);
    const results = [];
    for (const input of [{ host: CANARY }, { host: CANARY }, { host: `${CANARY}:443` }, { host: CANARY, port: 1 }]) {
      results.push(await cb(TOOL, input as never, opts() as never));
    }
    expect(mockWarnSilentFallback.mock.calls.length + mockLog.warn.mock.calls.length).toBeGreaterThan(0);
    // A Sentry event shaped as warnSilentFallback builds it, run through the real beforeSend scrub (second check).
    const events = mockWarnSilentFallback.mock.calls.map((c) =>
      scrubSentryEvent({ message: c[1].message, tags: { feature: c[1].feature, op: c[1].op, ...c[1].tags }, extra: c[1].extra }),
    );
    const sinks = JSON.stringify([
      mockWarnSilentFallback.mock.calls,
      mockReportSilentFallback.mock.calls,
      mockLog.info.mock.calls,
      mockLog.warn.mock.calls,
      mockLog.error.mock.calls,
      mockLog.debug.mock.calls,
      mockLogPermissionDecision.mock.calls,
      events,
      results,
    ]);
    expect(sinks).not.toContain(CANARY);
    expect(sinks).not.toContain("leak-canary");
    expect(sinks).not.toContain("user-1");
  });
});
