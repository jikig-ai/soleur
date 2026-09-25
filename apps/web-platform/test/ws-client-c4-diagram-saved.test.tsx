import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// #8739 — a Concierge `edit_c4_diagram` completion emits a server→client
// `c4_diagram_saved` WS frame. `useWebSocket` re-broadcasts it as a DOM
// CustomEvent so the open C4Workspace (which holds no handle on this socket)
// refetches and updates the stale banner. Same MockWebSocket harness as
// ws-client-key-invalid-teardown.test.tsx.

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
    wsInstance?.onmessage?.(
      new MessageEvent("message", { data: JSON.stringify(msg) }),
    );
  });
}

import { useWebSocket } from "@/lib/ws-client";
import { C4_DIAGRAM_SAVED_EVENT } from "@/lib/c4-constants";

describe("useWebSocket — c4_diagram_saved → DOM CustomEvent (#8739)", () => {
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

  it("pins the DOM event name (external listeners key on this literal)", () => {
    expect(C4_DIAGRAM_SAVED_EVENT).toBe("soleur:c4DiagramSaved");
  });

  it("re-broadcasts a c4_diagram_saved frame as a window CustomEvent", async () => {
    renderHook(() => useWebSocket("conv-1"));
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });

    const seen: Array<{
      dirPath: string;
      rerendered: boolean;
      diagnostic: string | null;
    }> = [];
    const onSaved = (e: Event) =>
      seen.push(
        (
          e as CustomEvent<{
            dirPath: string;
            rerendered: boolean;
            diagnostic: string | null;
          }>
        ).detail,
      );
    window.addEventListener(C4_DIAGRAM_SAVED_EVENT, onSaved);
    try {
      deliver({
        type: "c4_diagram_saved",
        dirPath: "engineering/architecture/diagrams",
        rerendered: true,
        diagnostic: null,
      });
      await waitFor(() => expect(seen).toHaveLength(1));
      expect(seen[0]).toEqual({
        dirPath: "engineering/architecture/diagrams",
        rerendered: true,
        diagnostic: null,
      });

      // Negative control: another known frame type must NOT dispatch the
      // event (guards a dispatch-on-every-type mutant).
      deliver({ type: "upgrade_pending" });
      await new Promise((r) => setTimeout(r, 0));
      expect(seen).toHaveLength(1);

      // `diagnostic` omitted on the wire normalizes to null in the detail.
      deliver({
        type: "c4_diagram_saved",
        dirPath: "engineering/architecture/diagrams",
        rerendered: false,
      });
      await waitFor(() => expect(seen).toHaveLength(2));
      expect(seen[1]).toEqual({
        dirPath: "engineering/architecture/diagrams",
        rerendered: false,
        diagnostic: null,
      });
    } finally {
      window.removeEventListener(C4_DIAGRAM_SAVED_EVENT, onSaved);
    }
  });
});
