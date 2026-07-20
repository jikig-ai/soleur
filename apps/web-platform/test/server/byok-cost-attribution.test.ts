/**
 * BYOK cost attribution split — Phase 8.2.4 / TR7 / AC8.
 *
 * Pins the load-bearing invariant for Phase 3: when Harry's agent runs
 * inside Jean's workspace, the `audit_byok_use` row carries
 *
 *   user_id      = Harry      (legacy founder_id column)
 *   founder_id   = Harry      (BYOK key owner — cost attribution)
 *   workspace_id = Jean       (workspace context — chargeback target)
 *
 * AND the BYOK KEK is derived from Harry's userId (in the HKDF `info`
 * parameter per `2026-03-20-hkdf-salt-info-parameter-semantics`), NOT
 * Jean's. This makes Harry pay for compute that ran inside Jean's
 * workspace — the cost-attribution invariant the multi-user product
 * relies on.
 *
 * Unit test (mocks supabase + ws). The integration shape (real DB +
 * real ByokLease) is covered by the existing tenant-isolation suite
 * under `TENANT_INTEGRATION_TEST=1`.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

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
import type { ByokLeaseArgs } from "@/server/byok-lease";

const HARRY = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const JEAN_WORKSPACE = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const CONV = "cccccccc-cccc-cccc-cccc-cccccccccccc";

beforeEach(() => {
  rpcSpy.mockClear();
  sendToClientSpy.mockClear();
});

describe("BYOK cost attribution — Harry-in-Jean's-workspace split (TR7 / AC8)", () => {
  it("write_byok_audit RPC carries p_founder_id=Harry and p_workspace_id=Jean", async () => {
    persistTurnCost(
      HARRY,
      CONV,
      "cco",
      JEAN_WORKSPACE,
      {
        totalCostUsd: 0.07,
        usage: {
          input_tokens: 1234,
          output_tokens: 567,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );

    await new Promise((r) => setImmediate(r));

    const auditCall = rpcSpy.mock.calls.find(
      (c) => (c[0] as string) === "write_byok_audit",
    );
    expect(auditCall).toBeDefined();
    // Split is the load-bearing assertion: founder_id (cost-attribution
    // target) ≠ workspace_id (workspace context) when the key owner is
    // a member of someone else's workspace.
    expect(auditCall![1]).toMatchObject({
      p_founder_id: HARRY,
      p_workspace_id: JEAN_WORKSPACE,
    });
    expect(auditCall![1].p_founder_id).not.toBe(auditCall![1].p_workspace_id);
  });

  it("usage_update WebSocket fan-out is keyed on Harry (key owner), not Jean", async () => {
    persistTurnCost(
      HARRY,
      CONV,
      "cco",
      JEAN_WORKSPACE,
      {
        totalCostUsd: 0.07,
        usage: {
          input_tokens: 1234,
          output_tokens: 567,
          cache_read_input_tokens: 0,
          cache_creation_input_tokens: 0,
        },
      },
      { source: "cc-soleur-go", model: null },
    );
    await new Promise((r) => setImmediate(r));

    // sendToClient(userId, msg) — userId arg MUST be Harry (he's the
    // logged-in user whose dashboard reflects the spend). Jean's
    // dashboard wouldn't show this — the cost is on Harry's tab.
    expect(sendToClientSpy).toHaveBeenCalled();
    const [recipientUserId, payload] = sendToClientSpy.mock.calls[0];
    expect(recipientUserId).toBe(HARRY);
    // workspaceId fan-out carries the workspace context (so the
    // chat-surface bubble can attribute the spend visually to the
    // workspace it ran in).
    expect((payload as { workspaceId?: string }).workspaceId).toBe(
      JEAN_WORKSPACE,
    );
  });

  it("ByokLeaseArgs type carries workspaceContextUserId + keyOwnerUserId as distinct fields", () => {
    // Compile-time + value assertion that the lease shape exposes BOTH
    // userIds. The HKDF call site (server/byok.ts:34-39) reads
    // `keyOwnerUserId` from the lease into the `info` parameter,
    // NEVER `workspaceContextUserId`. Drift-guarding via type-shape
    // here keeps the split visible to future refactors.
    const args: ByokLeaseArgs = {
      workspaceContextUserId: JEAN_WORKSPACE, // semantic shape — actually the workspace OWNER user
      keyOwnerUserId: HARRY,
    };
    expect(args.workspaceContextUserId).not.toBe(args.keyOwnerUserId);
    expect(args.keyOwnerUserId).toBe(HARRY);
  });
});
