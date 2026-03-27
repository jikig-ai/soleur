// Set env vars BEFORE dynamic imports — ws-handler.ts and agent-runner.ts
// create Supabase clients at module load time.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach, beforeAll } from "vitest";

// Minimal interface matching ws-handler's ClientSession (avoids static import
// that would trigger module evaluation before env vars are set).
interface ClientSession {
  ws: unknown;
  conversationId?: string;
  disconnectTimer?: ReturnType<typeof setTimeout>;
}

let abortActiveSession: (userId: string, session: ClientSession) => void;
let agentRunnerModule: { abortSession: (userId: string, conversationId: string) => void };

beforeAll(async () => {
  // Dynamic imports ensure env vars are set before modules evaluate
  agentRunnerModule = await import("../server/agent-runner");
  const wsHandler = await import("../server/ws-handler");
  abortActiveSession = wsHandler.abortActiveSession;
  vi.spyOn(agentRunnerModule, "abortSession");
});

describe("abortActiveSession", () => {
  let mockWs: ClientSession["ws"];

  beforeEach(() => {
    vi.clearAllMocks();
    mockWs = { readyState: 1, send: vi.fn(), ping: vi.fn() };
  });

  test("aborts the active session and clears conversationId", () => {
    const session: ClientSession = { ws: mockWs, conversationId: "conv-A" };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).toHaveBeenCalledWith("user-1", "conv-A");
    expect(session.conversationId).toBeUndefined();
  });

  test("no-ops when conversationId is undefined", () => {
    const session: ClientSession = { ws: mockWs };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).not.toHaveBeenCalled();
    expect(session.conversationId).toBeUndefined();
  });

  test("is idempotent — second call is a no-op after first clears conversationId", () => {
    const session: ClientSession = { ws: mockWs, conversationId: "conv-C" };

    abortActiveSession("user-1", session);
    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).toHaveBeenCalledTimes(1);
  });
});

describe("concurrent session abort scenarios", () => {
  let mockWs: ClientSession["ws"];

  beforeEach(() => {
    vi.clearAllMocks();
    mockWs = { readyState: 1, send: vi.fn(), ping: vi.fn() };
  });

  test("start_session with prior active session: abort fires before new session", () => {
    const session: ClientSession = { ws: mockWs, conversationId: "conv-A" };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).toHaveBeenCalledWith("user-1", "conv-A");
    expect(session.conversationId).toBeUndefined();

    // Caller sets new conversationId (simulating createConversation)
    session.conversationId = "conv-B";
    expect(session.conversationId).toBe("conv-B");
  });

  test("resume_session with prior active session: abort fires before ownership check", () => {
    const session: ClientSession = { ws: mockWs, conversationId: "conv-A" };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).toHaveBeenCalledWith("user-1", "conv-A");
    expect(session.conversationId).toBeUndefined();

    session.conversationId = "conv-B";
    expect(session.conversationId).toBe("conv-B");
  });

  test("close_conversation after prior abort: no-op since conversationId already cleared", () => {
    const session: ClientSession = { ws: mockWs, conversationId: "conv-A" };

    abortActiveSession("user-1", session);
    expect(agentRunnerModule.abortSession).toHaveBeenCalledTimes(1);

    abortActiveSession("user-1", session);
    expect(agentRunnerModule.abortSession).toHaveBeenCalledTimes(1);
  });

  test("first connection (no prior session): guard is no-op", () => {
    const session: ClientSession = { ws: mockWs };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).not.toHaveBeenCalled();
  });
});
