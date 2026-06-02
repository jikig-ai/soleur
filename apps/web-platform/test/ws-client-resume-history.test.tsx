import { describe, it, expect, vi, type MockInstance, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// --- Mocks ---

const mockGetSession = vi.fn().mockResolvedValue({
  data: { session: { access_token: "test-token" } },
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: { getSession: mockGetSession },
  }),
}));

// Capture the WebSocket instance so tests can simulate server messages
let wsInstance: {
  onopen: ((ev: Event) => void) | null;
  onmessage: ((ev: MessageEvent) => void) | null;
  onclose: ((ev: CloseEvent) => void) | null;
  onerror: ((ev: Event) => void) | null;
  send: ReturnType<typeof vi.fn>;
  close: ReturnType<typeof vi.fn>;
  readyState: number;
} | null = null;

class MockWebSocket {
  static OPEN = 1;
  static CONNECTING = 0;
  onopen: ((ev: Event) => void) | null = null;
  onmessage: ((ev: MessageEvent) => void) | null = null;
  onclose: ((ev: CloseEvent) => void) | null = null;
  onerror: ((ev: Event) => void) | null = null;
  send = vi.fn();
  close = vi.fn();
  readyState = MockWebSocket.OPEN;
  constructor() {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    wsInstance = this;
    // Simulate connection opening asynchronously
    queueMicrotask(() => {
      this.readyState = MockWebSocket.OPEN;
      this.onopen?.(new Event("open"));
    });
  }
}

// History messages returned by the fetch mock
const historyMessages = [
  { id: "hist-1", role: "user", content: "Hello", leader_id: null },
  { id: "hist-2", role: "assistant", content: "Hi there!", leader_id: "cto" },
  { id: "hist-3", role: "user", content: "How are you?", leader_id: null },
];

