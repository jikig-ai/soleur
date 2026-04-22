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
// `refreshSubscriptionStatus` now makes two DB calls per tick when status
// is not 'unpaid': (a) SELECT on `users` terminated by `.single()`, and
// (b) SELECT count on `user_concurrency_slots` terminated by `.eq()`
// (head: true, count: 'exact' — thenable returns `{ count, error }`).
const { mockSingle, mockEq, mockSelect, mockFrom, mockCount } = vi.hoisted(() => {
  const mockSingle = vi.fn();
  const mockCount = vi.fn();
  const mockEq = vi.fn((_col: string, _val: unknown) => {
    // Route the thenable case to mockCount. `.eq()` on the `users` path is
    // immediately followed by `.single()` so `single` is still reachable.
    const result = { single: mockSingle } as { single: typeof mockSingle; then?: unknown };
    result.then = (resolve: (v: unknown) => unknown) => resolve(mockCount());
    return result;
  });
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  const mockFrom = vi.fn(() => ({ select: mockSelect }));
  return { mockSingle, mockEq, mockSelect, mockFrom, mockCount };
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
  mockCount.mockReset();
  // Default: no cap drift (count <= any cap). Tests exercising drift override
  // this with a specific count value.
  mockCount.mockReturnValue({ count: 0, error: null });
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

    // First tick queries twice (users + user_concurrency_slots count).
    await vi.advanceTimersByTimeAsync(60_000);
    const callsAfterFirstTick = mockFrom.mock.calls.length;
    expect(callsAfterFirstTick).toBe(2);

    // Simulate teardown path (e.g., ws close handler) clearing the timer.
    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
    session.subscriptionRefreshTimer = undefined;

    // Advance two more intervals — no additional queries.
    await vi.advanceTimersByTimeAsync(120_000);
    expect(mockFrom.mock.calls.length).toBe(callsAfterFirstTick);
  });

  test("cap-drift self-evict: count > newCap closes session with 4011", async () => {
    // User was Scale (cap 50), downgraded to Solo (cap 2) via webhook that
    // landed on another process (simulated: our session never received the
    // 4011 push). The refresh tick re-reads plan_tier='solo' and sees
    // count=3 > newCap=2; passive check evicts THIS session so the user
    // reconverges at the new cap on reconnect.
    mockSingle.mockResolvedValue({
      data: { subscription_status: "active", plan_tier: "solo", concurrency_override: null },
      error: null,
    });
    mockCount.mockReturnValue({ count: 3, error: null });

    const session = makeSession({ subscriptionStatus: "active", planTier: "scale" });
    wsHandler.startSubscriptionRefresh("user-drift", session);
    await vi.advanceTimersByTimeAsync(60_000);

    // Fresh tier is committed to the session before the eviction.
    expect(session.planTier).toBe("solo");
    // closeWithPreamble sends the preamble then calls ws.close; both run.
    const sendCalls = (session.ws.send as ReturnType<typeof vi.fn>).mock.calls;
    expect(sendCalls.some((call: unknown[]) => {
      const raw = call[0];
      if (typeof raw !== "string") return false;
      const parsed = JSON.parse(raw);
      return parsed.type === "tier_changed" && parsed.previousTier === "scale" && parsed.newTier === "solo";
    })).toBe(true);
    expect((session.ws.close as ReturnType<typeof vi.fn>)).toHaveBeenCalled();

    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
  });

  test("cap-drift self-evict: count <= newCap does NOT close", async () => {
    // RED inversion of the test above. Same plan_tier change but count is
    // within new cap; no eviction should fire. Without this test, the
    // cap-drift branch could silently always-evict and the above test would
    // still pass.
    mockSingle.mockResolvedValue({
      data: { subscription_status: "active", plan_tier: "solo", concurrency_override: null },
      error: null,
    });
    mockCount.mockReturnValue({ count: 1, error: null });

    const session = makeSession({ subscriptionStatus: "active", planTier: "scale" });
    wsHandler.startSubscriptionRefresh("user-no-drift", session);
    await vi.advanceTimersByTimeAsync(60_000);

    expect(session.planTier).toBe("solo");
    expect((session.ws.close as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled();

    if (session.subscriptionRefreshTimer) clearInterval(session.subscriptionRefreshTimer);
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
