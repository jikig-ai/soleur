import { describe, it, expect, vi, beforeEach, afterEach, type MockInstance } from "vitest";
import { render, renderHook, act, waitFor } from "@testing-library/react";
import { chatReducer, useWebSocket, type ChatState } from "../lib/ws-client";
import type { ChatTaskCompletedMessage } from "../lib/chat-state-machine";
import { TaskCompletedCard } from "../components/chat/task-completed-card";

// feat-session-completion-inline — the client half of "inline + notify if
// unseen": the `task_completed` frame must (a) append a ChatTaskCompletedMessage
// via the reducer, (b) be dropped when bound to a DIFFERENT conversation
// (user-scoped socket serves every tab — #9515 guard class), and (c) fire the
// render-anchored read-mark POST — mount-anchored, so "read" implies the card
// actually committed to the tree.

let fetchSpy: MockInstance;

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
  readyState = MockWebSocket.CONNECTING;
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
        inboxItemId: "11111111-1111-4111-8111-111111111110",
        title: "Soleur finished your request",
      },
    });

    expect(next.messages).toHaveLength(1);
    const msg = next.messages[0] as ChatTaskCompletedMessage;
    expect(msg.type).toBe("task_completed");
    expect(msg.content).toBe("Soleur finished your request");
    expect(msg.inboxItemId).toBe("11111111-1111-4111-8111-111111111110");
    expect(msg.role).toBe("assistant");
  });
});

describe("TaskCompletedCard — render-anchored read-mark", () => {
  beforeEach(() => {
    fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response("{}", { status: 200 }));
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("renders the sanitized title and POSTs the read-mark on mount", async () => {
    const { getByTestId, getByText } = render(
      <TaskCompletedCard
        title="Soleur finished your request"
        inboxItemId="11111111-1111-4111-8111-111111111111"
      />,
    );

    expect(getByTestId("task-completed")).toBeTruthy();
    expect(getByText("Soleur finished your request")).toBeTruthy();

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/inbox/11111111-1111-4111-8111-111111111111/state",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ action: "read" }),
        }),
      );
    });
  });

  it("strips bidi/control chars and caps the title at 200 chars (InboxItemRow invariant)", () => {
    // Discriminating input: a clean title would pass with or without
    // sanitizeDisplayString — this one only renders correctly THROUGH it.
    const dirty = `done‮e\u0000${"x".repeat(300)}`;
    const { container } = render(
      <TaskCompletedCard
        title={dirty}
        inboxItemId="11111111-1111-4111-8111-111111111115"
      />,
    );
    const rendered = container.querySelector("p")!.textContent!;
    expect(rendered).not.toContain("‮");
    expect(rendered.length).toBeLessThanOrEqual(201); // 200 cap + ellipsis
  });
});

describe("useWebSocket — task_completed frame", () => {
  let originalWebSocket: typeof globalThis.WebSocket;

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
    vi.restoreAllMocks();
  });

  function serverSend(data: Record<string, unknown>) {
    act(() => {
      wsInstance?.onmessage?.(
        new MessageEvent("message", { data: JSON.stringify(data) }),
      );
    });
  }

  async function connectAndResume(conversationId: string) {
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

  it("appends the card when the frame matches the mounted conversation", async () => {
    const result = await connectAndResume("conv-live-1");

    serverSend({
      type: "task_completed",
      conversationId: "conv-live-1",
      inboxItemId: "11111111-1111-4111-8111-111111111111",
      title: "Soleur finished your request",
    });

    await waitFor(() => {
      expect(
        result.result.current.messages.some(
          (m) => m.type === "task_completed",
        ),
      ).toBe(true);
    });
    const msg = result.result.current.messages.find(
      (m) => m.type === "task_completed",
    ) as ChatTaskCompletedMessage;
    expect(msg.inboxItemId).toBe("11111111-1111-4111-8111-111111111111");

    // The ws case itself must NOT fire the read-mark — the POST lives only in
    // TaskCompletedCard's mount effect so "read" implies painted. A fetch
    // added back into the ws case would regress this silently.
    await act(async () => {});
    const inboxCalls = fetchSpy.mock.calls.filter(([url]) =>
      String(url).includes("/api/inbox/"),
    );
    expect(inboxCalls).toHaveLength(0);
  });

  it("drops a frame bound to a different conversation", async () => {
    const result = await connectAndResume("conv-live-1");

    serverSend({
      type: "task_completed",
      conversationId: "conv-other-9",
      inboxItemId: "11111111-1111-4111-8111-111111111112",
      title: "Soleur finished your request",
    });

    // Give the (absent) dispatch a tick, then assert nothing landed — no card,
    // and no read-mark POST for the foreign row.
    await act(async () => {});
    expect(
      result.result.current.messages.some((m) => m.type === "task_completed"),
    ).toBe(false);
    expect(
      fetchSpy.mock.calls.filter(([url]) =>
        String(url).includes("/api/inbox/"),
      ),
    ).toHaveLength(0);
  });

  it("a seq-bearing foreign-conversation frame does not advance this surface's replay cursor", async () => {
    const result = await connectAndResume("conv-live-1");

    // A buffered frame for another conversation carries ITS conversation's
    // seq — it must be dropped before lastRenderedSeq advances (perf-seat P2:
    // foreign seq would swallow this surface's own later frames).
    serverSend({
      type: "task_completed",
      conversationId: "conv-other-9",
      inboxItemId: "11111111-1111-4111-8111-111111111113",
      title: "x",
      seq: 99,
    });
    // …then a same-conversation buffered frame with a LOWER seq (correct for
    // conv-live-1's own counter) must still render, not be deduped away.
    serverSend({
      type: "task_completed",
      conversationId: "conv-live-1",
      inboxItemId: "11111111-1111-4111-8111-111111111114",
      title: "y",
      seq: 1,
    });

    await waitFor(() => {
      const cards = result.result.current.messages.filter(
        (m) => m.type === "task_completed",
      );
      expect(cards).toHaveLength(1);
      expect(cards[0].content).toBe("y");
    });
  });
});
