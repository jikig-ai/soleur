import { describe, it, expect, vi, type MockInstance, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// Task 5.8 (RED) — useWebSocket.abort() contract.
//
// The hook return surface gains:
//   - `streamState: "idle" | "streaming" | "stopping"`, driven by stream_start /
//     stream_end / session_ended events.
//   - `abort(): void`, which sends `{ type: "abort_turn", conversationId }`
//     over the socket and transitions streamState to "stopping" optimistically.
//
// Mirrors the patterns in ws-client-resume-history.test.tsx for WebSocket /
// supabase / fetch mocking.

const mockGetSession = vi.fn().mockResolvedValue({
  data: { session: { access_token: "test-token" } },
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: { getSession: mockGetSession },
  }),
}));

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
    queueMicrotask(() => {
      this.readyState = MockWebSocket.OPEN;
      this.onopen?.(new Event("open"));
    });
  }
}

function serverSend(data: Record<string, unknown>) {
  act(() => {
    wsInstance?.onmessage?.(new MessageEvent("message", { data: JSON.stringify(data) }));
  });
}

async function connectAndAuth(result: {
  current: ReturnType<typeof import("@/lib/ws-client").useWebSocket>;
}) {
  await waitFor(() => {
    expect(wsInstance).not.toBeNull();
    expect(wsInstance?.send).toHaveBeenCalled();
  });
  serverSend({ type: "auth_ok" });
  await waitFor(() => {
    expect(result.current.status).toBe("connected");
  });
}

describe("useWebSocket — abort() (task 5.8)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;
  let fetchSpy: MockInstance;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;
    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error — mock constructor shape
    globalThis.WebSocket = MockWebSocket;
    fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ messages: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  });

  afterEach(() => {
    globalThis.WebSocket = originalWebSocket;
    fetchSpy.mockRestore();
  });

  it("starts in streamState='idle'", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);

    expect(result.current.streamState).toBe("idle");
  });

  it("transitions to streamState='streaming' on stream_start", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "stream_start", leaderId: "cto" });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });
  });

  it("abort() sends { type: 'abort_turn', conversationId } over the socket", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "stream_start", leaderId: "cto" });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });

    const sendCallsBefore = wsInstance!.send.mock.calls.length;
    act(() => {
      result.current.abort();
    });

    // The latest send must be an abort_turn frame with the conversationId.
    const newCalls = wsInstance!.send.mock.calls.slice(sendCallsBefore);
    const aborts = newCalls
      .map((c) => {
        try {
          return JSON.parse(c[0] as string);
        } catch {
          return null;
        }
      })
      .filter((m) => m && m.type === "abort_turn");
    expect(aborts.length).toBe(1);
    expect(aborts[0].conversationId).toBe("cid-1");
  });

  it("abort() transitions streamState to 'stopping' optimistically", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "stream_start", leaderId: "cto" });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });

    act(() => {
      result.current.abort();
    });

    expect(result.current.streamState).toBe("stopping");
  });

  it("session_ended for the matching conversationId returns streamState to 'idle'", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "stream_start", leaderId: "cto" });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });

    act(() => {
      result.current.abort();
    });

    expect(result.current.streamState).toBe("stopping");

    serverSend({
      type: "session_ended",
      reason: "user_aborted",
      conversationId: "cid-1",
    });

    await waitFor(() => {
      expect(result.current.streamState).toBe("idle");
    });
  });

  it("transitions to streamState='streaming' on first `stream` event without prior `stream_start` (review fix — Finding 2)", async () => {
    // Brand-survival regression gate: if the server emits content directly
    // via `stream` (sub-agent path or tool-only turn) without a leading
    // `stream_start`, the Stop button must still appear. The original
    // implementation only handled `stream_start`.
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({
      type: "stream",
      content: "partial ",
      partial: true,
      leaderId: "cto",
    });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });
  });

  it("transitions to streamState='streaming' on first `tool_use` event without prior `stream_start` (review fix — Finding 2)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "tool_use", leaderId: "cto", label: "Bash" });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });
  });

  it("session_ended with mismatched conversationId still resets streamState to 'idle' (review fix — Finding 3)", async () => {
    // The original disambiguator gate would have left streamState stuck in
    // 'stopping' forever if the server emitted a mismatched conversationId.
    // Resolution: always reset on session_ended (mirrors clear_streams);
    // breadcrumb the mismatch for observability.
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "stream_start", leaderId: "cto" });

    await waitFor(() => {
      expect(result.current.streamState).toBe("streaming");
    });

    act(() => {
      result.current.abort();
    });

    expect(result.current.streamState).toBe("stopping");

    serverSend({
      type: "session_ended",
      reason: "user_aborted",
      conversationId: "cid-OTHER",
    });

    await waitFor(() => {
      expect(result.current.streamState).toBe("idle");
    });
  });

  it("abort() while streamState='idle' is a no-op (no abort_turn sent)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });

    const sendCallsBefore = wsInstance!.send.mock.calls.length;
    act(() => {
      result.current.abort();
    });
    const newCalls = wsInstance!.send.mock.calls.slice(sendCallsBefore);
    const aborts = newCalls
      .map((c) => {
        try {
          return JSON.parse(c[0] as string);
        } catch {
          return null;
        }
      })
      .filter((m) => m && m.type === "abort_turn");
    expect(aborts.length).toBe(0);
  });
});
