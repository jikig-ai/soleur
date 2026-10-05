import { describe, it, expect, vi, beforeEach, afterEach, type MockInstance } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { chatReducer, type ChatState } from "../lib/ws-client";
import type { ChatTaskCompletedMessage } from "../lib/chat-state-machine";

// feat-session-completion-inline — the client half of "inline + notify if
// unseen": the `task_completed` frame must (a) append a ChatTaskCompletedMessage
// via the reducer, (b) be dropped when bound to a DIFFERENT conversation
// (user-scoped socket serves every tab — #9515 guard class), and (c) fire the
// render-anchored read-mark POST so the inbox row is marked read only when the
// card actually rendered.

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
    wsInstance = this;
    queueMicrotask(() => {
      this.readyState = MockWebSocket.OPEN;
      this.onopen?.(new Event("open"));
    });
  }
}

function emptyState(): ChatState {
  return {
    messages: [],
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Set(),
    streamState: "idle",
    connection: { phase: "live" },
    liveNarration: null,
  };
}

describe("chatReducer — task_completed", () => {
  it("appends a ChatTaskCompletedMessage carrying title + inboxItemId", () => {
    const next = chatReducer(emptyState(), {
      type: "stream_event",
      msg: {
        type: "task_completed",
        conversationId: "conv-1",
        inboxItemId: "inbox-9",
        title: "Soleur finished your request",
      },
    });

    expect(next.messages).toHaveLength(1);
    const msg = next.messages[0] as ChatTaskCompletedMessage;
    expect(msg.type).toBe("task_completed");
    expect(msg.content).toBe("Soleur finished your request");
    expect(msg.inboxItemId).toBe("inbox-9");
    expect(msg.role).toBe("assistant");
  });
});

describe("useWebSocket — task_completed frame", () => {
  let originalWebSocket: typeof globalThis.WebSocket;
  let fetchSpy: MockInstance;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;
    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error — mock constructor shape
    globalThis.WebSocket = MockWebSocket;
    fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(
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

  function serverSend(data: Record<string, unknown>) {
    act(() => {
      wsInstance?.onmessage?.(
        new MessageEvent("message", { data: JSON.stringify(data) }),
      );
    });
  }

  async function connectAndResume(conversationId: string) {
    const { useWebSocket } = await import("@/lib/ws-client");
    const result = renderHook(() => useWebSocket(conversationId));

    await waitFor(() => {
      expect(wsInstance).not.toBeNull();
      expect(wsInstance?.send).toHaveBeenCalled();
    });
    serverSend({ type: "auth_ok" });
    await waitFor(() => {
      expect(result.result.current.status).toBe("connected");
    });
    serverSend({
      type: "session_resumed",
      conversationId,
      resumedFromTimestamp: "2026-10-05T12:00:00Z",
      messageCount: 0,
    });
    return result;
  }

  it("renders the card and fires the read-mark POST when the frame matches the mounted conversation", async () => {
    const result = await connectAndResume("conv-live-1");

    serverSend({
      type: "task_completed",
      conversationId: "conv-live-1",
      inboxItemId: "inbox-1",
      title: "Soleur finished your request",
    });

    await waitFor(() => {
      expect(
        result.result.current.messages.some(
          (m) => m.type === "task_completed",
        ),
      ).toBe(true);
    });

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/inbox/inbox-1/state",
        expect.objectContaining({ method: "POST" }),
      );
    });
    const readMarkCall = fetchSpy.mock.calls.find(
      ([url]) => url === "/api/inbox/inbox-1/state",
    );
    expect(JSON.parse(String(readMarkCall?.[1]?.body))).toEqual({
      action: "read",
    });
  });

  it("drops a frame bound to a different conversation — no render, no read-mark", async () => {
    const result = await connectAndResume("conv-live-1");
    fetchSpy.mockClear();

    serverSend({
      type: "task_completed",
      conversationId: "conv-other-9",
      inboxItemId: "inbox-2",
      title: "Soleur finished your request",
    });

    // Give the (absent) dispatch a tick, then assert nothing landed.
    await act(async () => {});
    expect(
      result.result.current.messages.some((m) => m.type === "task_completed"),
    ).toBe(false);
    expect(fetchSpy).not.toHaveBeenCalledWith(
      "/api/inbox/inbox-2/state",
      expect.anything(),
    );
  });
});
