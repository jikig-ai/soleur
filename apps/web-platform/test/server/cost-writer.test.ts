import { describe, it, expect, beforeEach, vi } from "vitest";

// Phase 3 (feat-team-workspace-multi-user) — pins that `persistTurnCost`
// threads `p_workspace_id` into the `write_byok_audit` RPC. Migration
// 055 made `audit_byok_use.workspace_id` NOT NULL; the 5-arg RPC
// shape would fail with a NOT NULL constraint violation. Migration
// 057 widens both RPCs to 6-arg signatures; this test pins the JS
// caller wire-up.

const { rpcSpy, sendToClientSpy } = vi.hoisted(() => ({
  rpcSpy: vi.fn(
    // Return type widened to the error union so per-test mockImplementation
    // can return an RPC error (e.g. the cross-tenant P0001 path) without
    // tripping TS2345 — the default value stays { error: null } (#4364).
    async (
      _name: string,
      _args: Record<string, unknown>,
    ): Promise<{ error: null | { message: string } }> => ({ error: null }),
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
  mirrorP0Deduped: vi.fn(),
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

const { emitMarkerSpy } = vi.hoisted(() => ({ emitMarkerSpy: vi.fn() }));
vi.mock("@/server/claude-cost-marker", () => ({
  emitClaudeCostMarker: emitMarkerSpy,
}));

import { persistTurnCost } from "@/server/cost-writer";
import { reportSilentFallback, mirrorP0Deduped } from "@/server/observability";
import { ByokDelegationCrossTenantError } from "@/server/byok-resolver";

const USER = "550e8400-e29b-41d4-a716-446655440000";
const WORKSPACE = "660e8400-e29b-41d4-a716-446655440111";
const CONV = "770e8400-e29b-41d4-a716-446655440222";

beforeEach(() => {
  rpcSpy.mockClear();
  sendToClientSpy.mockClear();
});

describe("persistTurnCost — cost marker threading (Phase 1, AC2)", () => {
  it("emits a SOLEUR_CLAUDE_COST marker with the threaded source + model", () => {
    emitMarkerSpy.mockClear();
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 4,
          cache_creation_input_tokens: 2,
        },
      },
      { source: "agent-runner", model: "claude-opus-4-8" },
    );
    expect(emitMarkerSpy).toHaveBeenCalledTimes(1);
    expect(emitMarkerSpy.mock.calls[0][0]).toMatchObject({
      source: "agent-runner",
      model: "claude-opus-4-8",
      input_tokens: 100,
      output_tokens: 50,
      cache_read_input_tokens: 4,
      cache_creation_input_tokens: 2,
      cost_usd: 0.012,
      id: CONV,
      capture_status: "ok",
    });
  });
});

describe("persistTurnCost — workspace_id wiring (Phase 3)", () => {
  it("passes p_workspace_id to the write_byok_audit RPC", async () => {
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

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
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

    await new Promise((r) => setImmediate(r));

    const incrementCall = rpcSpy.mock.calls.find(
      (c) => (c[0] as string) === "increment_conversation_cost",
    );
    expect(incrementCall).toBeDefined();
    // The conversation row carries workspace_id (migration 059 sweep); the
    // RPC signature is unchanged because the conversation_id already pins
    // the workspace. But the audit row needs explicit threading.
    expect(incrementCall![1]).toMatchObject({
      conv_id: CONV,
    });
  });

  it("usage_update WS event includes the workspaceId for client UI attribution", async () => {
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.012,
        usage: {
          input_tokens: 100,
          output_tokens: 50,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

    expect(sendToClientSpy).toHaveBeenCalledTimes(1);
    const evt = sendToClientSpy.mock.calls[0][1] as Record<string, unknown>;
    expect(evt).toMatchObject({
      type: "usage_update",
      conversationId: CONV,
      workspaceId: WORKSPACE,
    });
  });
});

describe("persistTurnCost — cross-tenant Art.33 emission (#4364, hardened #4656)", () => {
  it("routes byok_delegations:cross-tenant through mirrorP0Deduped (fatal, recurrence-resilient, clock-anchored)", async () => {
    const p0Mock = vi.mocked(mirrorP0Deduped);
    const reportMock = vi.mocked(reportSilentFallback);
    p0Mock.mockClear();
    reportMock.mockClear();
    // The migration-064 trigger raises the HYPHEN form on the cross-tenant
    // path. cost-writer must route it through `mirrorP0Deduped` (#4656 items
    // 2+3): fatal severity, no 5-min debounce, and `first_seen_at` clock
    // anchor — NEVER the `reportSilentFallback` path (capture-swallowed, no
    // clock anchor) and never the merged-rpc-failure catch-all. The
    // `feature` + `art33Breach` options carry the two tags the
    // `byok_art_33_breach` rule filters on (filter_match="all").
    rpcSpy.mockImplementation(
      async (
        name: string,
        _args: Record<string, unknown>,
      ): Promise<{ error: null | { message: string } }> => {
        if (name === "check_and_record_byok_delegation_use") {
          return {
            error: {
              message:
                "byok_delegations:cross-tenant: grantee g-1 is not a member of workspace ws-1",
            },
          };
        }
        return { error: null };
      },
    );
    persistTurnCost(
      USER,
      CONV,
      "cpo",
      WORKSPACE,
      {
        totalCostUsd: 0.02,
        usage: {
          input_tokens: 10,
          output_tokens: 5,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
      { delegationId: "deadbeef", callerUserId: "g-1" },
    );
    await new Promise((r) => setImmediate(r));

    expect(p0Mock).toHaveBeenCalledTimes(1);
    const [errArg, ctx] = p0Mock.mock.calls[0];
    expect(errArg).toBeInstanceOf(ByokDelegationCrossTenantError);
    expect(ctx).toMatchObject({
      op: "cross-tenant-violation",
      userId: USER,
      conversationId: CONV,
      delegationId: "deadbeef",
      feature: "byok-delegations",
      art33Breach: true,
    });

    // Must NOT route through reportSilentFallback for the cross-tenant op
    // (capture-swallow + no clock anchor was the #4656 item-2/3 gap), and must
    // NOT fall through to the merged-rpc-failure catch-all.
    const crossTenantViaFallback = reportMock.mock.calls.find(
      (c) => (c[1] as { op?: string })?.op === "cross-tenant-violation",
    );
    expect(crossTenantViaFallback).toBeFalsy();
    const fallback = reportMock.mock.calls.find(
      (c) => (c[1] as { op?: string })?.op === "merged-rpc-failure",
    );
    expect(fallback).toBeFalsy();
  });
});
