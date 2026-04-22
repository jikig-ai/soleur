import { describe, it, expect, vi, beforeEach } from "vitest";
import { WebSocket } from "ws";

const mockInsert = vi.fn().mockResolvedValue({ error: null });
const mockUpdateEq = vi.fn().mockResolvedValue({ error: null });
const mockUpdate = vi.fn().mockReturnValue({ eq: mockUpdateEq });

// conversations lookup by context_path
// from().select().eq(user_id, ...).eq(context_path, ...).is(archived_at, null).order().limit().maybeSingle()
let conversationLookupResult: { data: unknown; error: unknown } = { data: null, error: null };
let messageCountResult: { count: number; error: unknown } = { count: 0, error: null };

const mockMaybeSingle = vi.fn(() => Promise.resolve(conversationLookupResult));
const mockCountQuery = vi.fn(() => Promise.resolve(messageCountResult));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "messages") {
        return {
          select: () => ({
            eq: () => mockCountQuery(),
          }),
        };
      }
      return {
        insert: mockInsert,
        update: mockUpdate,
        select: () => {
          // Recursive eq() chain so any length of predicates terminates at
          // is().order().limit().maybeSingle(). The ws-handler lookup now
          // uses 3 .eq() calls (user_id, repo_url, context_path).
          const tail = {
            is: () => ({
              order: () => ({
                limit: () => ({
                  maybeSingle: mockMaybeSingle,
                }),
              }),
            }),
          };
          const eqChain: Record<string, unknown> = {
            eq: (...args: unknown[]) => {
              void args;
              return eqChain;
            },
            single: vi.fn().mockResolvedValue({
              data: { id: "conv-1", status: "active", repo_url: mockUserRepoUrl },
              error: null,
            }),
            ...tail,
          };
          return eqChain;
        },
      };
    },
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

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
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

// getCurrentRepoUrl is read before the context_path lookup so the query
// can scope by (user_id, repo_url, context_path). Tests default to a
// connected repo; null simulates the disconnected state.
let mockUserRepoUrl: string | null = "https://github.com/acme/repo";
vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: () => Promise.resolve(mockUserRepoUrl),
}));

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";

function createMockSession(): { session: ClientSession; sent: any[] } {
  const sent: any[] = [];
  const ws = {
    readyState: WebSocket.OPEN,
    send: (data: string) => sent.push(JSON.parse(data)),
    ping: vi.fn(),
    close: vi.fn(),
  } as unknown as WebSocket;
  const session: ClientSession = { ws, lastActivity: Date.now() };
  return { session, sent };
}

describe("start_session resumeByContextPath", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessions.clear();
    conversationLookupResult = { data: null, error: null };
    messageCountResult = { count: 0, error: null };
  });

  it("resumes existing conversation when context_path row is found", async () => {
    conversationLookupResult = {
      data: {
        id: "existing-conv-123",
        last_active: "2026-04-15T10:00:00Z",
        context_path: "knowledge-base/product/roadmap.md",
      },
      error: null,
    };
    messageCountResult = { count: 7, error: null };

    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        context: { path: "knowledge-base/product/roadmap.md", type: "kb-viewer" },
        resumeByContextPath: "knowledge-base/product/roadmap.md",
      }),
    );

    const resumed = sent.find((m) => m.type === "session_resumed");
    expect(resumed).toBeTruthy();
    expect(resumed.conversationId).toBe("existing-conv-123");
    expect(resumed.resumedFromTimestamp).toBe("2026-04-15T10:00:00Z");
    expect(resumed.messageCount).toBe(7);
    expect(session.conversationId).toBe("existing-conv-123");
    expect(session.pending).toBeUndefined();
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("falls through to pending creation when no existing row found", async () => {
    conversationLookupResult = { data: null, error: null };

    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        context: { path: "knowledge-base/new-doc.md", type: "kb-viewer" },
        resumeByContextPath: "knowledge-base/new-doc.md",
      }),
    );

    const started = sent.find((m) => m.type === "session_started");
    expect(started).toBeTruthy();
    expect(session.pending?.id).toBe(started.conversationId);
    expect(session.pending?.contextPath).toBe("knowledge-base/new-doc.md");
    expect(session.conversationId).toBeUndefined();
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("rejects non-string resumeByContextPath (review #2381)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        resumeByContextPath: { path: "knowledge-base/x.md" },
      }),
    );

    const err = sent.find((m) => m.type === "error");
    expect(err).toBeTruthy();
    expect(err.message).toMatch(/invalid/i);
    expect(session.pending).toBeUndefined();
    expect(mockMaybeSingle).not.toHaveBeenCalled();
  });

  it("rejects resumeByContextPath > 512 chars (review #2381)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    const long = "knowledge-base/" + "a".repeat(600);
    await handleMessage(
      "user-1",
      JSON.stringify({ type: "start_session", resumeByContextPath: long }),
    );

    const err = sent.find((m) => m.type === "error");
    expect(err).toBeTruthy();
    expect(mockMaybeSingle).not.toHaveBeenCalled();
  });

  it("rejects resumeByContextPath without knowledge-base/ prefix (review #2381)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        resumeByContextPath: "/etc/passwd",
      }),
    );

    const err = sent.find((m) => m.type === "error");
    expect(err).toBeTruthy();
    expect(mockMaybeSingle).not.toHaveBeenCalled();
  });

  it("rejects resumeByContextPath with disallowed characters (review #2381)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        resumeByContextPath: "knowledge-base/x; DROP TABLE conversations;",
      }),
    );

    const err = sent.find((m) => m.type === "error");
    expect(err).toBeTruthy();
    expect(mockMaybeSingle).not.toHaveBeenCalled();
  });

  it("accepts resumeByContextPath with spaces and unicode (review #2412)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        resumeByContextPath: "knowledge-base/overview/Au Chat Pôtan - Pitch Projet.pdf",
      }),
    );

    // Should NOT get an error — path is valid
    const err = sent.find((m) => m.type === "error" && /invalid resumeByContextPath/i.test(m.message));
    expect(err).toBeUndefined();
  });

  it("rejects resumeByContextPath with path traversal (review #2412)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        resumeByContextPath: "knowledge-base/../../../etc/passwd",
      }),
    );

    const err = sent.find((m) => m.type === "error");
    expect(err).toBeTruthy();
    expect(mockMaybeSingle).not.toHaveBeenCalled();
  });

  it("rejects resumeByContextPath with dotfile (review #2412)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({
        type: "start_session",
        resumeByContextPath: "knowledge-base/.env",
      }),
    );

    const err = sent.find((m) => m.type === "error");
    expect(err).toBeTruthy();
    expect(mockMaybeSingle).not.toHaveBeenCalled();
  });

  it("start_session without resumeByContextPath behaves as before (pending)", async () => {
    const { session, sent } = createMockSession();
    sessions.set("user-1", session);

    await handleMessage(
      "user-1",
      JSON.stringify({ type: "start_session" }),
    );

    const started = sent.find((m) => m.type === "session_started");
    expect(started).toBeTruthy();
    expect(session.pending?.id).toBeTruthy();
    expect(session.pending?.contextPath).toBeUndefined();
  });
});
