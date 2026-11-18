// #12585 AC24 (CTO D1): turning web access off through POST /api/workspace/web-egress tears down this process's live
// egress forwarders for that workspace at once, so the session's next SandboxNetworkAccess request is denied
// egress-not-running. The forwarder and the canUseTool arm are the real modules; only auth, the tenant client, the
// workspace resolver and the RPC write are stubbed.
import { mkdtempSync, rmSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { mockSetWebEgress } = vi.hoisted(() => ({ mockSetWebEgress: vi.fn() }));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: () => new Response("no", { status: 403 }),
}));
vi.mock("@/server/request-auth", () => ({ verifiedUserId: async () => "user-1" }));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: async () => ({}) }));
vi.mock("@/server/workspace-resolver", () => ({ resolveCurrentWorkspaceId: async () => "ws-toggle" }));
vi.mock("@/server/resolve-web-egress", () => ({ resolveWebEgress: vi.fn() }));
vi.mock("@/server/set-web-egress", () => ({
  setWebEgress: (...a: unknown[]) => mockSetWebEgress(...a),
  WebEgressOwnerDeniedError: class extends Error {},
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn(), captureMessage: vi.fn() }));

import { POST } from "../app/api/workspace/web-egress/route";
import { readdirSync } from "node:fs";
import {
  hasEgressForwarder,
  isEgressForwarderLive,
  isEgressRevoked,
  spawnEgressForwarder,
  teardownEgressForwarder,
  teardownEgressForwardersForWorkspace,
} from "@/server/egress-forwarder";
import { WebEgressOwnerDeniedError } from "@/server/set-web-egress";
import { createCanUseTool, type CanUseToolContext } from "@/server/permission-callback";
import { logPermissionDecision } from "@/server/permission-log";

vi.mock("@/server/permission-log", () => ({ logPermissionDecision: vi.fn() }));

const post = (value: boolean) =>
  POST(
    new Request("https://app.soleur.ai/api/workspace/web-egress", {
      method: "POST",
      headers: { Origin: "https://app.soleur.ai", "content-type": "application/json" },
      body: JSON.stringify({ value }),
    }),
  );

function ctxFor(conversationId: string, token: string): CanUseToolContext {
  return {
    userId: "user-1",
    conversationId,
    leaderId: "cc_router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    sandboxNetworkEgress: { isLive: () => isEgressForwarderLive(conversationId, token) },
    webEgressGranted: true,
    deps: {
      abortableReviewGate: vi.fn(),
      sendToClient: vi.fn(),
      notifyOfflineUser: vi.fn(),
      updateConversationStatus: vi.fn(),
    },
  } as unknown as CanUseToolContext;
}
const sdkOpts = { signal: new AbortController().signal, toolUseID: "tu-1", requestId: "req-1" } as never;
const lastReason = () => vi.mocked(logPermissionDecision).mock.calls.at(-1)?.[3];

