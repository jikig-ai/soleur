process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { EventEmitter } from "node:events";
import { createServer } from "node:http";
import { afterEach, expect, it, vi } from "vitest";
import { WebSocket } from "ws";

const { bootstrap, releaseSlot, authGetUser } = vi.hoisted(() => ({
  bootstrap: { resolve: undefined as ((value: unknown) => void) | undefined, started: vi.fn() },
  releaseSlot: vi.fn(),
  authGetUser: vi.fn(async () => ({ data: { user: { id: "synthetic-user" } }, error: null })),
}));
const { workspaceLookup } = vi.hoisted(() => ({ workspaceLookup: vi.fn(async () => null as string | null) }));
const { routeFixture } = vi.hoisted(() => ({ routeFixture: {
  enabled: false, forwarded: vi.fn(), attached: vi.fn(),
  resolve: vi.fn(async () => ({ decision: "proxy" as const, ownerAddress: "synthetic-owner" })),
} }));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ auth: { getUser: authGetUser } }),
  serverUrl: "https://test.supabase.co",
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(() => { bootstrap.started(); return new Promise((resolve) => { bootstrap.resolve = resolve; }); }),
  getMyRevocationStatus: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn(), addBreadcrumb: vi.fn(), captureMessage: vi.fn() }));
vi.mock("../server/concurrency", () => ({
  SLOT_STALENESS_THRESHOLD_SECONDS: 240, SLOT_HEARTBEAT_INTERVAL_MS: 60_000,
  releaseSlot, acquireSlot: vi.fn(), touchSlot: vi.fn(), emitConcurrencyCapHit: vi.fn(),
}));
vi.mock("../server/workspace-resolver", async (importOriginal) => ({
  ...await importOriginal<typeof import("../server/workspace-resolver")>(),
  resolveCurrentOrganizationId: workspaceLookup,
  getDefaultWorkspaceForUser: vi.fn(async () => "synthetic-old-workspace"),
  isGitDataStoreEnabled: vi.fn(() => routeFixture.enabled),
}));
vi.mock("../server/session-router", async (importOriginal) => ({
  ...await importOriginal<typeof import("../server/session-router")>(),
  resolveSessionRoute: routeFixture.resolve,
}));
vi.mock("../server/session-proxy", async (importOriginal) => ({
  ...await importOriginal<typeof import("../server/session-proxy")>(),
  proxyClientToOwner: vi.fn(async ({ clientWs }: { clientWs: EventEmitter }) => {
    routeFixture.attached();
    clientWs.on("message", routeFixture.forwarded);
  }),
}));

import { setupWebSocket } from "../server/ws-handler";
import { sessions } from "../server/session-registry";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { clearUserWorkspace, getUserWorkspace, setUserWorkspace } from "../server/agent-session-registry";

class FakeSocket extends EventEmitter {
  readyState: number = WebSocket.OPEN;
  emitClose = true;
  send = vi.fn();
  ping = vi.fn();
  close = vi.fn(() => { this.readyState = WebSocket.CLOSED; if (this.emitClose) this.emit("close"); });
}

afterEach(() => { sessions.delete("synthetic-user"); clearUserWorkspace("synthetic-user"); bootstrap.resolve = undefined; routeFixture.enabled = false; vi.clearAllMocks(); });

it("does not run concurrent token checks for repeated first frames", async () => {
  let resolveAuth!: (value: { data: { user: { id: string } }; error: null }) => void;
  authGetUser.mockImplementationOnce(() => new Promise((resolve) => { resolveAuth = resolve; }));
  const http = createServer();
  const server = setupWebSocket(http);
  const incoming = new FakeSocket();
  try {
    server.emit("connection", incoming as never, {} as never, "127.0.0.1" as never);
    const frame = Buffer.from(JSON.stringify({ type: "auth", token: "synthetic-token" }));
    incoming.emit("message", frame);
    incoming.emit("message", frame);
    expect(authGetUser).toHaveBeenCalledOnce();
    expect(incoming.close).toHaveBeenCalled();
  } finally {
    resolveAuth({ data: { user: { id: "synthetic-user" } }, error: null });
    await new Promise((resolve) => setImmediate(resolve));
    server.close(); http.close();
  }
});

