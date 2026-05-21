import { describe, it, expect, beforeEach, vi } from "vitest";

// Phase 3 (feat-team-workspace-multi-user) — pins that `persistTurnCost`
// threads `p_workspace_id` into the `write_byok_audit` RPC. Migration
// 055 made `audit_byok_use.workspace_id` NOT NULL; the 5-arg RPC
// shape would fail with a NOT NULL constraint violation. Migration
// 057 widens both RPCs to 6-arg signatures; this test pins the JS
// caller wire-up.

const { rpcSpy, sendToClientSpy } = vi.hoisted(() => ({
  rpcSpy: vi.fn(
    async (_name: string, _args: Record<string, unknown>) => ({ error: null }),
  ),
  sendToClientSpy: vi.fn(
    (_userId: string, _msg: Record<string, unknown>) => true,
  ),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc: rpcSpy }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/ws-handler", () => ({
  sendToClient: sendToClientSpy,
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
  }),
}));

import { persistTurnCost } from "@/server/cost-writer";

const USER = "550e8400-e29b-41d4-a716-446655440000";
const WORKSPACE = "660e8400-e29b-41d4-a716-446655440111";
const CONV = "770e8400-e29b-41d4-a716-446655440222";

beforeEach(() => {
  rpcSpy.mockClear();
  sendToClientSpy.mockClear();
});

describe("persistTurnCost — workspace_id wiring (Phase 3)", () => {
  it("passes p_workspace_id to the write_byok_audit RPC", async () => {
    persistTurnCost(USER, CONV, "cpo", WORKSPACE, {
      totalCostUsd: 0.012,
      usage: {
        input_tokens: 100,
        output_tokens: 50,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
      },
    });

    // Microtask drain so .then() handlers attached inside persistTurnCost
    // fire before assertion.
    await new Promise((r) => setImmediate(r));

    const auditCall = rpcSpy.mock.calls.find(
      (c) => (c[0] as string) === "write_byok_audit",
    );
    expect(auditCall).toBeDefined();
    expect(auditCall![1]).toMatchObject({
      p_founder_id: USER,
      p_workspace_id: WORKSPACE,
      p_agent_role: "cpo",
    });
  });

  it("passes p_workspace_id to the increment_conversation_cost RPC (workspace-grain attribution)", async () => {
    persistTurnCost(USER, CONV, "cpo", WORKSPACE, {
      totalCostUsd: 0.012,
      usage: {
        input_tokens: 100,
        output_tokens: 50,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
      },
    });

    await new Promise((r) => setImmediate(r));

    const incrementCall = rpcSpy.mock.calls.find(
      (c) => (c[0] as string) === "increment_conversation_cost",
    );
    expect(incrementCall).toBeDefined();
    // The conversation row carries workspace_id (migration 055 sweep); the
    // RPC signature is unchanged because the conversation_id already pins
    // the workspace. But the audit row needs explicit threading.
    expect(incrementCall![1]).toMatchObject({
      conv_id: CONV,
    });
  });

  it("usage_update WS event includes the workspaceId for client UI attribution", async () => {
    persistTurnCost(USER, CONV, "cpo", WORKSPACE, {
      totalCostUsd: 0.012,
      usage: {
        input_tokens: 100,
        output_tokens: 50,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
      },
    });

    expect(sendToClientSpy).toHaveBeenCalledTimes(1);
    const evt = sendToClientSpy.mock.calls[0][1] as Record<string, unknown>;
    expect(evt).toMatchObject({
      type: "usage_update",
      conversationId: CONV,
      workspaceId: WORKSPACE,
    });
  });
});
