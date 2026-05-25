/**
 * Tests for the `recordByokUseAndCheckCap` TS wrapper around the 6-arg
 * `record_byok_use_and_check_cap` RPC at
 * `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`.
 *
 * Covers AC4 (a-d) in 2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md:
 *   (a) Happy path — RPC returns { cumulative_cents, kill_tripped: false }
 *       → wrapper returns { cumulativeCents, killTripped: false }.
 *   (b) killTripped=true flow — RPC returns kill_tripped: true → wrapper
 *       returns killTripped: true (caller short-circuits the loop).
 *   (c) RPC error THROWS (fail-closed; per ADR-041 Layer 1).
 *   (d) N2 invariant — passing workspaceId !== founderId raises.
 *
 * Mock shape mirrors `byok-cost-attribution.test.ts` — mock the service
 * client's `rpc()` method via vi.hoisted.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

interface RpcResult {
  data: unknown;
  error: { message?: string; code?: string } | null;
}

const { rpcSpy } = vi.hoisted(() => ({
  rpcSpy: vi.fn<
    (name: string, args: Record<string, unknown>) => Promise<RpcResult>
  >(),
}));

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: () => ({ rpc: rpcSpy }),
}));

import { recordByokUseAndCheckCap } from "@/server/byok-cap-rpc";

const FOUNDER = "11111111-1111-1111-1111-111111111111";
const OTHER_WS = "22222222-2222-2222-2222-222222222222";
const INVOCATION = "33333333-3333-3333-3333-333333333333";

beforeEach(() => {
  rpcSpy.mockReset();
});

describe("recordByokUseAndCheckCap — AC4", () => {
  it("(a) happy path: returns cumulativeCents + killTripped=false", async () => {
    rpcSpy.mockResolvedValueOnce({
      data: { cumulative_cents: 1234, kill_tripped: false },
      error: null,
    });

    const result = await recordByokUseAndCheckCap({
      invocationId: INVOCATION,
      founderId: FOUNDER,
      workspaceId: FOUNDER, // N2: must equal founderId
      agentRole: "agent.spawn.requested",
      tokenCount: 0,
      unitCostCents: 0,
    });

    expect(result).toEqual({ cumulativeCents: 1234, killTripped: false });

    // Confirm RPC was called with the 6-arg shape from mig 061:81-148.
    expect(rpcSpy).toHaveBeenCalledWith(
      "record_byok_use_and_check_cap",
      expect.objectContaining({
        p_invocation_id: INVOCATION,
        p_founder_id: FOUNDER,
        p_workspace_id: FOUNDER,
        p_agent_role: "agent.spawn.requested",
        p_token_count: 0,
        p_unit_cost_cents: 0,
      }),
    );
  });

  it("(b) killTripped=true flow: returns killTripped=true (loop short-circuits)", async () => {
    rpcSpy.mockResolvedValueOnce({
      data: { cumulative_cents: 5099, kill_tripped: true },
      error: null,
    });

    const result = await recordByokUseAndCheckCap({
      invocationId: INVOCATION,
      founderId: FOUNDER,
      workspaceId: FOUNDER,
      agentRole: "agent.spawn.requested",
      tokenCount: 0,
      unitCostCents: 0,
    });

    expect(result.killTripped).toBe(true);
    expect(result.cumulativeCents).toBe(5099);
  });

  it("(c) RPC error THROWS rather than returning killTripped=false (fail-closed per ADR-041)", async () => {
    rpcSpy.mockResolvedValueOnce({
      data: null,
      error: { message: "transient connection error", code: "08006" },
    });

    await expect(
      recordByokUseAndCheckCap({
        invocationId: INVOCATION,
        founderId: FOUNDER,
        workspaceId: FOUNDER,
        agentRole: "agent.spawn.requested",
        tokenCount: 0,
        unitCostCents: 0,
      }),
    ).rejects.toThrow(/transient|byok cap rpc/i);
  });

  it("(d) N2 invariant: workspaceId !== founderId raises before issuing the RPC", async () => {
    await expect(
      recordByokUseAndCheckCap({
        invocationId: INVOCATION,
        founderId: FOUNDER,
        workspaceId: OTHER_WS, // VIOLATES N2
        agentRole: "agent.spawn.requested",
        tokenCount: 0,
        unitCostCents: 0,
      }),
    ).rejects.toThrow(/N2|workspaceId must equal founderId/i);

    // Critically: the RPC must NOT have been issued at all — pre-flight
    // assertion gates the network round-trip.
    expect(rpcSpy).not.toHaveBeenCalled();
  });

  it("(c.2) RPC returns null data without error raises (defensive — server returned empty)", async () => {
    rpcSpy.mockResolvedValueOnce({ data: null, error: null });

    await expect(
      recordByokUseAndCheckCap({
        invocationId: INVOCATION,
        founderId: FOUNDER,
        workspaceId: FOUNDER,
        agentRole: "agent.spawn.requested",
        tokenCount: 0,
        unitCostCents: 0,
      }),
    ).rejects.toThrow(/empty response|byok cap rpc/i);
  });
});
