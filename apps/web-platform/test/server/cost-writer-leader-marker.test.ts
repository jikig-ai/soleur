// #8611 — the leader-loop (founder BYOK) cost marker must carry the turn index and the Inngest
// attempt, or the 72h rollback trigger cannot tell a double-billed turn from a real second turn:
// the marker's only correlation field is the conversation id.
import { beforeEach, describe, expect, it, vi } from "vitest";

const { markerMock, rpcMock } = vi.hoisted(() => ({
  markerMock: vi.fn(),
  rpcMock: vi.fn(async () => ({ error: null })),
}));
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({ rpc: rpcMock }) }));
vi.mock("@/server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("@/server/claude-cost-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/claude-cost-marker")>()),
  emitClaudeCostMarker: markerMock,
}));

import { persistTurnCostAwaitable } from "@/server/cost-writer";

const usage = {
  input_tokens: 10,
  output_tokens: 5,
  cache_read_input_tokens: 0,
  cache_creation_input_tokens: 0,
};

beforeEach(() => {
  markerMock.mockReset();
  rpcMock.mockClear();
});

describe("persistTurnCostAwaitable leader-loop marker — #8611", () => {
  it("passes turn and attempt through to the SOLEUR_CLAUDE_COST marker", async () => {
    await persistTurnCostAwaitable(
      "11111111-1111-4111-8111-111111111111",
      "conv-1",
      "cfo",
      "11111111-1111-4111-8111-111111111111",
      { totalCostUsd: 0.01, usage },
      { source: "leader-loop", model: "claude-sonnet-5", turn: 3, attempt: 1 },
    );
    expect(markerMock).toHaveBeenCalledTimes(1);
    expect(markerMock.mock.calls[0][0]).toMatchObject({ source: "leader-loop", id: "conv-1", turn: 3, attempt: 1 });
  });

  it("omits the keys entirely for callers that do not supply them", async () => {
    await persistTurnCostAwaitable(
      "11111111-1111-4111-8111-111111111111",
      "conv-2",
      "cfo",
      "11111111-1111-4111-8111-111111111111",
      { totalCostUsd: 0.01, usage },
      { source: "leader-loop", model: "claude-sonnet-5" },
    );
    const marker = markerMock.mock.calls[0][0] as Record<string, unknown>;
    expect("turn" in marker).toBe(false);
    expect("attempt" in marker).toBe(false);
  });
});
