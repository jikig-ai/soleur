import { describe, it, expect, vi, beforeEach } from "vitest";

// #11086 — dispatcher-level wiring of the friendly auth-failure recovery: the lease-refusal arm of the dispatch catch and the
// `onAgentAuthFailure` / `onTextTurnEnd` events the runner calls. The runner-level behavior has its own wire tests
// (agent-auth-friendly-error-wire*.test.ts); THIS file pins what only the dispatcher does with it. Harness copied from
// cc-dispatcher-repo-gate.test.ts (#5394).

const {
  mockReportSilentFallback,
  mockMirrorP0Deduped,
  mockLogInfo,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockNotifyTaskCompleted,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockMirrorP0Deduped: vi.fn(),
  mockLogInfo: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockNotifyTaskCompleted: vi.fn(),
}));

vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return observabilityFactory({
    mockReportSilentFallback,
    mockMirrorP0Deduped,
    withTtlDedupWrapper: true,
  });
});

vi.mock("@/server/conversation-writer", async () => {
  const { conversationWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return conversationWriterFactory({ mockUpdateConversationFor });
});

vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return costWriterFactory();
});

vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath });
});

vi.mock("@/lib/supabase/tenant", async () => {
  const { supabaseTenantFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseTenantFactory({
    mockMessagesInsert,
    mockConversationWorkspaceId: "ws-A",
  });
});

vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseServiceFactory({
    mockMessagesInsert,
    mockConversationWorkspaceId: "ws-A",
  });
});

vi.mock("@/server/cc-reprovision", () => ({
  reprovisionWorkspaceOnDispatch: vi.fn().mockResolvedValue("ok"),
}));

vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: mockLogInfo,
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

vi.mock("@/server/notifications", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/notifications")>();
  return { ...actual, notifyTaskCompleted: mockNotifyTaskCompleted, notifyOfflineUser: vi.fn() };
});

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
  __registerCcWorktreeLeaseForTests,
} from "@/server/cc-dispatcher";
import { ByokLeaseError } from "@/server/byok-lease";
import { authFailureCopy, authModeUnresolvedFrame } from "@/server/agent-auth-user-message";

function dispatchMirrorCalls() {
  return mockReportSilentFallback.mock.calls.filter(
    ([, ctx]) =>
      (ctx as { feature?: string; op?: string })?.feature === "cc-dispatcher" &&
      (ctx as { op?: string })?.op === "dispatch",
  );
}


type WsFrame = { type?: string; message?: string; errorCode?: string; credentialScheme?: string };

