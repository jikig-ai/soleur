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
  hasSessionEndedCopy,
} from "@/lib/session-ended-copy";
import { WORKFLOW_END_USER_MESSAGES } from "@/server/cc-workflow-end-messages";

describe("SESSION_ENDED_COPY", () => {
  it("has an entry for every renderable session_ended reason", () => {
    // Every WorkflowEndStatus plus the non-runner lifecycle reasons the
    // frame carries (ws-handler.ts close_conversation, agent-runner.ts).
    // "turn_complete" is included so the suppression filter is load-bearing
    // — without it the filter could never remove anything.
    const expectedKeys = [
      ...WORKFLOW_END_STATUSES,
      "closed",
      "turn_complete",
    ].filter((r) => !SESSION_ENDED_SUPPRESSED.has(r));
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
        /[a-zA-Z]+_[a-zA-Z]+/,
      );
    }
    expect(SESSION_ENDED_GENERIC_COPY.length).toBeGreaterThan(0);
    expect(SESSION_ENDED_GENERIC_COPY).not.toMatch(/[a-zA-Z]+_[a-zA-Z]+/);
  });

  it("stays verbatim with WORKFLOW_END_USER_MESSAGES for shared statuses", () => {
    // Drift guard — the two maps are parallel copy sources for the same
    // conditions on different wire paths (`{type:"error"}` frames vs the
    // terminal `session_ended` frame). Every shared key whose server copy
    // is non-empty must match verbatim; `completed` is `""` server-side
    // by design (that path is handled via the terminal frame).
    for (const status of WORKFLOW_END_STATUSES) {
      const serverCopy = WORKFLOW_END_USER_MESSAGES[status];
      if (serverCopy === "") continue;
      expect(SESSION_ENDED_COPY[status], `copy drift for ${status}`).toBe(
        serverCopy,
      );
    }
  });

  it("hasSessionEndedCopy rejects Object.prototype keys and unknown reasons", () => {
    // The free-form wire `reason` must never resolve an inherited member —
    // a "constructor"/"__proto__" reason would otherwise bypass the
    // generic fallback and dispatch a non-string into ChatMessage.content.
    for (const protoKey of [
      "constructor",
      "toString",
      "hasOwnProperty",
      "__proto__",
      "valueOf",
      "isPrototypeOf",
    ]) {
      expect(hasSessionEndedCopy(protoKey), protoKey).toBe(false);
    }
    expect(hasSessionEndedCopy("brand_new_reason")).toBe(false);
    expect(hasSessionEndedCopy("internal_error")).toBe(true);
    expect(hasSessionEndedCopy("closed")).toBe(true);
    // Suppressed reasons have no copy row by design.
    expect(hasSessionEndedCopy("turn_complete")).toBe(false);
  });
});

// --- ws-client render path -------------------------------------------------
// Mock boilerplate mirrors useWebSocket-abort.test.tsx.

const mockGetSession = vi.fn().mockResolvedValue({
  data: { session: { access_token: "test-token" } },
});

const { captureMessageSpy } = vi.hoisted(() => ({
  captureMessageSpy: vi.fn(),
}));

// ws-client imports `* as Sentry` (addBreadcrumb for the conversationId
// mismatch); the unmapped-reason path goes through warnSilentFallback →
// captureMessage. Mock the module surface both call paths use.
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: (...args: unknown[]) => captureMessageSpy(...args),
  captureException: vi.fn(),
}));

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
    // The unmapped reason must self-report — warnSilentFallback routes
    // to captureMessage at warning level.
    await waitFor(() => {
      expect(captureMessageSpy).toHaveBeenCalledWith(
        "session_ended arrived with an unmapped reason",
        expect.objectContaining({
          level: "warning",
          tags: expect.objectContaining({
            op: "session-ended-unmapped-reason",
          }),
        }),
      );
    });
  });

  it("an Object.prototype-key reason yields generic copy + string content (no render crash)", async () => {
    // Regression gate for the prototype-chain bypass: `SESSION_ENDED_COPY[
    // "constructor"]` resolves an inherited member — the fallback MUST be
    // membership-gated (hasSessionEndedCopy), not truthiness-gated, or a
    // crafted frame dispatches a non-string into ChatMessage.content.
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("cid-1"));

    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "cid-1" });
    serverSend({ type: "session_ended", reason: "constructor" });

    await waitFor(() => {
      const last = result.current.messages.at(-1);
      expect(last?.content).toBe(SESSION_ENDED_GENERIC_COPY);
    });
    expect(typeof result.current.messages.at(-1)?.content).toBe("string");
  });

  it.each(["closed", "session_revoked", "user_aborted"] as const)(
    "session_ended{%s} renders its mapped copy",
    async (reason) => {
      const { useWebSocket } = await import("@/lib/ws-client");
      const { result } = renderHook(() => useWebSocket("cid-1"));

      await connectAndAuth(result);
      serverSend({ type: "session_started", conversationId: "cid-1" });
      serverSend({ type: "session_ended", reason });

      await waitFor(() => {
        expect(result.current.messages.at(-1)?.content).toBe(
          SESSION_ENDED_COPY[reason],
        );
      });
      // A mapped reason must not fire the unmapped-reason warning.
      expect(captureMessageSpy).not.toHaveBeenCalled();
    },
  );
});
