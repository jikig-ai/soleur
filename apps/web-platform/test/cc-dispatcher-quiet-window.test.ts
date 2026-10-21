import { describe, it, expect, vi, beforeEach } from "vitest";

// #8211 T2 build 1 — quiet-window kill-switch at the Concierge dispatch boundary.
//
// With `new-sessions-paused` ON, a dispatch for a conversation that has NO live
// Query (a cold, i.e. NEW, agent session) is refused with the maintenance
// message BEFORE anything is written. A dispatch for a conversation whose Query
// is live (a warm turn on a running session) is never refused: a refusal must
// not drop or alter an existing session. The flag is driven through the REAL
// feature-flag module's env-fallback path. Harness shared with
// cc-dispatcher-repo-gate.test.ts.

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
  activeCcQueryCount,
} from "@/server/cc-dispatcher";
import { QUIET_WINDOW_MESSAGE } from "@/server/quiet-window";
import { __resetFeatureFlagsForTests } from "@/lib/feature-flags/server";


function stubRunner(opts: { warm: boolean }) {
  return {
    dispatch: vi.fn(async () => {}),
    hasActiveQuery: () => opts.warm,
    activeQueriesSize: () => (opts.warm ? 1 : 0),
    reapIdle: () => 0,
    closeConversation: vi.fn(),
    respondToToolUse: () => false,
    notifyAwaitingUser: () => {},
    // biome-ignore lint/suspicious/noExplicitAny: minimal stub
  } as any;
}

function args(sendToClient: ReturnType<typeof vi.fn>, userId = "u-qw"): Parameters<typeof dispatchSoleurGo>[0] {
  return {
    persona: "command_center" as const,
    userId,
    conversationId: "conv-1",
    userMessage: "hi",
    currentRouting: { kind: "soleur_go_pending" as const },
    sendToClient: sendToClient as unknown as Parameters<typeof dispatchSoleurGo>[0]["sendToClient"],
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  };
}

function errorFrames(sendToClient: ReturnType<typeof vi.fn>) {
  return sendToClient.mock.calls
    .map(([, msg]) => msg as { type?: string; message?: string; errorCode?: string })
    .filter((m) => m && m.type === "error");
}

describe("cc-dispatcher quiet-window kill-switch (#8211)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetDispatcherForTests();
    delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
    delete process.env.FLAG_NEW_SESSIONS_PAUSED;
    __resetFeatureFlagsForTests();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/ws-quiet-window");
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
  });

  function setPaused(on: boolean) {
    process.env.FLAG_NEW_SESSIONS_PAUSED = on ? "1" : "0";
    __resetFeatureFlagsForTests();
  }

  it("flag ON + cold conversation: refuses with the maintenance message, no errorCode, runner never reached", async () => {
    setPaused(true);
    const runner = stubRunner({ warm: false });
    __setCcRunnerForTests(runner);
    const sendToClient = vi.fn().mockReturnValue(true);

    await dispatchSoleurGo(args(sendToClient));

    const errs = errorFrames(sendToClient);
    expect(errs).toHaveLength(1);
    expect(errs[0].message).toBe(QUIET_WINDOW_MESSAGE);
    expect(errs[0].errorCode).toBeUndefined();
    expect(runner.dispatch).not.toHaveBeenCalled();
  });

  it("flag ON + cold: writes nothing (no message INSERT, no ownership/status write) and no Sentry mirror", async () => {
    setPaused(true);
    __setCcRunnerForTests(stubRunner({ warm: false }));

    await dispatchSoleurGo(args(vi.fn().mockReturnValue(true)));

    expect(mockMessagesInsert).not.toHaveBeenCalled();
    expect(mockUpdateConversationFor).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("flag ON + cold: info breadcrumb carries a hashed user id and never the raw id", async () => {
    setPaused(true);
    __setCcRunnerForTests(stubRunner({ warm: false }));

    await dispatchSoleurGo(args(vi.fn().mockReturnValue(true), "raw-user-id-xyz"));

    const crumbs = mockLogInfo.mock.calls.filter(
      ([, msg]) =>
        msg === "quiet-window: refused a new agent session (new-sessions-paused)",
    );
    expect(crumbs).toHaveLength(1);
    expect(crumbs[0][0]).toMatchObject({ surface: "cc-dispatcher" });
    expect(JSON.stringify(crumbs[0][0])).not.toContain("raw-user-id-xyz");
    expect(crumbs[0][0]).not.toHaveProperty("userId");
  });

  it("flag ON + WARM conversation (live Query): NOT refused, the turn dispatches to the running session", async () => {
    setPaused(true);
    const runner = stubRunner({ warm: true });
    __setCcRunnerForTests(runner);
    const sendToClient = vi.fn().mockReturnValue(true);

    await dispatchSoleurGo(args(sendToClient));

    expect(runner.dispatch).toHaveBeenCalledTimes(1);
    expect(
      errorFrames(sendToClient).filter((e) => e.message === QUIET_WINDOW_MESSAGE),
    ).toHaveLength(0);
    // An existing session is never closed by a refusal path.
    expect(runner.closeConversation).not.toHaveBeenCalled();
  });

  it("flag ABSENT + cold: sessions allowed (default)", async () => {
    const runner = stubRunner({ warm: false });
    __setCcRunnerForTests(runner);
    const sendToClient = vi.fn().mockReturnValue(true);

    await dispatchSoleurGo(args(sendToClient));

    expect(runner.dispatch).toHaveBeenCalledTimes(1);
    expect(
      errorFrames(sendToClient).filter((e) => e.message === QUIET_WINDOW_MESSAGE),
    ).toHaveLength(0);
  });

  it("flag explicitly OFF + cold: sessions allowed", async () => {
    setPaused(false);
    const runner = stubRunner({ warm: false });
    __setCcRunnerForTests(runner);

    await dispatchSoleurGo(args(vi.fn().mockReturnValue(true)));

    expect(runner.dispatch).toHaveBeenCalledTimes(1);
  });

  it("activeCcQueryCount is a bare integer: 0 with no runner, the runner's live-Query count otherwise", () => {
    expect(activeCcQueryCount()).toBe(0);
    __setCcRunnerForTests(stubRunner({ warm: true }));
    expect(activeCcQueryCount()).toBe(1);
    __setCcRunnerForTests(stubRunner({ warm: false }));
    expect(activeCcQueryCount()).toBe(0);
  });
});