describe("POST /api/workspace/web-egress value=false (#12585 AC24)", () => {
  let tokenDir: string;
  let gw: net.Server;

  beforeEach(async () => {
    vi.clearAllMocks();
    tokenDir = mkdtempSync(join(tmpdir(), "egress-tokens-"));
    gw = net.createServer((s) => s.on("error", () => undefined));
    await new Promise<void>((r) => gw.listen(0, "127.0.0.1", r));
    vi.stubEnv("EGRESS_TOKEN_DIR", tokenDir);
    vi.stubEnv("EGRESS_FORWARDER_PATH", join(__dirname, "..", "infra", "egress-forwarder.mjs"));
    vi.stubEnv("EGRESS_GW_HOST", "127.0.0.1");
    vi.stubEnv("EGRESS_GW_PORT", String((gw.address() as net.AddressInfo).port));
  });

  afterEach(async () => {
    for (const c of ["conv-a", "conv-b"]) teardownEgressForwarder(c);
    await new Promise<void>((r) => gw.close(() => r()));
    vi.unstubAllEnvs();
    rmSync(tokenDir, { recursive: true, force: true });
  });

  test("tears down that workspace's live forwarder; the next SandboxNetworkAccess is egress-not-running", async () => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    const other = await spawnEgressForwarder("conv-b", "ws-other");
    const cb = createCanUseTool(ctxFor("conv-a", mine.token));
    await cb("SandboxNetworkAccess", { host: "example.com" }, sdkOpts);
    expect(lastReason()).toBe("gateway-unverified"); // live before the toggle

    mockSetWebEgress.mockResolvedValue(false);
    const res = await post(false);
    expect(res.status).toBe(200);
    expect(mockSetWebEgress).toHaveBeenCalledWith("user-1", false, "ws-toggle");

    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(false);
    expect(isEgressForwarderLive("conv-b", other.token)).toBe(true); // another workspace is untouched
    await cb("SandboxNetworkAccess", { host: "example.com" }, sdkOpts);
    expect(lastReason()).toBe("egress-not-running");
  }, 20_000);

  test("turning web access ON tears nothing down", async () => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    mockSetWebEgress.mockResolvedValue(true);
    expect((await post(true)).status).toBe(200);
    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(true);
  }, 20_000);

  test("CTO R1: the torn-down conversation is marked revoked, so its deny says web access was turned off", async () => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    const other = await spawnEgressForwarder("conv-b", "ws-other");
    expect(isEgressRevoked("conv-a")).toBe(false);
    mockSetWebEgress.mockResolvedValue(false);
    expect((await post(false)).status).toBe(200);
    expect(isEgressRevoked("conv-a")).toBe(true);
    expect(isEgressRevoked("conv-b")).toBe(false);
    const ctx = { ...ctxFor("conv-a", mine.token), webEgressRevoked: () => isEgressRevoked("conv-a") } as CanUseToolContext;
    const r = await createCanUseTool(ctx)("SandboxNetworkAccess", { host: "example.com" }, sdkOpts);
    expect((r as { message: string }).message).toMatch(/^Web access was turned off/);
    // A later successful spawn for that conversation (web access back on) clears the mark.
    await spawnEgressForwarder("conv-a", "ws-toggle");
    expect(isEgressRevoked("conv-a")).toBe(false);
    expect(isEgressForwarderLive("conv-b", other.token)).toBe(true);
  }, 20_000);

  test.each([
    ["403 (non-owner)", () => new WebEgressOwnerDeniedError("denied"), 403],
    ["500 (infra fault)", () => new Error("rpc down"), 500],
  ])("a failed write tears nothing down: %s", async (_label, makeErr, status) => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    mockSetWebEgress.mockRejectedValue(makeErr());
    expect((await post(false)).status).toBe(status);
    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(true);
    expect(isEgressRevoked("conv-a")).toBe(false);
  }, 20_000);

  test("CTO R4: a toggle-off that lands while a spawn is starting wins; nothing stays registered or minted", async () => {
    const pending = spawnEgressForwarder("conv-a", "ws-toggle");
    teardownEgressForwardersForWorkspace("ws-toggle"); // the spawn is awaiting the gateway probe
    await expect(pending).rejects.toThrow(/turned off while the egress forwarder was starting/);
    expect(hasEgressForwarder("conv-a")).toBe(false);
    expect(readdirSync(tokenDir)).toEqual([]);
  }, 20_000);

  test("K2: the registry is shared by two copies of the module (custom-server bundle vs Next route bundle)", async () => {
    vi.resetModules();
    const copy = await import("@/server/egress-forwarder");
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    expect(copy.isEgressForwarderLive("conv-a", mine.token)).toBe(true);
    expect(copy.teardownEgressForwardersForWorkspace("ws-toggle")).toBe(1);
    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(false);
    expect(isEgressRevoked("conv-a")).toBe(true);
  }, 20_000);
});
