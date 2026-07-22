/**
 * Phase 1 (#stuck-active fix) — result-branch finalization tests.
 *
 * Plan: knowledge-base/project/plans/2026-05-05-fix-cc-chat-stuck-conversation-blocks-concurrency-slot-plan.md
 *
 * The agent-runner result-branch (around lines 1076-1144) has SIX
 * throw-eligible steps after `saveMessage` succeeds. Without a
 * try/catch wrapping the branch, any throw between the message save
 * and the final `updateConversationStatus(..., "waiting_for_user")`
 * leaves the conversation row stuck at status='active' AND leaks the
 * concurrency slot — because the existing outer catch at line 1165
 * only writes "failed" when `controller.signal.aborted` is true.
 *
 * AC1 / AC6 requires:
 *   1. After `saveMessage` succeeds, a thrown step lands the row at
 *      `waiting_for_user` (assistant text was persisted) AND releases
 *      the slot.
 *   2. If the status flip itself fails, the slot is still released
 *      (best-effort).
 *   3. Clean-result path is unchanged: status flips to
 *      `waiting_for_user` and `releaseSlot` is NOT called (slot held
 *      legitimately for follow-up turns).
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// ---------------------------------------------------------------------------
// Hoisted mocks — vitest hoists vi.mock() before const/let declarations
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
  createSdkMcpServer: vi.fn(() => ({ type: "sdk", name: "test", instance: { tools: [] } })),
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
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn(), addBreadcrumb: vi.fn() }));
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
import { createSupabaseMockImpl } from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build an SDK iterator that emits a single `assistant` text block (so
 * `fullText` is non-empty and `saveMessage` is called) followed by a
 * `result` event. The `failOn` callback can throw at a chosen step to
 * simulate the wedge classes catalogued in the plan.
 */
function buildSdkIterator(args: {
  emitText?: string;
} = {}) {
  const text = args.emitText ?? "I'm unable to read the PDF in this environment — here's…";
  return {
    async *[Symbol.asyncIterator]() {
      yield {
        type: "assistant",
        message: { content: [{ type: "text", text }] },
      };
      yield {
        type: "result",
        session_id: "sess-final-1",
        total_cost_usd: 0,
        usage: { input_tokens: 0, output_tokens: 0 },
      };
    },
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
  };
}

/** Track conversation status writes via the conversations.update chain. */
interface UpdateRecord {
  patchKeys: string[];
  patch: Record<string, unknown>;
  /** `.in("status", values)` predicates appended to this UPDATE. The
   *  abort/result-branch cascade-to-`failed` writes appended the
   *  `onlyIfStatusIn: ["active"]` guard added by #3463; the primary
   *  `waiting_for_user` write does not. Tests can sort by patch.status
   *  to map an UpdateRecord back to its site. */
  ins: Array<{ column: string; values: unknown[] }>;
}

