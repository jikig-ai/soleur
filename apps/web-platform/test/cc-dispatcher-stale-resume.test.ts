/**
 * #9538 — dispatcher-side stale-resume recovery. When the runner fires
 * `DispatchEvents.onStaleResume` (mid-stream `No conversation found with
 * session ID` on a dispatch that attempted `resume:`), the dispatcher
 * clears `conversations.session_id`, emits the `context_reset` honesty
 * frame, and re-dispatches the same turn cold. The runner emits
 * `onStaleResume` AFTER `closeQuery`'s `activeQueries.delete`, so the
 * retry cannot take the `queryReused` path on the dying entry (which
 * would silently drop the user's message); the dispatch itself is
 * deferred past the `clearCcSessionId` write via `.then`.
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
  infoSilentFallback: vi.fn(),
  hashUserId: (u: string) => `hash-${u}`,
  mirrorP0Deduped: vi.fn(),
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
  __registerCcWorktreeLeaseForTests,
  handleCcCloseQuery,
} from "@/server/cc-dispatcher";
import {
  CONTEXT_RESET_NOTICE_GENERIC,
  CONTEXT_RESET_NOTICE_TOOL_USE_ORPHAN,
} from "@/server/agent-prefill-guard";
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
    events: {
      onStaleResume?: (info: {
        deadSessionId: string;
        lastBlockKind: "text" | "tool_use" | null;
      }) => void;
    };
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

  it("clears session_id, emits context_reset, and re-dispatches cold — after the dying activeQueries entry is deleted", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    // `entryActive` models the runner's `activeQueries` map: true while a
    // dispatch owns the entry. The real runner emits `onStaleResume`
    // AFTER `closeQuery`'s `activeQueries.delete`, so this stub clears the
    // entry BEFORE firing the event — a re-dispatch that observed `true`
    // would prove the listener ran on the dying entry.
    let entryActive = false;
    const reusedSeen: boolean[] = [];
    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      const reused = entryActive;
      reusedSeen.push(reused);
      entryActive = true;
      if (reusedSeen.length === 1) {
        // Simulated closeQuery → activeQueries.delete PRECEDES emit.
        entryActive = false;
        dispatchArgs.events.onStaleResume?.({
          deadSessionId: "sess-dead",
          lastBlockKind: "text",
        });
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
      events?: { onStaleResume?: unknown };
    };
    expect(retry.sessionId).toBeUndefined();
    expect(retry.contextResetNotice).toBe(CONTEXT_RESET_NOTICE_GENERIC);
    expect(retry.userMessage).toBe("hi");
    // The retry's events strip onStaleResume — a repeat signature
    // degrades to `internal_error` instead of re-dispatching: this is
    // what bounds the recovery to one re-dispatch per user message.
    expect(retry.events?.onStaleResume).toBeUndefined();

    // AC4: the retry observed the map already cleared — fresh query
    // construction, never the dying entry's input queue.
    expect(reusedSeen).toEqual([false, false]);
  });

  it("recovers keyed on the payload even when the dispatch arg's sessionId is absent (arg-falsy/state-truthy divergence)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient); // no sessionId arg

    // `state.sessionId` can rebind mid-stream on an SDK session-id change,
    // so the runner can fire with a truthy dead id even when the dispatch
    // arg carried none. Gating on the arg would silently drop recovery;
    // the payload is authoritative.
    let calls = 0;
    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      calls++;
      // First call only: the retry runs with sessionId: undefined, so in
      // production the runner's own gate cannot re-fire.
      if (calls === 1) {
        dispatchArgs.events.onStaleResume?.({
          deadSessionId: "sess-dead",
          lastBlockKind: "text",
        });
      }
      return { queryReused: false };
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    expect(stubRunner.dispatch).toHaveBeenCalledTimes(2);
    expect(clearStaleSessionIdCalls()).toHaveLength(1);
    expect(args.onSessionIdPersisted).toHaveBeenCalledWith(null);
    expect(framesOfType(sendToClient, "context_reset")).toHaveLength(1);
    expect(framesOfType(sendToClient, "session_ended")).toHaveLength(0);
  });

  it("retry dispatch throw → generic error frame + failed revert + Sentry mirror", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    let calls = 0;
    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      calls++;
      if (calls === 1) {
        dispatchArgs.events.onStaleResume?.({
          deadSessionId: "sess-dead",
          lastBlockKind: "text",
        });
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
  it("skips the retry when a concurrent turn already claimed the conversation (activeQueries guard)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    const stubRunner = makeStubRunner(
      async (dispatchArgs) => {
        dispatchArgs.events.onStaleResume?.({
          deadSessionId: "sess-dead",
          lastBlockKind: "text",
        });
        return { queryReused: false };
      },
      // A newer user send registered the slot in the window between the
      // dying close and the deferred retry — re-dispatching would clobber
      // it and orphan the newer query.
      () => true,
    );
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    // The clear + honesty frame still land; only the re-dispatch is held.
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
    expect(clearStaleSessionIdCalls()).toHaveLength(1);
    expect(framesOfType(sendToClient, "context_reset")).toHaveLength(1);
  });

  it("selects the tool_use_orphan reason + notice when the turn died mid-tool_use", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      dispatchArgs.events.onStaleResume?.({
        deadSessionId: "sess-dead",
        lastBlockKind: "tool_use",
      });
      return { queryReused: false };
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    const resets = framesOfType(sendToClient, "context_reset");
    expect(resets).toHaveLength(1);
    expect((resets[0]![1] as { reason?: string }).reason).toBe(
      "tool_use_orphan",
    );
    const retry = stubRunner.dispatch.mock.calls[1]![0] as {
      contextResetNotice?: string;
    };
    expect(retry.contextResetNotice).toBe(
      CONTEXT_RESET_NOTICE_TOOL_USE_ORPHAN,
    );
  });

  it("retry KeyInvalidError keeps the actionable key_invalid contract (typed taxonomy)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    const { KeyInvalidError } = await import("@/lib/types");
    let calls = 0;
    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      calls++;
      if (calls === 1) {
        dispatchArgs.events.onStaleResume?.({
          deadSessionId: "sess-dead",
          lastBlockKind: "text",
        });
        return { queryReused: false };
      }
      throw new KeyInvalidError();
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    // The retry's sole error boundary must discriminate like the primary
    // catch: key_invalid errorCode + actionable copy, NOT the generic
    // "try again shortly" dead-end.
    const errorFrames = framesOfType(sendToClient, "error");
    expect(errorFrames.length).toBeGreaterThan(0);
    const frame = errorFrames[0]![1] as {
      errorCode?: string;
      message?: string;
    };
    expect(frame.errorCode).toBe("key_invalid");
    expect(frame.message).not.toContain("try again shortly");
  });
  it("defers the retry until the session_id clear resolves (write-ordering pin)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    // Hold the clear's UPDATE — a retry that fires before it commits lets
    // the retried turn's persist lose the ordering race to the pending
    // `session_id = null` write.
    let resolveClear!: (v: { ok: boolean }) => void;
    const clearGate = new Promise<{ ok: boolean }>((r) => {
      resolveClear = r;
    });
    mockUpdateConversationFor.mockImplementation(
      (_u: string, _c: string, patch: Record<string, unknown>) => {
        if ("session_id" in patch) return clearGate as never;
        return Promise.resolve({ ok: true }) as never;
      },
    );

    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      dispatchArgs.events.onStaleResume?.({
        deadSessionId: "sess-dead",
        lastBlockKind: "text",
      });
      return { queryReused: false };
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    // Clear in flight — retry must not have dispatched.
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(1);
    resolveClear({ ok: true });
    await flushMicrotasks(20);
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(2);
  });

  it("still retries when the session_id clear rejects (persist heals the column)", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const args = baseDispatchArgs(sendToClient, { sessionId: "sess-dead" });

    mockUpdateConversationFor.mockImplementation(
      (_u: string, _c: string, patch: Record<string, unknown>) => {
        if ("session_id" in patch) {
          return Promise.reject(new Error("clear blew up")) as never;
        }
        return Promise.resolve({ ok: true }) as never;
      },
    );

    const stubRunner = makeStubRunner(async (dispatchArgs) => {
      dispatchArgs.events.onStaleResume?.({
        deadSessionId: "sess-dead",
        lastBlockKind: "text",
      });
      return { queryReused: false };
    });
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo(args);
    await flushMicrotasks(20);

    // `.then(retry, retry)` runs the retry on the rejected arm too — a
    // failed clear must not strand the user message (the retry's own
    // persist heals the column on its first result).
    expect(stubRunner.dispatch).toHaveBeenCalledTimes(2);
  });

  it("handleCcCloseQuery detaches (not releases) the worktree lease on stale-resume (tombstone fix)", async () => {
    const release = vi.fn().mockResolvedValue(undefined);
    const detach = vi.fn();
    __registerCcWorktreeLeaseForTests("u-stale", "conv-stale", {
      leaseGeneration: 1,
      release,
      detach,
    });

    handleCcCloseQuery({
      conversationId: "conv-stale",
      userId: "u-stale",
      reason: "stale-resume",
    });
    await flushMicrotasks(20);

    // Migration-116 tombstone window: the retry's same-host keep-gen
    // acquire would land AFTER a deferred release — detach keeps the row
    // live through the re-acquire while stopping the dead handle's
    // heartbeat (a zombie beat resurrects the tombstone forever).
    expect(release).not.toHaveBeenCalled();
    expect(detach).toHaveBeenCalledTimes(1);
  });

  it("control: a non-stale close still releases the worktree lease", async () => {
    const release = vi.fn().mockResolvedValue(undefined);
    __registerCcWorktreeLeaseForTests("u-ctl", "conv-ctl", {
      leaseGeneration: 1,
      release,
      detach: vi.fn(),
    });

    handleCcCloseQuery({ conversationId: "conv-ctl", userId: "u-ctl" });
    await flushMicrotasks(20);

    expect(release).toHaveBeenCalledTimes(1);
  });
});
