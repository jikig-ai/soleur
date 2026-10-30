import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// #11525 — hoisted so the refusal mirror can be asserted without touching Sentry.
const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

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

import { useWebSocket, chatReducer, type ChatState } from "@/lib/ws-client";

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

  // #11086 — server-authored copy + scheme surface only when the frame carries
  // a recognised `credentialScheme`; otherwise the hardcoded text is unchanged.
  it("uses the server message and scheme when credentialScheme is present", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));

    const socket = wsInstance!;
    deliver({
      type: "error",
      errorCode: "key_invalid",
      message: "We couldn't sign in to Claude with your connected subscription.",
      credentialScheme: "oauth_token",
    });

    await waitFor(() => expect(result.current.lastError?.code).toBe("key_invalid"));
    expect(result.current.lastError?.message).toBe(
      "We couldn't sign in to Claude with your connected subscription.",
    );
    expect(result.current.lastError?.credentialScheme).toBe("oauth_token");
    expect(result.current.lastError?.action?.href).toBe("/dashboard/settings");
    expect(socket.onclose).toBeNull();
    expect(socket.close).toHaveBeenCalled();
  });

  it("keeps the hardcoded text byte-identical when credentialScheme is absent", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));

    deliver({ type: "error", errorCode: "key_invalid", message: "server text that must be ignored" });

    await waitFor(() => expect(result.current.lastError?.code).toBe("key_invalid"));
    expect(result.current.lastError).toEqual({
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    });
  });

  it("a frame with an unrecognised credentialScheme is dropped by the strict schema, not rendered", async () => {
    const { result } = renderHook(() => useWebSocket("conv-1"));
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));

    deliver({ type: "error", errorCode: "key_invalid", message: "x", credentialScheme: "bearer" });

    expect(result.current.lastError).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// #11525 — chat state after a key_invalid / byok_key_missing card.
// ---------------------------------------------------------------------------

const allSockets: MockWebSocket[] = [];
class TrackingWebSocket extends MockWebSocket {
  constructor() {
    super();
    allSockets.push(this);
  }
}

function chatFrames(socket: MockWebSocket): unknown[] {
  return socket.send.mock.calls
    .map(([raw]) => JSON.parse(raw as string))
    .filter((f: { type: string }) => f.type === "chat");
}

function framesOfType(socket: MockWebSocket, type: string): unknown[] {
  return socket.send.mock.calls
    .map(([raw]) => JSON.parse(raw as string))
    .filter((f: { type: string }) => f.type === type);
}

const CONV_ID = "11111111-1111-4111-8111-111111111111";

