import { describe, it, expect, vi, type MockInstance, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// `session_ended` transcript copy — the raw wire `reason` (a free-form
// z.string() carrying internal enum names like `internal_error`) must
// never reach the founder-facing transcript. Two layers:
//   1. SESSION_ENDED_COPY — exhaustive per-reason copy keyed on
//      SessionEndedReason (WorkflowEndStatus | "turn_complete" | "closed").
//   2. ws-client.ts — suppresses SESSION_ENDED_SUPPRESSED reasons, looks
//      up copy, and falls back to SESSION_ENDED_GENERIC_COPY for
//      unmapped reasons.

import { WORKFLOW_END_STATUSES } from "@/lib/types";
import {
  SESSION_ENDED_COPY,
  SESSION_ENDED_GENERIC_COPY,
  SESSION_ENDED_SUPPRESSED,
} from "@/lib/session-ended-copy";

describe("SESSION_ENDED_COPY", () => {
  it("has an entry for every renderable session_ended reason", () => {
    // Every WorkflowEndStatus plus the non-runner lifecycle reasons the
    // frame carries (ws-handler.ts close_conversation, agent-runner.ts).
    const expectedKeys = [...WORKFLOW_END_STATUSES, "closed"].filter(
      (r) => !SESSION_ENDED_SUPPRESSED.has(r as never),
    );
    expect(Object.keys(SESSION_ENDED_COPY).sort()).toEqual(expectedKeys.sort());
  });

  it("suppresses turn_complete only — every other reason renders a line", () => {
    expect([...SESSION_ENDED_SUPPRESSED].sort()).toEqual(["turn_complete"]);
  });

  it("never leaks a raw wire token — no snake_case in any copy string", () => {
    for (const [reason, copy] of Object.entries(SESSION_ENDED_COPY)) {
      expect(copy.length, `copy for ${reason} is empty`).toBeGreaterThan(0);
      // The defect this fixes: `Session ended: ${reason}` rendered enum
      // names verbatim. Guard against reintroduction in ANY row.
      expect(copy, `copy for ${reason} leaks a raw token`).not.toMatch(
        /[a-z]+_[a-z]+/,
      );
    }
    expect(SESSION_ENDED_GENERIC_COPY.length).toBeGreaterThan(0);
    expect(SESSION_ENDED_GENERIC_COPY).not.toMatch(/[a-z]+_[a-z]+/);
  });
});

// --- ws-client render path -------------------------------------------------
// Mock boilerplate mirrors useWebSocket-abort.test.tsx.

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

describe("useWebSocket — session_ended transcript copy", () => {
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

  it("session_ended{internal_error} renders founder copy, not the raw reason", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "session_ended", reason: "internal_error" });

    await waitFor(() => {
      const last = result.current.messages.at(-1);
      expect(last?.content).toBe(SESSION_ENDED_COPY.internal_error);
    });
    expect(result.current.messages.at(-1)?.content).not.toContain(
      "internal_error",
    );
  });

  it("session_ended{turn_complete} is suppressed — no transcript line", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    const before = result.current.messages.length;
    serverSend({ type: "session_ended", reason: "turn_complete" });

    // Suppression is synchronous — the dispatch either appended or did not.
    expect(result.current.messages.length).toBe(before);
  });

  it("an unmapped reason falls back to generic copy, not the raw token", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "session_ended", reason: "brand_new_reason" });

    await waitFor(() => {
      const last = result.current.messages.at(-1);
      expect(last?.content).toBe(SESSION_ENDED_GENERIC_COPY);
    });
    expect(result.current.messages.at(-1)?.content).not.toContain(
      "brand_new_reason",
    );
  });
});
