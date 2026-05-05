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

const mockReportSilentFallback = vi.fn();
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: (...args: unknown[]) => mockReportSilentFallback(...args),
  warnSilentFallback: vi.fn(),
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

const historyMessages = [
  { id: "hist-1", role: "user", content: "Hello", leader_id: null },
  { id: "hist-2", role: "assistant", content: "Hi there!", leader_id: "cto" },
];

describe("useWebSocket — historyLoading flag + Sentry mirror (AC4, AC5)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;
  let fetchSpy: MockInstance;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;
    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error mock constructor shape
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

  it("exposes historyLoading=false after fetch completes for a Command Center conversation", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("conv-cc-789"));

    await connectAndAuth(result);

    // mount-time effect kicks off fetch for non-"new" conversationId
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-cc-789/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    await waitFor(() => {
      expect(result.current.messages.length).toBe(2);
      // historyLoading must be exposed by the hook return AC4.
      expect(result.current.historyLoading).toBe(false);
    });
  });

  it("hydrates Command Center history (non-'new' conversationId) — AC3", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("conv-cc-456"));

    await connectAndAuth(result);

    await waitFor(() => {
      expect(result.current.messages.map((m) => m.id)).toEqual(["hist-1", "hist-2"]);
    });
  });

  it("mirrors history fetch failure to Sentry via reportSilentFallback (AC5)", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(JSON.stringify({ error: "boom" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("conv-cc-fail"));

    await connectAndAuth(result);

    await waitFor(() => {
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "kb-chat",
          op: "history-fetch-failed",
          extra: expect.objectContaining({
            conversationId: "conv-cc-fail",
            status: 500,
          }),
        }),
      );
    });
  });

  it("mirrors thrown fetch error (non-Abort) to Sentry via reportSilentFallback (AC5)", async () => {
    fetchSpy.mockRejectedValueOnce(new TypeError("network down"));

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("conv-cc-throw"));

    await connectAndAuth(result);

    await waitFor(() => {
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.any(TypeError),
        expect.objectContaining({
          feature: "kb-chat",
          op: "history-fetch-error",
          extra: expect.objectContaining({ conversationId: "conv-cc-throw" }),
        }),
      );
    });
  });

  it("does NOT report AbortError as a silent fallback (navigation cancel is expected)", async () => {
    // Drive an AbortError directly: the fetch impl rejects with one, but the
    // ws-client error branch must filter it before reporting.
    fetchSpy.mockRejectedValueOnce(
      Object.assign(new DOMException("aborted", "AbortError"), { name: "AbortError" }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    renderHook(() => useWebSocket("conv-cc-abort"));

    // Give the effect a tick to run.
    await new Promise((r) => setTimeout(r, 50));

    expect(mockReportSilentFallback).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "history-fetch-error" }),
    );
  });
});
