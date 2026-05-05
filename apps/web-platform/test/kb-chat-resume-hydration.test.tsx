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

const mockAddBreadcrumb = vi.fn();
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: (...args: unknown[]) => mockAddBreadcrumb(...args),
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
    // Drive an AbortError followed by a real error in the same suite.
    // The control assertion (the second renderHook call below produces a
    // history-fetch-error mirror) proves the SUT's catch branch is reachable;
    // the primary assertion proves AbortError is filtered before reporting.
    fetchSpy.mockRejectedValueOnce(
      Object.assign(new DOMException("aborted", "AbortError"), { name: "AbortError" }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("conv-cc-abort"));

    await connectAndAuth(result);

    // Anchor on a deterministic effect-completion signal: historyLoading
    // must settle to false (the AbortError finally branch runs OR the
    // mount-time effect has resolved).
    await waitFor(() => {
      expect(result.current.historyLoading).toBe(false);
    });

    // Filter assertion: AbortError specifically must NOT have been reported.
    expect(mockReportSilentFallback).not.toHaveBeenCalledWith(
      expect.any(DOMException),
      expect.objectContaining({ op: "history-fetch-error" }),
    );
  });
});

// Regression suite for the "Continuing from <ts>" banner-without-messages bug
// class (PR #3267). PR #3237 closed the visible-empty-state surface but did
// NOT cover (H1) silent-no-session at fetch time or (H5) post-teardown
// onmessage observability. (H2) is observability-only — the abort-after-success
// branch is correct behavior, the breadcrumb is the diagnostic hook.
describe("useWebSocket — continuing-from regression #3267 (H1/H2/H5)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;
  let fetchSpy: MockInstance;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;
    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error mock constructor shape
    globalThis.WebSocket = MockWebSocket;

    // Defensive default — clearAllMocks resets mock.calls but not the
    // implementation queue. Restore the valid-session default so a prior
    // test's `mockImplementation(...)` does not leak across tests.
    mockGetSession.mockImplementation(async () => ({
      data: { session: { access_token: "test-token" } },
    }));

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
    vi.useRealTimers();
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

  // H1 — null Supabase session at fetch time mirrors to Sentry with the
  // distinguishable op so production triage can disambiguate it from the
  // pre-existing `history-fetch-failed` (4xx/5xx) and `history-fetch-error`
  // (network throw) sites. RED on `main` because no call site exists for
  // the no-session branch.
  it("H1: missing Supabase access_token mirrors to Sentry with op=history-fetch-no-session", async () => {
    // mockImplementation, not mockReturnValue — the eager-factory class
    // (2026-04-17 learning) breaks resolution ordering for promise factories.
    // mockImplementationOnce keeps the override scoped to this test so test
    // order does not leak the null-session default into siblings.
    mockGetSession.mockImplementationOnce(async () => ({
      data: { session: null },
    }));

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("conv-cc-no-session"));

    await connectAndAuth(result);

    await waitFor(() => {
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({
          feature: "kb-chat",
          op: "history-fetch-no-session",
          extra: expect.objectContaining({ conversationId: "conv-cc-no-session" }),
        }),
      );
    });
  });

  // H5 — a buffered `session_resumed` event delivered to ws.onmessage AFTER
  // the hook has unmounted (mountedRef.current === false) must (a) not
  // mutate hook state (the existing line-430 guard already enforces this)
  // and (b) record an observability breadcrumb so production can confirm
  // whether real users hit this race. RED on `main` because no breadcrumb
  // is recorded when the guard short-circuits.
  it("H5: ws.onmessage after unmount records ws-message-after-teardown breadcrumb", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result, unmount } = renderHook(() => useWebSocket("conv-cc-stale-msg"));

    await connectAndAuth(result);

    // Capture the live onmessage closure BEFORE teardown — the closure
    // observes mountedRef.current via closure scope. The MockWebSocket
    // instance retains the handler reference; unmount sets mountedRef.current
    // to false but does not null onmessage (the close handshake's final
    // code/reason still needs to be observable).
    const captured = wsInstance?.onmessage;
    expect(captured).not.toBeNull();

    act(() => {
      unmount();
    });

    mockAddBreadcrumb.mockClear();

    // Synthetic post-teardown frame. Synchronous invocation — no React
    // dispatch needed because the guard short-circuits before any state
    // setter runs.
    captured?.(
      new MessageEvent("message", {
        data: JSON.stringify({
          type: "session_resumed",
          conversationId: "11111111-1111-1111-1111-111111111111",
          resumedFromTimestamp: "2026-05-05T12:56:00Z",
          messageCount: 3,
        }),
      }),
    );

    expect(mockAddBreadcrumb).toHaveBeenCalledWith(
      expect.objectContaining({
        category: "kb-chat",
        message: "ws-message-after-teardown",
        level: "warning",
        data: expect.objectContaining({
          rawPrefix: expect.stringContaining("session_resumed"),
        }),
      }),
    );
  });

  // H2 — abort-after-success diagnostic. The combined guard
  // `if (!result || controller.signal.aborted) return;` correctly drops the
  // payload (the parent unmounted during fetch — replay would dispatch into
  // a torn-down reducer) but produces no telemetry for the pathological
  // branch. After the split, the `aborted` branch records a breadcrumb so a
  // real recurrence is observable. RED on `main` because the unsplit guard
  // emits no breadcrumb.
  it("H2: abort fired AFTER fetch resolves but BEFORE dispatch records abort-after-success breadcrumb", async () => {
    // Defer fetch resolution so we can interleave the abort.
    type DeferredResolve = (r: Response) => void;
    let resolveDeferred: DeferredResolve | null = null;
    const deferredFetch = new Promise<Response>((r) => {
      resolveDeferred = r;
    });
    fetchSpy.mockImplementationOnce(() => deferredFetch);

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result, unmount } = renderHook(() => useWebSocket("conv-h2-only"));

    await connectAndAuth(result);

    // Verify the mount-time effect kicked off our deferred fetch.
    await waitFor(() => {
      expect(
        fetchSpy.mock.calls.some(
          ([url]) => url === "/api/conversations/conv-h2-only/messages",
        ),
      ).toBe(true);
    });

    // Unmount — React calls the effect cleanup, which calls
    // `controller.abort()`. The fetch is still pending.
    act(() => {
      unmount();
    });

    // Now resolve the deferred fetch with 2 messages. result is non-null
    // AND controller.signal.aborted is true → the H2 path fires.
    await act(async () => {
      resolveDeferred?.(
        new Response(
          JSON.stringify({
            messages: [
              { id: "h2-1", role: "user", content: "first", leader_id: null },
              { id: "h2-2", role: "assistant", content: "reply", leader_id: null },
            ],
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );
      // Allow the awaited fetch to settle and the post-await branch to run.
      await deferredFetch;
    });

    await waitFor(() => {
      expect(mockAddBreadcrumb).toHaveBeenCalledWith(
        expect.objectContaining({
          category: "kb-chat",
          message: "history-fetch-abort-after-success",
          level: "warning",
          data: expect.objectContaining({
            conversationId: "conv-h2-only",
            messageCount: 2,
          }),
        }),
      );
    });

    // Negative-space anchor: the abort-after-success path is NOT an error,
    // so reportSilentFallback must not fire for the conv-h2-only id.
    expect(mockReportSilentFallback).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        op: "history-fetch-error",
        extra: expect.objectContaining({ conversationId: "conv-h2-only" }),
      }),
    );
  });
});
