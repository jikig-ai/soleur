/**
 * #9538 — dispatcher-side stale-resume recovery. When the runner fires
 * `DispatchEvents.onStaleResume` (mid-stream `No conversation found with
 * session ID` on a dispatch that attempted `resume:`), the dispatcher
 * clears `conversations.session_id`, emits the `context_reset` honesty
 * frame, and re-dispatches the same turn cold — DEFERRED past
 * `closeQuery`'s `activeQueries.delete` so the retry cannot take the
 * `queryReused` path on the dying entry (which would silently drop the
 * user's message).
 *
 * Mirrors the mock-pattern at `cc-dispatcher-session-id-writer.test.ts`.
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
  // #3369: mirrorWithDebounce extracted to observability.
  // These dispatcher tests do not exercise the debounce TTL, so
  // the stub forwards every call straight through to the spy.
  mirrorWithDebounce: mockReportSilentFallback,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
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
      // mig 059: cc-dispatcher reads the parent conversation's workspace_id
      // before the messages INSERT; satisfy that read.
      if (table === "conversations")
        return {
          select: () => ({
            eq: () => ({
              single: async () => ({
                data: { workspace_id: "ws-test" },
                error: null,
              }),
            }),
          }),
        };
      throw new Error(`unexpected table: ${table}`);
    },
    storage: { from: () => ({ download: vi.fn() }) },
  }),
}));

// PR-C §2.11 (#3244): tenant migration of cc-dispatcher message inserts.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({
    from: (table: string) => {
      if (table === "messages") return { insert: mockMessagesInsert };
      if (table === "conversations")
        return {
          select: () => ({
            eq: () => ({
              single: async () => ({
                data: { workspace_id: "ws-test" },
                error: null,
              }),
            }),
          }),
        };
      throw new Error(`unexpected table: ${table}`);
    },
  })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { CONTEXT_RESET_NOTICE_GENERIC } from "@/server/agent-prefill-guard";
import type { WSMessage } from "@/lib/types";
import { flushMicrotasks } from "./helpers/soleur-go-fixtures";

function clearStaleSessionIdCalls() {
  return mockUpdateConversationFor.mock.calls.filter(
    ([, , , opts]) =>
      opts?.feature === "cc-dispatcher" &&
      opts?.op === "clear-stale-session-id",
  );
}

function failedRevertCalls() {
  return mockUpdateConversationFor.mock.calls.filter(
    ([, , patch, opts]) =>
      opts?.feature === "cc-dispatcher" &&
      (patch as { status?: string }).status === "failed",
  );
}

function framesOfType(sendToClient: ReturnType<typeof vi.fn>, type: string) {
  return sendToClient.mock.calls.filter(
    ([, msg]) =>
      msg && typeof msg === "object" && (msg as { type?: string }).type === type,
  );
}

/** Minimal SoleurGoRunner stub; `dispatch` behavior is per-test. */
function makeStubRunner(
  dispatchImpl: (args: {
    events: { onStaleResume?: (info: { deadSessionId: string | null }) => void };
    sessionId?: string;
    contextResetNotice?: string;
  }) => Promise<{ queryReused: boolean }>,
  hasActiveQuery: () => boolean = () => false,
) {
  return {
    dispatch: vi.fn(dispatchImpl),
    hasActiveQuery,
    activeQueriesSize: () => 0,
    reapIdle: () => 0,
    closeConversation: () => {},
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

function baseDispatchArgs(
  sendToClient: ReturnType<typeof vi.fn>,
  overrides: Record<string, unknown> = {},
) {
  return {
    persona: "command_center" as const,
    userId: "u-stale",
    conversationId: "conv-stale",
    userMessage: "hi",
    currentRouting: { kind: "soleur_go_pending" as const },
    sendToClient: sendToClient as unknown as (
      userId: string,
      message: WSMessage,
    ) => boolean,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    onSessionIdPersisted: vi.fn(),
    ...overrides,
  };
}

describe("dispatchSoleurGo — onStaleResume recovery (#9538)", () => {
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

  it("clears session_id, emits context_reset, and re-dispatches cold — deferred past the dying activeQueries entry", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    // `entryActive` models the runner's `activeQueries` map: true while a
    // dispatch owns the entry, cleared by the simulated closeQuery that
    // runs after onStaleResume inside the first dispatch. A synchronous
    // re-dispatch (the ordering bug this fix exists to prevent) would
    // observe `true` and take the queryReused path.
    let entryActive = false;
    const reusedSeen: boolean[] = [];
    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      const reused = entryActive;
      reusedSeen.push(reused);
      entryActive = true;
      if (reusedSeen.length === 1) {
        dispatchArgs.events.onStaleResume?.({ deadSessionId: "sess-dead" });
        // Simulated closeQuery → activeQueries.delete.
        entryActive = false;
      }
      return { queryReused: reused };
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    // Stale id cleared: DB write + in-process cache update.
    const clears = clearStaleSessionIdCalls();
    expect(clears).toHaveLength(1);
    expect(clears[0]![2]).toEqual({ session_id: null });
    expect(args.onSessionIdPersisted).toHaveBeenCalledWith(null);

    // Honesty frame — exactly one context_reset, no session_ended.
    const resets = framesOfType(sendToClient, "context_reset");
    expect(resets).toHaveLength(1);
    expect(resets[0]![1]).toEqual({
      type: "context_reset",
      reason: "prefill-guard",
      conversationId: "conv-stale",
    });
    expect(framesOfType(sendToClient, "session_ended")).toHaveLength(0);

    // Deferred re-dispatch: a second dispatch ran COLD (sessionId
    // undefined so the signature cannot re-fire) carrying the generic
    // context-reset notice for the system prompt.
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(2);
    const retry = stubRunner.dispatch.mock.calls[1]![0] as {
      sessionId?: string;
      contextResetNotice?: string;
      userMessage?: string;
    };
    expect(retry.sessionId).toBeUndefined();
    expect(retry.contextResetNotice).toBe(CONTEXT_RESET_NOTICE_GENERIC);
    expect(retry.userMessage).toBe("hi");

    // AC4: the retry observed the map already cleared — fresh query
    // construction, never the dying entry's input queue.
    expect(reusedSeen).toEqual([false, false]);
  });

  it("is a no-op when the dispatch never attempted a resume (sessionId absent)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient); // no sessionId

    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      // Fire anyway — the runner-side signature gates on state.sessionId,
      // but the dispatcher belt-guards on its own arg too.
      dispatchArgs.events.onStaleResume?.({ deadSessionId: "sess-dead" });
      return { queryReused: false };
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
    expect(clearStaleSessionIdCalls()).toHaveLength(0);
    expect(args.onSessionIdPersisted).not.toHaveBeenCalledWith(null);
    expect(framesOfType(sendToClient, "context_reset")).toHaveLength(0);
    expect(framesOfType(sendToClient, "session_ended")).toHaveLength(0);
  });

  it("retry dispatch throw → generic error frame + failed revert + Sentry mirror", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    let calls = 0;
    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      calls++;
      if (calls === 1) {
        dispatchArgs.events.onStaleResume?.({ deadSessionId: "sess-dead" });
        return { queryReused: false };
      }
      throw new Error("retry factory blew up");
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    expect(stubRunner.dispatch).toHaveBeenCalledTimes(2);

    // Generic client-facing error (same copy as the dispatch-time catch).
    const errorFrames = framesOfType(sendToClient, "error");
    expect(errorFrames.length).toBeGreaterThan(0);
    expect(
      (errorFrames[0]![1] as { message?: string }).message,
    ).toContain("try again shortly");

    // Sentry mirror under the retry op.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "cc-dispatcher",
        op: "stale-resume-retry",
      }),
      "u-stale",
      expect.any(String),
    );

    // Row reverts to failed — onlyIfStatusIn guards the concurrent-turn
    // race (a live turn's `active` wins and is left untouched).
    const reverts = failedRevertCalls();
    expect(reverts).toHaveLength(1);
    expect(reverts[0]![3]).toMatchObject({
      onlyIfStatusIn: ["active"],
      expectMatch: false,
    });
  });
});
