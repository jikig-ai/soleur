/**
 * #11599 — Guard 2 row 2 (legacy `handleSessionError`): a lease refusal for an unresolvable authentication mode that
 * reaches `sendUserMessage`'s error handler sends the typed frame and adds NO call-site error-tracker event and NO
 * ERROR log; a non-lease error in the same harness IS captured (proves the spy is live); a real `fetch_failed` is still
 * mirrored and still sent as `key_invalid`. The harness is the one of conversation-turn-start-status.test.ts.
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
  mockLogError,
  mockSendToClient,
  mockResolveKeyOwnerThenLease,
  mockCaptureException,
} = vi.hoisted(() => ({
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockQuery: vi.fn(),
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockReportSilentFallback: vi.fn(),
  mockMirrorP0Deduped: vi.fn(),
  mockLogInfo: vi.fn(),
  mockLogError: vi.fn(),
  mockSendToClient: vi.fn(() => true),
  mockResolveKeyOwnerThenLease: vi.fn(),
  mockCaptureException: vi.fn(),
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
  default: { info: mockLogInfo, error: mockLogError, warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: mockLogInfo,
    warn: vi.fn(),
    error: mockLogError,
    debug: vi.fn(),
  }),
}));

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  captureException: mockCaptureException,
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
vi.mock("../server/agent-env", async () => {
  // feat-open-web-egress (#9534): keep the REAL exports —
  // agent-runner-sandbox-config derives the web-egress deny census
  // from ALLOWED_SERVICE_ENV_VARS at module init; a bare stub drops
  // it and crashes every transitive importer.
  const actual =
    await vi.importActual<typeof import("../server/agent-env")>("../server/agent-env");
  return { ...actual, buildAgentEnv: vi.fn(() => ({})) };
});
// feat-open-web-egress (#9534): entitlement read + forwarder lifecycle —
// default off; the factory must resolve the module (mocked) on every
// dispatch even when the grant is false.
vi.mock("@/server/resolve-web-egress", () => ({
  resolveWebEgress: vi.fn(async () => false),
  resolveWebEgressStrict: vi.fn(async () => false),
}));
vi.mock("@/server/egress-forwarder", () => ({
  spawnEgressForwarder: vi.fn(),
  teardownEgressForwarder: vi.fn(),
  reapOrphanEgressForwarders: vi.fn(),
  hasEgressForwarder: vi.fn(() => false),
  egressForwarderWorkspaceId: vi.fn(() => undefined),
}));

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
vi.mock("../server/byok-resolver", () => ({
  resolveKeyOwnerThenLease: (...a: unknown[]) => mockResolveKeyOwnerThenLease(...a),
}));
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

import { sendUserMessage } from "../server/agent-runner";
import { ByokLeaseError } from "../server/byok-lease";
import { authModeUnresolvedFrame } from "../server/agent-auth-user-message";
import { createSupabaseMockImpl } from "./helpers/agent-runner-mocks";

const USER = "55555555-5555-4555-8555-555555555555";

beforeEach(() => {
  vi.clearAllMocks();
  mockUpdateConversationFor.mockResolvedValue({ ok: true });
  mockMessagesInsert.mockResolvedValue({ error: null });
  createSupabaseMockImpl(mockFrom, { mockMessagesInsert });
  // No explicit leader: the conversation takes the routing branch, whose BYOK lease is the throw site.
  const base = mockFrom.getMockImplementation()!;
  mockFrom.mockImplementation((table: string) => {
    const t = base(table) as Record<string, unknown>;
    if (table !== "conversations") return t;
    const chain: Record<string, unknown> = {
      eq: vi.fn(() => chain),
      single: vi.fn(() => ({ data: { domain_leader: null, session_id: null, workspace_id: "ws-test" }, error: null })),
    };
    return { ...t, select: vi.fn(() => chain) };
  });
});

const errorFrames = () =>
  (mockSendToClient.mock.calls as unknown[][]).map((c) => c[1] as { type: string; errorCode?: string }).filter((f) => f.type === "error");

async function turnRejectedBy(err: unknown) {
  mockResolveKeyOwnerThenLease.mockRejectedValue(err);
  await sendUserMessage(USER, "conv-lease-refusal", "hello");
  await vi.waitFor(() => expect(errorFrames()).toHaveLength(1));
}

describe("sendUserMessage handleSessionError — lease refusals (#11599)", () => {
  it.each(["auth_mode_unresolved", "auth_mode_unavailable"] as const)(
    "%s: the typed frame, zero call-site captures, INFO not ERROR",
    async (cause) => {
      await turnRejectedBy(new ByokLeaseError(cause, "Authentication unavailable; retry shortly", cause === "auth_mode_unresolved" ? "unbound" : "read_failed"));
      expect(errorFrames()).toEqual([authModeUnresolvedFrame(cause)]);
      expect(mockCaptureException).not.toHaveBeenCalled();
      expect(mockLogError).not.toHaveBeenCalled();
    },
  );

  it("positive control (the spy is live): a non-lease error IS captured and logged at ERROR", async () => {
    await turnRejectedBy(new Error("boom"));
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(mockLogError).toHaveBeenCalled();
  });

  it("a real fetch_failed is still mirrored and still sent as key_invalid", async () => {
    await turnRejectedBy(new ByokLeaseError("fetch_failed", "boom"));
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(errorFrames()[0].errorCode).toBe("key_invalid");
  });
});
