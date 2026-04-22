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
// Lazy-evaluated `users.repo_url` lets individual tests simulate a
// disconnected user (repo_url=null) to exercise the abort path.
let mockUserRepoUrl: string | null = "https://github.com/acme/repo";

const { mockRpc } = vi.hoisted(() => ({
  mockRpc: vi.fn().mockResolvedValue({
    data: [{ status: "ok", active_count: 1, effective_cap: 2 }],
    error: null,
  }),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "users") {
        // `users` reads go through .select().eq().maybeSingle() to fetch
        // repo_url so conversation inserts can be scoped to the current repo.
        // Return shape is evaluated at call time so individual tests can
        // simulate the disconnected state via `mockUserRepoUrl = null`.
        //
        // NOT migrated to `test/mocks/supabase-query-builder.ts`: this
        // inline `chain` is a predicate-aware recursive mock that
        // `start_session` tests rely on for `.eq()` predicate inspection.
        // The shared `buildSupabaseQueryBuilder` serves non-predicate-aware
        // cases. See plan
        // `2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
        // §Non-Goals / R5 for the deliberate carve-out.
        const chain = {
          select: vi.fn(() => chain),
          eq: vi.fn(() => chain),
          maybeSingle: vi.fn(async () => ({
            data: { repo_url: mockUserRepoUrl },
            error: null,
          })),
        };
        return chain;
      }
      return {
        insert: mockInsert,
        update: mockUpdate,
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            eq: vi.fn().mockReturnValue({
              single: mockSelectSingle,
            }),
          }),
        }),
      };
    },
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    rpc: mockRpc,
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
    mockUserRepoUrl = "https://github.com/acme/repo";
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

  it("chat after disconnect (users.repo_url=null) aborts without inserting", async () => {
    // Plan risk R-D: user disconnects between start_session and their
    // first real chat message. createConversation must abort rather than
    // orphan a row stamped with a stale repo_url (or no repo_url at all).
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    // Connected for start_session; disconnected before the chat arrives.
    mockUserRepoUrl = "https://github.com/acme/repo";
    await handleMessage("user-1", JSON.stringify({ type: "start_session" }));

    mockUserRepoUrl = null;
    await handleMessage(
      "user-1",
      JSON.stringify({ type: "chat", content: "First message" }),
    );

    // No conversation row inserted.
    expect(mockInsert).not.toHaveBeenCalled();
    // An error was surfaced to the client.
    const errorMsg = sent.find((m: any) => m.type === "error") as any;
    expect(errorMsg).toBeTruthy();
    // Pending state retained so a reconnect could retry (or the client
    // can close cleanly).
    expect(session.conversationId).toBeUndefined();
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
