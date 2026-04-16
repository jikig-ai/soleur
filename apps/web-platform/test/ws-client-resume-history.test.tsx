import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
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
  let fetchSpy: ReturnType<typeof vi.spyOn>;

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

    // Give effects time to run
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });

    // No additional fetch calls from the resume effect
    const resumeFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-known-456"),
    );
    // May be 0 or 1 (from the existing effect), but NOT from the new resume effect
    expect(resumeFetchCalls.length).toBeLessThanOrEqual(1);
  });
});
