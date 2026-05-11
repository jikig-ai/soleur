/**
 * RED tests for issue #3266 Phase 4 — cc-dispatcher persists the
 * SDK-emitted session_id back to `conversations.session_id` via the
 * `onSessionIdCaptured` event, and clears the stale value on a
 * non-KeyInvalidError dispatch failure.
 *
 * Mirrors the mock-pattern at `cc-dispatcher.test.ts:1-50` —
 * `mockUpdateConversationFor` hoisted, `vi.mock("@/server/conversation-writer", …)`.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
}));

vi.mock("@/server/conversation-writer", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/conversation-writer")
  >("@/server/conversation-writer");
  return {
    ...actual,
    updateConversationFor: mockUpdateConversationFor,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/kb-document-resolver", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/kb-document-resolver")
  >("@/server/kb-document-resolver");
  return {
    ...actual,
    fetchUserWorkspacePath: mockFetchUserWorkspacePath,
  };
});

vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "messages") return { insert: mockMessagesInsert };
      throw new Error(`unexpected table: ${table}`);
    },
    storage: { from: () => ({ download: vi.fn() }) },
  }),
}));

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { KeyInvalidError } from "@/lib/types";

function persistSessionIdCalls() {
  return mockUpdateConversationFor.mock.calls.filter(
    ([, , , opts]) =>
      opts?.feature === "cc-dispatcher" && opts?.op === "persist-session-id",
  );
}

function clearStaleSessionIdCalls() {
  return mockUpdateConversationFor.mock.calls.filter(
    ([, , , opts]) =>
      opts?.feature === "cc-dispatcher" &&
      opts?.op === "clear-stale-session-id",
  );
}

describe("cc-dispatcher — session_id writer (#3266 Phase 4)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
    mockMessagesInsert.mockClear();
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockClear();
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
  });

  it("persists session_id via updateConversationFor when runner fires onSessionIdCaptured", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);
    const onSessionIdPersisted = vi.fn();

    const stubRunner = {
      dispatch: vi.fn(async (args: { events: { onSessionIdCaptured?: (id: string) => void } }) => {
        args.events.onSessionIdCaptured?.("sess-Y");
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-writer-1",
      conversationId: "conv-writer-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
      onSessionIdPersisted,
    });

    const calls = persistSessionIdCalls();
    expect(calls).toHaveLength(1);
    const [userId, conversationId, patch, opts] = calls[0]!;
    expect(userId).toBe("u-writer-1");
    expect(conversationId).toBe("conv-writer-1");
    expect(patch).toEqual({ session_id: "sess-Y" });
    expect(opts.expectMatch).toBe(true);
    // Cache-update callback fires synchronously so the next chat-case
    // warm-cache turn forwards the just-persisted value (Perf F1).
    expect(onSessionIdPersisted).toHaveBeenCalledTimes(1);
    expect(onSessionIdPersisted).toHaveBeenCalledWith("sess-Y");
  });

  it("does NOT re-write when runner does not fire onSessionIdCaptured", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const stubRunner = {
      dispatch: vi.fn(async () => {}),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-writer-2",
      conversationId: "conv-writer-2",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    expect(persistSessionIdCalls()).toHaveLength(0);
  });

  it("clears stale session_id when runner throws non-KeyInvalidError with sessionId provided", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);
    const onSessionIdPersisted = vi.fn();

    const stubRunner = {
      dispatch: vi.fn(async () => {
        throw new Error("SDK resume failed: session file missing");
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-stale-1",
      conversationId: "conv-stale-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sessionId: "sess-stale",
      sendToClient,
      persistActiveWorkflow,
      onSessionIdPersisted,
    });

    const calls = clearStaleSessionIdCalls();
    expect(calls).toHaveLength(1);
    const [userId, conversationId, patch] = calls[0]!;
    expect(userId).toBe("u-stale-1");
    expect(conversationId).toBe("conv-stale-1");
    expect(patch).toEqual({ session_id: null });
    // Cache-update callback fires alongside the DB clear so the next
    // chat-case warm-cache turn does not forward the stale value.
    expect(onSessionIdPersisted).toHaveBeenCalledTimes(1);
    expect(onSessionIdPersisted).toHaveBeenCalledWith(null);
  });

  it("does NOT clear session_id when runner throws KeyInvalidError", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const stubRunner = {
      dispatch: vi.fn(async () => {
        throw new KeyInvalidError();
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-key-1",
      conversationId: "conv-key-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sessionId: "sess-Y",
      sendToClient,
      persistActiveWorkflow,
    });

    expect(clearStaleSessionIdCalls()).toHaveLength(0);
    // Positive-control: the KeyInvalidError branch must surface
    // errorCode=key_invalid to the client. Without this, a regression
    // that fell through to the stale-clear branch could still pass the
    // "does NOT clear" assertion vacuously.
    const errorCalls = sendToClient.mock.calls.filter(
      ([, msg]) =>
        msg && typeof msg === "object" && (msg as { type?: string }).type === "error",
    );
    expect(errorCalls.length).toBeGreaterThan(0);
    expect((errorCalls[0]![1] as { errorCode?: string }).errorCode).toBe(
      "key_invalid",
    );
  });

  it("does NOT clear session_id when runner throws non-KeyInvalidError but no sessionId was provided", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const stubRunner = {
      dispatch: vi.fn(async () => {
        throw new Error("cold start failure");
      }),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-noid-1",
      conversationId: "conv-noid-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    expect(clearStaleSessionIdCalls()).toHaveLength(0);
  });
});
