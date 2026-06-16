import { describe, it, expect, vi, beforeEach } from "vitest";

// #5394 — Concierge dispatch readiness gate, dispatch-catch behavior.
//
// The factory-throw seam (a `cloning`/`error` repo throws RepoNotReadyError
// BEFORE ensureWorkspaceRepoCloned / query()) is proven in
// cc-dispatcher-real-factory.test.ts. THIS file pins what the dispatch catch
// does with that thrown error: route an honest client message, preserve a
// resumable session (the branch sits ABOVE the generic `session_id`-clearing
// `else`), and SKIP the Sentry mirror (an expected transient state, not an
// incident). The runner is stubbed via `__setCcRunnerForTests` so the error is
// injected at the dispatch boundary — same seam cc-dispatcher.test.ts T19 uses
// for the KeyInvalidError mapping.

const {
  mockReportSilentFallback,
  mockMirrorP0Deduped,
  mockLogInfo,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockMirrorP0Deduped: vi.fn(),
  mockLogInfo: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
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

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { RepoNotReadyError } from "@/server/repo-readiness";

type WsError = { type?: string; message?: string; errorCode?: string };

function stubRunnerThrowing(err: unknown) {
  return {
    dispatch: vi.fn(async () => {
      throw err;
    }),
    hasActiveQuery: () => false,
    activeQueriesSize: () => 0,
    reapIdle: () => 0,
    closeConversation: () => {},
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

function errorFrames(sendToClient: ReturnType<typeof vi.fn>): WsError[] {
  return sendToClient.mock.calls
    .map(([, msg]) => msg as WsError)
    .filter((m) => m && typeof m === "object" && m.type === "error");
}

function dispatchMirrorCalls() {
  return mockReportSilentFallback.mock.calls.filter(
    ([, ctx]) =>
      (ctx as { feature?: string; op?: string })?.feature === "cc-dispatcher" &&
      (ctx as { op?: string })?.op === "dispatch",
  );
}

describe("cc-dispatcher repo-readiness gate — dispatch catch (#5394)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetDispatcherForTests();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/ws-repo-gate");
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
  });

  it("cloning → client error with the cloning message and NO errorCode", async () => {
    __setCcRunnerForTests(
      stubRunnerThrowing(
        new RepoNotReadyError(
          "cloning",
          "Your repository is still being set up — it'll be ready in a moment.",
        ),
      ),
    );
    const sendToClient = vi.fn().mockReturnValue(true);

    await dispatchSoleurGo({
      userId: "u-cloning",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    const errs = errorFrames(sendToClient);
    expect(errs).toHaveLength(1);
    expect(errs[0].message).toContain("still being set up");
    expect(errs[0].errorCode).toBeUndefined();
  });

  it("error → client error carries errorCode=repo_setup_failed + reconnect copy", async () => {
    __setCcRunnerForTests(
      stubRunnerThrowing(
        new RepoNotReadyError(
          "error",
          "Repository setup failed: boom. Reconnect in Settings → Repository.",
          "repo_setup_failed",
        ),
      ),
    );
    const sendToClient = vi.fn().mockReturnValue(true);

    await dispatchSoleurGo({
      userId: "u-error",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    const errs = errorFrames(sendToClient);
    expect(errs).toHaveLength(1);
    expect(errs[0].errorCode).toBe("repo_setup_failed");
    expect(errs[0].message).toContain("Reconnect in Settings → Repository");
  });

  it("RepoNotReadyError → ZERO Sentry mirror calls (expected transient state, not an incident)", async () => {
    __setCcRunnerForTests(
      stubRunnerThrowing(new RepoNotReadyError("cloning", "still setting up")),
    );

    await dispatchSoleurGo({
      userId: "u-no-mirror",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient: vi.fn().mockReturnValue(true),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    expect(dispatchMirrorCalls()).toHaveLength(0);
    // A structured breadcrumb keeps the rate observable WITHOUT Sentry noise.
    const breadcrumbs = mockLogInfo.mock.calls.filter(
      ([, msg]) => msg === "repo-readiness gate: blocked dispatch (repo not ready)",
    );
    expect(breadcrumbs).toHaveLength(1);
    // Breadcrumb payload is observable + PII-free (hashed user id, no raw id).
    expect(breadcrumbs[0][0]).toMatchObject({ code: "cloning" });
    expect(breadcrumbs[0][0]).not.toHaveProperty("userId");
  });

  it("positive control: a generic runner error DOES mirror to Sentry (proves the skip is RepoNotReadyError-specific)", async () => {
    __setCcRunnerForTests(stubRunnerThrowing(new Error("router exploded")));

    await dispatchSoleurGo({
      userId: "u-generic",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient: vi.fn().mockReturnValue(true),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    expect(dispatchMirrorCalls()).toHaveLength(1);
  });

  it("session survival: RepoNotReadyError does NOT clear a resumable session_id", async () => {
    __setCcRunnerForTests(
      stubRunnerThrowing(new RepoNotReadyError("cloning", "still setting up")),
    );
    const onSessionIdPersisted = vi.fn();

    await dispatchSoleurGo({
      userId: "u-survive",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient: vi.fn().mockReturnValue(true),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      sessionId: "sess-123",
      onSessionIdPersisted,
    });

    // The branch sits ABOVE the generic `else` that calls
    // onSessionIdPersisted(null) — a transient cloning block must not nuke a
    // resumable session.
    expect(onSessionIdPersisted).not.toHaveBeenCalledWith(null);
  });

  it("negative control: a generic error DOES clear the session_id (proves survival is RepoNotReadyError-specific)", async () => {
    // A plain Error falls through to the generic `else` which clears session_id.
    __setCcRunnerForTests(stubRunnerThrowing(new Error("router exploded")));
    const onSessionIdPersisted = vi.fn();

    await dispatchSoleurGo({
      userId: "u-clears",
      conversationId: "conv-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient: vi.fn().mockReturnValue(true),
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
      sessionId: "sess-123",
      onSessionIdPersisted,
    });

    expect(onSessionIdPersisted).toHaveBeenCalledWith(null);
  });
});