function setupSupabaseMockWithStatusCapture(opts: {
  /** Throw on the Nth `update().eq().eq().select()` call (1-indexed). */
  failStatusWriteOnCall?: number;
  /** Custom error to throw from update chain. */
  failWithError?: { message: string };
} = {}): { updates: UpdateRecord[]; messageInserts: Array<Record<string, unknown>> } {
  const updates: UpdateRecord[] = [];
  const messageInserts: Array<Record<string, unknown>> = [];
  let conversationsUpdateCallCount = 0;

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
          conversationsUpdateCallCount += 1;
          const callIndex = conversationsUpdateCallCount;
          const updateRecord: UpdateRecord = {
            patchKeys: Object.keys(patch),
            patch,
            ins: [],
          };
          updates.push(updateRecord);
          const chain: Record<string, unknown> = {
            error: null,
            eq: vi.fn(),
            // #3463: `updateConversationStatusIfActive` appends
            // `.in("status", ["active"])` to the chain. The mock returns
            // the same chain so the wrapper's `await guardedQuery`
            // resolves to `{ error: null }` (silent success — matches
            // the conversation-writer's no-expectMatch contract).
            in: vi.fn((column: string, values: unknown[]) => {
              updateRecord.ins.push({ column, values: [...values] });
              return chain;
            }),
            select: vi.fn(() => {
              if (
                opts.failStatusWriteOnCall !== undefined &&
                callIndex === opts.failStatusWriteOnCall
              ) {
                return Promise.resolve({
                  data: null,
                  error: opts.failWithError ?? { message: "simulated update failure" },
                });
              }
              return Promise.resolve({
                data: [{ id: "conv-1" }],
                error: null,
              });
            }),
            // Thenable so `await guardedQuery` (no-expectMatch path)
            // resolves with a plain `{ error: null }` without going
            // through `.select()`.
            then: (resolve: (v: unknown) => void) =>
              resolve({ error: null }),
          };
          (chain.eq as ReturnType<typeof vi.fn>).mockReturnValue(chain);
          // chain.in is set up via mockImplementation above so the
          // captured call lands in updateRecord.ins. mockReturnValue
          // would shadow that capture.
          return chain;
        }),
        // SELECT chain for the workspace_id read added to `saveMessage`
        // by the messages-workspace_id RLS fix:
        //   .select("workspace_id").eq("id", …).single()
        select: vi.fn(() => {
          const selectChain: Record<string, unknown> = {
            eq: vi.fn(),
            single: vi.fn(() => ({
              data: { workspace_id: "33333333-3333-4333-8333-333333333333" },
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
      return {
        insert: (row: Record<string, unknown>) => {
          messageInserts.push(row);
          return { error: null };
        },
      };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      update: () => ({ eq: () => ({ error: null }) }),
      insert: () => ({ error: null }),
    };
  });

  return { updates, messageInserts };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("agent-runner result-branch finalization (AC1/AC6)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
  });

  test("clean result (no throw) → status set to waiting_for_user, releaseSlot NOT called", async () => {
    // The slot should stay HELD on a clean turn — the conversation is
    // alive and waiting for the user's next message. Release happens
    // on archive, close, or timeout (not on every turn end).
    const { updates } = setupSupabaseMockWithStatusCapture();
    mockQuery.mockReturnValue(buildSdkIterator() as never);

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    // Find the conversation status write — should be waiting_for_user.
    const statusUpdates = updates.filter((u) => "status" in u.patch);
    expect(statusUpdates.length).toBeGreaterThan(0);
    const finalStatus = statusUpdates[statusUpdates.length - 1].patch.status;
    expect(finalStatus).toBe("waiting_for_user");

    // Slot held — release NOT called from the result-branch path.
    expect(mockReleaseSlot).not.toHaveBeenCalled();
  });

  test("T3-workspace-id: saveMessage INSERT carries workspace_id from the parent conversation (mig 059 RLS)", async () => {
    // The assistant-row INSERT in `saveMessage` must carry `workspace_id`
    // read from the parent conversation so `messages_workspace_member_insert`
    // WITH CHECK (is_workspace_member(workspace_id, auth.uid())) is satisfied.
    // The conversations SELECT mock returns "33333333-3333-4333-8333-333333333333".
    const { messageInserts } = setupSupabaseMockWithStatusCapture();
    mockQuery.mockReturnValue(buildSdkIterator() as never);

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    const assistantRows = messageInserts.filter((r) => r.role === "assistant");
    expect(assistantRows.length).toBeGreaterThan(0);
    for (const row of assistantRows) {
      expect(row.workspace_id).toBe("33333333-3333-4333-8333-333333333333");
    }
  });

  test("sendToClient throws on stream_end → status finalized + releaseSlot called", async () => {
    // Simulate the wedge class: assistant text was saved, but a downstream
    // step in the result branch throws (e.g., stream_end emit on a dead
    // socket). Without the AC1 try/catch wrap, the row stays at active
    // and the slot leaks.
    const { updates } = setupSupabaseMockWithStatusCapture();
    mockQuery.mockReturnValue(buildSdkIterator() as never);

    // Throw from sendToClient on the stream_end message. Other emissions
    // (stream, usage_update, session_ended) succeed.
    mockSendToClient.mockImplementation((_userId: string, message: { type: string }) => {
      if (message.type === "stream_end") {
        throw new Error("WebSocket is in CLOSING state");
      }
    });

    // The wrap should re-throw the original error so the outer catch at
    // ~line 1165 still fires the existing failed-path side effects.
    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    // Status was finalized to waiting_for_user (assistant text was saved).
    // The outer catch may also write "failed" — accept either as the final
    // state, but the catch must have ATTEMPTED waiting_for_user before
    // re-throw landed in the outer catch.
    const statusUpdates = updates.filter((u) => "status" in u.patch);
    const statusValues = statusUpdates.map((u) => u.patch.status);
    expect(statusValues).toContain("waiting_for_user");

    // Slot was released by the result-branch catch (#stuck-active AC1) AND
    // by the outer catch (P2-A defense in depth). Both calls are keyed
    // DELETEs and idempotent — assert the call happened, not the exact
    // count, since the second call is the safety-net and may be 1 or 2
    // depending on whether the result-branch catch landed.
    expect(mockReleaseSlot).toHaveBeenCalledWith("11111111-1111-4111-8111-111111111111", "conv-1");
    expect(mockReleaseSlot.mock.calls.length).toBeGreaterThanOrEqual(1);
  });

  test("clean result → primary waiting_for_user write does NOT thread onlyIfStatusIn (#3463 win-the-race contract)", async () => {
    // The result branch's primary `waiting_for_user` flip MUST stay
    // strict — `expectMatch: true`, no status guard. If we guarded it,
    // a row that legitimately reached terminus (concurrent close,
    // archive trigger) would silently fail to flip and the UI would
    // desync. The disconnect-after-result race is fixed at the
    // ABORT branch's write, not by neutering the result branch.
    const { updates } = setupSupabaseMockWithStatusCapture();
    mockQuery.mockReturnValue(buildSdkIterator() as never);

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    const waitingWrite = updates.find(
      (u) => u.patch.status === "waiting_for_user",
    );
    expect(waitingWrite).toBeDefined();
    expect(waitingWrite?.ins).toEqual([]);
  });

  test("result-branch fallback failed-cascade threads onlyIfStatusIn=['active'] (#3463 cascade guard)", async () => {
    // Force the waiting_for_user flip to throw (call #2 = the result
    // branch's primary status write). The catch then runs the cascade
    // — first re-tries `waiting_for_user`, then on failure cascades to
    // `failed`. The cascade `failed` write goes through
    // `updateConversationStatusIfActive`, which appends
    // `.in("status", ["active"])` so a row that reached a terminal
    // state via a concurrent writer is left untouched.
    const { updates } = setupSupabaseMockWithStatusCapture({
      failStatusWriteOnCall: 2,
      failWithError: { message: "expectMatch row miss" },
    });
    mockQuery.mockReturnValue(buildSdkIterator() as never);

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    // Find a `failed` write — the cascade target. There may be more
    // than one (defense-in-depth between result-branch catch and outer
    // catch); at least one must carry the `.in("status", ["active"])`
    // guard.
    const failedWrites = updates.filter((u) => u.patch.status === "failed");
    expect(failedWrites.length).toBeGreaterThanOrEqual(1);
    const guardedFailedWrite = failedWrites.find((u) =>
      u.ins.some(
        (entry) =>
          entry.column === "status" &&
          entry.values.length === 1 &&
          entry.values[0] === "active",
      ),
    );
    expect(guardedFailedWrite).toBeDefined();
  });

  test("updateConversationStatus throws (0-row, expectMatch) → releaseSlot still called (best-effort)", async () => {
    // The result branch's last DB write is updateConversationStatus with
    // expectMatch: true. A 0-row outcome (concurrent archive race, or a
    // composite-key miss) throws. The catch must STILL release the slot.
    //
    // Sequence of conversations.update calls on a clean run:
    //   1. session_id persistence (line ~968)
    //   2. waiting_for_user status flip (line ~1134)
    // Fail call #2 to simulate the status flip throwing.
    const { updates } = setupSupabaseMockWithStatusCapture({
      failStatusWriteOnCall: 2,
      failWithError: { message: "expectMatch row miss" },
    });
    mockQuery.mockReturnValue(buildSdkIterator() as never);

    await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");

    // Slot is released even though the intended status write failed. This
    // is the load-bearing assertion: a wedge in the status update must not
    // strand the slot. The outer catch (P2-A) provides defense-in-depth,
    // so the call count may be 1 (result-branch only) or 2 (both layers).
    expect(mockReleaseSlot).toHaveBeenCalledWith("11111111-1111-4111-8111-111111111111", "conv-1");
    expect(mockReleaseSlot.mock.calls.length).toBeGreaterThanOrEqual(1);

    // Some attempt at status finalization happened (waiting_for_user OR
    // failed fallback after the catch).
    const statusUpdates = updates.filter((u) => "status" in u.patch);
    expect(statusUpdates.length).toBeGreaterThan(0);
  });
});