it("does not route a new socket's frames into an existing session during bootstrap", async () => {
  const http = createServer();
  const server = setupWebSocket(http);
  const existing = new FakeSocket();
  const incoming = new FakeSocket();
  const pending = { id: "synthetic-pending" };
  sessions.set("synthetic-user", { ws: existing as never, lastActivity: Date.now(), pending } as never);
  try {
    server.emit("connection", incoming as never, {} as never, "127.0.0.1" as never);
    incoming.emit("message", Buffer.from(JSON.stringify({ type: "auth", token: "synthetic-token" })));
    await vi.waitFor(() => expect(bootstrap.started).toHaveBeenCalledOnce());
    incoming.emit("message", Buffer.from(JSON.stringify({ type: "close_conversation" })));
    await new Promise((resolve) => setImmediate(resolve));
    expect(sessions.get("synthetic-user")?.pending).toBe(pending);
    expect(releaseSlot).not.toHaveBeenCalled();
    expect(existing.send).not.toHaveBeenCalled();
  } finally {
    bootstrap.resolve?.(null);
    await new Promise((resolve) => setImmediate(resolve));
    incoming.close();
    server.close();
    http.close();
  }
});

it("routes a current socket's commands only after bootstrap completes", async () => {
  const http = createServer();
  const server = setupWebSocket(http);
  const incoming = new FakeSocket();
  try {
    server.emit("connection", incoming as never, {} as never, "127.0.0.1" as never);
    incoming.emit("message", Buffer.from(JSON.stringify({ type: "auth", token: "synthetic-token" })));
    await vi.waitFor(() => expect(bootstrap.started).toHaveBeenCalledOnce());
    bootstrap.resolve?.({ from: () => ({ select: () => ({ eq: () => ({
      single: async () => ({ data: { tc_accepted_version: TC_VERSION }, error: null }),
    }) }) }) });
    await vi.waitFor(() => expect(incoming.send).toHaveBeenCalledWith(JSON.stringify({ type: "auth_ok" })));
    incoming.send.mockClear();
    incoming.emit("message", Buffer.from("not-json"));
    await vi.waitFor(() => expect(incoming.send).toHaveBeenCalledWith(JSON.stringify({ type: "error", message: "Invalid JSON" })));
  } finally {
    incoming.close(); server.close(); http.close();
  }
});

it.each(["superseded", "closed"])("does not bind a stale workspace or start heartbeat after being %s during lookup", async (outcome) => {
  let releaseLookup!: (value: string | null) => void;
  workspaceLookup.mockImplementationOnce(() => new Promise((resolve) => { releaseLookup = resolve; }));
  const intervalSpy = vi.spyOn(globalThis, "setInterval");
  const http = createServer();
  const server = setupWebSocket(http);
  const incoming = new FakeSocket();
  const successor = new FakeSocket();
  try {
    server.emit("connection", incoming as never, {} as never, "127.0.0.1" as never);
    incoming.emit("message", Buffer.from(JSON.stringify({ type: "auth", token: "synthetic-token" })));
    await vi.waitFor(() => expect(bootstrap.started).toHaveBeenCalledOnce());
    bootstrap.resolve?.({ from: () => ({ select: () => ({ eq: () => ({
      single: async () => ({ data: { tc_accepted_version: TC_VERSION }, error: null }),
    }) }) }) });
    await vi.waitFor(() => expect(workspaceLookup).toHaveBeenCalledOnce());
    const current = { ws: successor as never, lastActivity: Date.now() };
    if (outcome === "superseded") {
      sessions.set("synthetic-user", current as never);
      setUserWorkspace("synthetic-user", "synthetic-current-workspace");
    } else {
      incoming.close();
    }
    const heartbeatCount = intervalSpy.mock.calls.filter((call) => call[1] === 60_000).length;
    releaseLookup(null);
    await new Promise((resolve) => setImmediate(resolve));
    await new Promise((resolve) => setImmediate(resolve));
    expect(sessions.get("synthetic-user")).toBe(outcome === "superseded" ? current : undefined);
    expect(getUserWorkspace("synthetic-user")).toBe(outcome === "superseded" ? "synthetic-current-workspace" : undefined);
    expect(intervalSpy.mock.calls.filter((call) => call[1] === 60_000)).toHaveLength(heartbeatCount);
    expect(incoming.send).not.toHaveBeenCalledWith(JSON.stringify({ type: "auth_ok" }));
  } finally {
    releaseLookup?.(null); incoming.close(); server.close(); http.close(); intervalSpy.mockRestore();
  }
});

