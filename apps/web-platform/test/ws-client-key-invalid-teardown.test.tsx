import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// #11525 — hoisted so the refusal mirror can be asserted without touching Sentry.
const { mockReportSilentFallback, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
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
import { CONVERSATION_NOT_FOUND_MESSAGE } from "@/lib/ws-constants";

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

  /** Connected, session started, one user message sent, then the blocked frame.
   *  `surfaceId` other than "new" models a deep-linked UUID surface; the setup
   *  delivers `session_resumed` there. DEFENSIVE modelling only: the real server
   *  answers every `resume_session` with `session_started`, so `session_resumed`
   *  is not expected to complete a rebind - these cases pin the hook's behaviour
   *  should that reply ever arrive. */
  async function blockedAfterOneMessage(
    frame: Record<string, unknown> = {
      type: "error",
      errorCode: "key_invalid",
      message: "x",
      credentialScheme: "oauth_token",
    },
    surfaceId = "new",
  ) {
    const hook = await connected(surfaceId);
    deliver(
      surfaceId === "new"
        ? { type: "session_started", conversationId: CONV_ID }
        : {
            type: "session_resumed",
            conversationId: CONV_ID,
            resumedFromTimestamp: "2026-01-01T00:00:00.000Z",
            messageCount: 0,
          },
    );
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
    const before = result.current.messages.map((m) => ({ id: m.id, content: m.content }));
    const chatsBefore = chatFrames(first).length;

    let accepted: boolean | undefined;
    act(() => {
      accepted = result.current.sendMessage("lost message");
    });

    expect(accepted).toBe(false);
    expect(result.current.messages.map((m) => ({ id: m.id, content: m.content }))).toEqual(before);
    expect(result.current.messages.some((m) => m.content === "lost message")).toBe(false);
    expect(chatFrames(first)).toHaveLength(chatsBefore);
    // Expected blocked refusal is not a silent fallback.
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // Item-5 evidence: a non-transient close sets `unrecoverable` AND leaves the
  // socket CLOSED, so the not-OPEN refusal is where this state is reachable. The
  // escape from it is `resumeAfterUnrecoverable` (reset + reconnect); a bare
  // `reset_connection` with no socket would hide the State-3 banner while
  // nothing can be sent, so the refusal must leave the phase alone.
  it("a not-open refusal (closed socket after a non-transient close) does not reset a sticky unrecoverable connection", async () => {
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

      const beforeStarted = result.current.messages.map((m) => ({ id: m.id, content: m.content }));
      deliver({ type: "session_started", conversationId: CONV_ID });
      await waitFor(() => expect(result.current.realConversationId).toBe(CONV_ID));
      expect(result.current.rebindRefused).toBe(false);
      expect(result.current.messages.map((m) => ({ id: m.id, content: m.content }))).toEqual(
        beforeStarted,
      );
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

  /** Blocked, reconnected on a fresh socket, `resume_session` armed. */
  async function armedRebind(surfaceId = "new") {
    const hook = await blockedAfterOneMessage(undefined, surfaceId);
    act(() => {
      hook.result.current.reconnect();
    });
    await waitFor(() => expect(allSockets).toHaveLength(2));
    const second = wsInstance!;
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(hook.result.current.status).toBe("connected"));
    act(() => {
      hook.result.current.resumeSession(CONV_ID);
    });
    expect(framesOfType(second, "resume_session")).toHaveLength(1);
    return { ...hook, second };
  }

  const snapshot = (messages: { id: string; content: string }[]) =>
    messages.map((m) => ({ id: m.id, content: m.content }));
  const errorBubbles = (messages: { role: string; content: string }[]) =>
    messages.filter((m) => m.role === "assistant" && m.content.startsWith("Error:"));

  it("rebind refused: the genuine 'Conversation not found' refusal drops the id, adds no bubble, sets rebindRefused and mirrors ONCE", async () => {
    const { result, second } = await armedRebind();
    const before = snapshot(result.current.messages);
    deliver({ type: "error", message: "Conversation not found" });

    await waitFor(() => expect(result.current.rebindRefused).toBe(true));
    expect(result.current.rebindConversationId).toBeNull();
    expect(snapshot(result.current.messages)).toEqual(before);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockWarnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "credential-rebind",
      op: "resume-refused",
    });

    // The hook only reports the refusal (the SURFACE owns the single fallback;
    // see chat-surface-credential-blocked.test.tsx). Once consumed, a later
    // error is an ordinary bubble again - the armed ref is cleared, no loop.
    act(() => {
      result.current.startSession({ leaderId: undefined });
    });
    expect(framesOfType(second, "start_session")).toHaveLength(1);
    deliver({ type: "error", message: "boom" });
    await waitFor(() =>
      expect(result.current.messages.some((m) => m.content === "Error: boom")).toBe(true),
    );
    expect(framesOfType(second, "resume_session")).toHaveLength(1);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
  });

  it("rebind: a non-refusal error while armed (checkpoint notice, no errorCode) is an ordinary bubble and does NOT set rebindRefused; the following session_started still completes the rebind", async () => {
    const { result } = await armedRebind();
    deliver({ type: "error", message: "Checkpoint refused - your earlier work is kept." });
    await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(1));
    expect(result.current.rebindRefused).toBe(false);
    expect(result.current.rebindConversationId).toBe(CONV_ID); // still armed, not consumed

    deliver({ type: "session_started", conversationId: CONV_ID });
    await waitFor(() => expect(result.current.realConversationId).toBe(CONV_ID));
    expect(result.current.rebindRefused).toBe(false);
    expect(result.current.rebindConversationId).toBeNull();
    // The transcript keeps the original user bubble.
    expect(result.current.messages.filter((m) => m.id.startsWith("user-"))).toHaveLength(1);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("rebind: a transient 'Auth probe failed' / rate_limited error while armed does not set rebindRefused", async () => {
    const { result } = await armedRebind();
    deliver({ type: "error", message: "Auth probe failed - please retry." });
    deliver({ type: "error", errorCode: "rate_limited", message: "slow down" });
    await waitFor(() => expect(result.current.lastError?.code).toBe("rate_limited"));
    expect(result.current.rebindRefused).toBe(false);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("rebind: stays armed after a non-refusal error - a later genuine refusal is still honoured (sets rebindRefused, exactly one warn mirror)", async () => {
    const { result } = await armedRebind();
    deliver({ type: "error", message: "Checkpoint refused - your earlier work is kept." });
    deliver({ type: "error", message: "Auth probe failed - please retry." });
    await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(2));
    expect(result.current.rebindRefused).toBe(false);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();

    deliver({ type: "error", message: CONVERSATION_NOT_FOUND_MESSAGE });
    await waitFor(() => expect(result.current.rebindRefused).toBe(true));
    expect(result.current.rebindConversationId).toBeNull();
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    expect(errorBubbles(result.current.messages)).toHaveLength(2); // the refusal adds no bubble
  });

  it("mount effect clears the rebind: re-rendering with a new conversationId after a block drops the captured id, the blocked state and rebindRefused", async () => {
    const hook = renderHook(({ id }) => useWebSocket(id), { initialProps: { id: "new" } });
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(hook.result.current.status).toBe("connected"));
    deliver({ type: "session_started", conversationId: CONV_ID });
    await waitFor(() => expect(hook.result.current.realConversationId).toBe(CONV_ID));
    act(() => {
      hook.result.current.sendMessage("hello");
    });
    deliver({ type: "error", errorCode: "key_invalid", message: "x" });
    await waitFor(() => expect(hook.result.current.credentialBlocked).toBe(true));
    expect(hook.result.current.rebindConversationId).toBe(CONV_ID);

    hook.rerender({ id: "22222222-2222-4222-8222-222222222222" });
    await waitFor(() => expect(hook.result.current.rebindConversationId).toBeNull());
    expect(hook.result.current.credentialBlocked).toBe(false);
    expect(hook.result.current.rebindRefused).toBe(false);
    expect(hook.result.current.lastError).toBeNull();
  });

  it("rebind: after session_started the armed state is disarmed - an unrelated later error is a plain bubble (no rebindRefused, no start_session)", async () => {
    const { result, second } = await armedRebind();
    deliver({ type: "session_started", conversationId: CONV_ID });
    await waitFor(() => expect(result.current.realConversationId).toBe(CONV_ID));

    deliver({ type: "error", message: "Conversation not found" });
    await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(1));
    expect(result.current.rebindRefused).toBe(false);
    expect(framesOfType(second, "start_session")).toHaveLength(0);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("defensive (the server replies session_started, never session_resumed, to resume_session): a session_resumed on a UUID surface still disarms - an unrelated later error is a plain bubble", async () => {
    const fetchSpy = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ messages: [] }), { status: 200 }),
    );
    const originalFetch = globalThis.fetch;
    globalThis.fetch = fetchSpy as unknown as typeof fetch;
    try {
      const { result, second } = await armedRebind(CONV_ID);
      deliver({
        type: "session_resumed",
        conversationId: CONV_ID,
        resumedFromTimestamp: "2026-01-01T00:00:00.000Z",
        messageCount: 1,
      });
      await waitFor(() => expect(result.current.resumedFrom?.conversationId).toBe(CONV_ID));
      expect(result.current.rebindConversationId).toBeNull();

      deliver({ type: "error", message: "Conversation not found" });
      await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(1));
      expect(result.current.rebindRefused).toBe(false);
      expect(framesOfType(second, "start_session")).toHaveLength(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("resumeSession on a CLOSED socket does not arm the rebind (the send was dropped)", async () => {
    const { result } = await blockedAfterOneMessage();
    act(() => {
      result.current.reconnect();
    });
    await waitFor(() => expect(allSockets).toHaveLength(2));
    const second = wsInstance!;
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));
    second.readyState = MockWebSocket.CLOSED;

    act(() => {
      result.current.resumeSession(CONV_ID);
    });
    expect(framesOfType(second, "resume_session")).toHaveLength(0);

    deliver({ type: "error", message: "Conversation not found" });
    await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(1));
    expect(result.current.rebindRefused).toBe(false);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("the armed rebind is cleared on reconnect(): a refusal-shaped error on the next socket is an ordinary bubble", async () => {
    const { result } = await armedRebind();
    act(() => {
      result.current.reconnect();
    });
    await waitFor(() => expect(allSockets).toHaveLength(3));
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(result.current.status).toBe("connected"));
    deliver({ type: "error", message: "Conversation not found" });
    await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(1));
    expect(result.current.rebindRefused).toBe(false);
  });

  it("the armed rebind is cleared when the socket closes: a late refusal-shaped error is an ordinary bubble", async () => {
    const { result, second } = await armedRebind();
    // Transient close -> reconnect scheduling; the armed rebind died with the socket.
    act(() => {
      second.onclose?.({ code: 1006 } as CloseEvent);
    });
    deliver({ type: "error", message: "Conversation not found" });
    await waitFor(() => expect(errorBubbles(result.current.messages)).toHaveLength(1));
    expect(result.current.rebindRefused).toBe(false);
  });

  // #11525 - gate-response senders must not report "resolved" when nothing was sent.
  describe("gate-response senders drop honestly", () => {
    const gateOf = (messages: { type?: string }[], type: string) =>
      messages.find((m) => m.type === type) as
        | { resolved?: boolean; selectedOption?: string }
        | undefined;

    it("sendReviewGateResponse on a closed socket sends no frame, leaves the card actionable and mirrors to Sentry", async () => {
      const { result } = await connected();
      const socket = wsInstance!;
      deliver({ type: "review_gate", gateId: "g1", question: "ok?", options: ["Yes", "No"] });
      await waitFor(() => expect(gateOf(result.current.messages, "review_gate")).toBeDefined());
      socket.readyState = MockWebSocket.CLOSED;

      act(() => {
        result.current.sendReviewGateResponse("g1", "Yes");
      });
      expect(framesOfType(socket, "review_gate_response")).toHaveLength(0);
      expect(gateOf(result.current.messages, "review_gate")?.resolved).toBeFalsy();
      expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
      expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
        feature: "send-message",
        op: "refused-socket-not-open",
      });
    });

    it("sendReviewGateResponse on an open socket sends one frame and resolves the card", async () => {
      const { result } = await connected();
      const socket = wsInstance!;
      deliver({ type: "review_gate", gateId: "g1", question: "ok?", options: ["Yes", "No"] });
      await waitFor(() => expect(gateOf(result.current.messages, "review_gate")).toBeDefined());
      act(() => {
        result.current.sendReviewGateResponse("g1", "Yes");
      });
      expect(framesOfType(socket, "review_gate_response")).toHaveLength(1);
      expect(gateOf(result.current.messages, "review_gate")?.resolved).toBe(true);
    });

    it("sendAutonomousDisclosureResponse on a closed socket sends no frame and leaves the banner actionable", async () => {
      const { result } = await connected();
      const socket = wsInstance!;
      deliver({ type: "autonomous_disclosure", gateId: "d1", existingWorkspace: false });
      await waitFor(() =>
        expect(gateOf(result.current.messages, "autonomous_disclosure")).toBeDefined(),
      );
      socket.readyState = MockWebSocket.CLOSED;

      act(() => {
        result.current.sendAutonomousDisclosureResponse("d1", "ack");
      });
      expect(framesOfType(socket, "autonomous_disclosure_response")).toHaveLength(0);
      expect(gateOf(result.current.messages, "autonomous_disclosure")?.resolved).toBeFalsy();
    });

    it("sendInteractivePromptResponse returns false and sends no frame when the socket is not open", async () => {
      const { result } = await connected();
      const socket = wsInstance!;
      socket.readyState = MockWebSocket.CLOSED;
      let sent: boolean | undefined;
      act(() => {
        sent = result.current.sendInteractivePromptResponse({
          type: "interactive_prompt_response",
          promptId: "p1",
          conversationId: CONV_ID,
          kind: "ask_user",
          response: "a",
        } as never);
      });
      expect(sent).toBe(false);
      expect(framesOfType(socket, "interactive_prompt_response")).toHaveLength(0);
    });

    it("gate senders while credential-blocked send nothing and do NOT mirror (expected refusal)", async () => {
      const { result, first } = await blockedAfterOneMessage();
      // A real `close()` flips readyState to CLOSING; the mock does not.
      first.readyState = MockWebSocket.CLOSING;
      mockReportSilentFallback.mockClear();
      act(() => {
        result.current.sendReviewGateResponse("g1", "Yes");
        result.current.sendAutonomousDisclosureResponse("d1", "ack");
      });
      expect(framesOfType(first, "review_gate_response")).toHaveLength(0);
      expect(framesOfType(first, "autonomous_disclosure_response")).toHaveLength(0);
      expect(mockReportSilentFallback).not.toHaveBeenCalled();
    });
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