function stubRunner(dispatch: (args: { events: Record<string, (...a: unknown[]) => void> }) => Promise<void>) {
  return {
    dispatch: vi.fn(dispatch),
    hasActiveQuery: () => false,
    activeQueriesSize: () => 0,
    reapIdle: () => 0,
    closeConversation: () => {},
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

function frames(sendToClient: ReturnType<typeof vi.fn>): WsFrame[] {
  return sendToClient.mock.calls.map(([, msg]) => msg as WsFrame).filter((m) => m && typeof m === "object");
}

const BASE = {
  userId: "u-auth",
  conversationId: "conv-auth",
  userMessage: "hi",
  currentRouting: { kind: "soleur_go_pending" as const },
  persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
};

describe("cc-dispatcher — lease refusal for an unusable stored credential (#11086)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetDispatcherForTests();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/ws-auth");
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
  });

  it("sends the oauth recovery frame, does NOT clear a resumable session_id, and adds no dispatcher mirror", async () => {
    __setCcRunnerForTests(
      stubRunner(async () => {
        throw new ByokLeaseError("oauth_unusable", "refused");
      }),
    );
    const sendToClient = vi.fn().mockReturnValue(true);
    const onSessionIdPersisted = vi.fn();

    await dispatchSoleurGo({ ...BASE, persona: "command_center", sendToClient, sessionId: "sess-1", onSessionIdPersisted });

    const errs = frames(sendToClient).filter((f) => f.type === "error");
    expect(errs).toEqual([
      {
        type: "error",
        message: authFailureCopy("oauth_unusable", "oauth_token"),
        errorCode: "key_invalid",
        credentialScheme: "oauth_token",
      },
    ]);
    // The arm sits ABOVE the generic `else` that clears the session and mirrors.
    expect(onSessionIdPersisted).not.toHaveBeenCalledWith(null);
    expect(dispatchMirrorCalls()).toHaveLength(0);
    expect(
      mockLogInfo.mock.calls.filter(([, msg]) => msg === "lease refused a stored credential the CLI cannot use"),
    ).toHaveLength(1);
  });

  // #11599 — the Concierge path used to render an unresolvable authentication mode as "Dashboard router is unavailable" and
  // cleared the resumable session_id. It now sends the typed frame above the generic else.
  it.each(["auth_mode_unresolved", "auth_mode_unavailable"] as const)(
    "%s: sends the typed frame, keeps the resumable session_id, adds no dispatcher mirror, logs info",
    async (cause) => {
      __setCcRunnerForTests(
        stubRunner(async () => {
          throw new ByokLeaseError(cause, "refused", cause === "auth_mode_unresolved" ? "unbound" : "read_failed");
        }),
      );
      const sendToClient = vi.fn().mockReturnValue(true);
      const onSessionIdPersisted = vi.fn();

      await dispatchSoleurGo({ ...BASE, persona: "command_center", sendToClient, sessionId: "sess-1", onSessionIdPersisted });

      expect(frames(sendToClient).filter((f) => f.type === "error")).toEqual([authModeUnresolvedFrame(cause)]);
      expect(onSessionIdPersisted).not.toHaveBeenCalledWith(null);
      expect(dispatchMirrorCalls()).toHaveLength(0);
      expect(mockLogInfo.mock.calls.filter(([, msg]) => typeof msg === "string" && /lease refused/.test(msg))).toHaveLength(1);
    },
  );

  it("drops the worktree lease record kept by an auth-failed close for the new causes too", async () => {
    const release = vi.fn().mockResolvedValue(undefined);
    __registerCcWorktreeLeaseForTests(BASE.userId, BASE.conversationId, { leaseGeneration: 1, release, detach: vi.fn() });
    __setCcRunnerForTests(
      stubRunner(async () => {
        throw new ByokLeaseError("auth_mode_unresolved", "refused", "unbound");
      }),
    );
    await dispatchSoleurGo({ ...BASE, persona: "command_center", sendToClient: vi.fn().mockReturnValue(true) });
    await new Promise((r) => setTimeout(r, 0));
    expect(release).toHaveBeenCalledTimes(1);
  });

  it("drops a worktree lease record kept by an auth-failed close, so a refused re-lease does not leak it", async () => {
    const release = vi.fn().mockResolvedValue(undefined);
    __registerCcWorktreeLeaseForTests(BASE.userId, BASE.conversationId, { leaseGeneration: 1, release, detach: vi.fn() });
    __setCcRunnerForTests(
      stubRunner(async () => {
        throw new ByokLeaseError("oauth_unusable", "refused");
      }),
    );

    await dispatchSoleurGo({ ...BASE, persona: "command_center", sendToClient: vi.fn().mockReturnValue(true) });
    await new Promise((r) => setTimeout(r, 0));

    expect(release).toHaveBeenCalledTimes(1);
  });

  it("positive control: any other lease cause takes the generic path (mirror + session clear)", async () => {
    __setCcRunnerForTests(
      stubRunner(async () => {
        throw new ByokLeaseError("fetch_failed", "boom");
      }),
    );
    const sendToClient = vi.fn().mockReturnValue(true);
    const onSessionIdPersisted = vi.fn();

    await dispatchSoleurGo({ ...BASE, persona: "command_center", sendToClient, sessionId: "sess-1", onSessionIdPersisted });

    expect(dispatchMirrorCalls()).toHaveLength(1);
    expect(onSessionIdPersisted).toHaveBeenCalledWith(null);
    expect(frames(sendToClient).filter((f) => f.type === "error")[0]?.credentialScheme).toBeUndefined();
    // A real fetch_failed is never mistaken for a reported refusal: still the generic frame, not a typed auth-mode frame.
    expect(frames(sendToClient).filter((f) => f.type === "error")[0]?.errorCode ?? "").not.toMatch(/^auth_mode_/);
  });
});

describe("cc-dispatcher — runner events for a terminal sign-in failure (#11086)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetDispatcherForTests();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/ws-auth");
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
  });

  const FRAME = {
    type: "error",
    message: "x",
    errorCode: "key_invalid",
    credentialScheme: "api_key",
  };

  async function runTurn(persona: "command_center" | "support", authFailure: boolean) {
    __setCcRunnerForTests(
      stubRunner(async ({ events }) => {
        events.onText("friendly text");
        events.onResult({ totalCostUsd: 0, usage: { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } });
        events.onTextTurnEnd(authFailure ? { authFailure: true } : undefined);
        if (authFailure) events.onAgentAuthFailure(FRAME);
      }),
    );
    const sendToClient = vi.fn().mockReturnValue(true);
    await dispatchSoleurGo({ ...BASE, persona, sendToClient });
    return sendToClient;
  }

  it("forwards onAgentAuthFailure to the client (the runner wire test pins the stream_end ordering)", async () => {
    const sendToClient = await runTurn("command_center", true);
    const kinds = frames(sendToClient).map((f) => f.type);
    expect(kinds.indexOf("stream_end")).toBeGreaterThanOrEqual(0);
    expect(kinds.lastIndexOf("error")).toBeGreaterThan(kinds.indexOf("stream_end"));
    expect(frames(sendToClient).filter((f) => f.type === "error")).toEqual([FRAME]);
  });

  it("support persona keeps the friendly bubble only: no error frame", async () => {
    const sendToClient = await runTurn("support", true);
    expect(frames(sendToClient).some((f) => f.type === "error")).toBe(false);
  });

  it("a turn that ended in an auth failure is not announced as finished", async () => {
    await runTurn("command_center", true);
    expect(mockNotifyTaskCompleted).not.toHaveBeenCalled();
  });

  it("positive control: an ordinary completed turn IS announced", async () => {
    await runTurn("command_center", false);
    expect(mockNotifyTaskCompleted).toHaveBeenCalledTimes(1);
  });
});
