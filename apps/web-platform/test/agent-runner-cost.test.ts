import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Hoisted mocks — vitest hoists vi.mock() before const/let declarations
// ---------------------------------------------------------------------------

const { mockFrom, mockQuery, mockRpc, mockSendToClient } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockRpc: vi.fn(),
  mockSendToClient: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(() => ({ type: "sdk", name: "test", instance: { tools: [] } })),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
}));

// PR-B (#3244 §1.5.1): tenant-client factory; route through the same
// mockFrom/mockRpc chain so existing assertions still apply.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom, rpc: mockRpc })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {
    cause: string;
    constructor(cause: string, msg: string) {
      super(msg);
      this.name = "RuntimeAuthError";
      this.cause = cause;
    }
  },
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));
vi.mock("../server/byok", () => ({
  // PR-B (#3244 §1.4.2): decryptKey* now return Buffer (zeroize-on-finally).
  decryptKey: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  decryptKeyLegacy: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  zeroize: vi.fn(),
  encryptKey: vi.fn(),
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
  ROUTABLE_DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
  DOMAIN_LEADERS: [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }],
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

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";
import {
  createSupabaseMockImpl,
  createQueryMock,
} from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupSupabaseMock() {
  createSupabaseMockImpl(mockFrom);
}

function setupQueryWithCost(costUsd: number, inputTokens: number, outputTokens: number) {
  createQueryMock(mockQuery, {
    type: "result",
    session_id: "sess-cost-1",
    total_cost_usd: costUsd,
    usage: { input_tokens: inputTokens, output_tokens: outputTokens },
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("agent-runner cost capture", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setupSupabaseMock();
  });

  test("calls increment_conversation_cost RPC v2 with 5 deltas (cache zero when missing)", async () => {
    setupQueryWithCost(0.0042, 1200, 300);
    mockRpc.mockResolvedValue({ error: null });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    expect(mockRpc).toHaveBeenCalledWith("increment_conversation_cost", {
      conv_id: "conv-1",
      cost_delta: 0.0042,
      input_delta: 1200,
      output_delta: 300,
      cache_read_delta: 0,
      cache_creation_delta: 0,
    });
  });

  test("appends a write_byok_audit row with the same turn's totals", async () => {
    setupQueryWithCost(0.0042, 1200, 300);
    mockRpc.mockResolvedValue({ error: null });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    const auditCall = mockRpc.mock.calls.find(
      ([fn]) => fn === "write_byok_audit",
    );
    expect(auditCall).toBeDefined();
    const args = auditCall![1];
    expect(args.p_founder_id).toBe("11111111-1111-4111-8111-111111111111");
    expect(args.p_agent_role).toBe("cpo");
    // 1200 input + 300 output + 0 cache = 1500 combined
    expect(args.p_token_count).toBe(1500);
    // Math.round(0.0042 * 100) = 0 (sub-cent precision lost intentionally —
    // forensic surface only; cent-precision UI stays on conversations.total_cost_usd)
    expect(args.p_unit_cost_cents).toBe(0);
  });

  test("sends usage_update WebSocket message with cost delta + cache fields", async () => {
    setupQueryWithCost(0.0123, 500, 150);
    mockRpc.mockResolvedValue({ error: null });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    // Phase 3 (#4229) — usage_update widened with workspaceId.
    expect(mockSendToClient).toHaveBeenCalledWith("11111111-1111-4111-8111-111111111111", {
      type: "usage_update",
      conversationId: "conv-1",
      workspaceId: "11111111-1111-4111-8111-111111111111",
      totalCostUsd: 0.0123,
      inputTokens: 500,
      outputTokens: 150,
      cacheReadInputTokens: 0,
      cacheCreationInputTokens: 0,
    });
  });

  test("does not block conversation when RPC fails", async () => {
    setupQueryWithCost(0.005, 100, 50);
    mockRpc.mockResolvedValue({ error: { message: "DB connection failed" } });

    // Should not throw — cost tracking is non-blocking
    await expect(
      startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo"),
    ).resolves.not.toThrow();

    // session_ended should still be sent (conversation completes)
    expect(mockSendToClient).toHaveBeenCalledWith("11111111-1111-4111-8111-111111111111", {
      type: "session_ended",
      reason: "turn_complete",
    });
  });

  test("handles missing cost data gracefully (zero defaults)", async () => {
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        yield { type: "result", session_id: "sess-no-cost" };
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);
    mockRpc.mockResolvedValue({ error: null });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    expect(mockRpc).toHaveBeenCalledWith("increment_conversation_cost", {
      conv_id: "conv-1",
      cost_delta: 0,
      input_delta: 0,
      output_delta: 0,
      cache_read_delta: 0,
      cache_creation_delta: 0,
    });
  });

  test("persists cache token deltas when SDK emits them", async () => {
    createQueryMock(mockQuery, {
      type: "result",
      session_id: "sess-cache-1",
      total_cost_usd: 0.012,
      usage: {
        input_tokens: 521,
        output_tokens: 88,
        cache_read_input_tokens: 14_000,
        cache_creation_input_tokens: 800,
      },
    } as never);
    mockRpc.mockResolvedValue({ error: null });

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    expect(mockRpc).toHaveBeenCalledWith("increment_conversation_cost", {
      conv_id: "conv-1",
      cost_delta: 0.012,
      input_delta: 521,
      output_delta: 88,
      cache_read_delta: 14_000,
      cache_creation_delta: 800,
    });
    // Phase 3 (#4229) — usage_update widened with workspaceId for
    // workspace-grain attribution at the client. Under N2 invariant
    // workspaceId === userId for solo callers.
    expect(mockSendToClient).toHaveBeenCalledWith("11111111-1111-4111-8111-111111111111", {
      type: "usage_update",
      conversationId: "conv-1",
      workspaceId: "11111111-1111-4111-8111-111111111111",
      totalCostUsd: 0.012,
      inputTokens: 521,
      outputTokens: 88,
      cacheReadInputTokens: 14_000,
      cacheCreationInputTokens: 800,
    });
    // Audit row's `token_count` MUST sum all 4 axes (uncached input +
    // output + cache_read + cache_creation). Without this assertion a
    // refactor dropping cache axes from the sum would still pass the
    // 1500-token "no cache" fixture above (vacuous pass).
    const auditCall = mockRpc.mock.calls.find(
      ([fn]) => fn === "write_byok_audit",
    );
    expect(auditCall).toBeDefined();
    expect(auditCall![1].p_token_count).toBe(521 + 88 + 14_000 + 800);
  });
});