describe("useWebSocket — credential blocked state (#11525)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;

  beforeEach(() => {
    vi.clearAllMocks();
    wsInstance = null;
    allSockets.length = 0;
    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error test double
    globalThis.WebSocket = TrackingWebSocket;
  });

  afterEach(() => {
    globalThis.WebSocket = originalWebSocket;
  });

  async function connected(id = "new") {
    const hook = renderHook(() => useWebSocket(id));
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(hook.result.current.status).toBe("connected"));
    return hook;
  }

  /** Connected, session started, one user message sent, then the blocked frame. */
  async function blockedAfterOneMessage(
    frame: Record<string, unknown> = {
      type: "error",
      errorCode: "key_invalid",
      message: "x",
      credentialScheme: "oauth_token",
    },
  ) {
    const hook = await connected();
    deliver({ type: "session_started", conversationId: CONV_ID });
    await waitFor(() => expect(hook.result.current.realConversationId).toBe(CONV_ID));
    let accepted = false;
    act(() => {
      accepted = hook.result.current.sendMessage("hello");
    });
    expect(accepted).toBe(true);
    const first = wsInstance!;
    deliver(frame);
    await waitFor(() => expect(hook.result.current.credentialBlocked).toBe(true));
    return { ...hook, first };
  }

  it("is not blocked before any credential error", async () => {
    const { result } = await connected();
    expect(result.current.credentialBlocked).toBe(false);
    expect(result.current.rebindConversationId).toBeNull();
    expect(result.current.rebindRefused).toBe(false);
  });

  it("key_invalid derives credentialBlocked and flags the last user message unanswered", async () => {
    const { result, first } = await blockedAfterOneMessage();
    expect(result.current.lastError?.code).toBe("key_invalid");
    expect(first.onclose).toBeNull();
    const users = result.current.messages.filter((m) => m.role === "user");
    expect(users).toHaveLength(1);
    expect(users[0].unanswered).toBe(true);
  });

  it("byok_key_missing derives the same blocked state with its card shape and NO generic error bubble", async () => {
    const { result, first } = await blockedAfterOneMessage({
      type: "error",
      errorCode: "byok_key_missing",
      message: "server text",
    });
    expect(result.current.lastError).toEqual({
      code: "byok_key_missing",
      message: "Add an API key in Settings to continue.",
      action: { label: "Add API key", href: "/dashboard/settings" },
    });
    expect(first.onclose).toBeNull();
    expect(first.close).toHaveBeenCalled();
    expect(
      result.current.messages.some((m) => m.role === "assistant" && m.content.startsWith("Error:")),
    ).toBe(false);
  });

  it("captures rebindConversationId only when the thread has at least one user message", async () => {
    const withMsg = await blockedAfterOneMessage();
    expect(withMsg.result.current.rebindConversationId).toBe(CONV_ID);
    withMsg.unmount();

    allSockets.length = 0;
    wsInstance = null;
    const { result } = await connected();
    deliver({ type: "session_started", conversationId: CONV_ID });
    await waitFor(() => expect(result.current.realConversationId).toBe(CONV_ID));
    deliver({ type: "error", errorCode: "key_invalid", message: "x" });
    await waitFor(() => expect(result.current.credentialBlocked).toBe(true));
    expect(result.current.rebindConversationId).toBeNull();
    expect(result.current.messages.filter((m) => m.role === "user")).toHaveLength(0);
  });

  it("sendMessage refuses while blocked: returns false, no add_message, no reset_connection, no chat frame (socket readyState stays OPEN)", async () => {
    const { result, first } = await blockedAfterOneMessage();
    expect(first.readyState).toBe(MockWebSocket.OPEN);
    const before = result.current.messages;
    const chatsBefore = chatFrames(first).length;

    let accepted: boolean | undefined;
    act(() => {
      accepted = result.current.sendMessage("lost message");
    });

    expect(accepted).toBe(false);
    expect(result.current.messages).toBe(before);
    expect(result.current.messages.some((m) => m.content === "lost message")).toBe(false);
    expect(chatFrames(first)).toHaveLength(chatsBefore);
    // Expected blocked refusal is not a silent fallback.
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("a blocked refusal does not reset a sticky unrecoverable connection", async () => {
    const { result } = await connected();
    const socket = wsInstance!;
    // Non-transient close (superseded) without redirect target -> unrecoverable.
    act(() => {
      socket.onclose?.({ code: 4002 } as CloseEvent);
    });
    await waitFor(() => expect(result.current.connection.phase).toBe("unrecoverable"));
    // Socket gone (the mock does not flip readyState on its own): the refusal
    // must not silently reset the sticky phase.
    socket.readyState = MockWebSocket.CLOSED;
    act(() => {
      result.current.sendMessage("nope");
    });
    expect(result.current.connection.phase).toBe("unrecoverable");
  });

  it("sendMessage on a non-open, non-blocked socket returns false, adds no bubble and mirrors to Sentry", async () => {
    const { result } = await connected();
    const socket = wsInstance!;
    socket.readyState = MockWebSocket.CLOSED;

    let accepted: boolean | undefined;
    act(() => {
      accepted = result.current.sendMessage("x");
    });

    expect(accepted).toBe(false);
    expect(result.current.messages).toHaveLength(0);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "send-message",
      op: "refused-socket-not-open",
    });
  });

  it("sendMessage on an open socket returns true and sends exactly one chat frame", async () => {
    const { result } = await connected();
    const socket = wsInstance!;
    let accepted: boolean | undefined;
    act(() => {
      accepted = result.current.sendMessage("hi");
    });
    expect(accepted).toBe(true);
    expect(chatFrames(socket)).toHaveLength(1);
  });

  it("reconnect() clears the blocked state synchronously and re-opens a socket; no auto-reconnect before it", async () => {
    const { result, first } = await blockedAfterOneMessage();
    expect(allSockets).toHaveLength(1);

    act(() => {
      result.current.reconnect();
    });
    expect(result.current.credentialBlocked).toBe(false);
    expect(result.current.lastError).toBeNull();
    await waitFor(() => expect(allSockets).toHaveLength(2));
    expect(wsInstance).not.toBe(first);
  });

  it("rebind: resume_session for the captured id, session_started leaves messages unchanged (one user- bubble, no history refetch), exactly one chat frame on re-send", async () => {
    const fetchSpy = vi.fn();
    const originalFetch = globalThis.fetch;
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    try {
      const { result, first } = await blockedAfterOneMessage();
      const original = result.current.messages.filter((m) => m.role === "user");

      act(() => {
        result.current.reconnect();
      });
      await waitFor(() => expect(allSockets).toHaveLength(2));
      const second = wsInstance!;
      deliver({ type: "auth_ok" });
      await waitFor(() => expect(result.current.status).toBe("connected"));
      expect(result.current.rebindConversationId).toBe(CONV_ID);

      act(() => {
        result.current.resumeSession(CONV_ID);
      });
      expect(framesOfType(second, "resume_session")).toEqual([
        { type: "resume_session", conversationId: CONV_ID },
      ]);
      expect(framesOfType(second, "start_session")).toHaveLength(0);

      const beforeStarted = result.current.messages;
      deliver({ type: "session_started", conversationId: CONV_ID });
      await waitFor(() => expect(result.current.realConversationId).toBe(CONV_ID));
      expect(result.current.rebindRefused).toBe(false);
      expect(result.current.messages).toBe(beforeStarted);
      const users = result.current.messages.filter((m) => m.id.startsWith("user-"));
      expect(users).toHaveLength(1);
      expect(users[0].id).toBe(original[0].id);
      expect(fetchSpy).not.toHaveBeenCalled();

      // The user re-sends: exactly one chat frame on the new socket; the refused
      // attempt while blocked produced none, the original socket still has its one.
      let accepted: boolean | undefined;
      act(() => {
        accepted = result.current.sendMessage("again");
      });
      expect(accepted).toBe(true);
      expect(chatFrames(second)).toHaveLength(1);
      expect(chatFrames(first)).toHaveLength(1);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("rebind refused: an error frame while armed drops the id, adds no bubble, and falls back ONCE to start_session", async () => {
    const { result } = await blockedAfterOneMessage();
    act(() => {
      result.current.reconnect();
    });
    await waitFor(() => expect(allSockets).toHaveLength(2));
    const second = wsInstance!;
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));

    act(() => {
      result.current.resumeSession(CONV_ID);
    });
    const before = result.current.messages;
    deliver({ type: "error", message: "Conversation not found" });

    await waitFor(() => expect(result.current.rebindRefused).toBe(true));
    expect(result.current.rebindConversationId).toBeNull();
    expect(result.current.messages).toBe(before);

    // The surface re-runs its start effect, which now calls startSession.
    act(() => {
      result.current.startSession({ leaderId: undefined });
    });
    expect(framesOfType(second, "start_session")).toHaveLength(1);

    // Never loop: a later error is a normal error bubble again.
    deliver({ type: "error", message: "boom" });
    await waitFor(() =>
      expect(result.current.messages.some((m) => m.content === "Error: boom")).toBe(true),
    );
    expect(framesOfType(second, "start_session")).toHaveLength(1);
    expect(framesOfType(second, "resume_session")).toHaveLength(1);
  });

  it("a repeated key_invalid after the rebind resume re-blocks and keeps the rebind id", async () => {
    const { result } = await blockedAfterOneMessage();
    act(() => {
      result.current.reconnect();
    });
    await waitFor(() => expect(allSockets).toHaveLength(2));
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));
    act(() => {
      result.current.resumeSession(CONV_ID);
    });
    deliver({ type: "error", errorCode: "key_invalid", message: "x" });
    await waitFor(() => expect(result.current.credentialBlocked).toBe(true));
    expect(result.current.rebindConversationId).toBe(CONV_ID);
    expect(result.current.rebindRefused).toBe(false);
  });

  it("supersede precedence: a 4002 close after key_invalid is a no-op; after Reconnect it yields disconnected with credentialBlocked false", async () => {
    const { result, first } = await blockedAfterOneMessage();
    // Blocked tab has no live onclose (teardown nulled it) - nothing can overwrite lastError.
    expect(first.onclose).toBeNull();
    expect(result.current.lastError?.code).toBe("key_invalid");

    act(() => {
      result.current.reconnect();
    });
    await waitFor(() => expect(allSockets).toHaveLength(2));
    const second = wsInstance!;
    expect(second.onclose).not.toBeNull();
    act(() => {
      second.onclose?.({ code: 4002 } as CloseEvent);
    });
    await waitFor(() => expect(result.current.lastError?.code).toBe("disconnected"));
    expect(result.current.credentialBlocked).toBe(false);
  });
});

describe("chatReducer — mark_last_user_unanswered (#11525)", () => {
  const base = (messages: ChatState["messages"]): ChatState => ({
    messages,
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Set(),
    streamState: "idle",
    connection: { phase: "live" },
    liveNarration: null,
    liveNarrationStartedAt: null,
  });

  it("flags the last message when it is a user message", () => {
    const next = chatReducer(
      base([
        { id: "a", role: "assistant", content: "hi", type: "text" },
        { id: "user-1", role: "user", content: "q", type: "text" },
      ]),
      { type: "mark_last_user_unanswered" },
    );
    expect(next.messages[1].unanswered).toBe(true);
    expect(next.messages[0].unanswered).toBeUndefined();
  });

  it("is a no-op (same state reference) when the last message is not a user message", () => {
    const state = base([
      { id: "user-1", role: "user", content: "q", type: "text" },
      { id: "a", role: "assistant", content: "hi", type: "text" },
    ]);
    expect(chatReducer(state, { type: "mark_last_user_unanswered" })).toBe(state);
    const empty = base([]);
    expect(chatReducer(empty, { type: "mark_last_user_unanswered" })).toBe(empty);
  });
});
