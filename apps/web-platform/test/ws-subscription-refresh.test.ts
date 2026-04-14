// Set env vars BEFORE dynamic imports — ws-handler.ts creates a Supabase
// client at module load time. Also fix the refresh interval to a known value
// so `vi.advanceTimersByTime` lines up with the timer cadence.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";
process.env.WS_SUBSCRIPTION_REFRESH_INTERVAL_MS = "60000";

import { describe, test, expect, vi, beforeEach, beforeAll, afterEach } from "vitest";
import type { ClientSession } from "../server/ws-handler";

// WebSocket ready states (ws package constants mirror browser values).
const WS_OPEN = 1;
const WS_CLOSED = 3;

// Hoisted supabase mock — shared by every test, reconfigured per case.
const { mockSingle, mockEq, mockSelect, mockFrom } = vi.hoisted(() => {
  const mockSingle = vi.fn();
  const mockEq = vi.fn(() => ({ single: mockSingle }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  const mockFrom = vi.fn(() => ({ select: mockSelect }));
  return { mockSingle, mockEq, mockSelect, mockFrom };
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    auth: {
      getUser: vi.fn(),
    },
  }),
  serverUrl: "https://test.supabase.co",
}));

// Stub agent-runner to avoid loading @anthropic-ai/claude-agent-sdk.
vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

type WsHandler = typeof import("../server/ws-handler");
let wsHandler: WsHandler;

beforeAll(async () => {
  wsHandler = await import("../server/ws-handler");
});

beforeEach(() => {
  vi.useFakeTimers();
  mockSingle.mockReset();
  mockEq.mockClear();
  mockSelect.mockClear();
  mockFrom.mockClear();
});

afterEach(() => {
  vi.useRealTimers();
});

function makeSession(overrides: Partial<ClientSession> = {}): ClientSession {
  const ws = {
    readyState: WS_OPEN,
    send: vi.fn(),
    close: vi.fn(),
    ping: vi.fn(),
  } as unknown as ClientSession["ws"];
  return {
    ws,
    lastActivity: Date.now(),
    ...overrides,
  };
}

describe("ws-handler subscription refresh timer", () => {
  test("refresh tick to 'unpaid' closes the connection", async () => {
    mockSingle.mockResolvedValue({ data: { subscription_status: "unpaid" }, error: null });
    const session = makeSession({ subscriptionStatus: "active" });

    wsHandler.startSubscriptionRefresh("user-1", session);

    // Fire one refresh tick and drain the resulting microtasks.
    await vi.advanceTimersByTimeAsync(60_000);

    expect(mockFrom).toHaveBeenCalledWith("users");
    expect(session.subscriptionStatus).toBe("unpaid");
    expect((session.ws.close as ReturnType<typeof vi.fn>)).toHaveBeenCalled();

    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  });

  test("refresh tick to 'active' no-ops", async () => {
    mockSingle.mockResolvedValue({ data: { subscription_status: "active" }, error: null });
    const session = makeSession({ subscriptionStatus: "active" });

    wsHandler.startSubscriptionRefresh("user-2", session);
    await vi.advanceTimersByTimeAsync(60_000);

    expect(session.subscriptionStatus).toBe("active");
    expect((session.ws.close as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled();

    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  });

  test("refresh DB error preserves cached subscriptionStatus", async () => {
    mockSingle.mockResolvedValue({ data: null, error: { message: "db down" } });
    const session = makeSession({ subscriptionStatus: "active" });

    wsHandler.startSubscriptionRefresh("user-3", session);
    await vi.advanceTimersByTimeAsync(60_000);

    expect(session.subscriptionStatus).toBe("active");
    expect((session.ws.close as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled();

    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  });

  test("clearing the subscriptionRefreshTimer stops further DB queries", async () => {
    mockSingle.mockResolvedValue({ data: { subscription_status: "active" }, error: null });
    const session = makeSession({ subscriptionStatus: "active" });

    wsHandler.startSubscriptionRefresh("user-4", session);

    // First tick queries once.
    await vi.advanceTimersByTimeAsync(60_000);
    const callsAfterFirstTick = mockFrom.mock.calls.length;
    expect(callsAfterFirstTick).toBe(1);

    // Simulate teardown path (e.g., ws close handler) clearing the timer.
    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
    session.subscriptionRefreshTimer = undefined;

    // Advance two more intervals — no additional queries.
    await vi.advanceTimersByTimeAsync(120_000);
    expect(mockFrom.mock.calls.length).toBe(callsAfterFirstTick);
  });

  test("post-await readyState guard: no mutation when socket already closed", async () => {
    // Configure supabase to resolve to 'unpaid'. The guard must still prevent
    // mutation + close because readyState is CLOSED by the time the await settles.
    mockSingle.mockResolvedValue({ data: { subscription_status: "unpaid" }, error: null });

    const session = makeSession({ subscriptionStatus: "active" });
    // Flip readyState to CLOSED BEFORE the tick fires — simulates the socket
    // closing between timer scheduling and the await resolving.
    (session.ws as unknown as { readyState: number }).readyState = WS_CLOSED;

    wsHandler.startSubscriptionRefresh("user-5", session);
    await vi.advanceTimersByTimeAsync(60_000);

    // Cached value preserved, close() NOT called again (the ws is already closed).
    expect(session.subscriptionStatus).toBe("active");
    expect((session.ws.close as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled();

    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  });
});