it("does not dispatch locally after transferring a socket to the proxy", async () => {
  routeFixture.enabled = true;
  const http = createServer();
  const server = setupWebSocket(http);
  const incoming = new FakeSocket();
  const successor = new FakeSocket();
  try {
    server.emit("connection", incoming as never, {} as never, "127.0.0.1" as never);
    incoming.emit("message", Buffer.from(JSON.stringify({ type: "auth", token: "synthetic-token" })));
    await vi.waitFor(() => expect(bootstrap.started).toHaveBeenCalledOnce());
    bootstrap.resolve?.({ from: () => ({ select: () => ({ eq: () => ({
      single: async () => ({ data: { tc_accepted_version: TC_VERSION }, error: null }),
    }) }) }) });
    await vi.waitFor(() => expect(routeFixture.attached).toHaveBeenCalledOnce());
    sessions.set("synthetic-user", { ws: successor as never, lastActivity: Date.now() } as never);
    incoming.emit("message", Buffer.from("not-json"));
    await new Promise((resolve) => setImmediate(resolve));
    expect(routeFixture.forwarded).toHaveBeenCalledOnce();
    expect(successor.send).not.toHaveBeenCalled();
  } finally { incoming.close(); server.close(); http.close(); }
});

it("closes and cleans up a stale socket superseded during routing", async () => {
  routeFixture.enabled = true;
  let releaseRoute!: (value: { decision: "proxy"; ownerAddress: string }) => void;
  routeFixture.resolve.mockImplementationOnce(() => new Promise((resolve) => { releaseRoute = resolve; }));
  const http = createServer();
  const server = setupWebSocket(http);
  const incoming = new FakeSocket();
  incoming.emitClose = false;
  const successor = new FakeSocket();
  const intervalSpy = vi.spyOn(globalThis, "setInterval");
  const clearIntervalSpy = vi.spyOn(globalThis, "clearInterval");
  const clearTimeoutSpy = vi.spyOn(globalThis, "clearTimeout");
  let successorInterval: ReturnType<typeof setInterval> | undefined;
  let successorIdle: ReturnType<typeof setTimeout> | undefined;
  try {
    server.emit("connection", incoming as never, {} as never, "127.0.0.1" as never);
    incoming.emit("message", Buffer.from(JSON.stringify({ type: "auth", token: "synthetic-token" })));
    await vi.waitFor(() => expect(bootstrap.started).toHaveBeenCalledOnce());
    bootstrap.resolve?.({ from: () => ({ select: () => ({ eq: () => ({
      single: async () => ({ data: { tc_accepted_version: TC_VERSION }, error: null }),
    }) }) }) });
    await vi.waitFor(() => expect(routeFixture.resolve).toHaveBeenCalledOnce());
    const oldSession = sessions.get("synthetic-user")!;
    const oldSubscriptionTimer = oldSession.subscriptionRefreshTimer;
    const oldIdleTimer = oldSession.idleTimer;
    const heartbeat = intervalSpy.mock.results.at(-1)?.value;
    expect(oldSubscriptionTimer).toBeDefined();
    expect(oldIdleTimer).toBeDefined();
    expect(heartbeat).toBeDefined();
    successorInterval = setInterval(() => {}, 60_000);
    successorIdle = setTimeout(() => {}, 60_000);
    const current = { ws: successor as never, lastActivity: Date.now(), subscriptionRefreshTimer: successorInterval, idleTimer: successorIdle };
    sessions.set("synthetic-user", current as never);
    setUserWorkspace("synthetic-user", "synthetic-current-workspace");
    releaseRoute({ decision: "proxy", ownerAddress: "synthetic-owner" });
    await new Promise((resolve) => setImmediate(resolve));
    expect(incoming.close).toHaveBeenCalled();
    expect(clearIntervalSpy).toHaveBeenCalledWith(oldSubscriptionTimer);
    expect(clearIntervalSpy).toHaveBeenCalledWith(heartbeat);
    expect(clearTimeoutSpy).toHaveBeenCalledWith(oldIdleTimer);
    expect(clearIntervalSpy).not.toHaveBeenCalledWith(successorInterval);
    expect(clearTimeoutSpy).not.toHaveBeenCalledWith(successorIdle);
    expect(routeFixture.attached).not.toHaveBeenCalled();
    expect(sessions.get("synthetic-user")).toBe(current);
    expect(getUserWorkspace("synthetic-user")).toBe("synthetic-current-workspace");
  } finally {
    releaseRoute?.({ decision: "proxy", ownerAddress: "synthetic-owner" });
    incoming.close(); incoming.emit("close"); server.close(); http.close();
    if (successorInterval) clearInterval(successorInterval);
    if (successorIdle) clearTimeout(successorIdle);
    intervalSpy.mockRestore(); clearIntervalSpy.mockRestore(); clearTimeoutSpy.mockRestore();
  }
});
