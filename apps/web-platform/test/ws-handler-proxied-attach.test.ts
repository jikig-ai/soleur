/**
 * Unit tests — ws-handler `attachProxiedSession` OWNER-side relay completion
 * (multi-host /workspaces epic #5274 Phase 3 Sub-PR 3.D, ADR-068 b2).
 *
 * A session that lands on a NON-owning web host is transparently relayed to the
 * host holding that user's worktree lease (session-proxy.ts). The owner's proxy
 * listener re-verifies AP-2 membership and then hands the socket to
 * `attachProxiedSession`, which must register a PRE-AUTHENTICATED native session:
 * register → bind workspace → idle timer → heartbeat → send `auth_ok`, then wire
 * message→handleMessage and close→teardown.
 *
 * A proxied socket arrives already-authed (no token) so the attach MUST:
 *   (a) register the session in the `sessions` registry,
 *   (b) bind the workspace (Phase 5.5 SIGTERM precision),
 *   (c) send `auth_ok` and NOT a fresh-session greeting (AC8: a drain/deploy-
 *       migrated session resumes, it does not greet fresh),
 *   (d) wire message → handleMessage,
 *   (e) NOT run the placement/routing path (it is already on its owner).
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`. Mirrors the
 * mock harness in `ws-handler-disconnect-grace-owning-host-guard.test.ts` +
 * `session-proxy.test.ts` (fake EventEmitter WebSocket).
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { EventEmitter } from "node:events";
import { afterEach, describe, expect, it, vi } from "vitest";
import { WebSocket } from "ws";

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: vi.fn(), auth: { getUser: vi.fn() } }),
  serverUrl: "https://test.supabase.co",
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: vi.fn() })),
  getMyRevocationStatus: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
}));
vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));
vi.mock("../server/concurrency", () => ({
  releaseSlot: vi.fn(),
  acquireSlot: vi.fn(),
  touchSlot: vi.fn(),
  emitConcurrencyCapHit: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
// Assert the proxied attach does NOT touch the placement/routing path — it is
// already on the owner. Both must remain uncalled.
vi.mock("../server/session-router", () => ({
  resolveSessionRoute: vi.fn(),
}));
vi.mock("../server/session-proxy", () => ({
  proxyClientToOwner: vi.fn(),
}));

import { attachProxiedSession } from "../server/ws-handler";
import { sessions } from "../server/session-registry";
import {
  getUserWorkspace,
  clearUserWorkspace,
} from "../server/agent-session-registry";
import { resolveSessionRoute } from "../server/session-router";
import { proxyClientToOwner } from "../server/session-proxy";

const USER = "u-proxied-1";
const WS_ID = "ws-proxied-1";

class FakeWs extends EventEmitter {
  readyState: number = WebSocket.OPEN;
  sent: string[] = [];
  pinged = 0;
  closed?: { code: number; reason: string };
  send(data: string) {
    this.sent.push(data);
  }
  ping() {
    this.pinged += 1;
  }
  close(code: number, reason: string) {
    this.closed = { code, reason };
    this.readyState = WebSocket.CLOSED;
  }
}

afterEach(() => {
  sessions.delete(USER);
  clearUserWorkspace(USER);
  vi.clearAllMocks();
});

describe("attachProxiedSession — owner-side pre-authed relay (#5274 Phase 3 3.D)", () => {
  it("(a) registers the pre-authed session in the `sessions` registry", async () => {
    const ws = new FakeWs();
    await attachProxiedSession(ws as never, { userId: USER, workspaceId: WS_ID });
    expect(sessions.get(USER)?.ws).toBe(ws);
  });

  it("(b) binds the workspace (Phase 5.5 revoke precision)", async () => {
    const ws = new FakeWs();
    await attachProxiedSession(ws as never, { userId: USER, workspaceId: WS_ID });
    expect(getUserWorkspace(USER)).toBe(WS_ID);
  });

  it("(c) sends auth_ok and NOT a fresh-session greeting (AC8)", async () => {
    const ws = new FakeWs();
    await attachProxiedSession(ws as never, { userId: USER, workspaceId: WS_ID });
    const types = ws.sent.map((f) => JSON.parse(f).type);
    expect(types).toContain("auth_ok");
    // AC8 — a migrated session resumes; it must not be greeted as a fresh one.
    expect(types).not.toContain("session_start");
    expect(types).not.toContain("greeting");
  });

  it("(d) wires message → handleMessage (a frame after attach is handled, not re-auth'd)", async () => {
    const ws = new FakeWs();
    await attachProxiedSession(ws as never, { userId: USER, workspaceId: WS_ID });
    ws.sent.length = 0; // drop the auth_ok

    // handleMessage's invalid-JSON branch replies with an "Invalid JSON" error
    // synchronously (before any await) — proof the frame reached handleMessage
    // rather than an auth handler (which would close the socket).
    ws.emit("message", "not-json");
    await new Promise((r) => setImmediate(r));

    expect(ws.closed).toBeUndefined();
    const parsed = ws.sent.map((f) => JSON.parse(f));
    expect(parsed).toContainEqual(
      expect.objectContaining({ type: "error", message: "Invalid JSON" }),
    );
  });

  it("(e) does NOT invoke the placement/routing path (already on owner)", async () => {
    const ws = new FakeWs();
    await attachProxiedSession(ws as never, { userId: USER, workspaceId: WS_ID });
    expect(resolveSessionRoute).not.toHaveBeenCalled();
    expect(proxyClientToOwner).not.toHaveBeenCalled();
  });

  it("close tears down the registered session (grace-abort teardown parity)", async () => {
    const ws = new FakeWs();
    await attachProxiedSession(ws as never, { userId: USER, workspaceId: WS_ID });
    expect(sessions.get(USER)?.ws).toBe(ws);

    ws.emit("close");
    expect(sessions.get(USER)).toBeUndefined();
    expect(getUserWorkspace(USER)).toBeUndefined();
  });
});
