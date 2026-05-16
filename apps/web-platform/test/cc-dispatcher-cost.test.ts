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

// #3641 F5 — Shared `vi.mock` factory bodies live in
// `test/helpers/cc-dispatcher-harness.ts`. This file consumes 5/6 of the
// harness modules; the 1 omitted (`mockMirrorP0Deduped`) is not exercised
// by the cost-writer wiring tests (W4-orphan path is unit-tested in
// cc-dispatcher.test.ts). Five sibling cc-dispatcher-*.test.ts files
// stay on bespoke hoists per the plan's harness consumer scoping.
const {
  mockReportSilentFallback,
  mockFetchUserWorkspacePath,
  mockMessagesInsert,
  mockUpdateConversationFor,
  mockMirrorP0Deduped,
  mockPersistTurnCost,
} = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockFetchUserWorkspacePath: vi.fn(),
  mockMessagesInsert: vi.fn().mockResolvedValue({ error: null }),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
  mockMirrorP0Deduped: vi.fn(),
  mockPersistTurnCost: vi.fn(),
}));

vi.mock("@/server/conversation-writer", async () => {
  const { conversationWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return conversationWriterFactory({ mockUpdateConversationFor });
});

vi.mock("@/server/observability", async () => {
  const { observabilityFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return observabilityFactory({
    mockReportSilentFallback,
    mockMirrorP0Deduped,
    // This file doesn't exercise the 5-min TTL coalescing — collapse
    // `mirrorWithDebounce` to the spy directly.
    withTtlDedupWrapper: false,
  });
});

vi.mock("@/server/kb-document-resolver", async () => {
  const { kbDocumentResolverFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return kbDocumentResolverFactory({ mockFetchUserWorkspacePath });
});

vi.mock("@/lib/supabase/service", async () => {
  const { supabaseServiceFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return supabaseServiceFactory({ mockMessagesInsert });
});

vi.mock("@/server/cost-writer", async () => {
  const { costWriterFactory } = await import(
    "@/test/helpers/cc-dispatcher-harness"
  );
  return costWriterFactory({ mockPersistTurnCost });
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
