import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";

// feat-concierge-activity-trail (#9515) — the WS boundary admission test.
// `parseWSMessage`'s discriminated union is the SOLE admission authority
// (isKnownWSMessageType was deleted — it was a strict subset of the parse
// that runs anyway, and its hand-maintained literal had drifted 11 members
// stale with a vacuous exhaustiveness proof). These tests pin the two
// behaviors the deleted guard carried:
//   (a) a frame whose `type` matches NO schema variant reports
//       `op: ws-unknown-event` and never dispatches;
//   (b) a frame whose `type` matches a variant but fails shape validation
//       reports `op: ws-zod-parse-failure`;
//   (c) a valid `reasoning_narration` frame reaches the reducer —
//       the regression this PR exists to fix.

const mockGetSession = vi.fn().mockResolvedValue({
  data: { session: { access_token: "test-token" } },
});

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { getSession: mockGetSession } }),
}));

const reportSilentFallback = vi.fn();
const warnSilentFallback = vi.fn();
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
  warnSilentFallback: (...args: unknown[]) => warnSilentFallback(...args),
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
  // Loud-no-op guard: a silent `wsInstance?.` no-op would produce an
  // unactionable "0 calls" when the socket never connected (test seat).
  if (!wsInstance) throw new Error("socket never constructed");
  act(() => {
    wsInstance?.onmessage?.(
      new MessageEvent("message", { data: JSON.stringify(msg) }),
    );
  });
}

import { useWebSocket } from "@/lib/ws-client";

describe("useWebSocket — boundary admission (#9515)", () => {
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

  it("bogus type reports ws-unknown-event and never dispatches", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await act(async () => {});

    deliver({ type: "zz_does_not_exist", message: "hello" });

    const unknownCalls = reportSilentFallback.mock.calls.filter(
      ([, opts]) => (opts as { op?: string }).op === "ws-unknown-event",
    );
    expect(unknownCalls.length).toBe(1);
    expect(result.current.liveNarration).toBeNull();
  });

  it("shape-miss on a known type reports ws-zod-parse-failure, not ws-unknown-event", async () => {
    renderHook(() => useWebSocket("conv-1"));
    await act(async () => {});

    // `stream` is a real union member but `content` is missing — the
    // discriminator matched, the shape did not.
    deliver({ type: "stream", leaderId: "cc_router" });

    const parseCalls = reportSilentFallback.mock.calls.filter(
      ([, opts]) => (opts as { op?: string }).op === "ws-zod-parse-failure",
    );
    const unknownCalls = reportSilentFallback.mock.calls.filter(
      ([, opts]) => (opts as { op?: string }).op === "ws-unknown-event",
    );
    expect(parseCalls.length).toBe(1);
    expect(unknownCalls.length).toBe(0);
  });

  it("valid reasoning_narration frame reaches the reducer (was dropped pre-fix)", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await act(async () => {});

    deliver({ type: "reasoning_narration", message: "Checking your open change requests…" });

    expect(result.current.liveNarration).toBe(
      "Checking your open change requests…",
    );
    const unknownCalls = reportSilentFallback.mock.calls.filter(
      ([, opts]) => (opts as { op?: string }).op === "ws-unknown-event",
    );
    expect(unknownCalls.length).toBe(0);
  });

  it("narration scoped to another conversationId is dropped (cross-tab guard)", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await act(async () => {});

    deliver({
      type: "reasoning_narration",
      message: "Other tab's work…",
      conversationId: "some-other-conv",
    });

    expect(result.current.liveNarration).toBeNull();
  });

  it("valid turn_summary frame is admitted (was dropped pre-fix)", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await act(async () => {});

    deliver({
      type: "turn_summary",
      summary: "Done",
      seq: 5,
    });

    const unknownCalls = reportSilentFallback.mock.calls.filter(
      ([, opts]) => (opts as { op?: string }).op === "ws-unknown-event",
    );
    expect(unknownCalls.length).toBe(0);
    // "Admitted" means it reached the reducer — a parse-then-drop regression
    // in the dispatch switch would keep this green on the op assertion alone.
    expect(
      result.current.messages.some((m) => m.type === "turn_summary"),
    ).toBe(true);
  });
});
