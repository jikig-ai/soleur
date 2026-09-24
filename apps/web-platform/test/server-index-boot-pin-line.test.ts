// #7226 review (tdr P2) — the startup pin line is WIRED into the real boot path.
//
// A source regex over server/index.ts matched a commented-out call and an `if (false)`
// wrapper alike. This test instead imports the boot module itself, with every heavy
// dependency replaced, lets `app.prepare()` resolve, and asserts the boot callback
// actually invoked `logGitDataHostKeyPinAtStartup` exactly once.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  logPin: vi.fn(),
  bootStarted: vi.fn(),
  listen: vi.fn(),
  startClock: vi.fn(),
  stopClock: vi.fn(),
}));

vi.mock("../sentry.server.config", () => ({}));
vi.mock("@sentry/nextjs", () => ({ captureMessage: vi.fn(), flush: vi.fn() }));
vi.mock("next", () => ({
  default: () => ({
    prepare: () => Promise.resolve(),
    getRequestHandler: () => vi.fn(),
  }),
}));
vi.mock("http", async (importOriginal) => ({
  ...(await importOriginal<typeof import("http")>()),
  createServer: () => ({
    listen: h.listen,
    close: vi.fn(),
    closeAllConnections: vi.fn(),
    closeIdleConnections: vi.fn(),
  }),
}));
vi.mock("ws", () => ({ WebSocket: { OPEN: 1 } }));
vi.mock("../server/ws-handler", () => ({
  setupWebSocket: () => ({ clients: new Set() }),
  attachProxiedSession: vi.fn(),
}));
vi.mock("../server/session-proxy", () => ({ createProxyServer: () => null }));
vi.mock("../server/proxy-tls", () => ({ logProxyCertExpiryAtStartup: vi.fn() }));
vi.mock("../server/stream-replay-buffer", () => ({ streamReplayBuffer: { clearAll: vi.fn() } }));
vi.mock("@/lib/types", () => ({ WS_CLOSE_CODES: { SERVER_GOING_AWAY: 1001 } }));
vi.mock("../server/agent-runner", () => ({
  abortAllSessions: vi.fn(),
  cleanupOrphanedConversations: () => Promise.resolve(),
  startInactivityTimer: vi.fn(),
  startStuckActiveReaper: vi.fn(),
}));
vi.mock("../server/cc-dispatcher", () => ({
  drainCcQueriesForShutdown: vi.fn(),
  startCcIdleReaper: vi.fn(),
}));
vi.mock("../server/api-messages", () => ({ handleConversationMessages: vi.fn() }));
vi.mock("../server/worktree-write-lease", () => ({ releaseAllHeldLeases: vi.fn() }));
vi.mock("../server/logger", () => {
  const child = () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn(), child });
  return { createChildLogger: child, default: child() };
});
vi.mock("../server/crash-handlers", () => ({ installCrashHandlers: vi.fn() }));
vi.mock("../server/plugin-mount-check", () => ({ verifyPluginMountOnce: vi.fn() }));
vi.mock("../server/single-replica-assertion", () => ({
  // First call in the boot callback: proves the callback ran at all.
  assertSingleReplicaInvariant: h.bootStarted,
}));
vi.mock("../server/team-workspace-boot", () => ({ emitTeamWorkspaceInviteBootBreadcrumb: vi.fn() }));
vi.mock("../server/git-data-replication", () => ({
  logGitDataHostKeyPinAtStartup: h.logPin,
}));
vi.mock("../server/health", () => ({
  buildHealthResponse: vi.fn(),
  buildInternalMetricsResponse: vi.fn(),
  writeHealthResponse: vi.fn(),
}));
vi.mock("../server/readiness", () => ({
  handleReadyzRequest: vi.fn(),
  verifyWorkspacesMountOnce: vi.fn(),
}));
vi.mock("../server/loopback", () => ({ isLoopbackHost: vi.fn() }));
vi.mock("@/server/inngest/send-with-retry", () => ({ sendInngestWithRetry: vi.fn() }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
// #8495: the watchdog dispatch clock is armed at boot and stopped on SIGTERM.
vi.mock("../server/watchdog-dispatch-clock", () => ({
  startWatchdogDispatchClock: (...a: unknown[]) => {
    h.startClock(...a);
    return { stop: h.stopClock };
  },
}));

describe("server/index.ts boot — git-data host-key pin line (#7226 AC16)", () => {
  let processOn: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.stubEnv("INNGEST_SIGNING_KEY", "");
    // The boot callback registers a SIGTERM handler; keep it off the test process.
    processOn = vi.spyOn(process, "on").mockImplementation(() => process);
  });

  afterEach(() => {
    processOn.mockRestore();
    vi.unstubAllEnvs();
  });

  it("the boot callback calls logGitDataHostKeyPinAtStartup exactly once", async () => {
    await import("../server/index");
    // Let `app.prepare().then(...)` run, and wait until the server reaches listen() —
    // i.e. the whole boot callback has executed, not merely started.
    await vi.waitFor(() => expect(h.listen).toHaveBeenCalledTimes(1));
    expect(h.bootStarted).toHaveBeenCalledTimes(1);
    expect(h.logPin).toHaveBeenCalledTimes(1);

    // #8495 — the watchdog dispatch clock is armed exactly once, with defaults.
    expect(h.startClock).toHaveBeenCalledTimes(1);
    expect(h.startClock.mock.calls[0]).toEqual([]);
    // ...and SIGTERM stops it, synchronously (before the handler's first await).
    const sigterm = processOn.mock.calls.find((c: unknown[]) => c[0] === "SIGTERM")?.[1] as
      | (() => Promise<void>)
      | undefined;
    expect(sigterm).toBeTypeOf("function");
    const exit = vi.spyOn(process, "exit").mockImplementation((() => undefined) as never);
    try {
      expect(h.stopClock).not.toHaveBeenCalled();
      void sigterm!();
      expect(h.stopClock).toHaveBeenCalledTimes(1);
      await vi.waitFor(() => expect(exit).toHaveBeenCalled());
    } finally {
      exit.mockRestore();
    }
  });
});