describe("useWebSocket — resume history fetch (AC1, AC3, AC4)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;
  let fetchSpy: MockInstance;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;

    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error — mock constructor shape
    globalThis.WebSocket = MockWebSocket;

    fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ messages: historyMessages }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  });

  afterEach(() => {
    globalThis.WebSocket = originalWebSocket;
    fetchSpy.mockRestore();
  });

  /** Helper: simulate server sending a WS message to the client */
  function serverSend(data: Record<string, unknown>) {
    act(() => {
      wsInstance?.onmessage?.(new MessageEvent("message", {
        data: JSON.stringify(data),
      }));
    });
  }

  /** Helper: bring the hook to "connected + session confirmed" state */
  async function connectAndAuth(result: { current: ReturnType<typeof import("@/lib/ws-client").useWebSocket> }) {
    // Wait for WebSocket onopen + auth send
    await waitFor(() => {
      expect(wsInstance).not.toBeNull();
      expect(wsInstance?.send).toHaveBeenCalled();
    });

    // Server confirms auth
    serverSend({ type: "auth_ok" });

    await waitFor(() => {
      expect(result.current.status).toBe("connected");
    });
  }

  it("fetches history when realConversationId is set from session_resumed", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // Server sends session_resumed (the sidebar resume path)
    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    // The new effect should fire and fetch history
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-existing-123/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // Messages should contain the fetched history
    await waitFor(() => {
      expect(result.current.messages.length).toBe(3);
      expect(result.current.messages[0].id).toBe("hist-1");
      expect(result.current.messages[1].id).toBe("hist-2");
      expect(result.current.messages[2].id).toBe("hist-3");
    });
  });

  it("preserves chronological order (oldest first)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    await waitFor(() => {
      expect(result.current.messages.length).toBe(3);
    });

    // Verify order: user, assistant, user (oldest first)
    expect(result.current.messages[0].role).toBe("user");
    expect(result.current.messages[0].content).toBe("Hello");
    expect(result.current.messages[1].role).toBe("assistant");
    expect(result.current.messages[1].content).toBe("Hi there!");
    expect(result.current.messages[2].role).toBe("user");
    expect(result.current.messages[2].content).toBe("How are you?");
  });

  it("deduplicates messages if a stream event arrives during fetch", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // Simulate a stream_start that creates a message with ID "hist-2"
    // BEFORE the resume event fires (simulates race condition)
    serverSend({
      type: "stream_start",
      leaderId: "cto",
      messageId: "hist-2",
    });

    // Now server sends session_resumed — the history fetch should
    // deduplicate "hist-2" which already exists from the stream
    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    // Wait for history to load
    await waitFor(() => {
      // Should have history messages PLUS the stream message, but
      // "hist-2" should appear only once (deduplication)
      const hist2Count = result.current.messages.filter((m) => m.id === "hist-2").length;
      expect(hist2Count).toBe(1);
      // Total should be 3 (hist-1, hist-2 deduplicated, hist-3) + 0 extra
      // The stream_start created a bubble for "hist-2" which history also contains
      expect(result.current.messages.length).toBeGreaterThanOrEqual(3);
    });
  });

  it("seeds usageData from cost fields in the history response", async () => {
    // Override fetch mock to include cost data in response
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify({
        messages: historyMessages,
        totalCostUsd: 0.0042,
        inputTokens: 1200,
        outputTokens: 300,
      }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    // Wait for history to load AND usageData to be seeded
    await waitFor(() => {
      expect(result.current.messages.length).toBe(3);
      // Cache token fields default to 0 when the history response
      // omits them (pre-2026-05-12 conversations). New conversations
      // surface non-zero values; resume of those is exercised by
      // `chat-page-resume.test.tsx`.
      expect(result.current.usageData).toEqual({
        totalCostUsd: 0.0042,
        inputTokens: 1200,
        outputTokens: 300,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
      });
    });
  });

  it("does NOT fetch history for a fresh session_started conversation (FR1/AC1)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // Server starts a BRAND-NEW conversation: deferred-creation path emits
    // session_started with a pending UUID and NO DB row yet. resumedFrom
    // stays null. The resume-history effect must NOT fire a fetch — the row
    // does not exist, so GET /messages would 404 (the bug this fixes).
    serverSend({
      type: "session_started",
      conversationId: "conv-fresh-deferred-999",
    });

    // The handler ran (realConversationId resolved). With both state updates
    // batched, the resume effect has had its chance to fire.
    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-fresh-deferred-999");
    });

    // No history fetch for the fresh deferred id, and the hook never enters
    // the loading state for it.
    const freshFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-fresh-deferred-999"),
    );
    expect(freshFetchCalls.length).toBe(0);
    expect(result.current.historyLoading).toBe(false);
  });

  it("fetches history for a session_resumed row with zero messages (FR2/AC2)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // A genuine resume of an existing row that happens to have 0 messages
    // MUST still fetch (the row exists; api-messages returns 200-empty). The
    // gate keys on session_started vs session_resumed, NOT on message count.
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify({ messages: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    serverSend({
      type: "session_resumed",
      conversationId: "conv-resumed-empty-777",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 0,
    });

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-resumed-empty-777/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // Exactly one fetch for the resolved id (the resume effect fired once).
    const resumedFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-resumed-empty-777"),
    );
    expect(resumedFetchCalls.length).toBe(1);

    await waitFor(() => {
      expect(result.current.historyLoading).toBe(false);
      expect(result.current.messages.length).toBe(0);
    });
  });

  it("flips resumed→fresh within one mounted hook: switching from a resumed thread to a new chat does NOT fetch (FR1 hook-reuse)", async () => {
    // The KB sidebar reuses ONE useWebSocket across conversation switches
    // (resumeByContextPath resolves a new realConversationId while the hook
    // stays mounted). If sessionKind failed to flip back to "fresh" on the
    // second session_started, the resume effect would fire a would-be-404
    // fetch for the fresh id. This locks the FR1 gate against that path.
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // 1) Resume an existing thread → fetch fires.
    serverSend({
      type: "session_resumed",
      conversationId: "conv-A-resumed",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-A-resumed/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // 2) Same mounted hook now starts a BRAND-NEW conversation. sessionKind
    //    must flip "resumed" → "fresh", so NO fetch fires for the new id.
    fetchSpy.mockClear();
    serverSend({
      type: "session_started",
      conversationId: "conv-B-fresh",
    });

    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-B-fresh");
    });

    const freshFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-B-fresh"),
    );
    expect(freshFetchCalls.length).toBe(0);
    expect(result.current.historyLoading).toBe(false);
  });

  it("deep-link to a never-materialized uuid 404s into the empty state, not the error boundary (FR5/AC9)", async () => {
    // Full-route navigation to /dashboard/chat/<uuid> for a valid-but-
    // deferred / never-persisted id (stale bookmark). The mount-time effect
    // fetches, gets a 404, returns null silently. The resting state must be
    // the empty composer: historyLoading false, no messages, no lastError
    // (lastError is a WS-connection error, NOT a history-fetch 404).
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("11111111-2222-3333-4444-555555555555"));

    await connectAndAuth(result);

    // Mount-time effect fired the fetch for the non-"new" id.
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/11111111-2222-3333-4444-555555555555/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // Resting state = empty composer, not error boundary.
    await waitFor(() => {
      expect(result.current.historyLoading).toBe(false);
    });
    expect(result.current.messages.length).toBe(0);
    expect(result.current.lastError).toBeNull();
  });

  it("does NOT fetch history when conversationId is not 'new'", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    // Using a real conversation ID (not "new") — the existing effect handles this
    const { result } = renderHook(() => useWebSocket("conv-known-456"));

    await connectAndAuth(result);

    serverSend({
      type: "session_started",
      conversationId: "conv-known-456",
    });

    // The existing effect already fetches for non-"new" IDs.
    // The new resume-specific effect should NOT fire because
    // realConversationId matches the prop conversationId.
    // Clear the fetch spy calls from the existing effect
    fetchSpy.mockClear();

    // Wait for any pending effects to settle deterministically
    await waitFor(() => {
      // No additional fetch calls from the resume effect — the guard
      // (realConversationId === conversationId) prevents the resume
      // effect from firing when both IDs match.
      const resumeFetchCalls = fetchSpy.mock.calls.filter(
        (call) => typeof call[0] === "string" && call[0].includes("conv-known-456"),
      );
      expect(resumeFetchCalls.length).toBe(0);
    });
  });
});
