import { describe, it, expect, vi, type MockInstance, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// --- Mocks ---

const { mockReportSilentFallback } = vi.hoisted(() => ({ mockReportSilentFallback: vi.fn() }));
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

const mockGetSession = vi.fn().mockResolvedValue({
  data: { session: { access_token: "test-token" } },
});
const authListeners = new Set<(event: string, session: { access_token: string } | null) => void>();
const mockOnAuthStateChange = vi.fn((listener: (event: string, session: { access_token: string } | null) => void) => {
  authListeners.add(listener);
  return { data: { subscription: { unsubscribe: () => authListeners.delete(listener) } } };
});

function syntheticScopeToken(userId = "synthetic-user", workspaceId = "synthetic-workspace") {
  const claims = { sub: userId, app_metadata: { current_workspace_id: workspaceId, current_organization_id: "synthetic-org" } };
  return `synthetic.${btoa(JSON.stringify(claims))}.synthetic`;
}

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: { getSession: mockGetSession, onAuthStateChange: mockOnAuthStateChange },
  }),
}));

// Capture the WebSocket instance so tests can simulate server messages
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
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    wsInstance = this;
    // Simulate connection opening asynchronously
    queueMicrotask(() => {
      this.readyState = MockWebSocket.OPEN;
      this.onopen?.(new Event("open"));
    });
  }
}

// History messages returned by the fetch mock
const historyMessages = [
  { id: "hist-1", role: "user", content: "Hello", leader_id: null },
  { id: "hist-2", role: "assistant", content: "Hi there!", leader_id: "cto" },
  { id: "hist-3", role: "user", content: "How are you?", leader_id: null },
];

