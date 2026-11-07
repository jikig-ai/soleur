import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// #11599 — the client half of the unresolved-authentication-mode refusal. Unlike key_invalid / byok_key_missing these
// codes are NOT credential-blocked: the socket stays up (no teardown), the composer stays enabled, the unanswered message
// is marked, and the card clears on the next send. (The card itself is asserted in chat-surface-credential-blocked.test.tsx.)

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

const mockGetSession = vi.fn().mockResolvedValue({ data: { session: { access_token: "test-token" } } });
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
import { isCredentialErrorCode } from "@/lib/types";

const CONV_ID = "11111111-1111-4111-8111-111111111111";
const DETERMINISTIC = "We couldn't confirm which authentication mode this conversation uses, so your message was not processed. Start a new conversation to continue.";
const TRANSIENT = "We couldn't check which authentication mode this conversation uses just now, so your message was not processed. Please send it again in a moment.";

describe("useWebSocket — authentication mode unresolved (#11599)", () => {
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

  async function afterOneMessage(frame: Record<string, unknown>) {
    const hook = renderHook(() => useWebSocket("new"));
    await waitFor(() => expect(wsInstance).not.toBeNull());
    deliver({ type: "auth_ok" });
    await waitFor(() => expect(hook.result.current.status).toBe("connected"));
    deliver({ type: "session_started", conversationId: CONV_ID });
    await waitFor(() => expect(hook.result.current.realConversationId).toBe(CONV_ID));
    let accepted = false;
    act(() => {
      accepted = hook.result.current.sendMessage("hello");
    });
    expect(accepted).toBe(true);
    const socket = wsInstance!;
    deliver(frame);
    return { ...hook, socket };
  }

  it.each([
    ["auth_mode_unresolved", DETERMINISTIC],
    ["auth_mode_unavailable", TRANSIENT],
  ])("%s: sets lastError, marks the message unanswered, does NOT tear down, is not credential-blocked", async (code, text) => {
    const { result, socket } = await afterOneMessage({ type: "error", errorCode: code, message: text });
    await waitFor(() => expect(result.current.lastError?.code).toBe(code));
    expect(result.current.lastError?.message).toBe(text);
    // Not the blocked pair: composer stays enabled, the socket stays up and is not closed.
    expect(isCredentialErrorCode(code)).toBe(false);
    expect(result.current.credentialBlocked).toBe(false);
    expect(socket.onclose).not.toBeNull();
    expect(socket.close).not.toHaveBeenCalled();
    // The turn did not complete: the last user message is flagged, exactly as for the credential cards.
    const users = result.current.messages.filter((m) => m.role === "user");
    expect(users).toHaveLength(1);
    expect(users[0].unanswered).toBe(true);
    // No generic "Error:" bubble duplicates the card.
    expect(result.current.messages.some((m) => m.role === "assistant" && /^Error:/.test(m.content))).toBe(false);
  });

  it("only the deterministic code carries the 'Start a new conversation' action", async () => {
    const a = await afterOneMessage({ type: "error", errorCode: "auth_mode_unresolved", message: DETERMINISTIC });
    await waitFor(() => expect(a.result.current.lastError?.code).toBe("auth_mode_unresolved"));
    expect(a.result.current.lastError?.action).toEqual({ label: "Start a new conversation", href: "/dashboard/chat/new" });
    a.unmount();
    wsInstance = null;
    const b = await afterOneMessage({ type: "error", errorCode: "auth_mode_unavailable", message: TRANSIENT });
    await waitFor(() => expect(b.result.current.lastError?.code).toBe("auth_mode_unavailable"));
    expect(b.result.current.lastError?.action).toBeUndefined();
  });

  it.each(["auth_mode_unresolved", "auth_mode_unavailable"])("the next sendMessage clears the %s card", async (code) => {
    const { result } = await afterOneMessage({ type: "error", errorCode: code, message: "m" });
    await waitFor(() => expect(result.current.lastError?.code).toBe(code));
    let accepted = false;
    act(() => {
      accepted = result.current.sendMessage("again");
    });
    expect(accepted).toBe(true);
    await waitFor(() => expect(result.current.lastError).toBeNull());
  });

  // The ENTRY condition of the new branch: a code that is not one of the pair must not get the pair's treatment (the user's
  // message flagged unanswered, an action link). Complements the scoped-clear row, which only pins the exit condition.
  it.each(["rate_limited", "subscription_limit"])("an unrelated %s error does not take the authentication-mode branch", async (code) => {
    const { result } = await afterOneMessage({ type: "error", errorCode: code, message: "m" });
    await waitFor(() => expect(result.current.lastError?.code).toBe(code));
    expect(result.current.lastError?.action).toBeUndefined();
    const users = result.current.messages.filter((m) => m.role === "user");
    expect(users).toHaveLength(1);
    expect(users[0].unanswered).not.toBe(true);
  });

  it("the scoped clear leaves every other error code untouched", async () => {
    const { result } = await afterOneMessage({ type: "error", errorCode: "rate_limited", message: "slow down" });
    await waitFor(() => expect(result.current.lastError?.code).toBe("rate_limited"));
    act(() => {
      result.current.sendMessage("again");
    });
    expect(result.current.lastError?.code).toBe("rate_limited");
  });

  it("a refused send (socket not open) does not clear the card", async () => {
    const { result, socket } = await afterOneMessage({ type: "error", errorCode: "auth_mode_unresolved", message: "m" });
    await waitFor(() => expect(result.current.lastError?.code).toBe("auth_mode_unresolved"));
    socket.readyState = MockWebSocket.CLOSED;
    let accepted = true;
    act(() => {
      accepted = result.current.sendMessage("again");
    });
    expect(accepted).toBe(false);
    expect(result.current.lastError?.code).toBe("auth_mode_unresolved");
  });
});
