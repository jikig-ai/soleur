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
import { existsSync, readdirSync, writeFileSync } from "node:fs";
import {
  EgressRevokedError,
  egressRevocationEpoch,
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

  test("a non-owner's denied toggle-off tears nothing down (403: no write happened)", async () => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    mockSetWebEgress.mockRejectedValue(new WebEgressOwnerDeniedError("denied"));
    expect((await post(false)).status).toBe(403);
    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(true);
    expect(isEgressRevoked("conv-a")).toBe(false);
  }, 20_000);

  test("a toggle-off whose write errors fails CLOSED (500: the RPC may have committed)", async () => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    const other = await spawnEgressForwarder("conv-b", "ws-other");
    mockSetWebEgress.mockRejectedValue(new Error("rpc response lost after commit"));
    expect((await post(false)).status).toBe(500);
    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(false);
    expect(isEgressRevoked("conv-a")).toBe(true);
    expect(isEgressForwarderLive("conv-b", other.token)).toBe(true); // another workspace is untouched
  }, 20_000);

  test("a toggle-ON whose write errors tears nothing down (500)", async () => {
    const mine = await spawnEgressForwarder("conv-a", "ws-toggle");
    mockSetWebEgress.mockRejectedValue(new Error("rpc down"));
    expect((await post(true)).status).toBe(500);
    expect(isEgressForwarderLive("conv-a", mine.token)).toBe(true);
    expect(isEgressRevoked("conv-a")).toBe(false);
  }, 20_000);

  test("CTO R4: a toggle-off that lands while a spawn is starting wins; nothing stays registered or minted", async () => {
    const pending = spawnEgressForwarder("conv-a", "ws-toggle");
    teardownEgressForwardersForWorkspace("ws-toggle"); // the spawn is awaiting the gateway probe
    await expect(pending).rejects.toThrow(/turned off while the egress forwarder was starting/);
    expect(hasEgressForwarder("conv-a")).toBe(false);
    expect(readdirSync(tokenDir)).toEqual([]);
    // Marked revoked even though nothing was registered yet: its denies read granted=false, not degraded.
    expect(isEgressRevoked("conv-a")).toBe(true);
  }, 20_000);

  test("fix round: a toggle-off between the dispatcher's grant read and the spawn wins (epochAtGrant)", async () => {
    const atGrant = egressRevocationEpoch("ws-toggle");
    teardownEgressForwardersForWorkspace("ws-toggle"); // lands during the dispatcher's other awaits
    await expect(spawnEgressForwarder("conv-a", "ws-toggle", atGrant)).rejects.toThrow(/turned off/);
    expect(hasEgressForwarder("conv-a")).toBe(false);
    expect(readdirSync(tokenDir)).toEqual([]);
    expect(isEgressRevoked("conv-a")).toBe(true);
  }, 20_000);

  // Each R4 check pinned on its own window. A fake forwarder writes a marker when it starts and binds 600 ms later.
  function slowForwarder(): { marker: string } {
    const marker = join(tokenDir, "..", `fwd-started-${Math.random().toString(36).slice(2)}`);
    const script = join(tokenDir, "..", `slow-fwd-${Math.random().toString(36).slice(2)}.mjs`);
    writeFileSync(
      script,
      `import { writeFileSync } from "node:fs"; writeFileSync(${JSON.stringify(marker)}, "1");
       setTimeout(() => console.log("egress-forwarder-listening 1"), 600); setInterval(() => {}, 1000);`,
    );
    vi.stubEnv("EGRESS_FORWARDER_PATH", script);
    return { marker };
  }

  test("R4 check 1 (spawn start): a stale epochAtGrant refuses before the gateway probe", async () => {
    const atGrant = egressRevocationEpoch("ws-toggle");
    teardownEgressForwardersForWorkspace("ws-toggle");
    vi.stubEnv("EGRESS_GW_PORT", "1"); // a probe would fail with a different error
    await expect(spawnEgressForwarder("conv-a", "ws-toggle", atGrant)).rejects.toBeInstanceOf(EgressRevokedError);
  }, 20_000);

  test("R4 check 2 (after the gateway probe): the forwarder process never starts", async () => {
    const { marker } = slowForwarder();
    const pending = spawnEgressForwarder("conv-a", "ws-toggle");
    teardownEgressForwardersForWorkspace("ws-toggle"); // lands during the gateway probe
    await expect(pending).rejects.toBeInstanceOf(EgressRevokedError);
    await new Promise((r) => setTimeout(r, 300));
    expect(existsSync(marker)).toBe(false);
    expect(readdirSync(tokenDir)).toEqual([]);
  }, 20_000);

  test("R4 check 3 (after the bind): a toggle-off during the bind leaves nothing live or minted", async () => {
    const { marker } = slowForwarder();
    const pending = spawnEgressForwarder("conv-a", "ws-toggle");
    const deadline = Date.now() + 5_000;
    while (!existsSync(marker) && Date.now() < deadline) await new Promise((r) => setTimeout(r, 20));
    expect(existsSync(marker)).toBe(true); // the child started: we are inside the bind wait
    teardownEgressForwardersForWorkspace("ws-toggle");
    await expect(pending).rejects.toBeInstanceOf(EgressRevokedError);
    expect(hasEgressForwarder("conv-a")).toBe(false);
    expect(readdirSync(tokenDir)).toEqual([]);
    expect(isEgressRevoked("conv-a")).toBe(true);
  }, 20_000);

  test("fix round: a re-granted spawn clears an old revoked mark even when it fails, so the failure pages", async () => {
    await spawnEgressForwarder("conv-a", "ws-toggle");
    teardownEgressForwardersForWorkspace("ws-toggle");
    expect(isEgressRevoked("conv-a")).toBe(true);
    vi.stubEnv("EGRESS_GW_PORT", "1"); // gateway unreachable: the re-granted spawn fails
    await expect(spawnEgressForwarder("conv-a", "ws-toggle", egressRevocationEpoch("ws-toggle"))).rejects.toThrow();
    expect(isEgressRevoked("conv-a")).toBe(false);
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

describe("revocation bookkeeping (verification pass)", () => {
  test("the revoked Set is bounded: the oldest marks are dropped past 10 000", async () => {
    const { markEgressRevoked } = await import("@/server/egress-forwarder");
    markEgressRevoked("bound-first");
    for (let i = 0; i < 10_000; i++) markEgressRevoked(`bound-${i}`);
    expect(isEgressRevoked("bound-first")).toBe(false);
    expect(isEgressRevoked("bound-9999")).toBe(true);
  });
});
