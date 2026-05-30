import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// feat-skip-api-key-onboarding (#4642) — AC5. A chat-time `key_invalid` error
// must render an in-chat actionable CTA and TEAR DOWN the socket — never a
// hard `window.location.href = "/setup-key"` redirect (which, combined with
// the redirect gate, produced the skip→chat→/setup-key loop). The teardown
// (onclose nulled, socket closed, no reconnect timer) is the load-bearing
// invariant: leaving onclose attached would fire the backoff reconnect and
// re-storm /ws → getUserApiKey → key_invalid.

const mockGetSession = vi.fn().mockResolvedValue({
  data: { session: { access_token: "test-token" } },
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { getSession: mockGetSession } }),
}));

let wsInstance: MockWebSocket | null = null;

class MockWebSocket {
  static OPEN = 1;
  static CONNECTING = 0;
  static CLOSING = 2;
  static CLOSED = 3;
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

function deliver(msg: unknown) {
  act(() => {
    wsInstance?.onmessage?.(new MessageEvent("message", { data: JSON.stringify(msg) }));
  });
}

import { useWebSocket } from "@/lib/ws-client";

describe("useWebSocket — key_invalid teardown (AC5)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;
    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error test double
    globalThis.WebSocket = MockWebSocket;
  });

  afterEach(() => {
    globalThis.WebSocket = originalWebSocket;
  });

  it("renders an in-chat CTA and tears down the socket (no reconnect storm)", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));

    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));

    const socket = wsInstance!;
    deliver({
      type: "error",
      errorCode: "key_invalid",
      message: "Your API key is invalid or expired.",
    });

    // In-chat actionable error (CTA), NOT a navigation.
    await waitFor(() => expect(result.current.lastError?.code).toBe("key_invalid"));
    expect(result.current.lastError?.action?.href).toBeTruthy();

    // Teardown ran: onclose detached + socket closed so the backoff reconnect
    // can never fire. A reconnect would have constructed a NEW MockWebSocket;
    // assert the captured instance is the same and was closed.
    expect(socket.onclose).toBeNull();
    expect(socket.close).toHaveBeenCalled();
    expect(wsInstance).toBe(socket);
  });
});
