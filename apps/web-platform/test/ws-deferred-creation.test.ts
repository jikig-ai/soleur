import { describe, it, expect, vi, beforeEach } from "vitest";
import { WebSocket } from "ws";

// Track Supabase calls
const mockInsert = vi.fn().mockResolvedValue({ error: null });
const mockUpdateEq = vi.fn().mockResolvedValue({ error: null });
const mockUpdate = vi.fn().mockReturnValue({ eq: mockUpdateEq });
const mockSelectSingle = vi.fn().mockResolvedValue({
  data: { id: "conv-1", status: "active" },
  error: null,
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: () => ({
      insert: mockInsert,
      update: mockUpdate,
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            single: mockSelectSingle,
          }),
          single: vi.fn().mockResolvedValue({
            data: { subscription_status: "active" },
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

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

vi.mock("./error-sanitizer", () => ({
  sanitizeErrorForClient: (err: Error) => err.message,
}));

vi.mock("./logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    debug: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
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

/** Create a fake WS that captures sent messages. */
function createMockSession(): { session: ClientSession; sent: unknown[] } {
  const sent: unknown[] = [];
  const ws = {
    readyState: WebSocket.OPEN,
    send: (data: string) => sent.push(JSON.parse(data)),
    ping: vi.fn(),
    close: vi.fn(),
  } as unknown as WebSocket;
  const session: ClientSession = { ws, lastActivity: Date.now() };
  return { session, sent };
}

describe("deferred conversation creation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessions.clear();
  });

  it("start_session does not insert a conversation row", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));

    // No insert should have been called — conversation deferred
    expect(mockInsert).not.toHaveBeenCalled();

    // session_started should be sent with a pending UUID
    const started = sent.find((m: any) => m.type === "session_started") as any;
    expect(started).toBeTruthy();
    expect(started.conversationId).toBeTruthy();

    // Session should have pending state, not conversationId
    expect(session.pending?.id).toBe(started.conversationId);
    expect(session.conversationId).toBeUndefined();
  });

  it("first chat message with real content creates the conversation", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    // Step 1: start_session (deferred)
    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));
    const started = sent.find((m: any) => m.type === "session_started") as any;
    expect(session.pending?.id).toBe(started.conversationId);

    // Step 2: send chat with real content
    await handleMessage("user-1", JSON.stringify({
      type: "chat",
      content: "Set up Stripe webhooks",
    }));

    // Now a conversation should have been inserted
    expect(mockInsert).toHaveBeenCalled();
    // Session should transition from pending to active
    expect(session.conversationId).toBe(started.conversationId);
    expect(session.pending?.id).toBeUndefined();
  });

  it("chat with only @-mention does not create conversation", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({
      type: "start_session",
      leaderId: "cto",
    }));

    await handleMessage("user-1", JSON.stringify({
      type: "chat",
      content: "@cto",
    }));

    expect(mockInsert).not.toHaveBeenCalled();
    const errorMsg = sent.find((m: any) => m.type === "error") as any;
    expect(errorMsg).toBeTruthy();
    expect(errorMsg.message).toContain("@-mention");
  });

  it("close_conversation with pending state cleans up without DB update", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));
    expect(session.pending?.id).toBeTruthy();

    await handleMessage("user-1", JSON.stringify({ type: "close_conversation" }));

    // No DB update — conversation was never created
    expect(mockUpdate).not.toHaveBeenCalled();
    // Pending state cleaned up
    expect(session.pending?.id).toBeUndefined();
    // session_ended should be sent
    const ended = sent.find((m: any) => m.type === "session_ended") as any;
    expect(ended).toBeTruthy();
  });
});
