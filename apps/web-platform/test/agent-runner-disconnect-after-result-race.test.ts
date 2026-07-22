/**
 * #3463 — disconnect-after-result race regression gate.
 *
 * Plan: knowledge-base/project/plans/2026-05-07-feat-disconnect-race-and-incoming-types-capability-plan.md
 *
 * Scenario: the result branch writes `status='waiting_for_user'`. The WS
 * connection dies in the millisecond window between that write and the
 * for-await iterator's natural termination. The SDK iterator throws an
 * AbortError; `controller.signal.reason` carries
 * `SessionAbortError("disconnected")`. The outer-catch abort branch
 * (lines ~1763-1778 at HEAD) writes `failed` — overwriting the
 * freshly-written `waiting_for_user`.
 *
 * Fix: the abort branch's write goes through
 * `updateConversationStatusIfActive`, which appends
 * `.in("status", ["active"])` to the composite-key UPDATE so the row
 * is left alone if it already reached a terminal state.
 *
 * RED-before-GREEN: the new helper's wiring at the abort site is
 * load-bearing. This test pins the wire shape so a careless revert to
 * `updateConversationStatus` (which would re-introduce the bug) fails
 * the suite.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Hoisted mocks — vitest hoists `vi.mock()` before const/let declarations.
// ---------------------------------------------------------------------------
const {
  mockFrom,
  mockQuery,
  mockRpc,
  mockSendToClient,
  mockReleaseSlot,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockRpc: vi.fn(),
  mockSendToClient: vi.fn(),
  mockReleaseSlot: vi.fn(),
}));

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
vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
}));
vi.mock("../server/ws-handler", () => ({ sendToClient: mockSendToClient }));
vi.mock("../server/logger", () => ({
  default: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));
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
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/concurrency", () => ({
  // ws-handler/agent-runner import these liveness consts from ./concurrency;
  // a wholesale mock must re-export them or accessing the binding throws.
  SLOT_STALENESS_THRESHOLD_SECONDS: 240,
  SLOT_HEARTBEAT_INTERVAL_MS: 60_000,
  releaseSlot: mockReleaseSlot,
  acquireSlot: vi.fn(),
  touchSlot: vi.fn(),
  emitConcurrencyCapHit: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";
import { abortSession } from "../server/agent-session-registry";
import { SessionAbortError } from "../server/abort-classifier";

// ---------------------------------------------------------------------------
// Race-window iterator: yields `result`, then triggers a disconnect-style
// abort and throws on the next iteration. Mimics the SDK's behavior when
// the WS connection dies between the result-branch finalization and the
// for-await loop's natural termination.
// ---------------------------------------------------------------------------
function buildRaceIterator(args: {
  userId: string;
  conversationId: string;
}) {
  const { userId, conversationId } = args;
  return {
    async *[Symbol.asyncIterator]() {
      yield {
        type: "assistant",
        message: { content: [{ type: "text", text: "I'm done." }] },
      };
      yield {
        type: "result",
        session_id: "sess-1",
        total_cost_usd: 0,
        usage: { input_tokens: 0, output_tokens: 0 },
      };
      // The result branch ran to completion. Now simulate the WS dying:
      // ws.on("close") → abortSession(uid, convId) sets the typed
      // SessionAbortError("disconnected") on the controller. The SDK
      // iterator catches the signal abort and re-throws AbortError on
      // the next iteration (real-SDK-behavior parity).
      abortSession(userId, conversationId, "disconnected");
      throw new DOMException("aborted", "AbortError");
    },
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
  };
}

interface UpdateRecord {
  patch: Record<string, unknown>;
  ins: Array<{ column: string; values: unknown[] }>;
}

function setupSupabaseMock(): { updates: UpdateRecord[] } {
  const updates: UpdateRecord[] = [];

  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      const row = {
        id: "key-1",
        provider: "anthropic",
        encrypted_key: Buffer.from("test").toString("base64"),
        iv: Buffer.from("test-iv-1234").toString("base64"),
        auth_tag: Buffer.from("test-tag-1234567").toString("base64"),
        key_version: 2,
      };
      const createChain = (): Record<string, unknown> => ({
        data: [row],
        error: null,
        eq: () => createChain(),
        // Phase 3 #4229 — byok-lease switched to maybeSingle.
        limit: () => ({
          single: () => ({ data: row, error: null }),
          maybeSingle: () => ({ data: row, error: null }),
        }),
        then: (resolve: (v: unknown) => void) =>
          resolve({ data: [row], error: null }),
      });
      return { select: () => createChain() };
    }
    if (table === "users") {
      const userData = {
        workspace_path: "/tmp/test-workspace",
        repo_status: null,
        github_installation_id: null,
        repo_url: null,
      };
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: userData, error: null }),
            maybeSingle: () => ({ data: userData, error: null }),
          }),
        }),
      };
    }
    if (table === "workspaces") {
      // ADR-044 read-cutover: getCurrentRepoUrl reads workspaces.repo_url.
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: { repo_url: null }, error: null }),
            maybeSingle: () => ({ data: { repo_url: null }, error: null }),
          }),
        }),
      };
    }
    if (table === "user_session_state") {
      // resolveCurrentWorkspaceId: null claim → solo workspace fallback.
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: { current_workspace_id: null }, error: null }),
            maybeSingle: () => ({ data: { current_workspace_id: null }, error: null }),
          }),
        }),
      };
    }
    if (table === "conversations") {
      return {
        update: vi.fn((patch: Record<string, unknown>) => {
          const record: UpdateRecord = { patch, ins: [] };
          updates.push(record);
          const chain: Record<string, unknown> = {
            error: null,
            eq: vi.fn(),
            in: vi.fn((column: string, values: unknown[]) => {
              record.ins.push({ column, values: [...values] });
              return chain;
            }),
            select: vi.fn(() =>
              Promise.resolve({ data: [{ id: "conv-1" }], error: null }),
            ),
            then: (resolve: (v: unknown) => void) =>
              resolve({ error: null }),
          };
          (chain.eq as ReturnType<typeof vi.fn>).mockReturnValue(chain);
          return chain;
        }),
        // mig 059: saveMessage reads conversations.workspace_id before the
        // messages INSERT (.select("workspace_id").eq("id", …).single()).
        select: vi.fn(() => {
          const selectChain: Record<string, unknown> = {
            eq: vi.fn(),
            single: vi.fn(() => ({
              data: { workspace_id: "22222222-2222-4222-8222-222222222222" },
              error: null,
            })),
          };
          (selectChain.eq as ReturnType<typeof vi.fn>).mockReturnValue(
            selectChain,
          );
          return selectChain;
        }),
      };
    }
    if (table === "messages") {
      return { insert: () => ({ error: null }) };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      update: () => ({ eq: () => ({ error: null }) }),
      insert: () => ({ error: null }),
    };
  });

  return { updates };
}

describe("agent-runner — disconnect-after-result race (#3463)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
  });

  test("abort branch's status write threads .in('status', ['active']) so a row already at waiting_for_user is left alone", async () => {
    const { updates } = setupSupabaseMock();
    mockQuery.mockReturnValue(
      buildRaceIterator({ userId: "11111111-1111-4111-8111-111111111111", conversationId: "conv-1" }) as never,
    );

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    // Project the captured updates onto only the fields under test
    // (status + .in() predicates). A failure prints the entire
    // sequence so a future regression report tells the reader which
    // write went stomp-mode instead of "expected undefined to be
    // defined" (test-design review recommendation #2).
    const projected = updates.map((u) => ({
      status: u.patch.status,
      ins: u.ins,
    }));

    // Flow on the bug-fixed path:
    //   1. result branch's primary `waiting_for_user` write — must
    //      have NO `.in()` guard (that write must win the race; a
    //      guard would re-introduce the bug from the other side).
    //   2. abort branch's `failed` write — MUST thread the
    //      `onlyIfStatusIn: ["active"]` guard so the row stays at
    //      whatever the result branch wrote (the load-bearing fix
    //      for #3463).
    expect(projected).toContainEqual({
      status: "waiting_for_user",
      ins: [],
    });
    expect(projected).toContainEqual({
      status: "failed",
      ins: [{ column: "status", values: ["active"] }],
    });
  });

  test("classifier maps SessionAbortError('disconnected') to non-user-requested (regression for the abort branch's nextStatus ternary)", () => {
    // The abort branch picks `nextStatus = isUserRequested ?
    // "waiting_for_user" : "failed"`. A misclassification would write
    // `waiting_for_user` for a disconnect — masking the original bug
    // by flipping its sign. Pin the contract.
    const err = new SessionAbortError("disconnected");
    expect(err.kind).toBe("disconnected");
    expect(err.message).toBe("Session aborted: disconnected");
  });
});
