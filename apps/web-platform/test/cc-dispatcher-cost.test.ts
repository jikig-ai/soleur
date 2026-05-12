/**
 * RED tests for the API-usage undercount fix
 * (plan: 2026-05-12-fix-api-usage-tracking-undercount-plan.md, Phase 3.3).
 *
 * The cc-soleur-go path's `onResult` event was a no-op stub at
 * `cc-dispatcher.ts:1202` ("wire in Stage 3"). Every chat conversation
 * routed through `dispatchSoleurGo` emits cost telemetry into the void
 * while the dashboard reads `conversations.total_cost_usd`. This test
 * pins the contract that `onResult` invokes `persistTurnCost` with the
 * cost + 4-token-axis payload from the SDK result message.
 *
 * Mocks `@/server/cost-writer` to spy on `persistTurnCost` rather than
 * driving Supabase RPC + WS event side-effects directly — those are
 * pinned in `cost-writer.test.ts`.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockPersistTurnCost,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockPersistTurnCost: vi.fn(),
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
      throw new Error(`unexpected table: ${table}`);
    },
    storage: { from: () => ({ download: vi.fn() }) },
  }),
}));

vi.mock("@/server/cost-writer", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/cost-writer")
  >("@/server/cost-writer");
  return {
    ...actual,
    persistTurnCost: mockPersistTurnCost,
  };
});

import {
  dispatchSoleurGo,
  __setCcRunnerForTests,
  __resetDispatcherForTests,
  CC_ROUTER_LEADER_ID,
} from "@/server/cc-dispatcher";

describe("cc-dispatcher — onResult wires persistTurnCost (#3626)", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    mockReportSilentFallback.mockClear();
    mockFetchUserWorkspacePath.mockReset();
    mockMessagesInsert.mockClear();
    mockMessagesInsert.mockResolvedValue({ error: null });
    mockUpdateConversationFor.mockClear();
    mockUpdateConversationFor.mockResolvedValue({ ok: true });
    mockPersistTurnCost.mockClear();
    mockFetchUserWorkspacePath.mockResolvedValue("/tmp/claude-XXXX/workspace");
  });

  it("invokes persistTurnCost with cost + 4-token-axis payload from SDK result", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const stubRunner = {
      dispatch: vi.fn(
        async (args: {
          events: {
            onResult?: (result: {
              totalCostUsd: number;
              usage: {
                input_tokens: number;
                output_tokens: number;
                cache_read_input_tokens: number;
                cache_creation_input_tokens: number;
              };
            }) => void;
          };
        }) => {
          args.events.onResult?.({
            totalCostUsd: 0.0042,
            usage: {
              input_tokens: 521,
              output_tokens: 88,
              cache_read_input_tokens: 14_000,
              cache_creation_input_tokens: 800,
            },
          });
        },
      ),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-cost-1",
      conversationId: "conv-cost-1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    expect(mockPersistTurnCost).toHaveBeenCalledTimes(1);
    expect(mockPersistTurnCost).toHaveBeenCalledWith(
      "u-cost-1",
      "conv-cost-1",
      CC_ROUTER_LEADER_ID,
      {
        totalCostUsd: 0.0042,
        usage: {
          input_tokens: 521,
          output_tokens: 88,
          cache_read_input_tokens: 14_000,
          cache_creation_input_tokens: 800,
        },
      },
    );
  });

  it("does NOT invoke persistTurnCost when the runner never fires onResult", async () => {
    const sendToClient = vi.fn().mockReturnValue(true);
    const persistActiveWorkflow = vi.fn().mockResolvedValue(undefined);

    const stubRunner = {
      dispatch: vi.fn(async () => {}),
      hasActiveQuery: () => false,
      activeQueriesSize: () => 0,
      reapIdle: () => 0,
      closeConversation: () => {},
      respondToToolUse: () => false,
      notifyAwaitingUser: () => {},
      // biome-ignore lint/suspicious/noExplicitAny: minimal stub
    } as any;
    __setCcRunnerForTests(stubRunner);

    await dispatchSoleurGo({
      userId: "u-cost-2",
      conversationId: "conv-cost-2",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      sendToClient,
      persistActiveWorkflow,
    });

    expect(mockPersistTurnCost).not.toHaveBeenCalled();
  });
});
