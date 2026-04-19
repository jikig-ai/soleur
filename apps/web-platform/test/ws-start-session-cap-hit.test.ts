import { describe, it, expect, vi, beforeEach } from "vitest";
import { WebSocket } from "ws";

process.env.STRIPE_SECRET_KEY = "sk_test";
process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: mockRpc,
    from: () => ({
      insert: vi.fn().mockResolvedValue({ error: null }),
      update: () => ({ eq: vi.fn().mockResolvedValue({ error: null }) }),
      select: () => ({
        eq: () => ({
          single: vi.fn().mockResolvedValue({
            data: { id: "conv-1", status: "active", subscription_status: "active", plan_tier: "solo" },
            error: null,
          }),
        }),
      }),
    }),
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
  }),
}));

vi.mock("./agent-runner", () => ({
  startAgentSession: vi.fn().mockResolvedValue(undefined),
  sendUserMessage: vi.fn().mockResolvedValue(undefined),
  resolveReviewGate: vi.fn().mockResolvedValue(undefined),
  abortSession: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn(), addBreadcrumb: vi.fn() }));
vi.mock("./error-sanitizer", () => ({ sanitizeErrorForClient: (err: Error) => err.message }));
vi.mock("./logger", () => ({
  createChildLogger: () => ({ info: vi.fn(), debug: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
vi.mock("./rate-limiter", () => ({
  connectionThrottle: { isAllowed: () => true },
  sessionThrottle: { isAllowed: () => true },
  pendingConnections: { add: () => true, remove: () => {}, get: () => 0 },
  extractClientIp: () => "127.0.0.1",
  logRateLimitRejection: vi.fn(),
}));
vi.mock("./context-validation", () => ({
  validateConversationContext: (ctx: unknown) => ctx,
}));

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";

interface SentCapture {
  sent: unknown[];
  closeCalls: Array<{ code: number; reason: string }>;
}

function createMockSession(planTier: "free" | "solo" | "startup" = "solo"): {
  session: ClientSession;
  capture: SentCapture;
} {
  const capture: SentCapture = { sent: [], closeCalls: [] };
  const ws = {
    readyState: WebSocket.OPEN,
    send: (data: string) => capture.sent.push(JSON.parse(data)),
    ping: vi.fn(),
    close: (code: number, reason: string) => {
      capture.closeCalls.push({ code, reason });
      (ws as { readyState: number }).readyState = WebSocket.CLOSED;
    },
  } as unknown as WebSocket;
  const session: ClientSession = {
    ws,
    lastActivity: Date.now(),
    planTier,
    concurrencyOverride: null,
  };
  return { session, capture };
}

describe("start_session — concurrency cap enforcement", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessions.clear();
    mockRpc.mockReset();
  });

  it("cap_hit: sends preamble, closes with 4010, does not set pending", async () => {
    mockRpc.mockResolvedValue({
      data: [{ status: "cap_hit", active_count: 2, effective_cap: 2 }],
      error: null,
    });
    const { session, capture } = createMockSession("solo");
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));

    expect(capture.closeCalls).toEqual([{ code: 4010, reason: "CONCURRENCY_CAP" }]);
    expect(session.pending).toBeUndefined();

    const preamble = capture.sent.find((m) => (m as { type?: string }).type === "concurrency_cap_hit") as Record<string, unknown>;
    expect(preamble).toBeTruthy();
    expect(preamble).toMatchObject({
      type: "concurrency_cap_hit",
      currentTier: "solo",
      nextTier: "startup",
      activeCount: 2,
      effectiveCap: 2,
    });
  });

  it("ok: proceeds to deferred creation and does not close", async () => {
    mockRpc.mockResolvedValue({
      data: [{ status: "ok", active_count: 1, effective_cap: 2 }],
      error: null,
    });
    const { session, capture } = createMockSession("solo");
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));

    expect(capture.closeCalls).toEqual([]);
    expect(session.pending?.id).toBeTruthy();
    expect(capture.sent.some((m) => (m as { type?: string }).type === "session_started")).toBe(true);
  });

  it("free tier emits nextTier='solo' in preamble", async () => {
    mockRpc.mockResolvedValue({
      data: [{ status: "cap_hit", active_count: 1, effective_cap: 1 }],
      error: null,
    });
    const { session, capture } = createMockSession("free");
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));

    const preamble = capture.sent.find((m) => (m as { type?: string }).type === "concurrency_cap_hit") as Record<string, unknown>;
    expect(preamble).toMatchObject({ currentTier: "free", nextTier: "solo" });
  });

  it("enterprise cap-hit returns nextTier=null (top of ladder)", async () => {
    mockRpc.mockResolvedValue({
      data: [{ status: "cap_hit", active_count: 50, effective_cap: 50 }],
      error: null,
    });
    const { session, capture } = createMockSession("solo");
    session.planTier = "enterprise";
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));

    const preamble = capture.sent.find((m) => (m as { type?: string }).type === "concurrency_cap_hit") as Record<string, unknown>;
    expect(preamble.nextTier).toBeNull();
  });
});
