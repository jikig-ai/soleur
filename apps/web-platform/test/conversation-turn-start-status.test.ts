/**
 * RED tests — conversation `status` must flip to `active` when a user turn
 * starts on an existing conversation (the rail-live-status bug, PR #9270).
 *
 * Verified inventory: `conversations.status` is written `'active'` only at
 * row INSERT and by permission-callback gate resolution. A follow-up `chat`
 * message on an existing `completed`/`waiting_for_user` conversation flips
 * nothing — the row keeps its terminal value for the whole run, so the
 * conversations rail renders a stale badge until remount.
 *
 * Contract (plan 2026-09-30-fix-conversations-rail-live-status-plan.md):
 *   1. `dispatchSoleurGo` (cc/Concierge path) writes `{ status: "active" }`
 *      via `updateConversationFor` immediately before `runner.dispatch` —
 *      NOT in the earlier ownership write, so a setup throw (tenant mint,
 *      workspace_id read, message INSERT) can never leave a falsely-active
 *      row that the fresh session heartbeat hides from the stuck-active
 *      reaper.
 *   2. A `runner.dispatch` throw lands a guarded revert:
 *      `{ status: "failed" }` + `onlyIfStatusIn: ["active"]` +
 *      `expectMatch: false` — mirrors legacy
 *      `updateConversationStatusIfActive` (#3463); never stomps a row a
 *      concurrent writer already moved on.
 *   3. `sendUserMessage` (legacy path) writes `{ status: "active",
 *      last_active }` via `updateConversationFor` after its ownership probe
 *      and before the user-message INSERT/dispatch.
 *   4. `resume_session` / socket bind writes nothing (viewing is not a turn).
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Hoisted mocks
// ---------------------------------------------------------------------------

const {
  mockUpdateConversationFor,
  mockQuery,
  mockFrom,
  mockRpc,
  mockMessagesInsert,
  mockReportSilentFallback,
  mockMirrorP0Deduped,
  mockLogInfo,
  mockSendToClient,
} = vi.hoisted(() => ({
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockQuery: vi.fn(),
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockReportSilentFallback: vi.fn(),
  mockMirrorP0Deduped: vi.fn(),
  mockLogInfo: vi.fn(),
  mockSendToClient: vi.fn(() => true),
}));

// --- shared: the sanctioned conversations-write wrapper ---------------------
vi.mock("@/server/conversation-writer", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/conversation-writer")
  >("@/server/conversation-writer");
  return {
    ...actual,
    updateConversationFor: mockUpdateConversationFor,
  };
});

// --- shared: tenant client (serves BOTH agent-runner and cc-dispatcher) -----
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom, rpc: mockRpc })),
  mintFounderJwt: vi.fn(),
  getMyRevocationStatus: vi.fn(async () => null),
  RuntimeAuthError: class RuntimeAuthError extends Error {
    public readonly cause: string;
    constructor(cause: string, message: string) {
      super(message);
      this.cause = cause;
      this.name = "RuntimeAuthError";
    }
  },
}));

// --- shared: observability (cc-dispatcher mirror + agent-runner fallback) ----
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

vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: mockLogInfo,
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  captureException: vi.fn(),
}));

// --- cc-dispatcher's own dep surface (repo-gate harness shape) --------------
vi.mock("@/server/cost-writer", () => ({ persistTurnCost: vi.fn() }));
vi.mock("@/server/kb-document-resolver", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/kb-document-resolver")
  >("@/server/kb-document-resolver");
  return {
    ...actual,
    fetchUserWorkspacePath: vi.fn().mockResolvedValue("/tmp/ws-turn-status"),
  };
});
vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "messages") return { insert: mockMessagesInsert };
      if (table === "conversations") {
        return {
          select: () => ({
            eq: () => ({
              single: async () => ({ data: { workspace_id: "ws-test" }, error: null }),
            }),
          }),
        };
      }
      throw new Error(`unexpected service table: ${table}`);
    },
    storage: { from: () => ({ download: vi.fn() }) },
  }),
}));
vi.mock("@/server/cc-reprovision", () => ({
  reprovisionWorkspaceOnDispatch: vi.fn().mockResolvedValue("ok"),
}));

// --- agent-runner's dep surface (result-branch harness shape) ---------------
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(() => ({
    type: "sdk",
    name: "test",
    instance: { tools: [] },
  })),
}));
vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
}));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(() => Buffer.from("sk-test-key")),
  decryptKeyLegacy: vi.fn(() => Buffer.from("sk-test-key")),
  encryptKey: vi.fn(),
  zeroize: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [],
  extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false),
  isSafeTool: vi.fn(() => false),
}));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => vi.fn()),
}));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn(),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => ({
  ROUTABLE_DOMAIN_LEADERS: [
    { id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" },
  ],
  DOMAIN_LEADERS: [
    { id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" },
  ],
}));
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: vi.fn(),
  syncPush: vi.fn(),
}));
vi.mock("../server/github-app", () => ({ createPullRequest: vi.fn() }));
vi.mock("../server/vision-helpers", () => ({
  tryCreateVision: vi.fn(),
  buildVisionEnhancementPrompt: vi.fn(),
}));
vi.mock("../server/providers", () => ({
  PROVIDER_CONFIG: {},
  EXCLUDED_FROM_SERVICES_UI: [],
}));
vi.mock("../server/concurrency", () => ({
  SLOT_STALENESS_THRESHOLD_SECONDS: 240,
  SLOT_HEARTBEAT_INTERVAL_MS: 60_000,
  releaseSlot: vi.fn(),
  acquireSlot: vi.fn(),
  touchSlot: vi.fn(),
  emitConcurrencyCapHit: vi.fn(),
}));

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { sendUserMessage } from "../server/agent-runner";
import { createSupabaseMockImpl } from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function stubRunner(opts: { throw?: unknown } = {}) {
  return {
    dispatch: vi.fn(async () => {
      if (opts.throw) throw opts.throw;
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

function updateCalls() {
  return mockUpdateConversationFor.mock.calls.map(([userId, convId, patch, options]) => ({
    userId: userId as string,
    convId: convId as string,
    patch: patch as Record<string, unknown>,
    options: (options ?? {}) as Record<string, unknown>,
  }));
}

function callsWithStatus(status: string) {
  return updateCalls().filter((c) => c.patch.status === status);
}

function ccDispatchArgs(overrides: Record<string, unknown> = {}) {
  return {
    persona: "command_center" as const,
    userId: "u-turn-status",
    conversationId: "conv-existing",
    userMessage: "hi",
    currentRouting: { kind: "soleur_go_pending" as const },
    sendToClient: vi.fn().mockReturnValue(true),
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  __resetDispatcherForTests();
  mockUpdateConversationFor.mockResolvedValue({ ok: true });
  mockMessagesInsert.mockResolvedValue({ error: null });
  // sendUserMessage's tenant from-chain: conversations select (probe),
  // messages insert, messages select (history) — the shared helper shape.
  createSupabaseMockImpl(mockFrom, { mockMessagesInsert });
  // Detached startAgentSession sees an empty SDK stream — resolves quietly.
  mockQuery.mockReturnValue({
    async *[Symbol.asyncIterator]() {},
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
  });
});

// ---------------------------------------------------------------------------
// cc/soleur-go path (the reported Concierge lineage)
// ---------------------------------------------------------------------------

describe("dispatchSoleurGo — turn-start status='active' write", () => {
  it("writes { status: 'active' } via updateConversationFor before runner.dispatch", async () => {
    __setCcRunnerForTests(stubRunner());
    await dispatchSoleurGo(ccDispatchArgs());

    const active = callsWithStatus("active");
    expect(active.length).toBeGreaterThanOrEqual(1);
    expect(active[0].convId).toBe("conv-existing");
    expect(active[0].userId).toBe("u-turn-status");
  });

  it("the 'active' write lands AFTER setup — a messages-INSERT failure never produces an 'active' write", async () => {
    // The narrow-window contract: the status flip sits immediately before
    // runner.dispatch so early setup throws (tenant mint, workspace_id read,
    // message INSERT) leave the row at its previous honest value rather than
    // a falsely-'active' one that a fresh session heartbeat hides from the
    // stuck-active reaper.
    mockMessagesInsert.mockResolvedValue({ error: { message: "insert boom" } });
    __setCcRunnerForTests(stubRunner());

    await expect(dispatchSoleurGo(ccDispatchArgs())).rejects.toThrow();

    expect(callsWithStatus("active")).toHaveLength(0);
    // And no revert either — nothing was flipped.
    expect(callsWithStatus("failed")).toHaveLength(0);
  });

  it("a runner.dispatch throw lands the guarded { status: 'failed' } revert", async () => {
    __setCcRunnerForTests(stubRunner({ throw: new Error("router exploded") }));
    await dispatchSoleurGo(ccDispatchArgs());

    expect(callsWithStatus("active")).toHaveLength(1);
    const failed = callsWithStatus("failed");
    expect(failed).toHaveLength(1);
    expect(failed[0].options.onlyIfStatusIn).toEqual(["active"]);
    expect(failed[0].options.expectMatch).toBe(false);
    expect(failed[0].convId).toBe("conv-existing");
  });

  it("ownership/auth gate unchanged: the early write still carries last_active + expectMatch", async () => {
    __setCcRunnerForTests(stubRunner());
    await dispatchSoleurGo(ccDispatchArgs());

    const ownership = updateCalls().find(
      (c) => c.options.op === "verify-conversation-ownership",
    );
    expect(ownership).toBeDefined();
    expect(ownership!.patch.last_active).toBeDefined();
    expect(ownership!.options.expectMatch).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// legacy path (sendUserMessage / startAgentSession lineage)
// ---------------------------------------------------------------------------

describe("sendUserMessage — turn-start status='active' write", () => {
  it("writes { status: 'active', last_active } via updateConversationFor on the turn-start path", async () => {
    await sendUserMessage("u-turn-status", "conv-existing", "hello");

    const active = callsWithStatus("active");
    expect(active.length).toBeGreaterThanOrEqual(1);
    const write = active[0];
    expect(write.convId).toBe("conv-existing");
    expect(write.userId).toBe("u-turn-status");
    expect(write.patch.last_active).toBeDefined();
    expect(write.options.feature).toBe("agent-runner");
    expect(write.options.op).toBe("turn-start-active");
    expect(write.options.expectMatch).toBe(true);
  });

  it("a user-message INSERT failure produces no 'active' write (narrow-window parity with the cc path)", async () => {
    // The flip sits after the messages INSERT + attachments, immediately
    // before session dispatch — an early persistence failure leaves the row
    // at its previous honest value, not a falsely-'active' one.
    mockMessagesInsert.mockResolvedValue({
      error: { message: "insert boom" },
    });

    await expect(
      sendUserMessage("u-turn-status", "conv-existing", "hello"),
    ).rejects.toThrow("Failed to save message");

    expect(callsWithStatus("active")).toHaveLength(0);
  });
});