describe("useWebSocket — resume history fetch (AC1, AC3, AC4)", () => {
  let originalWebSocket: typeof globalThis.WebSocket;
  let fetchSpy: MockInstance;

  beforeEach(async () => {
    vi.clearAllMocks();
    mockGetSession.mockResolvedValue({ data: { session: { access_token: "test-token" } } });
    const { codexHeldTurnCache } = await import("@/lib/codex-held-turn-cache");
    codexHeldTurnCache.clear();
    wsInstance = null;

    originalWebSocket = globalThis.WebSocket;
    // @ts-expect-error — mock constructor shape
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

  /** Helper: simulate server sending a WS message to the client */
  function serverSend(data: Record<string, unknown>) {
    act(() => {
      wsInstance?.onmessage?.(new MessageEvent("message", {
        data: JSON.stringify(data),
      }));
    });
  }

  /** Helper: bring the hook to "connected + session confirmed" state */
  async function connectAndAuth(result: { current: ReturnType<typeof import("@/lib/ws-client").useWebSocket> }) {
    // Wait for WebSocket onopen + auth send
    await waitFor(() => {
      expect(wsInstance).not.toBeNull();
      expect(wsInstance?.send).toHaveBeenCalled();
    });

    // Server confirms auth
    serverSend({ type: "auth_ok" });

    await waitFor(() => {
      expect(result.current.status).toBe("connected");
    });
  }

  async function acknowledgeHeldDraft() {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    const attachments = [{ storagePath: "synthetic/draft.txt", filename: "draft.txt", contentType: "text/plain", sizeBytes: 42 }];
    act(() => result.current.sendMessage("Keep this original draft", attachments));
    if (!wsInstance) throw new Error("expected connected test socket");
    const ws = wsInstance;
    const chat = ws.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).find((frame) => frame.type === "chat");
    serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-history-ack",
      authModeGeneration: 2, authMode: "api-key", clientTurnId: chat.clientTurnId,
    });
    act(() => result.current.acknowledgeCodexHistoryTransfer("conv-history-ack", 2));
    serverSend({ type: "codex_history_transfer_acknowledged", conversationId: "conv-history-ack", authModeGeneration: 2 });
    const retainedMessage = result.current.messages[0];
    if (retainedMessage.type !== "text") throw new Error("expected retained text draft");
    expect(retainedMessage.delivery).toBe("retryable");
    ws.send.mockClear();
    return { result, ws, chat, retainedMessage };
  }

  async function holdUnacknowledgedDraft() {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    act(() => result.current.sendMessage("Keep this unacknowledged draft"));
    if (!wsInstance) throw new Error("expected connected test socket");
    const ws = wsInstance;
    const chat = ws.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).find((frame) => frame.type === "chat");
    serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-history-ack",
      authModeGeneration: 2, authMode: "api-key", clientTurnId: chat.clientTurnId,
    });
    const retainedMessage = result.current.messages[0];
    if (retainedMessage.type !== "text") throw new Error("expected retained text draft");
    expect(retainedMessage.delivery).toBe("unsent");
    expect(result.current.hasPendingCodexHistoryTransfer).toBe(true);
    ws.send.mockClear();
    return { result, ws, chat, retainedMessage };
  }

  async function cacheTwoHeldTurns() {
    mockGetSession.mockResolvedValue({ data: { session: { access_token: syntheticScopeToken() } } });
    const { useWebSocket } = await import("@/lib/ws-client");
    const mounted = renderHook(() => useWebSocket("new"));
    await connectAndAuth(mounted.result);
    serverSend({ type: "session_started", conversationId: "conv-held-remount" });
    act(() => mounted.result.current.sendMessage("First held turn"));
    act(() => mounted.result.current.sendMessage("Second held turn"));
    const chats = (wsInstance?.send.mock.calls ?? []).map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat");
    for (const chat of chats) serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-held-remount",
      authModeGeneration: 3, authMode: "managed", clientTurnId: chat.clientTurnId,
    });
    act(() => mounted.result.current.acknowledgeCodexHistoryTransfer("conv-held-remount", 3));
    serverSend({ type: "codex_history_transfer_acknowledged", conversationId: "conv-held-remount", authModeGeneration: 3 });
    expect(mounted.result.current.messages.map((message) => message.type === "text" ? message.delivery : null)).toEqual(["retryable", "retryable"]);
    mounted.unmount();
    return { useWebSocket, chats };
  }

  it("restores every held turn after actual unmount/remount, requiring new acknowledgment and explicit resend", async () => {
    const { useWebSocket, chats } = await cacheTwoHeldTurns();
    const mounted = renderHook(() => useWebSocket("new"));
    await connectAndAuth(mounted.result);
    expect(mounted.result.current.messages).toEqual([]); // No transcript hydration before server conversation authorization.
    serverSend({ type: "session_resumed", conversationId: "conv-held-remount", resumedFromTimestamp: "2026-10-01T00:00:00Z", messageCount: 0 });
    const held = mounted.result.current.messages.filter((message) => message.type === "text" && message.delivery === "unsent");
    expect(held.map((message) => message.id)).toEqual(chats.map((chat) => `user-${chat.clientTurnId}`));
    expect(held.map((message) => message.content)).toEqual(["First held turn", "Second held turn"]);
    expect(mounted.result.current.lastError?.code).toBe("codex_history_transfer_required");
    const socket = wsInstance!;
    socket.send.mockClear();
    for (const message of held) if (message.type === "text") act(() => mounted.result.current.resendMessage({ ...message, delivery: "retryable" }));
    expect(socket.send).not.toHaveBeenCalled(); // A forged local delivery flag cannot restore prior permission.
    act(() => mounted.result.current.acknowledgeCodexHistoryTransfer("conv-held-remount", 3));
    expect(socket.send.mock.calls.map(([frame]) => JSON.parse(frame as string).type)).toEqual(["codex_history_transfer_acknowledge"]);
    serverSend({ type: "codex_history_transfer_acknowledged", conversationId: "conv-held-remount", authModeGeneration: 3 });
    expect(socket.send).toHaveBeenCalledTimes(1); // The ACK never sends a held turn.
    for (const message of mounted.result.current.messages) if (message.type === "text" && message.delivery === "retryable") act(() => mounted.result.current.resendMessage(message));
    expect(socket.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat")).toEqual(chats);
    mounted.unmount();
    const reopened = renderHook(() => useWebSocket("new"));
    await connectAndAuth(reopened.result);
    serverSend({ type: "session_started", conversationId: "conv-held-remount" });
    expect(reopened.result.current.messages.some((message) => message.type === "text" && message.delivery !== undefined)).toBe(false);
  });

  it.each(["user", "workspace", "unverified", "logout", "revocation"])("does not restore held turns after %s scope invalidation", async (change) => {
    const { useWebSocket } = await cacheTwoHeldTurns();
    if (change === "logout") for (const listener of authListeners) listener("SIGNED_OUT", null);
    mockGetSession.mockResolvedValue({ data: { session: { access_token: change === "user" ? syntheticScopeToken("synthetic-other-user")
      : change === "workspace" ? syntheticScopeToken("synthetic-user", "synthetic-other-workspace")
        : change === "unverified" ? "test-token" : syntheticScopeToken() } } });
    const mounted = renderHook(() => useWebSocket("new"));
    await connectAndAuth(mounted.result);
    if (change === "revocation") act(() => wsInstance?.onclose?.(new CloseEvent("close", { code: 4012 })));
    else serverSend({ type: "session_started", conversationId: "conv-held-remount" });
    expect(mounted.result.current.messages.some((message) => message.type === "text" && message.delivery !== undefined)).toBe(false);
    mounted.unmount();
    // Returning to the former account/workspace cannot resurrect its invalidated collection.
    mockGetSession.mockResolvedValue({ data: { session: { access_token: syntheticScopeToken() } } });
    const original = renderHook(() => useWebSocket("new"));
    await connectAndAuth(original.result);
    serverSend({ type: "session_started", conversationId: "conv-held-remount" });
    expect(original.result.current.messages.some((message) => message.type === "text" && message.delivery !== undefined)).toBe(false);
  });

  it.each([MockWebSocket.CLOSING, MockWebSocket.CLOSED])("retains the acknowledged draft when socket state %s precedes the close-status update", async (readyState) => {
    const { result, ws, chat, retainedMessage } = await acknowledgeHeldDraft();
    ws.readyState = readyState;
    expect(result.current.status).toBe("connected");
    act(() => result.current.resendMessage(retainedMessage));
    expect(ws.send).not.toHaveBeenCalled();
    expect(result.current.messages).toEqual([retainedMessage]);

    ws.readyState = MockWebSocket.OPEN;
    act(() => result.current.resendMessage(retainedMessage));
    act(() => result.current.resendMessage(retainedMessage));
    expect(ws.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([chat]);
    expect(result.current.messages).toHaveLength(1);
    expect(result.current.messages[0]).toEqual(expect.objectContaining({
      id: retainedMessage.id, content: retainedMessage.content, attachments: retainedMessage.attachments,
    }));
    expect(result.current.messages[0]).not.toHaveProperty("delivery");
  });

  it("retains the acknowledged draft after a synchronous socket send failure", async () => {
    const { result, ws, chat, retainedMessage } = await acknowledgeHeldDraft();
    ws.send.mockImplementationOnce(() => { throw new DOMException("Socket is closing", "InvalidStateError"); });
    expect(() => act(() => result.current.resendMessage(retainedMessage))).not.toThrow();
    expect(result.current.messages).toEqual([retainedMessage]);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(expect.any(DOMException), expect.objectContaining({
      feature: "codex-history-transfer", op: "send-resend-throw",
    }));

    ws.send.mockClear();
    act(() => result.current.resendMessage(retainedMessage));
    act(() => result.current.resendMessage(retainedMessage));
    expect(ws.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([chat]);
    expect(result.current.messages).toHaveLength(1);
    expect(result.current.messages[0]).not.toHaveProperty("delivery");
  });

  it("waits for same-conversation session confirmation after reconnect auth before explicitly resending the original draft once", async () => {
    const { result, ws: previousWs, chat, retainedMessage } = await acknowledgeHeldDraft();
    act(() => result.current.reconnect());
    await waitFor(() => {
      expect(wsInstance).not.toBe(previousWs);
      expect(wsInstance?.send).toHaveBeenCalled();
    });
    serverSend({ type: "auth_ok" });
    expect(result.current.status).toBe("connected");
    expect(result.current.sessionConfirmed).toBe(false);
    expect(result.current.connection.phase).toBe("unrecoverable");
    if (!wsInstance) throw new Error("expected reconnected test socket");
    const reconnectedWs = wsInstance;
    reconnectedWs.send.mockClear();
    act(() => result.current.resendMessage(retainedMessage));
    expect(reconnectedWs.send).not.toHaveBeenCalled();
    expect(result.current.messages).toEqual([retainedMessage]);

    act(() => result.current.resumeAfterUnrecoverable());
    await waitFor(() => {
      expect(wsInstance).not.toBe(reconnectedWs);
      expect(wsInstance?.send).toHaveBeenCalled();
    });
    if (!wsInstance) throw new Error("expected explicit recovery socket");
    const recoveryWs = wsInstance;
    recoveryWs.send.mockClear();
    serverSend({ type: "auth_ok" });
    expect(result.current.sessionConfirmed).toBe(false);
    expect(recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([
      { type: "resume_session", conversationId: "conv-history-ack" },
    ]);
    act(() => result.current.resendMessage(retainedMessage));
    expect(recoveryWs.send).toHaveBeenCalledTimes(1);
    expect(result.current.messages).toEqual([retainedMessage]);

    fetchSpy.mockResolvedValueOnce(new Response(JSON.stringify({ messages: [] }), {
      status: 200, headers: { "Content-Type": "application/json" },
    }));
    serverSend({
      type: "session_resumed", conversationId: "conv-history-ack",
      resumedFromTimestamp: "2026-09-30T00:00:00Z", messageCount: 0,
    });
    await waitFor(() => expect(result.current.historyLoading).toBe(false));
    expect(result.current.sessionConfirmed).toBe(true);
    expect(recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([
      { type: "resume_session", conversationId: "conv-history-ack" },
    ]);
    act(() => result.current.resendMessage(retainedMessage));
    act(() => result.current.resendMessage(retainedMessage));
    const chats = recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat");
    expect(chats).toEqual([chat]);
    expect(result.current.messages).toHaveLength(1);
    expect(result.current.messages[0]).toEqual(expect.objectContaining({
      id: retainedMessage.id, content: retainedMessage.content, attachments: retainedMessage.attachments,
    }));
    expect(result.current.messages[0]).not.toHaveProperty("delivery");
  });

  it("preserves an unacknowledged transfer through explicit same-conversation recovery", async () => {
    const { result, ws: previousWs, chat, retainedMessage } = await holdUnacknowledgedDraft();
    act(() => result.current.resumeAfterUnrecoverable());
    await waitFor(() => {
      expect(wsInstance).not.toBe(previousWs);
      expect(wsInstance?.send).toHaveBeenCalled();
    });
    if (!wsInstance) throw new Error("expected explicit recovery socket");
    const recoveryWs = wsInstance;
    recoveryWs.send.mockClear();
    serverSend({ type: "auth_ok" });
    expect(recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([
      { type: "resume_session", conversationId: "conv-history-ack" },
    ]);
    expect(result.current.lastError?.code).toBe("codex_history_transfer_required");
    expect(result.current.hasPendingCodexHistoryTransfer).toBe(true);
    fetchSpy.mockResolvedValueOnce(new Response(JSON.stringify({ messages: [] }), {
      status: 200, headers: { "Content-Type": "application/json" },
    }));
    serverSend({
      type: "session_resumed", conversationId: "conv-history-ack",
      resumedFromTimestamp: "2026-09-30T00:00:00Z", messageCount: 0,
    });
    await waitFor(() => expect(result.current.historyLoading).toBe(false));
    expect(result.current.sessionConfirmed).toBe(true);
    expect(result.current.messages).toEqual([retainedMessage]);

    act(() => result.current.acknowledgeCodexHistoryTransfer("conv-history-ack", 2));
    expect(recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([
      { type: "resume_session", conversationId: "conv-history-ack" },
      { type: "codex_history_transfer_acknowledge", conversationId: "conv-history-ack", authModeGeneration: 2 },
    ]);
    serverSend({ type: "codex_history_transfer_acknowledged", conversationId: "conv-history-ack", authModeGeneration: 2 });
    expect(result.current.lastError).toBeNull();
    const retryable = result.current.messages[0];
    if (retryable.type !== "text") throw new Error("expected retryable text draft");
    act(() => result.current.resendMessage(retryable));
    const frames = recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string));
    expect(frames.filter((frame) => frame.type === "chat")).toEqual([chat]);
    expect(result.current.messages).toHaveLength(1);
    expect(result.current.hasPendingCodexHistoryTransfer).toBe(false);
  });

  it("keeps a held draft awaiting explicit session recovery even when stamped replay frames arrive", async () => {
    const { result, ws: previousWs, chat, retainedMessage } = await acknowledgeHeldDraft();
    serverSend({ type: "stream_start", leaderId: "cto", seq: 0 });
    act(() => result.current.reconnect());
    await waitFor(() => {
      expect(wsInstance).not.toBe(previousWs);
      expect(wsInstance?.send).toHaveBeenCalled();
    });
    serverSend({ type: "auth_ok" });
    expect(result.current.sessionConfirmed).toBe(false);
    expect(result.current.connection.phase).toBe("unrecoverable");
    expect(wsInstance?.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toContainEqual({
      type: "resume_stream", conversationId: "conv-history-ack", ackSeq: 0,
    });
    serverSend({ type: "stream", leaderId: "cto", content: "Unstamped frame", partial: true });
    expect(result.current.sessionConfirmed).toBe(false);
    serverSend({ type: "stream", leaderId: "cto", content: "Replayed reply", partial: true, seq: 1 });
    expect(result.current.sessionConfirmed).toBe(false);
    expect(result.current.connection.phase).toBe("unrecoverable");
    expect(result.current.messages.find((message) => message.id === retainedMessage.id)).toEqual(retainedMessage);
    act(() => result.current.resendMessage(retainedMessage));
    expect(wsInstance?.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat")).toEqual([]);

    const replayWs = wsInstance;
    act(() => result.current.resumeAfterUnrecoverable());
    await waitFor(() => {
      expect(wsInstance).not.toBe(replayWs);
      expect(wsInstance?.send).toHaveBeenCalled();
    });
    if (!wsInstance) throw new Error("expected explicit recovery socket");
    const recoveryWs = wsInstance;
    recoveryWs.send.mockClear();
    serverSend({ type: "auth_ok" });
    expect(recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([
      { type: "resume_session", conversationId: "conv-history-ack" },
    ]);
    expect(result.current.sessionConfirmed).toBe(false);
    fetchSpy.mockResolvedValueOnce(new Response(JSON.stringify({ messages: [] }), {
      status: 200, headers: { "Content-Type": "application/json" },
    }));
    serverSend({
      type: "session_resumed", conversationId: "conv-history-ack",
      resumedFromTimestamp: "2026-09-30T00:00:00Z", messageCount: 0,
    });
    await waitFor(() => expect(result.current.historyLoading).toBe(false));
    expect(result.current.sessionConfirmed).toBe(true);
    act(() => result.current.resendMessage(retainedMessage));
    act(() => result.current.resendMessage(retainedMessage));
    expect(recoveryWs.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat")).toEqual([chat]);
    expect(result.current.messages.filter((message) => message.role === "user")).toHaveLength(1);
  });

  it.each([
    { authMode: "api-key", billing: "your own credential", account: "your provider account" },
    { authMode: "managed", billing: "your own connected ChatGPT account", account: "confirm applicable billing" },
  ])("correlates an unsent turn and explains history transfer for $authMode without resending on acknowledgment", async ({ authMode, billing, account }) => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    const attachments = [{ storagePath: "synthetic/draft.txt", filename: "draft.txt", contentType: "text/plain", sizeBytes: 42 }];
    act(() => result.current.sendMessage("Keep this original draft", attachments));
    act(() => result.current.sendMessage("A separate turn"));
    const chats = (wsInstance?.send.mock.calls ?? []).map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat");
    expect(chats).toHaveLength(2);

    serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-history-ack",
      authModeGeneration: 2, authMode, clientTurnId: chats[0].clientTurnId,
    });

    expect(result.current.messages[0]).toEqual(expect.objectContaining({
      id: `user-${chats[0].clientTurnId}`, content: "Keep this original draft", attachments, delivery: "unsent",
    }));
    expect(result.current.messages[1]).not.toHaveProperty("delivery");
    expect(result.current.lastError?.message).toContain("OpenAI");
    expect(result.current.lastError?.message).toContain("stored history");
    expect(result.current.lastError?.message).toContain(billing);
    expect(result.current.lastError?.message).toContain(account);
    expect(result.current.lastError?.message).toContain("then resend");

    serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-history-ack",
      authModeGeneration: 2, authMode, clientTurnId: chats[1].clientTurnId,
    });
    expect(result.current.messages[1]).toEqual(expect.objectContaining({ content: "A separate turn", delivery: "unsent" }));

    wsInstance?.send.mockClear();
    act(() => result.current.acknowledgeCodexHistoryTransfer("conv-history-ack", 2));
    expect(result.current.lastError?.code).toBe("codex_history_transfer_required");
    expect(wsInstance?.send.mock.calls.map(([frame]) => JSON.parse(frame as string))).toEqual([{
      type: "codex_history_transfer_acknowledge", conversationId: "conv-history-ack", authModeGeneration: 2,
    }]);
    serverSend({ type: "codex_history_transfer_acknowledged", conversationId: "conv-history-ack", authModeGeneration: 2 });
    expect(result.current.lastError).toBeNull();
    expect(result.current.messages[0]).toEqual(expect.objectContaining({ content: "Keep this original draft", attachments, delivery: "retryable" }));
    expect(wsInstance?.send).toHaveBeenCalledTimes(1);

    const retainedMessage = result.current.messages[0];
    act(() => result.current.resendMessage(retainedMessage as Extract<typeof retainedMessage, { type: "text" }>));
    const resentChats = (wsInstance?.send.mock.calls ?? []).map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat");
    expect(resentChats).toHaveLength(1);
    expect(resentChats[0]).toEqual({
      type: "chat", content: "Keep this original draft", attachments, clientTurnId: chats[0].clientTurnId,
    });
    expect(result.current.messages).toHaveLength(2);
    expect(result.current.messages[0]).not.toHaveProperty("delivery");
    expect(result.current.messages[1]).toEqual(expect.objectContaining({ content: "A separate turn", delivery: "retryable" }));
    act(() => result.current.resendMessage(result.current.messages[1] as Extract<typeof result.current.messages[number], { type: "text" }>));
    const allExplicitRetries = (wsInstance?.send.mock.calls ?? []).map(([frame]) => JSON.parse(frame as string)).filter((frame) => frame.type === "chat");
    expect(allExplicitRetries).toHaveLength(2);
    expect(allExplicitRetries[1]).toEqual({
      type: "chat", content: "A separate turn", attachments: undefined, clientTurnId: chats[1].clientTurnId,
    });
    expect(result.current.messages).toHaveLength(2);
    expect(result.current.messages[1]).not.toHaveProperty("delivery");
  });

  it("ignores another conversation's required notice even when its turn ID matches a local message", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-active" });
    act(() => result.current.sendMessage("Keep active conversation"));
    const chat = (wsInstance?.send.mock.calls ?? []).map(([frame]) => JSON.parse(frame as string)).find((frame) => frame.type === "chat");
    serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-stale",
      authModeGeneration: 2, authMode: "api-key", clientTurnId: chat.clientTurnId,
    });
    expect(result.current.lastError).toBeNull();
    expect(result.current.messages[0]).not.toHaveProperty("delivery");
  });

  it("keeps a legacy notice usable without inventing correlation or credential ownership", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    act(() => result.current.sendMessage("Older server turn"));
    serverSend({ type: "codex_history_transfer_required", conversationId: "conv-history-ack", authModeGeneration: 2 });
    expect(result.current.lastError?.message).toContain("OpenAI");
    expect(result.current.lastError?.message).toContain("then resend");
    expect(result.current.messages[0]).not.toHaveProperty("delivery");
  });

  it.each([
    { conversationId: "conv-history-ack", authModeGeneration: 1 },
    { conversationId: "conv-stale", authModeGeneration: 2 },
  ])("keeps the current notice after a stale acknowledgment %j", async (confirmation) => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    act(() => result.current.sendMessage("Keep the unacknowledged draft"));
    const chat = wsInstance?.send.mock.calls.map(([frame]) => JSON.parse(frame as string)).find((frame) => frame.type === "chat");
    serverSend({
      type: "codex_history_transfer_required", conversationId: "conv-history-ack",
      authModeGeneration: 2, authMode: "managed", clientTurnId: chat.clientTurnId,
    });
    const retainedMessage = result.current.messages[0];
    if (retainedMessage.type !== "text") throw new Error("expected held text draft");
    wsInstance?.send.mockClear();
    serverSend({ type: "codex_history_transfer_acknowledged", ...confirmation });
    expect(result.current.lastError).toEqual(expect.objectContaining({ conversationId: "conv-history-ack", authModeGeneration: 2 }));
    expect(result.current.messages[0]).toEqual({ ...retainedMessage, delivery: "unsent" });
    act(() => result.current.resendMessage({ ...retainedMessage, delivery: "retryable" }));
    expect(wsInstance?.send).not.toHaveBeenCalled();
  });

  it.each(["codex_history_transfer_acknowledgment_rejected", "codex_history_transfer_acknowledgment_failed"])("keeps the notice after %s", async (errorCode) => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    serverSend({ type: "codex_history_transfer_required", conversationId: "conv-history-ack", authModeGeneration: 2, authMode: "managed" });
    wsInstance?.send.mockClear();
    serverSend({ type: "error", errorCode, message: "Review the current notice and try again." });
    expect(result.current.lastError?.code).toBe("codex_history_transfer_required");
    expect(wsInstance?.send).not.toHaveBeenCalled();
  });

  it("clears an old conversation's notice when a different session starts", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));
    await connectAndAuth(result);
    serverSend({ type: "session_started", conversationId: "conv-history-ack" });
    serverSend({ type: "codex_history_transfer_required", conversationId: "conv-history-ack", authModeGeneration: 2, authMode: "managed" });
    serverSend({ type: "session_started", conversationId: "conv-next" });
    expect(result.current.lastError).toBeNull();
  });

  it.each(["session_started", "session_resumed"])("invalidates an acknowledged held draft when another conversation emits %s", async (type) => {
    const { result, ws, retainedMessage } = await acknowledgeHeldDraft();
    fetchSpy.mockResolvedValueOnce(new Response(JSON.stringify({ messages: [] }), {
      status: 200, headers: { "Content-Type": "application/json" },
    }));
    serverSend({
      type, conversationId: "conv-next",
      ...(type === "session_resumed" ? { resumedFromTimestamp: "2026-09-30T00:00:00Z", messageCount: 0 } : {}),
    });
    expect(result.current.messages[0]).toEqual({ ...retainedMessage, delivery: "unsent" });
    act(() => result.current.resendMessage(retainedMessage));
    expect(ws.send).not.toHaveBeenCalled();
  });

  it("fetches history when realConversationId is set from session_resumed", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // Server sends session_resumed (the sidebar resume path)
    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    // The new effect should fire and fetch history
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-existing-123/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // Messages should contain the fetched history
    await waitFor(() => {
      expect(result.current.messages.length).toBe(3);
      expect(result.current.messages[0].id).toBe("hist-1");
      expect(result.current.messages[1].id).toBe("hist-2");
      expect(result.current.messages[2].id).toBe("hist-3");
    });
  });

  it("preserves chronological order (oldest first)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    await waitFor(() => {
      expect(result.current.messages.length).toBe(3);
    });

    // Verify order: user, assistant, user (oldest first)
    expect(result.current.messages[0].role).toBe("user");
    expect(result.current.messages[0].content).toBe("Hello");
    expect(result.current.messages[1].role).toBe("assistant");
    expect(result.current.messages[1].content).toBe("Hi there!");
    expect(result.current.messages[2].role).toBe("user");
    expect(result.current.messages[2].content).toBe("How are you?");
  });

  it("deduplicates messages if a stream event arrives during fetch", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // Simulate a stream_start that creates a message with ID "hist-2"
    // BEFORE the resume event fires (simulates race condition)
    serverSend({
      type: "stream_start",
      leaderId: "cto",
      messageId: "hist-2",
    });

    // Now server sends session_resumed — the history fetch should
    // deduplicate "hist-2" which already exists from the stream
    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    // Wait for history to load
    await waitFor(() => {
      // Should have history messages PLUS the stream message, but
      // "hist-2" should appear only once (deduplication)
      const hist2Count = result.current.messages.filter((m) => m.id === "hist-2").length;
      expect(hist2Count).toBe(1);
      // Total should be 3 (hist-1, hist-2 deduplicated, hist-3) + 0 extra
      // The stream_start created a bubble for "hist-2" which history also contains
      expect(result.current.messages.length).toBeGreaterThanOrEqual(3);
    });
  });

  it("seeds usageData from cost fields in the history response", async () => {
    // Override fetch mock to include cost data in response
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify({
        messages: historyMessages,
        totalCostUsd: 0.0042,
        inputTokens: 1200,
        outputTokens: 300,
      }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    serverSend({
      type: "session_resumed",
      conversationId: "conv-existing-123",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });

    // Wait for history to load AND usageData to be seeded
    await waitFor(() => {
      expect(result.current.messages.length).toBe(3);
      // Cache token fields default to 0 when the history response
      // omits them (pre-2026-05-12 conversations). New conversations
      // surface non-zero values; resume of those is exercised by
      // `chat-page-resume.test.tsx`.
      expect(result.current.usageData).toEqual({
        totalCostUsd: 0.0042,
        inputTokens: 1200,
        outputTokens: 300,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
      });
    });
  });

  it("does NOT fetch history for a fresh session_started conversation (FR1/AC1)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // Server starts a BRAND-NEW conversation: deferred-creation path emits
    // session_started with a pending UUID and NO DB row yet. resumedFrom
    // stays null. The resume-history effect must NOT fire a fetch — the row
    // does not exist, so GET /messages would 404 (the bug this fixes).
    serverSend({
      type: "session_started",
      conversationId: "conv-fresh-deferred-999",
    });

    // The handler ran (realConversationId resolved). With both state updates
    // batched, the resume effect has had its chance to fire.
    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-fresh-deferred-999");
    });

    // No history fetch for the fresh deferred id, and the hook never enters
    // the loading state for it.
    const freshFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-fresh-deferred-999"),
    );
    expect(freshFetchCalls.length).toBe(0);
    expect(result.current.historyLoading).toBe(false);
  });

  it("fetches history for a session_resumed row with zero messages (FR2/AC2)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // A genuine resume of an existing row that happens to have 0 messages
    // MUST still fetch (the row exists; api-messages returns 200-empty). The
    // gate keys on session_started vs session_resumed, NOT on message count.
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify({ messages: [] }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    serverSend({
      type: "session_resumed",
      conversationId: "conv-resumed-empty-777",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 0,
    });

    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-resumed-empty-777/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // Exactly one fetch for the resolved id (the resume effect fired once).
    const resumedFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-resumed-empty-777"),
    );
    expect(resumedFetchCalls.length).toBe(1);

    await waitFor(() => {
      expect(result.current.historyLoading).toBe(false);
      expect(result.current.messages.length).toBe(0);
    });
  });

  it("flips resumed→fresh within one mounted hook: switching from a resumed thread to a new chat does NOT fetch (FR1 hook-reuse)", async () => {
    // The KB sidebar reuses ONE useWebSocket across conversation switches
    // (resumeByContextPath resolves a new realConversationId while the hook
    // stays mounted). If sessionKind failed to flip back to "fresh" on the
    // second session_started, the resume effect would fire a would-be-404
    // fetch for the fresh id. This locks the FR1 gate against that path.
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result);

    // 1) Resume an existing thread → fetch fires.
    serverSend({
      type: "session_resumed",
      conversationId: "conv-A-resumed",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/conv-A-resumed/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // 2) Same mounted hook now starts a BRAND-NEW conversation. sessionKind
    //    must flip "resumed" → "fresh", so NO fetch fires for the new id.
    fetchSpy.mockClear();
    serverSend({
      type: "session_started",
      conversationId: "conv-B-fresh",
    });

    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-B-fresh");
    });

    const freshFetchCalls = fetchSpy.mock.calls.filter(
      (call) => typeof call[0] === "string" && call[0].includes("conv-B-fresh"),
    );
    expect(freshFetchCalls.length).toBe(0);
    expect(result.current.historyLoading).toBe(false);
  });

  it("deep-link to a never-materialized conversation 404s into the empty state, not the error boundary (FR5/AC9)", async () => {
    // Full-route navigation to /dashboard/chat/<uuid> for a valid-but-
    // deferred / never-persisted id (stale bookmark). The mount-time effect
    // fetches, gets a 404, returns null silently. The resting state must be
    // the empty composer: historyLoading false, no messages, no lastError
    // (lastError is a WS-connection error, NOT a history-fetch 404).
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify({ error: "Conversation not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      }),
    );

    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("synthetic-deferred-conversation-id"));

    await connectAndAuth(result);

    // Mount-time effect fired the fetch for the non-"new" id.
    await waitFor(() => {
      expect(fetchSpy).toHaveBeenCalledWith(
        "/api/conversations/synthetic-deferred-conversation-id/messages",
        expect.objectContaining({
          headers: expect.objectContaining({ Authorization: "Bearer test-token" }),
        }),
      );
    });

    // Resting state = empty composer, not error boundary.
    await waitFor(() => {
      expect(result.current.historyLoading).toBe(false);
    });
    expect(result.current.messages.length).toBe(0);
    expect(result.current.lastError).toBeNull();
  });

  // #5290 — resume_stream reconnect gate: only a "resumed" (materialized,
  // owned) session may request replay. A "fresh" deferred conversation has no
  // DB row yet, so a resume_stream for it triggers the server's
  // op=ownership-mismatch false positive. Paired positive/negative under the
  // same harness so the negative is non-vacuous (the send mechanism is proven
  // to fire for "resumed").
  function sentTypes(): string[] {
    return (wsInstance?.send.mock.calls ?? []).map(
      (c) => (JSON.parse(c[0] as string) as { type: string }).type,
    );
  }

  it("reconnect with sessionKind='resumed' SENDS resume_stream (happy-path regression guard, FR)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result); // auth_ok #1 → hasConnectedBefore=true

    serverSend({
      type: "session_resumed",
      conversationId: "conv-resumed-gate",
      resumedFromTimestamp: "2026-04-16T14:15:00Z",
      messageCount: 3,
    });
    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-resumed-gate");
    });

    wsInstance?.send.mockClear();
    // Simulate a transient reconnect: a second auth_ok on the live socket.
    serverSend({ type: "auth_ok" });

    await waitFor(() => {
      const sent = (wsInstance?.send.mock.calls ?? []).map(
        (c) => JSON.parse(c[0] as string) as { type: string; conversationId?: string },
      );
      expect(
        sent.some(
          (f) => f.type === "resume_stream" && f.conversationId === "conv-resumed-gate",
        ),
      ).toBe(true);
    });
  });

  it("reconnect with sessionKind='fresh' does NOT send resume_stream (the false-positive fix, FR)", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result); // auth_ok #1 → hasConnectedBefore=true

    serverSend({
      type: "session_started",
      conversationId: "conv-fresh-gate",
    });
    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-fresh-gate");
    });

    wsInstance?.send.mockClear();
    // Reconnect (second auth_ok). The fresh deferred conv has no DB row → the
    // gate must SKIP the resume_stream send.
    serverSend({ type: "auth_ok" });

    // Settle the handler deterministically: status stays connected and the
    // microtask queue flushes. (The companion "resumed" test proves the send
    // mechanism fires under this exact harness, so this absence is meaningful.)
    await act(async () => {
      await Promise.resolve();
    });

    expect(sentTypes()).not.toContain("resume_stream");
  });

  it("reconnect with sessionKind='fresh' that has STREAMED a frame SENDS resume_stream (mid-turn drop recovery, review P2)", async () => {
    // A brand-new conversation whose first turn is already streaming: the
    // deferred row has materialized (the agent only streams after it persists),
    // proven client-side by a rendered server-stamped frame (seq >= 0). A
    // mid-turn socket drop must still recover its gap frames — the gate keys on
    // "row provably exists", not merely sessionKind === "resumed".
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket("new"));

    await connectAndAuth(result); // auth_ok #1 → hasConnectedBefore=true

    serverSend({ type: "session_started", conversationId: "conv-fresh-streamed" });
    await waitFor(() => {
      expect(result.current.realConversationId).toBe("conv-fresh-streamed");
    });

    // Agent streams a server-stamped frame → lastRenderedSeq advances to 0,
    // proving the row materialized.
    serverSend({ type: "stream_start", leaderId: "cto", messageId: "m1" });
    serverSend({
      type: "stream",
      content: "hello",
      partial: true,
      leaderId: "cto",
      seq: 0,
    });

    wsInstance?.send.mockClear();
    serverSend({ type: "auth_ok" }); // reconnect

    await waitFor(() => {
      const sent = (wsInstance?.send.mock.calls ?? []).map(
        (c) => JSON.parse(c[0] as string) as { type: string; conversationId?: string },
      );
      expect(
        sent.some(
          (f) => f.type === "resume_stream" && f.conversationId === "conv-fresh-streamed",
        ),
      ).toBe(true);
    });
  });

  it("does NOT fetch history when conversationId is not 'new'", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    // Using a real conversation ID (not "new") — the existing effect handles this
    const { result } = renderHook(() => useWebSocket("conv-known-456"));

    await connectAndAuth(result);

    serverSend({
      type: "session_started",
      conversationId: "conv-known-456",
    });

    // The existing effect already fetches for non-"new" IDs.
    // The new resume-specific effect should NOT fire because
    // realConversationId matches the prop conversationId.
    // Clear the fetch spy calls from the existing effect
    fetchSpy.mockClear();

    // Wait for any pending effects to settle deterministically
    await waitFor(() => {
      // No additional fetch calls from the resume effect — the guard
      // (realConversationId === conversationId) prevents the resume
      // effect from firing when both IDs match.
      const resumeFetchCalls = fetchSpy.mock.calls.filter(
        (call) => typeof call[0] === "string" && call[0].includes("conv-known-456"),
      );
      expect(resumeFetchCalls.length).toBe(0);
    });
  });

  it("drops a conversation-scoped Codex frame when the hook has no active conversation", async () => {
    const { useWebSocket } = await import("@/lib/ws-client");
    const { result } = renderHook(() => useWebSocket(""));

    await connectAndAuth(result);
    serverSend({ type: "stream", content: "stale conversation output", partial: true, leaderId: "cto", conversationId: "conv-stale" });

    expect(result.current.messages).toEqual([]);
  });
});
